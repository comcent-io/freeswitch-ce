-- Records CHANNEL_HOLD / CHANNEL_UNHOLD timestamps (in milliseconds relative
-- to the channel's answer time) into the channel variable
-- `comcent_hold_ranges` as semicolon-separated "startMs-endMs" pairs.  The
-- value is read by on_record_stop.lua to splice silence into the recording
-- at exactly the hold position — covering the gap left when a WebRTC leg
-- goes media-inactive during hold and no RTP frames reach the recording bug.

local eventName = event:getHeader("Event-Name")
local uuid = event:getHeader("Unique-ID")
local eventTimeUs = tonumber(event:getHeader("Event-Date-Timestamp")) or 0
local api = freeswitch.API()

local answeredUs = tonumber(api:executeString(
  "uuid_getvar " .. uuid .. " start_epoch"
)) or 0
if answeredUs == 0 then
  -- Fall back to channel create time if answer time isn't populated yet
  answeredUs = tonumber(api:executeString(
    "uuid_getvar " .. uuid .. " start_stamp"
  )) or 0
end

local session = freeswitch.Session(uuid)
if not session:ready() then
  return
end

local answeredStr = session:getVariable("answered_time")
  or session:getVariable("answer_epoch")
local answeredMs = tonumber(answeredStr) or 0

-- Prefer the precise Caller-Channel-Answered-Time header (epoch µs).
local answeredHeaderUs = tonumber(
  event:getHeader("Caller-Channel-Answered-Time")
) or 0

local answerUs
if answeredHeaderUs > 0 then
  answerUs = answeredHeaderUs
elseif answeredMs > 0 then
  answerUs = answeredMs * 1000
else
  -- Absolute timestamps; fall back to using eventTime directly.
  answerUs = 0
end

local relMs
if answerUs > 0 and eventTimeUs > 0 then
  relMs = math.floor((eventTimeUs - answerUs) / 1000)
else
  relMs = 0
end

if eventName == "CHANNEL_HOLD" then
  session:setVariable("comcent_hold_start_ms", tostring(relMs))
  freeswitch.consoleLog("info",
    string.format("hold_start uuid=%s rel_ms=%d\n", uuid, relMs))
elseif eventName == "CHANNEL_UNHOLD" then
  local startMs = tonumber(session:getVariable("comcent_hold_start_ms")) or 0
  local endMs = relMs
  if endMs > startMs then
    local existing = session:getVariable("comcent_hold_ranges") or ""
    local pair = string.format("%d-%d", startMs, endMs)
    local combined = (existing == "" and pair) or (existing .. ";" .. pair)
    session:setVariable("comcent_hold_ranges", combined)
    session:setVariable("comcent_hold_start_ms", "")
    freeswitch.consoleLog("info",
      string.format("hold_range uuid=%s %s\n", uuid, pair))
  end
end
