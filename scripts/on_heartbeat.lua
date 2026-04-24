-- on_heartbeat.lua
-- Fires a custom heartbeat event with sip_bind_ip included

-- Get the sip_bind_ip from global variables
local sip_bind_ip = freeswitch.getGlobalVariable("sip_bind_ip")

-- Get all headers from the original HEARTBEAT event
local core_uuid = event:getHeader("Core-UUID")
local hostname = event:getHeader("FreeSWITCH-Hostname")
local ipv4 = event:getHeader("FreeSWITCH-IPv4")
local ipv6 = event:getHeader("FreeSWITCH-IPv6")
local switchname = event:getHeader("FreeSWITCH-Switchname")
local version = event:getHeader("FreeSWITCH-Version")
local uptime = event:getHeader("Up-Time")
local uptime_msec = event:getHeader("Uptime-msec")
local session_count = event:getHeader("Session-Count")
local max_sessions = event:getHeader("Max-Sessions")
local session_per_sec = event:getHeader("Session-Per-Sec")
local session_per_sec_last = event:getHeader("Session-Per-Sec-Last")
local session_per_sec_max = event:getHeader("Session-Per-Sec-Max")
local session_per_sec_fivemin = event:getHeader("Session-Per-Sec-FiveMin")
local session_since_startup = event:getHeader("Session-Since-Startup")
local session_peak_max = event:getHeader("Session-Peak-Max")
local session_peak_fivemin = event:getHeader("Session-Peak-FiveMin")
local idle_cpu = event:getHeader("Idle-CPU")
local event_info = event:getHeader("Event-Info")

-- Create custom heartbeat event with sip_bind_ip
local custom_event = freeswitch.Event("custom", "comcent::heartbeat")

-- Add original heartbeat headers
custom_event:addHeader("Core-UUID", core_uuid or "")
custom_event:addHeader("FreeSWITCH-Hostname", hostname or "")
custom_event:addHeader("FreeSWITCH-IPv4", ipv4 or "")
custom_event:addHeader("FreeSWITCH-IPv6", ipv6 or "")
custom_event:addHeader("FreeSWITCH-Switchname", switchname or "")
custom_event:addHeader("FreeSWITCH-Version", version or "")
custom_event:addHeader("Up-Time", uptime or "")
custom_event:addHeader("Uptime-msec", uptime_msec or "")
custom_event:addHeader("Session-Count", session_count or "")
custom_event:addHeader("Max-Sessions", max_sessions or "")
custom_event:addHeader("Session-Per-Sec", session_per_sec or "")
custom_event:addHeader("Session-Per-Sec-Last", session_per_sec_last or "")
custom_event:addHeader("Session-Per-Sec-Max", session_per_sec_max or "")
custom_event:addHeader("Session-Per-Sec-FiveMin", session_per_sec_fivemin or "")
custom_event:addHeader("Session-Since-Startup", session_since_startup or "")
custom_event:addHeader("Session-Peak-Max", session_peak_max or "")
custom_event:addHeader("Session-Peak-FiveMin", session_peak_fivemin or "")
custom_event:addHeader("Idle-CPU", idle_cpu or "")
custom_event:addHeader("Event-Info", event_info or "")

-- Add our custom sip_bind_ip header - THIS IS THE KEY ADDITION
custom_event:addHeader("SIP-Bind-IP", sip_bind_ip or ipv4 or "")

-- Fire the custom event
custom_event:fire()

