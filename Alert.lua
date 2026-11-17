-- Alert.lua
-- On-screen banner at the top of the screen for big hitches: how long the frame took,
-- which addon caused it (or the game itself) and the events just before it.

local ADDON_NAME, ns = ...
local L, Core = ns.L, ns.Core

local SHOW_TIME = 6      -- seconds fully visible
local FADE_TIME = 1.5
local REPEAT_WINDOW = 10 -- hitches within this many seconds are counted on one banner
-- Frequent background events say little about the cause; listed after the others.
local NOISY = {
    NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true, UPDATE_MOUSEOVER_UNIT = true,
    PLAYER_TARGET_CHANGED = true, BAG_UPDATE = true, BAG_UPDATE_DELAYED = true, QUEST_LOG_UPDATE = true,
    CRITERIA_UPDATE = true, CHAT_MSG_SYSTEM = true,
}

local banner, line1, line2, line3, hint
local shownAt, repeatCount, lastAlert = 0, 0, -1e9

local function EventsText(events)
    local first, later = {}, {}
    for _, e in ipairs(events or {}) do
        local name = e:gsub("x%d+$", "")
        if NOISY[name] then later[#later + 1] = e else first[#first + 1] = e end
    end
    for _, e in ipairs(later) do first[#first + 1] = e end
    if not first[1] then return nil end
    return table.concat(first, ", ", 1, math.min(#first, 4))
end

local function CauseText(h)
    local cause, causeMs = Core.Cause(h)
    if cause then
        local parts = { string.format(L.CAUSE_ADDON, cause, string.format("%.0f", causeMs)) }
        for i = 2, math.min(3, #(h.addons or {})) do
            local a = h.addons[i]
            parts[#parts + 1] = string.format(L.CAUSE_ADDON, a[1], string.format("%.0f", a[2]))
        end
        return string.format(L.BANNER_CAUSE, table.concat(parts, "  ·  "))
    end
    if h.addonMs then return string.format(L.BANNER_CLIENT, string.format("%.0f", h.addonMs)) end
    return L.NO_PROFILER
end

local function Create()
    banner = CreateFrame("Button", "HitchProbeBanner", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    banner:SetSize(560, 74)
    banner:SetPoint("TOP", UIParent, "TOP", 0, -110)
    banner:SetFrameStrata("HIGH")
    if banner.SetBackdrop then
        banner:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        banner:SetBackdropColor(0.08, 0.02, 0.02, 0.85)
        banner:SetBackdropBorderColor(1, 0.35, 0.2, 0.9)
    end
    line1 = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    line1:SetPoint("TOP", 0, -9)
    line1:SetTextColor(1, 0.45, 0.3)
    line2 = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line2:SetPoint("TOP", line1, "BOTTOM", 0, -4)
    line2:SetWidth(540)
    line3 = banner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    line3:SetPoint("TOP", line2, "BOTTOM", 0, -3)
    line3:SetWidth(540)
    hint = banner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -8, 5)
    hint:SetText(L.BANNER_HINT)
    banner:SetScript("OnClick", function()
        banner:Hide()
        if ns.UI then ns.UI.Open() end
    end)
    banner:SetScript("OnUpdate", function(self)
        local age = GetTime() - shownAt
        if age > SHOW_TIME + FADE_TIME then
            self:Hide()
        elseif age > SHOW_TIME then
            self:SetAlpha(1 - (age - SHOW_TIME) / FADE_TIME)
        end
    end)
    banner:Hide()
end

local function Show(h)
    if not banner then Create() end
    local now = GetTime()
    repeatCount = (now - lastAlert <= REPEAT_WINDOW) and repeatCount + 1 or 1
    lastAlert = now
    local title = string.format(L.BANNER_TITLE, h.ms)
    if repeatCount > 1 then title = title .. string.format(L.BANNER_REPEAT, repeatCount) end
    line1:SetText(title)
    line2:SetText(CauseText(h))
    local events = EventsText(h.events)
    line3:SetText(events and string.format(L.BANNER_BEFORE, events) or "")
    shownAt = now
    banner:SetAlpha(1)
    banner:Show()
    local db = Core.DB()
    if db.alertChat then
        Core.Print(title .. " - " .. CauseText(h) .. (events and (" - " .. string.format(L.BANNER_BEFORE, events)) or ""))
    end
end

Core.OnHitch(function(h)
    local db = Core.DB()
    if db.alert and h.ms >= db.alertMs then Show(h) end
end)

-- Exposed for tests.
ns.Alert = { _Show = Show, _CauseText = CauseText, _EventsText = EventsText }
