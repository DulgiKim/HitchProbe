-- Core.lua
-- Records every frame that takes longer than a threshold, with:
--   * the addons that used the most CPU in that frame (C_AddOnProfiler, when the client has it),
--   * the game events seen just before it (including group and addon-message events),
--   * whether a Lua garbage-collection step happened (total Lua memory dropped),
--   * combat / moving / world map / group state.
-- Loading screens and the first seconds after them are skipped.
-- Never registers COMBAT_LOG_EVENT* (WoW Forever blocks addons that do).

local ADDON_NAME, ns = ...
local L = ns.L

local Core = {}
ns.Core = Core

local MAX_HITCHES = 300
local EVENT_WINDOW = 1.0      -- seconds of events kept before a hitch
local SETTLE_AFTER_LOAD = 10  -- seconds ignored after a loading screen
local GC_DROP_KB = 1024       -- memory drop between frames treated as a GC step (1 MB)
local TOP_ADDONS = 4
local MIN_ADDON_MS = 0.5
-- An addon is named as the cause when it used at least this much of the frame.
local CAUSE_SHARE = 0.3
local CAUSE_MIN_MS = 15

local DEFAULTS = { thresholdMs = 60, alertMs = 150, alert = true, alertChat = false }

local db
local loading = true
local settleUntil = 0
local recentEvents = {}       -- ring of { time, name }
local lastMemory = collectgarbage("count")
local listeners = {}

function Core.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffHitchProbe|r " .. tostring(msg))
end

function Core.DB() return db end

--- fn(entry) is called after each recorded hitch.
function Core.OnHitch(fn) listeners[#listeners + 1] = fn end

---------------------------------------------------------------------------------------------
-- Per-addon CPU from the client profiler
---------------------------------------------------------------------------------------------

local profiler = C_AddOnProfiler
local metricLast
if profiler and profiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
    metricLast = Enum.AddOnProfilerMetric.LastTime or Enum.AddOnProfilerMetric.RecentAverageTime
end

function Core.HasProfiler() return metricLast ~= nil end

local addonNames
local function LoadedAddons()
    if addonNames then return addonNames end
    addonNames = {}
    local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
    for i = 1, num do
        local name = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)(i)
        if name and loaded then addonNames[#addonNames + 1] = name end
    end
    return addonNames
end

--- Addons that used the most time in the last frame ({ {name, ms}, ... }) and the total
--- time of all addons in that frame.
local function TopAddons()
    if not metricLast then return nil, nil end
    local list, total = {}, 0
    for _, name in ipairs(LoadedAddons()) do
        local ok, ms = pcall(profiler.GetAddOnMetric, name, metricLast)
        if ok and type(ms) == "number" and ms > 0 then
            total = total + ms
            if ms >= MIN_ADDON_MS then list[#list + 1] = { name, ms } end
        end
    end
    if profiler.GetOverallMetric then
        local ok, ms = pcall(profiler.GetOverallMetric, metricLast)
        if ok and type(ms) == "number" and ms > 0 then total = ms end
    end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i = #list, TOP_ADDONS + 1, -1 do list[i] = nil end
    return list, total
end

--- The addon to blame for a hitch, or nil when the game itself used most of the frame.
function Core.Cause(h)
    local top = h.addons and h.addons[1]
    if top and top[2] >= CAUSE_MIN_MS and top[2] >= h.ms * CAUSE_SHARE then return top[1], top[2] end
    return nil
end

---------------------------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------------------------

local function EventsBefore(now)
    local names, seen = {}, {}
    for i = #recentEvents, 1, -1 do
        local e = recentEvents[i]
        if now - e[1] > EVENT_WINDOW then break end
        local key = e[2]
        seen[key] = (seen[key] or 0) + 1
        if seen[key] == 1 then names[#names + 1] = key end
    end
    for i, key in ipairs(names) do
        if seen[key] > 1 then names[i] = key .. "x" .. seen[key] end
    end
    return names
end

local function InGroup()
    if IsInGroup then return IsInGroup() end
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end

local function Record(frameMs, now, gcKB)
    local addons, total = TopAddons()
    local entry = {
        t = date("%H:%M:%S"),
        ms = math.floor(frameMs + 0.5),
        addons = addons,
        addonMs = total and math.floor(total * 10 + 0.5) / 10 or nil,
        events = EventsBefore(now),
        gcMB = gcKB and math.floor(gcKB / 102.4 + 0.5) / 10 or nil,
        combat = InCombatLockdown() or nil,
        moving = (GetUnitSpeed and GetUnitSpeed("player") or 0) > 0 or nil,
        map = (WorldMapFrame and WorldMapFrame:IsShown()) or nil,
        group = InGroup() or nil,
        zone = GetRealZoneText and GetRealZoneText() or nil,
    }
    local list = db.hitches
    list[#list + 1] = entry
    while #list > MAX_HITCHES do table.remove(list, 1) end
    for _, fn in ipairs(listeners) do pcall(fn, entry) end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function(_, elapsed)
    local memory = collectgarbage("count")
    local drop = lastMemory - memory
    lastMemory = memory
    if not db or loading then return end
    local now = GetTime()
    if now < settleUntil then return end
    local frameMs = elapsed * 1000
    if frameMs >= db.thresholdMs or (db.alert and frameMs >= db.alertMs) then
        Record(frameMs, now, drop >= GC_DROP_KB and drop or nil)
    end
end)

---------------------------------------------------------------------------------------------
-- Events (a fixed list; RegisterAllEvents would include the blocked combat log)
---------------------------------------------------------------------------------------------

local WATCHED = {
    -- levelling and quests
    "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM",
    "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
    "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "GOSSIP_SHOW", "GOSSIP_CLOSED",
    "UNIT_QUEST_LOG_CHANGED", "CHAT_MSG_COMBAT_FACTION_CHANGE", "UPDATE_FACTION", "SKILL_LINES_CHANGED",
    -- world
    "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "AREA_POIS_UPDATED",
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "LOOT_OPENED", "LOOT_CLOSED", "CHAT_MSG_LOOT",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "TAXIMAP_OPENED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "CRITERIA_UPDATE",
    -- groups: joining a party wakes up unit frames, raid tools and addon messages
    "PARTY_INVITE_REQUEST", "GROUP_JOINED", "GROUP_FORMED", "GROUP_LEFT", "GROUP_ROSTER_UPDATE",
    "PARTY_LEADER_CHANGED", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE", "RAID_ROSTER_UPDATE",
    "UNIT_CONNECTION", "READY_CHECK", "INSPECT_READY", "CHAT_MSG_ADDON", "CHAT_MSG_PARTY", "CHAT_MSG_WHISPER",
    "LFG_LIST_APPLICANT_UPDATED", "LFG_LIST_APPLICANT_LIST_UPDATED", "LFG_LIST_SEARCH_RESULTS_RECEIVED",
    -- loading
    "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_ENTERING_WORLD", "ADDON_LOADED",
}

local function Push(name)
    recentEvents[#recentEvents + 1] = { GetTime(), name }
    if #recentEvents > 600 then
        local keep = {}
        for i = #recentEvents - 299, #recentEvents do keep[#keep + 1] = recentEvents[i] end
        recentEvents = keep
    end
end

local events = CreateFrame("Frame")
for _, name in ipairs(WATCHED) do pcall(events.RegisterEvent, events, name) end
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        addonNames = nil -- load-on-demand addons join the list
        if arg1 == ADDON_NAME then
            HitchProbeDB = HitchProbeDB or {}
            db = HitchProbeDB
            db.hitches = db.hitches or {}
            for k, v in pairs(DEFAULTS) do
                if db[k] == nil then db[k] = v end
            end
        end
        return
    end
    if event == "LOADING_SCREEN_ENABLED" then
        loading = true
    elseif event == "LOADING_SCREEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then
        loading = false
        settleUntil = GetTime() + SETTLE_AFTER_LOAD
    end
    if event == "CHAT_MSG_ADDON" and type(arg1) == "string" then
        -- The prefix tells which addon is talking (e.g. a party-sync addon).
        Push("CHAT_MSG_ADDON:" .. arg1:sub(1, 16))
    else
        Push(event)
    end
end)

---------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------

local function Ms(v) return string.format("%.0f", v) end

--- One hitch on one line. `plain` leaves out color codes (for the copied report).
function Core.Describe(h, plain)
    local parts = { string.format("%s  %d ms", h.t, h.ms) }
    local cause, causeMs = Core.Cause(h)
    if h.addons and h.addons[1] then
        local a = {}
        for _, x in ipairs(h.addons) do a[#a + 1] = x[1] .. " " .. Ms(x[2]) end
        local text = "[" .. table.concat(a, ", ") .. "]"
        if cause and not plain then text = "|cffff8040" .. text .. "|r" end
        parts[#parts + 1] = text
        if not cause then parts[#parts + 1] = "(" .. L.CAUSE_GAME .. ")" end
    elseif h.addonMs then
        parts[#parts + 1] = "[" .. L.CAUSE_GAME .. "]"
    end
    if h.gcMB then parts[#parts + 1] = "GC " .. h.gcMB .. "MB" end
    local flags = {}
    if h.combat then flags[#flags + 1] = L.FLAG_COMBAT end
    if h.moving then flags[#flags + 1] = L.FLAG_MOVING end
    if h.map then flags[#flags + 1] = L.FLAG_MAP end
    if h.group then flags[#flags + 1] = L.FLAG_GROUP end
    if flags[1] then parts[#parts + 1] = table.concat(flags, "/") end
    if h.events and h.events[1] then
        local e = "<- " .. table.concat(h.events, " ", 1, math.min(#h.events, 6))
        parts[#parts + 1] = plain and e or ("|cff999999" .. e .. "|r")
    end
    return table.concat(parts, "  ")
end

local function EventName(e) return (e:gsub("x%d+$", "")) end

--- Summary lines: totals, causes by addon, and the most common preceding events.
function Core.SummaryLines()
    local list = db.hitches
    if #list == 0 then
        local lines = { string.format(L.SUMMARY_NONE, db.thresholdMs) }
        if not metricLast then lines[2] = L.NO_PROFILER end
        return lines
    end
    local blame, client, worst, gc = {}, 0, 0, 0
    local eventCount = {}
    for _, h in ipairs(list) do
        worst = math.max(worst, h.ms)
        if h.gcMB then gc = gc + 1 end
        local cause, causeMs = Core.Cause(h)
        if cause then
            local b = blame[cause] or { n = 0, ms = 0, worst = 0 }
            b.n, b.ms, b.worst = b.n + 1, b.ms + causeMs, math.max(b.worst, causeMs)
            blame[cause] = b
        else
            client = client + 1
        end
        local seen = {}
        for _, e in ipairs(h.events or {}) do
            local name = EventName(e)
            if not seen[name] then
                seen[name] = true
                eventCount[name] = (eventCount[name] or 0) + 1
            end
        end
    end
    local lines = { string.format(L.SUMMARY_HEAD, #list, db.thresholdMs, worst, gc), L.SUMMARY_CAUSES }
    local rows = {}
    for name, b in pairs(blame) do rows[#rows + 1] = { name, b } end
    table.sort(rows, function(a, b) return a[2].n > b[2].n end)
    for i = 1, math.min(6, #rows) do
        local b = rows[i][2]
        lines[#lines + 1] = string.format(L.SUMMARY_ADDON, rows[i][1], b.n, Ms(b.ms / b.n), Ms(b.worst))
    end
    if client > 0 then lines[#lines + 1] = string.format(L.SUMMARY_CLIENT, client) end
    local ev = {}
    for name, n in pairs(eventCount) do ev[#ev + 1] = { name, n } end
    table.sort(ev, function(a, b) return a[2] > b[2] end)
    if ev[1] then
        lines[#lines + 1] = L.SUMMARY_EVENTS
        for i = 1, math.min(5, #ev) do lines[#lines + 1] = string.format(L.SUMMARY_EVENT, ev[i][1], ev[i][2]) end
    end
    if not metricLast then lines[#lines + 1] = L.NO_PROFILER end
    return lines
end

--- Plain-text report for bug reports.
function Core.ReportText()
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "?"
    local build, buildNumber, _, interface = GetBuildInfo()
    local lines = {
        string.format("HitchProbe %s | client %s (%s, %s) | %s", version, tostring(build), tostring(buildNumber),
            tostring(interface), date("%Y-%m-%d %H:%M")),
        "",
    }
    for _, line in ipairs(Core.SummaryLines()) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    local list = db.hitches
    for i = #list, math.max(1, #list - 49), -1 do
        lines[#lines + 1] = Core.Describe(list[i], true) .. (list[i].zone and ("  @" .. list[i].zone) or "")
    end
    return table.concat(lines, "\n")
end

function Core.Reset()
    db.hitches = {}
    Core.Print(L.RESET_DONE)
end

-- Exposed for tests.
Core._events = events
Core._frame = frame
