-- UI.lua
-- Results window (summary + recent hitches), copyable report, thresholds, slash commands.

local ADDON_NAME, ns = ...
local L, Core = ns.L, ns.Core

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 640, 480
local LIST_COUNT = 100
local STEP_RECORD, MIN_RECORD = 10, 20
local STEP_ALERT, MIN_ALERT = 25, 50

local frame, summaryText, listText, listChild, recordValue, alertValue, alertCheck, chatCheck
local copyFrame, copyBox

local function Gold(text) return "|cffffd100" .. text .. "|r" end

---------------------------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------------------------

local function Backdrop(f)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
    f:SetBackdropBorderColor(0.4, 0.75, 1, 1)
end

local function Button(parent, width, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function CheckBox(parent, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    label:SetText(text)
    cb.label = label
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
end

--- "Label  [-] 60 ms [+]" control. get/set work on the saved value.
local function Stepper(parent, label, get, set, step, minimum)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(190, 22)
    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT")
    text:SetText(label)
    local minus = Button(holder, 24, "-", function() set(math.max(minimum, get() - step)) end)
    minus:SetPoint("LEFT", text, "RIGHT", 6, 0)
    local value = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    value:SetWidth(56)
    local plus = Button(holder, 24, "+", function() set(get() + step) end)
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    holder.value = value
    return holder
end

---------------------------------------------------------------------------------------------
-- Copy window
---------------------------------------------------------------------------------------------

local function ShowCopy()
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "HitchProbeCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        copyFrame:SetSize(600, 400)
        copyFrame:SetPoint("CENTER", 0, 20)
        copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        copyFrame:EnableMouse(true)
        Backdrop(copyFrame)
        local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText(L.COPY_TITLE)
        local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        local scroll = CreateFrame("ScrollFrame", "HitchProbeCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -36)
        scroll:SetPoint("BOTTOMRIGHT", -32, 14)
        copyBox = CreateFrame("EditBox", nil, scroll)
        copyBox:SetMultiLine(true)
        copyBox:SetAutoFocus(false)
        copyBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        copyBox:SetWidth(550)
        copyBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        scroll:SetScrollChild(copyBox)
        tinsert(UISpecialFrames, "HitchProbeCopyFrame")
    end
    copyBox:SetText(Core.ReportText())
    copyFrame:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
end

---------------------------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------------------------

function UI.Render()
    if not frame or not frame:IsShown() then return end
    local db = Core.DB()
    local summary = Core.SummaryLines()
    for i, line in ipairs(summary) do
        if line == L.SUMMARY_CAUSES or line == L.SUMMARY_EVENTS then summary[i] = Gold(line) end
    end
    summaryText:SetText(table.concat(summary, "\n"))

    local lines = { Gold(L.LIST_TITLE) }
    local list = db.hitches
    for i = #list, math.max(1, #list - LIST_COUNT + 1), -1 do
        local h = list[i]
        local line = Core.Describe(h)
        if h.ms >= db.alertMs then line = "|cffff6040!|r " .. line end
        lines[#lines + 1] = line
    end
    listText:SetText(table.concat(lines, "\n"))
    local height = listText.GetStringHeight and listText:GetStringHeight() or 0
    listChild:SetHeight(math.max((height or 0) + 8, 10))

    recordValue.value:SetText(string.format(L.MS, db.thresholdMs))
    alertValue.value:SetText(string.format(L.MS, db.alertMs))
    alertCheck:SetChecked(db.alert and true or false)
    chatCheck:SetChecked(db.alertChat and true or false)
end

local function Create()
    frame = CreateFrame("Frame", "HitchProbeFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        Core.DB().position = { point, relativePoint, x, y }
    end)
    Backdrop(frame)
    local pos = Core.DB().position
    if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER") end

    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(ns.ICON)
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", 12, -9)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or ""
    title:SetText(L.TITLE .. " |cff888888" .. version .. "|r")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryText:SetPoint("TOPLEFT", 16, -40)
    summaryText:SetPoint("RIGHT", -16, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetJustifyV("TOP")
    summaryText:SetHeight(150)

    local scroll = CreateFrame("ScrollFrame", "HitchProbeListScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -196)
    scroll:SetPoint("BOTTOMRIGHT", -34, 76)
    listChild = CreateFrame("Frame", nil, scroll)
    listChild:SetSize(WIDTH - 52, 10)
    scroll:SetScrollChild(listChild)
    listText = listChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listText:SetPoint("TOPLEFT", 2, -2)
    listText:SetWidth(WIDTH - 56)
    listText:SetJustifyH("LEFT")
    listText:SetJustifyV("TOP")
    if listText.SetSpacing then listText:SetSpacing(2) end

    local db = Core.DB()
    recordValue = Stepper(frame, L.SET_RECORD, function() return Core.DB().thresholdMs end, function(v)
        Core.DB().thresholdMs = v
        UI.Render()
    end, STEP_RECORD, MIN_RECORD)
    recordValue:SetPoint("BOTTOMLEFT", 16, 44)
    alertValue = Stepper(frame, L.SET_ALERT, function() return Core.DB().alertMs end, function(v)
        Core.DB().alertMs = v
        UI.Render()
    end, STEP_ALERT, MIN_ALERT)
    alertValue:SetPoint("LEFT", recordValue, "RIGHT", 20, 0)

    alertCheck = CheckBox(frame, L.SET_ALERT_ON, function(checked) Core.DB().alert = checked end)
    alertCheck:SetPoint("BOTTOMLEFT", 12, 12)
    chatCheck = CheckBox(frame, L.SET_ALERT_CHAT, function(checked) Core.DB().alertChat = checked end)
    chatCheck:SetPoint("LEFT", alertCheck.label, "RIGHT", 16, -1)

    local reset = Button(frame, 110, L.BTN_RESET, function()
        Core.Reset()
        UI.Render()
    end)
    reset:SetPoint("BOTTOMRIGHT", -14, 12)
    local copy = Button(frame, 110, L.BTN_COPY, ShowCopy)
    copy:SetPoint("RIGHT", reset, "LEFT", -6, 0)

    tinsert(UISpecialFrames, "HitchProbeFrame")
    frame:SetScript("OnShow", UI.Render)
    frame:Hide()
end

function UI.Open()
    if not Core.DB() then return end
    if not frame then Create() end
    frame:Show()
end

function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Open() end
end

-- New hitches show up while the window is open.
Core.OnHitch(function() UI.Render() end)

---------------------------------------------------------------------------------------------
-- Slash commands and addon compartment
---------------------------------------------------------------------------------------------

SLASH_HITCHPROBE1 = "/hitch"
SLASH_HITCHPROBE2 = "/hitchprobe"
SlashCmdList.HITCHPROBE = function(msg)
    local db = Core.DB()
    if not db then return end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "reset" then
        Core.Reset()
        UI.Render()
    elseif cmd == "ms" and tonumber(arg) then
        db.thresholdMs = math.max(MIN_RECORD, math.floor(tonumber(arg)))
        Core.Print(string.format(L.THRESHOLD, db.thresholdMs))
        UI.Render()
    elseif cmd == "alert" then
        if arg == "off" then
            db.alert = false
            Core.Print(L.ALERT_OFF)
        elseif arg == "on" then
            db.alert = true
            Core.Print(L.ALERT_ON)
        elseif tonumber(arg) then
            db.alert = true
            db.alertMs = math.max(MIN_ALERT, math.floor(tonumber(arg)))
            Core.Print(string.format(L.ALERT_THRESHOLD, db.alertMs))
        else
            Core.Print(L.HELP)
        end
        UI.Render()
    elseif cmd == "last" then
        for i = math.max(1, #db.hitches - 9), #db.hitches do Core.Print(Core.Describe(db.hitches[i])) end
    elseif cmd == "summary" then
        for _, line in ipairs(Core.SummaryLines()) do Core.Print(line) end
    elseif cmd == "help" then
        Core.Print(L.HELP)
    else
        UI.Toggle()
    end
end

function HitchProbe_OnAddonCompartmentClick() UI.Toggle() end
function HitchProbe_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.TITLE)
    GameTooltip:AddLine(L.COMPARTMENT_HINT, 1, 1, 1)
    GameTooltip:Show()
end
function HitchProbe_OnAddonCompartmentLeave() GameTooltip:Hide() end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function() Core.Print(L.LOADED) end)
