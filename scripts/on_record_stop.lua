-- Fire-and-forget hand-off to s3_upload_bg.sh.
--
-- Everything expensive (sox hold-splicing, shasum, `aws s3 mv`,
-- pushing the comcent::s3UploadCompleted CUSTOM event back into FS)
-- runs in a detached shell process, so this hook returns in microseconds
-- and never blocks FS's event dispatch thread.

local bucketName     = event:getHeader("variable_comcent_recording_bucket_name")
local subdomain      = event:getHeader("variable_comcent_subdomain")
local channelId      = event:getHeader("Unique-ID")
local callStoryId    = event:getHeader("variable_comcent_context_id")
local recordFilePath = event:getHeader("Record-File-Path")
local holdRanges     = event:getHeader("variable_comcent_hold_ranges") or ""

-- Shell-escape a value for single-quoted context.
local function shq(s)
  if s == nil then return "''" end
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

if bucketName == nil or subdomain == nil or channelId == nil
   or callStoryId == nil or recordFilePath == nil then
  freeswitch.consoleLog("err",
    string.format("on_record_stop: missing required header (bucket=%s sub=%s ch=%s call=%s file=%s)\n",
      tostring(bucketName), tostring(subdomain), tostring(channelId),
      tostring(callStoryId), tostring(recordFilePath)))
  return
end

local command = string.format(
  "/scripts/s3_upload_bg.sh %s %s %s %s %s %s </dev/null >/dev/null 2>&1 &",
  shq(recordFilePath), shq(bucketName), shq(subdomain),
  shq(channelId), shq(callStoryId), shq(holdRanges))

os.execute(command)
