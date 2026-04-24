uuid = event:getHeader("Unique-ID")
-- freeswitch.consoleLog("info", "uuid *************** " .. uuid .. "\n");
fileNameBoth = "/tmp/" .. uuid .. "-both.wav"
fileNameIn = "/tmp/" .. uuid .. "-in.wav"
max_len_secs = 0
silence_threshold = -30
silence_secs = -1
api = freeswitch.API();
-- Keep recording during hold so the held period shows as silence/MOH in the
-- recording instead of being omitted (which would shorten the agent's file).
api:executeString("uuid_setvar " .. uuid .. " record_waste_resources true");
api:executeString("uuid_setvar " .. uuid .. " record_pause_on_hold false");
api:executeString("uuid_record " .. uuid .. " start " .. fileNameBoth);
freeswitch.consoleLog("info", "Started recording " .. fileNameBoth .. "\n");
api:executeString("uuid_setvar " .. uuid .. " RECORD_READ_ONLY true");
api:executeString("uuid_record " .. uuid .. " start " .. fileNameIn);
freeswitch.consoleLog("info", "Started recording " .. fileNameIn  .. "\n");
