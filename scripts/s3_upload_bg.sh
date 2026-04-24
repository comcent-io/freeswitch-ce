#!/bin/bash
# Async recording post-processor.
#
# on_record_stop.lua used to do all its work synchronously inside FreeSWITCH's
# Lua VM, on whatever FS thread was dispatching the RECORD_STOP event. Each
# shell-out (`sox` for hold splicing, `shasum`, `aws s3 mv`) took 100-500 ms,
# and under bursts the FS event dispatch thread got blocked for many seconds
# — starving mod_amqp (and therefore our downstream scheduler) of all other
# events during that window.
#
# This script runs the whole pipeline (splice-holds → sha512 → aws s3 mv →
# upload-completed event) in a detached shell process so the Lua script can
# return in microseconds. When the upload finishes we push a CUSTOM event
# back into FS via its event socket, which mod_amqp then publishes as if
# the work had happened inline.
#
# Args:
#   $1 record_file_path
#   $2 bucket
#   $3 subdomain
#   $4 channel_id
#   $5 call_story_id
#   $6 hold_ranges  — semicolon-separated "startMs-endMs" pairs, or empty.
#                     Same encoding that on_channel_hold.lua puts into
#                     comcent_hold_ranges; if non-empty we splice silence
#                     into the recording at the correct positions before
#                     uploading.

set -u

record_file="$1"
bucket="$2"
subdomain="$3"
channel_id="$4"
call_story_id="$5"
hold_ranges="${6:-}"

log() {
  # Re-use FS's log file so debugging stays in one place
  echo "$(date -u +%FT%TZ) [s3_upload_bg] $*" >> /var/log/freeswitch.log
}

# ──────────────────────────────────────────────────────────────────────
# splice_holds: insert silence into the recording at each hold position.
# Mirrors the algorithm that used to live in on_record_stop.lua —
# documented inline in that file's splice_holds function.
#
# For each (start_ms, end_ms) pair in hold_ranges:
#   cut  = start_ms - sum_prior_holds     (position in the recording)
#   dur  = end_ms - start_ms               (silence duration)
# Emit: <recording slice from prev_cut to cut> <silence file of length dur>
# Finally append the tail (prev_cut → EOF) and `sox` concat all parts.
# ──────────────────────────────────────────────────────────────────────
splice_holds() {
  local file="$1" ranges="$2"
  [ -z "$ranges" ] && return 0

  local info rate channels
  info=$(soxi "$file" 2>/dev/null) || { log "soxi failed for $file"; return 1; }
  rate=$(printf '%s\n' "$info" | awk -F': *' '/Sample Rate/  {print $2; exit}')
  channels=$(printf '%s\n' "$info" | awk -F': *' '/Channels/  {print $2; exit}')
  rate="${rate:-8000}"
  channels="${channels:-1}"

  local workdir=/tmp
  local tmp_files=()
  local parts=()
  local sum_prior_holds_ms=0
  local prev_cut_rec_ms=0
  local i=0

  local oldIFS="$IFS"
  IFS=';'
  local pair
  for pair in $ranges; do
    IFS="$oldIFS"
    [ -z "$pair" ] && { IFS=';'; continue; }
    local start_ms="${pair%%-*}"
    local end_ms="${pair##*-}"
    if ! [[ "$start_ms" =~ ^[0-9]+$ && "$end_ms" =~ ^[0-9]+$ ]]; then
      IFS=';'; continue
    fi
    i=$((i + 1))

    local cut_rec_ms=$((start_ms - sum_prior_holds_ms))
    local part_dur_ms=$((cut_rec_ms - prev_cut_rec_ms))
    if [ "$part_dur_ms" -gt 0 ]; then
      local part_file="$workdir/$channel_id-part$i.wav"
      if ! sox "$file" "$part_file" trim \
          "$(awk -v m="$prev_cut_rec_ms" 'BEGIN{printf "%.3f", m/1000}')" \
          "$(awk -v m="$part_dur_ms"    'BEGIN{printf "%.3f", m/1000}')" \
          >/dev/null 2>&1; then
        log "sox trim part failed for $file (range $pair)"
        for f in "${tmp_files[@]}"; do rm -f "$f"; done
        IFS="$oldIFS"
        return 1
      fi
      parts+=("$part_file")
      tmp_files+=("$part_file")
    fi

    local hold_dur_ms=$((end_ms - start_ms))
    if [ "$hold_dur_ms" -gt 0 ]; then
      local silence_file="$workdir/$channel_id-silence$i.wav"
      if ! sox -n -r "$rate" -c "$channels" -b 16 "$silence_file" trim 0.0 \
          "$(awk -v m="$hold_dur_ms" 'BEGIN{printf "%.3f", m/1000}')" \
          >/dev/null 2>&1; then
        log "sox silence failed for $file (range $pair)"
        for f in "${tmp_files[@]}"; do rm -f "$f"; done
        IFS="$oldIFS"
        return 1
      fi
      parts+=("$silence_file")
      tmp_files+=("$silence_file")
    fi

    sum_prior_holds_ms=$((sum_prior_holds_ms + hold_dur_ms))
    prev_cut_rec_ms=$cut_rec_ms
    IFS=';'
  done
  IFS="$oldIFS"

  # Tail: everything after the last split point
  local tail_file="$workdir/$channel_id-tail.wav"
  if ! sox "$file" "$tail_file" trim \
      "$(awk -v m="$prev_cut_rec_ms" 'BEGIN{printf "%.3f", m/1000}')" \
      >/dev/null 2>&1; then
    log "sox tail failed for $file"
    for f in "${tmp_files[@]}"; do rm -f "$f"; done
    return 1
  fi
  parts+=("$tail_file")
  tmp_files+=("$tail_file")

  local spliced_file="$file.spliced.wav"
  if ! sox "${parts[@]}" "$spliced_file" >/dev/null 2>&1; then
    log "sox concat failed for $file"
    for f in "${tmp_files[@]}"; do rm -f "$f"; done
    return 1
  fi

  mv -f "$spliced_file" "$file"
  for f in "${tmp_files[@]}"; do rm -f "$f"; done
  log "spliced holds into $file (ranges=$ranges)"
  return 0
}

# 1. Splice silence into the recording at hold positions (if any).
if [ -n "$hold_ranges" ]; then
  splice_holds "$record_file" "$hold_ranges" || log "splice_holds failed; uploading un-spliced file"
fi

# 2. sha512 + file size
sha512=$(shasum -a 512 "$record_file" 2>/dev/null | awk '{print $1}')
file_size=$(stat -c%s "$record_file" 2>/dev/null || echo 0)

# 3. aws s3 mv — the expensive part that used to block FS
endpoint_arg=""
if [ -n "${AWS_ENDPOINT_URL:-}" ]; then
  endpoint_arg="--endpoint-url $AWS_ENDPOINT_URL"
fi

filename="${record_file##*/}"
if ! aws $endpoint_arg s3 mv "$record_file" "s3://$bucket/$subdomain/recording/$filename" >/dev/null 2>&1; then
  log "aws s3 mv failed for $record_file"
  exit 1
fi

# 4. Fire the upload-completed CUSTOM event back into FS via raw ESL.
# `fs_cli -x sendevent` can't carry the multiline body cleanly, so we
# speak ESL directly. Event socket is bound on the container's docker-
# network IP (127.0.0.1 is ACL-rejected here), so we use `hostname -I`.
fs_ip=$(hostname -I | awk '{print $1}')

python3 - "$fs_ip" "$subdomain" "$call_story_id" "$channel_id" "$filename" "$file_size" "$record_file" "$sha512" <<'PY' >/dev/null 2>&1
import socket, sys, time
ip, subdomain, call_story_id, channel_id, filename, file_size, record_file, sha512 = sys.argv[1:]
s = socket.socket()
s.settimeout(5)
s.connect((ip, 8021))
s.sendall(b"auth ClueCon\n\n")
time.sleep(0.05)
try:
    s.recv(4096)
except Exception:
    pass
body = (
    f"sendevent CUSTOM\n"
    f"Event-Subclass: comcent::s3UploadCompleted\n"
    f"Subdomain: {subdomain}\n"
    f"Call-Story-Id: {call_story_id}\n"
    f"Channel-Id: {channel_id}\n"
    f"Filename: {filename}\n"
    f"File-Size: {file_size}\n"
    f"Record-File-Path: {record_file}\n"
    f"SHA-512: {sha512}\n\n"
)
s.sendall(body.encode())
time.sleep(0.05)
try:
    s.recv(4096)
except Exception:
    pass
s.close()
PY

log "uploaded $filename (${file_size}B) and fired completion event for call=$call_story_id"
