ManaGainedLite = {}
local frame = CreateFrame("Frame", "ManaGainedLiteFrame", UIParent)

-- Saved DB
if not ManaGainedLiteDB then
	ManaGainedLiteDB = {
		total = {},
		current = {},
		window = {
			point = "CENTER",
			relativePoint = "CENTER",
			x = 0,
			y = 0,
			width = 240,
			height = 120,
			scale = 1,
		},
	}
end

--Defaults
if not ManaGainedLiteDB.current then
	ManaGainedLiteDB.current = {}
end

if not ManaGainedLiteDB.total then
	ManaGainedLiteDB.total = {}
end

if not ManaGainedLiteDB.reportChannel then
	ManaGainedLiteDB.reportChannel = "SAY"
end

if not ManaGainedLiteDB.mode then
	ManaGainedLiteDB.mode = "total"
end

if ManaGainedLiteDB.combatOnly == nil then
	ManaGainedLiteDB.combatOnly = true
end

if not ManaGainedLiteDB.currentTime then
	ManaGainedLiteDB.currentTime = 0
end

if not ManaGainedLiteDB.totalTime then
	ManaGainedLiteDB.totalTime = 0
end

if ManaGainedLiteDB.locked == nil then
	ManaGainedLiteDB.locked = false
end

if not ManaGainedLiteDB.window.scale then
	ManaGainedLiteDB.window.scale = 1
end

-- LOCALS BELOW

-- Stored player bar click
local PendingDetailReportPlayer = nil

-- Combat state
local InCombat = false

--Update Accumulator
local TimerUpdateElapsed = 0
local TimerUpdateRate = 0.3333

-- Group roster
local Roster = {}

-- UI stuffs
local MeterFrame = nil
local BarFrames = {}
local HeaderText = nil
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local ClassCache = {}

-- Bar stuffs
local BAR_HEIGHT = 11
local BAR_SPACING = 4
local HEADER_SPACE = 28
local BOTTOM_SPACE = 10

---------------------------------------------------
-- OnUpdate
---------------------------------------------------

function ManaGainedLite:OnUpdate(elapsed)
	if ManaGainedLiteDB.combatOnly and not InCombat then
		return
	end

	ManaGainedLiteDB.currentTime = (ManaGainedLiteDB.currentTime or 0) + elapsed
	ManaGainedLiteDB.totalTime = (ManaGainedLiteDB.totalTime or 0) + elapsed

	TimerUpdateElapsed = TimerUpdateElapsed + elapsed
	if TimerUpdateElapsed >= TimerUpdateRate then
		TimerUpdateElapsed = 0
		self:UpdateWindow()
	end
end

---------------------------------------------------
-- Helpers
---------------------------------------------------

function ManaGainedLite:FormatTime(sec)
	if not sec then sec = 0 end

	local mins = math.floor(sec / 60)
	local secs = math.floor(math.mod(sec, 60))

	if secs < 10 then
		secs = "0"..secs
	end

	return mins..":"..secs
end

local function MGL_CommaValue(v)
	if not v then return "0" end
	local s = tostring(v)
	while true do
		local n, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		s = n
		if k == 0 then break end
	end
	return s
end

function ManaGainedLite:GetActiveTable()
	if ManaGainedLiteDB.mode == "total" then
		return ManaGainedLiteDB.total
	end
	return ManaGainedLiteDB.current
end

local function MGL_TableWipe(tbl)
	for k in pairs(tbl) do
		tbl[k] = nil
	end
end

function ManaGainedLite:GetMaxVisibleBars()
	if not MeterFrame then return 1 end

	local usableHeight = MeterFrame:GetHeight() - HEADER_SPACE - BOTTOM_SPACE
	local rowSize = BAR_HEIGHT + BAR_SPACING

	if usableHeight < BAR_HEIGHT then
		return 1
	end

	local bars = math.floor((usableHeight + BAR_SPACING) / rowSize)

	if bars < 1 then
		bars = 1
	end

	if bars > table.getn(BarFrames) then
		bars = table.getn(BarFrames)
	end

	return bars
end

function ManaGainedLite:UpdateClassCache()
	local name, class

	name = UnitName("player")
	if name then
		_, class = UnitClass("player")
		if class then
			ClassCache[name] = class
		end
	end

	name = UnitName("target")
	if name then
		_, class = UnitClass("target")
		if class then
			ClassCache[name] = class
		end
	end

	name = UnitName("mouseover")
	if name then
		_, class = UnitClass("mouseover")
		if class then
			ClassCache[name] = class
		end
	end

	for i=1, GetNumPartyMembers() do
		name = UnitName("party"..i)
		if name then
			_, class = UnitClass("party"..i)
			if class then
				ClassCache[name] = class
			end
		end
	end

	for i=1, GetNumRaidMembers() do
		name = UnitName("raid"..i)
		if name then
			_, class = UnitClass("raid"..i)
			if class then
				ClassCache[name] = class
			end
		end
	end
end

---------------------------------------------------
-- Print spell breakdown to chat frame (PLAYER ONLY)
---------------------------------------------------

function ManaGainedLite:PrintBreakdown(useTotal)
	local player = UnitName("player")
	local modeText = "Current"
	local shownTime = ManaGainedLiteDB.currentTime or 0

	if useTotal then
		modeText = "Total"
		shownTime = ManaGainedLiteDB.totalTime or 0
	end

	local rows, total = self:GetSpellBreakdown(player, useTotal)

	if total <= 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: no "..string.lower(modeText).." mana data.")
		return
	end

	DEFAULT_CHAT_FRAME:AddMessage(
		"|cff33ff99ManaGainedLite "..string.lower(modeText).." for "..player.." ["..self:FormatTime(shownTime).."]: "..MGL_CommaValue(total)
	)

	for i = 1, table.getn(rows) do
		local pct = 0
		if total > 0 then
			pct = rows[i].amount * 100 / total
		end

		DEFAULT_CHAT_FRAME:AddMessage(
			i..". "..rows[i].spell.." - "..MGL_CommaValue(rows[i].amount).." ("..string.format("%.1f", pct).."%%)"
		)
	end
end

function ManaGainedLite:GetBarColor(playerName)
	local class = ClassCache[playerName]

	if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local c = RAID_CLASS_COLORS[class]
		return c.r, c.g, c.b
	end

	return 0.65, 0.65, 0.65
end

---------------------------------------------------
-- Detailed player report output (spell breakdown)
---------------------------------------------------

function ManaGainedLite:SendDetailReport(playerName, channel)
	if not playerName then return end

	local useTotal = false
	local modeText = "Current"
	local shownTime = ManaGainedLiteDB.currentTime or 0

	if ManaGainedLiteDB.mode == "total" then
		useTotal = true
		modeText = "Total"
		shownTime = ManaGainedLiteDB.totalTime or 0
	end

	local rows, total = self:GetSpellBreakdown(playerName, useTotal)

	if total <= 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: no "..string.lower(modeText).." mana data for "..playerName..".")
		return
	end

	SendChatMessage(
		"ManaGainedLite - "..playerName.."'s Mana Gained - "..modeText.." ["..self:FormatTime(shownTime).."] - "..MGL_CommaValue(total),
		channel
	)

	local maxLines = 5
	for i = 1, maxLines do
		if not rows[i] then break end

		local pct = 0
		if total > 0 then
			pct = rows[i].amount * 100 / total
		end

		SendChatMessage(
			i..". "..rows[i].spell.." - "..MGL_CommaValue(rows[i].amount).." ("..string.format("%.1f", pct).."%%)",
			channel
		)
	end
end

---------------------------------------------------
-- Update group roster + ClassCache
---------------------------------------------------

function ManaGainedLite:UpdateRoster()
	MGL_TableWipe(Roster)

	local name, class

	-- Player
	name = UnitName("player")
	if name then
		Roster[name] = true
		_, class = UnitClass("player")
		if class then
			ClassCache[name] = class
		end
	end

	-- Party
	local numParty = GetNumPartyMembers()
	if numParty and numParty > 0 then
		for i = 1, numParty do
			local unit = "party"..i
			name = UnitName(unit)
			if name then
				Roster[name] = true
				_, class = UnitClass(unit)
				if class then
					ClassCache[name] = class
				end
			end
		end
	end

	-- Raid
	local numRaid = GetNumRaidMembers()
	if numRaid and numRaid > 0 then
		for i = 1, numRaid do
			local unit = "raid"..i
			name = UnitName(unit)
			if name then
				Roster[name] = true
				_, class = UnitClass(unit)
				if class then
					ClassCache[name] = class
				end
			end
		end
	end
end

---------------------------------------------------
-- Record mana + ClassCache
---------------------------------------------------

function ManaGainedLite:RecordMana(target, spell, amount)
	if not target or not spell or not amount or amount <= 0 then
		return
	end

	-- Try to cache class immediately if we don't know it yet
	if target and not ClassCache[target] then
		local playerName = UnitName("player")
		if target == playerName then
			local _, class = UnitClass("player")
			if class then
				ClassCache[target] = class
			end
		else
			for i = 1, GetNumRaidMembers() do
				local unit = "raid"..i
				if UnitName(unit) == target then
					local _, class = UnitClass(unit)
					if class then
						ClassCache[target] = class
					end
					break
				end
			end

			if not ClassCache[target] then
				for i = 1, GetNumPartyMembers() do
					local unit = "party"..i
					if UnitName(unit) == target then
						local _, class = UnitClass(unit)
						if class then
							ClassCache[target] = class
						end
						break
					end
				end
			end
		end
	end

	-- CURRENT
	if not ManaGainedLiteDB.current[target] then
		ManaGainedLiteDB.current[target] = {}
	end
	if not ManaGainedLiteDB.current[target][spell] then
		ManaGainedLiteDB.current[target][spell] = 0
	end
	ManaGainedLiteDB.current[target][spell] = ManaGainedLiteDB.current[target][spell] + amount

	-- TOTAL
	if not ManaGainedLiteDB.total[target] then
		ManaGainedLiteDB.total[target] = {}
	end
	if not ManaGainedLiteDB.total[target][spell] then
		ManaGainedLiteDB.total[target][spell] = 0
	end
	ManaGainedLiteDB.total[target][spell] = ManaGainedLiteDB.total[target][spell] + amount

	self:UpdateWindow()
end

---------------------------------------------------
-- Parse mana gain message
---------------------------------------------------

function ManaGainedLite:ParseMana(msg)
	if ManaGainedLiteDB.combatOnly and not InCombat then
		return
	end
	
	local player = UnitName("player")
	local target, amount, caster, spell

	-- You gain X Mana from Khanviction's Blessing of Wisdom.
	amount, caster, spell = string.match(msg, "You gain (%d+) Mana from (.+)'s (.+)%.")
	if amount then
		self:RecordMana(player, spell, tonumber(amount))
		return
	end

	-- You gain X Mana from Blessing of Wisdom.
	amount, spell = string.match(msg, "You gain (%d+) Mana from (.+)%.")
	if amount then
		self:RecordMana(player, spell, tonumber(amount))
		return
	end

	-- Aegistation gains X Mana from Khanviction's Blessing of Wisdom.
	target, amount, caster, spell =
		string.match(msg, "(.+) gains (%d+) Mana from (.+)'s (.+)%.")
	if target then
		self:RecordMana(target, spell, tonumber(amount))
		return
	end

	-- Aegistation gains X Mana from Blessing of Wisdom.
	target, amount, spell =
		string.match(msg, "(.+) gains (%d+) Mana from (.+)%.")
	if target then
		self:RecordMana(target, spell, tonumber(amount))
		return
	end
end

---------------------------------------------------
-- Data builders
---------------------------------------------------

function ManaGainedLite:GetActiveTotals()
	local rows = {}
	local grandTotal = 0
	local src = self:GetActiveTable()

	for playerName, spells in pairs(src) do
		local total = 0
		for _, amount in pairs(spells) do
			total = total + amount
		end

		if total > 0 then
			table.insert(rows, {
				name = playerName,
				total = total
			})
			grandTotal = grandTotal + total
		end
	end

	table.sort(rows, function(a, b)
		return a.total > b.total
	end)

	return rows, grandTotal
end

function ManaGainedLite:GetSpellBreakdown(name, useTotal)
	local sourceTable = useTotal and ManaGainedLiteDB.total or ManaGainedLiteDB.current
	local spells = sourceTable[name]
	local rows = {}
	local total = 0

	if not spells then
		return rows, 0
	end

	for spell, amount in pairs(spells) do
		if amount and amount > 0 then
			table.insert(rows, { spell = spell, amount = amount })
			total = total + amount
		end
	end

	table.sort(rows, function(a, b)
		return a.amount > b.amount
	end)

	return rows, total
end

---------------------------------------------------
-- Summary report output (meter totals) 1. Name1 2. Name2 etc.
---------------------------------------------------

function ManaGainedLite:SendSummaryReport(channel)
	local rows, grandTotal = self:GetActiveTotals()
	local modeText = "Current"
	local shownTime = ManaGainedLiteDB.currentTime or 0

	if ManaGainedLiteDB.mode == "total" then
		modeText = "Total"
		shownTime = ManaGainedLiteDB.totalTime or 0
	end

	if not rows or table.getn(rows) == 0 or grandTotal <= 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: no "..string.lower(modeText).." mana data to report.")
		return
	end

	SendChatMessage(
		"ManaGainedLite - "..modeText.." ["..self:FormatTime(shownTime).."] - "..MGL_CommaValue(grandTotal),
		channel
	)

	local maxLines = 5
	for i = 1, maxLines do
		if not rows[i] then break end

		local pct = 0
		if grandTotal > 0 then
			pct = rows[i].total * 100 / grandTotal
		end

		SendChatMessage(
			i..". "..rows[i].name.." - "..MGL_CommaValue(rows[i].total).." ("..string.format("%.1f", pct).."%%)",
			channel
		)
	end
end

---------------------------------------------------
-- Report output Details Spell1 % Spell2 % etc.
---------------------------------------------------

function ManaGainedLite:SendReport(channel)
	local player = UnitName("player")
	local useTotal = false
	local modeText = "Current"
	local shownTime = ManaGainedLiteDB.currentTime or 0

	if ManaGainedLiteDB.mode == "total" then
		useTotal = true
		modeText = "Total"
		shownTime = ManaGainedLiteDB.totalTime or 0
	end

	local rows, total = self:GetSpellBreakdown(player, useTotal)

	if total <= 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: no "..string.lower(modeText).." mana data to report.")
		return
	end

	SendChatMessage(
		"ManaGainedLite - "..player.."'s Mana Gained - "..modeText.." ["..self:FormatTime(shownTime).."] - "..MGL_CommaValue(total),
		channel
	)

	local maxLines = 3
	for i = 1, maxLines do
		if not rows[i] then break end

		local pct = 0
		if total > 0 then
			pct = (rows[i].amount * 100 / total)
		end

		SendChatMessage(
			i..". "..rows[i].spell.." - "..MGL_CommaValue(rows[i].amount).." ("..string.format("%.1f", pct).."%%)",
			channel
		)
	end
end

---------------------------------------------------
-- Popup Reset confirmation Data
---------------------------------------------------

StaticPopupDialogs["MGL_CONFIRM_RESET"] = {
	text = "Reset all ManaGainedLite data?",
	button1 = TEXT(YES),
	button2 = TEXT(NO),
	OnAccept = function()
		ManaGainedLiteDB.total = {}
		ManaGainedLiteDB.current = {}

		ManaGainedLiteDB.currentTime = 0
		ManaGainedLiteDB.totalTime = 0
		TimerUpdateElapsed = 0

		ManaGainedLite:UpdateWindow()
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: data reset.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

---------------------------------------------------
-- Popup for detailed player bar report
---------------------------------------------------

StaticPopupDialogs["MGL_CONFIRM_DETAIL_REPORT"] = {
	text = "Send detailed mana report?",
	button1 = TEXT(YES),
	button2 = TEXT(NO),
	OnAccept = function()
		if PendingDetailReportPlayer then
			local ch = ManaGainedLiteDB.reportChannel
			ManaGainedLite:SendDetailReport(PendingDetailReportPlayer, ch)
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

---------------------------------------------------
-- Popup Anti-Chat Spam confirmation  /Say /Party /Raid 1. 2. 3. 4. 5.
---------------------------------------------------

StaticPopupDialogs["MGL_CONFIRM_REPORT"] = {
	text = "Send ManaGainedLite summary report?",
	button1 = TEXT(YES),
	button2 = TEXT(NO),
	OnAccept = function()
		local ch = ManaGainedLiteDB.reportChannel
		ManaGainedLite:SendSummaryReport(ch)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

---------------------------------------------------
-- Window Tooltip
---------------------------------------------------

function ManaGainedLite:ShowTooltip(playerName)
	if not playerName then return end

	local src = self:GetActiveTable()
	local spells = src[playerName]
	if not spells then return end

	GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
	GameTooltip:ClearLines()

	local total = 0
	for _, v in pairs(spells) do
		total = total + v
	end

	if total <= 0 then return end

	GameTooltip:AddLine(playerName.." - "..MGL_CommaValue(total).." Mana", 1, 1, 1)

	local rows = {}

	for spell, val in pairs(spells) do
		table.insert(rows, {spell, val})
	end

	table.sort(rows, function(a, b)
		return a[2] > b[2]
	end)

	for i = 1, table.getn(rows) do
		local spell = rows[i][1]
		local val = rows[i][2]
		local pct = (val / total) * 100

		GameTooltip:AddDoubleLine(
			spell,
			MGL_CommaValue(val).." ("..string.format("%.1f", pct).."%)",
			1,1,1, 1,1,1
		)
	end

	GameTooltip:Show()
end

---------------------------------------------------
-- Window
---------------------------------------------------

function ManaGainedLite:CreateWindow()
	if MeterFrame then return end
	
	MeterFrame = CreateFrame("Frame", "ManaGainedLiteMeter", UIParent)
	MeterFrame:SetWidth(ManaGainedLiteDB.window.width or 217)
	MeterFrame:SetHeight(ManaGainedLiteDB.window.height or 117)
	MeterFrame:SetScale(ManaGainedLiteDB.window.scale or 1)
	MeterFrame:SetMovable(true)
	MeterFrame:SetResizable(true)
	MeterFrame:SetMinResize(200, 85)
	MeterFrame:SetClampedToScreen(true)
	MeterFrame:EnableMouse(true)
	MeterFrame:RegisterForDrag("LeftButton")
	MeterFrame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	MeterFrame:SetBackdropColor(0, 0, 0, 0.85)

	MeterFrame:SetPoint(
		ManaGainedLiteDB.window.point or "CENTER",
		UIParent,
		ManaGainedLiteDB.window.relativePoint or "CENTER",
		ManaGainedLiteDB.window.x or 0,
		ManaGainedLiteDB.window.y or 0
	)

	MeterFrame:SetScript("OnDragStart", function()
		this:StartMoving()
	end)

	MeterFrame:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		local point, _, relativePoint, x, y = this:GetPoint()
		ManaGainedLiteDB.window.point = point
		ManaGainedLiteDB.window.relativePoint = relativePoint
		ManaGainedLiteDB.window.x = x
		ManaGainedLiteDB.window.y = y
	end)

	HeaderText = MeterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	HeaderText:SetPoint("TOPLEFT", MeterFrame, "TOPLEFT", 8, -8)
	HeaderText:SetText("Mana Gained")
	
		-- Header separator
	local separator = MeterFrame:CreateTexture(nil, "ARTWORK")
	separator:SetHeight(1)
	separator:SetPoint("TOPLEFT", MeterFrame, "TOPLEFT", 6, -22.5)
	separator:SetPoint("TOPRIGHT", MeterFrame, "TOPRIGHT", -6, -22.5)
	separator:SetTexture(1, 1, 1, 0.18)

	MeterFrame.separator = separator
	
-- Close button
	local close = CreateFrame("Button", "ManaGainedLiteCloseButton", MeterFrame)
	close:SetWidth(20)
	close:SetHeight(20)
	close:SetPoint("TOPRIGHT", MeterFrame, "TOPRIGHT", -4, -3)

	close:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	close:SetBackdropColor(0.15, 0.05, 0.05, 0.9)

	close.text = close:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	close.text:SetPoint("CENTER", close, "CENTER", 0, 0)
	close.text:SetText("X")
	close.text:SetTextColor(1, 0.15, 0.15)

	close:SetScript("OnClick", function()
		MeterFrame:Hide()
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: window hidden. Type |cffffff00/mgl show|cff33ff99 to show it again.")
	end)

	close:SetScript("OnEnter", function()
		close.text:SetTextColor(1, 0.4, 0.4)
		close:SetBackdropColor(1,1,1,1)
	end)

	close:SetScript("OnLeave", function()
		close.text:SetTextColor(1, 0.15, 0.15)
		close:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
	end)
	
		-- Reset button
	local resetBtn = CreateFrame("Button", "ManaGainedLiteResetButton", MeterFrame)
	resetBtn:SetWidth(20)
	resetBtn:SetHeight(20)
	resetBtn:SetPoint("RIGHT", close, "LEFT", 2, 0)

	resetBtn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	resetBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

	resetBtn.text = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	resetBtn.text:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
	resetBtn.text:SetText("D")
	resetBtn.text:SetTextColor(1, 0.55, 0.1)

	resetBtn:SetScript("OnClick", function()
		StaticPopup_Show("MGL_CONFIRM_RESET")
	end)

	resetBtn:SetScript("OnEnter", function()
		resetBtn.text:SetTextColor(1, 0.7, 0.2)
		resetBtn:SetBackdropColor(1,1,1,1)
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("|cffff8800Delete Data|r", 1, 1, 1)
		GameTooltip:AddLine("Left-Click: Clear all data", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)

	resetBtn:SetScript("OnLeave", function()
		resetBtn.text:SetTextColor(1, 0.55, 0.1)
		resetBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
		GameTooltip:Hide()
	end)

	MeterFrame.resetBtn = resetBtn
	
	-- Mode button
	local modeBtn = CreateFrame("Button", "ManaGainedLiteModeButton", MeterFrame)
	modeBtn:SetWidth(20)
	modeBtn:SetHeight(20)
	modeBtn:SetPoint("RIGHT", resetBtn, "LEFT", 2, 0)

	modeBtn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	modeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

	modeBtn.text = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	modeBtn.text:SetPoint("CENTER", modeBtn, "CENTER", 0, 0)

	modeBtn:SetScript("OnClick", function()

		if IsShiftKeyDown() then
			if ManaGainedLiteDB.mode == "current" then
				ManaGainedLiteDB.current = {}
				ManaGainedLiteDB.currentTime = 0
				DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: Only current data reset.")
			end

			if ManaGainedLiteDB.mode == "total" then
				ManaGainedLiteDB.total = {}
				ManaGainedLiteDB.totalTime = 0
				DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: Only total data reset.")
			end

			ManaGainedLite:UpdateWindow()
			return
		end


		if ManaGainedLiteDB.mode == "current" then
			ManaGainedLiteDB.mode = "total"

		elseif ManaGainedLiteDB.mode == "total" then
			ManaGainedLiteDB.mode = "current"

		end

	ManaGainedLite:UpdateWindow()

	end)

	modeBtn:SetScript("OnEnter", function()
		modeBtn:SetBackdropColor(1, 1, 1, 1)

		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("|cffffff00Left-Click|r: Toggle Current / Total", 1, 1, 1)

		if ManaGainedLiteDB.mode == "current" then
			GameTooltip:AddLine("|cffffff00Shift + Left-Click|r: Reset Current only", 0.8, 0.8, 0.8)
		elseif ManaGainedLiteDB.mode == "total" then
			GameTooltip:AddLine("|cffffff00Shift + Left-Click|r: Reset Total only", 0.8, 0.8, 0.8)
		end

		GameTooltip:Show()
	end)

	modeBtn:SetScript("OnLeave", function()
		modeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
		GameTooltip:Hide()
	end)

	MeterFrame.modeBtn = modeBtn
	
	-- Report button
	local reportBtn = CreateFrame("Button", "ManaGainedLiteReportButton", MeterFrame)
	reportBtn:SetWidth(20)
	reportBtn:SetHeight(20)
	reportBtn:SetPoint("RIGHT", modeBtn, "LEFT", 2, 0)

	reportBtn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	reportBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

	reportBtn.text = reportBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	reportBtn.text:SetPoint("CENTER", reportBtn, "CENTER", 0, 0)
	
	local function UpdateReportButton()
		local ch = ManaGainedLiteDB.reportChannel

		if ch == "SAY" then
			reportBtn.text:SetText("S")
		elseif ch == "PARTY" then
			reportBtn.text:SetText("P")
		elseif ch == "RAID" then
			reportBtn.text:SetText("R")
		end
	end

	UpdateReportButton()
	
	reportBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	reportBtn:SetScript("OnClick", function()

		if arg1 == "LeftButton" then
			-- Cycle report channel
			local ch = ManaGainedLiteDB.reportChannel

			if ch == "SAY" then
				ManaGainedLiteDB.reportChannel = "PARTY"

			elseif ch == "PARTY" then
				ManaGainedLiteDB.reportChannel = "RAID"

			else
				ManaGainedLiteDB.reportChannel = "SAY"
			end

			UpdateReportButton()
		end


		if arg1 == "RightButton" then
			-- Send report confirmation popup
			StaticPopup_Show("MGL_CONFIRM_REPORT")
		end

	end)
	
	reportBtn:SetScript("OnEnter", function()
		reportBtn:SetBackdropColor(1, 1, 1, 1)

		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("|cffffff00Left-Click|r: Change channel", 1, 1, 1)
		GameTooltip:AddLine("S = Say   P = Party   R = Raid", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffff00Right-Click|r: Send meter report", 1, 1, 1)
		GameTooltip:AddLine("Right-click a player bar for details", 0.8, 0.8, 0.8)
		
		GameTooltip:Show()
	end)
	
	reportBtn:SetScript("OnLeave", function()
		reportBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
		GameTooltip:Hide()
	end)
	
	MeterFrame.reportBtn = reportBtn

	-- Footer separator
	local footerSeparator = MeterFrame:CreateTexture(nil, "ARTWORK")
	footerSeparator:SetHeight(1)
	footerSeparator:SetPoint("BOTTOMLEFT", MeterFrame, "BOTTOMLEFT", 6, 18.5)
	footerSeparator:SetPoint("BOTTOMRIGHT", MeterFrame, "BOTTOMRIGHT", -6, 18.5)
	footerSeparator:SetTexture(1, 1, 1, 0.18)

	MeterFrame.footerSeparator = footerSeparator
	
	-- Resize handle
	local resizeBtn = CreateFrame("Button", nil, MeterFrame)
	resizeBtn:SetWidth(16)
	resizeBtn:SetHeight(16)
	resizeBtn:SetPoint("BOTTOMRIGHT", MeterFrame, "BOTTOMRIGHT", -3, 3)
	resizeBtn:EnableMouse(true)

	resizeBtn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	resizeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

	resizeBtn.text = resizeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	resizeBtn.text:SetPoint("CENTER", resizeBtn, "CENTER", 0, 0)
	resizeBtn.text:SetText("»")
	resizeBtn.text:SetTextColor(0.7, 0.7, 0.7)

	resizeBtn:SetScript("OnMouseDown", function()
		MeterFrame:SetResizable(true)
		MeterFrame:StartSizing("BOTTOMRIGHT")
	end)

	resizeBtn:SetScript("OnMouseUp", function()
		MeterFrame:StopMovingOrSizing()

		local width = MeterFrame:GetWidth()
		local height = MeterFrame:GetHeight()

		if width < 140 then width = 140 end
		if height < 85 then height = 85 end

		MeterFrame:SetWidth(width)
		MeterFrame:SetHeight(height)

		ManaGainedLiteDB.window.width = width
		ManaGainedLiteDB.window.height = height

		ManaGainedLite:UpdateWindow()
	end)

	resizeBtn:SetScript("OnEnter", function()
		resizeBtn.text:SetTextColor(0, 0, 0)
		resizeBtn:SetBackdropColor(1, 1, 1, 1)
	end)

	resizeBtn:SetScript("OnLeave", function()
		if ManaGainedLiteDB.locked then
			resizeBtn.text:SetTextColor(0.3, 0.3, 0.3)
			resizeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
		else
			resizeBtn.text:SetTextColor(0.7, 0.7, 0.7)
			resizeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
		end
	end)

	MeterFrame.resizeBtn = resizeBtn

	for i = 1, 40 do
		local bar = CreateFrame("StatusBar", nil, MeterFrame)
		bar:SetWidth((ManaGainedLiteDB.window.width or 180) - 16)
		bar:SetHeight(BAR_HEIGHT)
		bar:SetMinMaxValues(0, 1)
		bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
		bar:EnableMouse(true)
		bar.displayValue = 0
		bar.targetValue = 0

		if i == 1 then
			bar:SetPoint("TOPLEFT", MeterFrame, "TOPLEFT", 8, -24)
		else
			bar:SetPoint("TOPLEFT", BarFrames[i-1], "BOTTOMLEFT", 0, -BAR_SPACING)
		end

		bar.bg = bar:CreateTexture(nil, "BACKGROUND")
		bar.bg:SetAllPoints(bar)
		bar.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
		bar.bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
		
		bar.highlight = bar:CreateTexture(nil, "OVERLAY")
		bar.highlight:SetAllPoints(bar)
		bar.highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
		bar.highlight:SetGradientAlpha("VERTICAL",
			1,1,1,0.18,   -- top light
			1,1,1,0.02)   -- bottom almost invisible

		bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.name:SetPoint("LEFT", bar, "LEFT", 2, 0)
		bar.name:SetJustifyH("LEFT")
		bar.name:SetWidth(110)

		bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.value:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
		bar.value:SetJustifyH("RIGHT")
		bar.value:SetWidth(55)

		bar:SetScript("OnMouseUp", function()
			if arg1 ~= "RightButton" then
				return
			end
			
			if not this.playerName then
				return
			end

			PendingDetailReportPlayer = this.playerName
			
			if StaticPopupDialogs["MGL_CONFIRM_DETAIL_REPORT"] then
				StaticPopupDialogs["MGL_CONFIRM_DETAIL_REPORT"].text =
					"Send detailed "..ManaGainedLiteDB.mode.." mana report for "..this.playerName.."?"
			end
			
			StaticPopup_Show("MGL_CONFIRM_DETAIL_REPORT")
		end)
		
		bar:SetScript("OnEnter", function()
			ManaGainedLite:ShowTooltip(this.playerName)
		end)
		bar:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		
		bar:SetScript("OnUpdate", function()
			if not this.targetValue then return end
			if not this.displayValue then this.displayValue = 0 end

			local diff = this.targetValue - this.displayValue
			if diff < 0 then diff = -diff end

			if diff < 0.5 then
				this.displayValue = this.targetValue
			else
				this.displayValue = this.displayValue + ((this.targetValue - this.displayValue) * 0.20)
			end

			this:SetValue(this.displayValue)
		end)

		bar:Hide()
		BarFrames[i] = bar
	end
end

function ManaGainedLite:UpdateWindow()
	if not MeterFrame then return end

	self:UpdateClassCache()
	

	local rows, grandTotal = self:GetActiveTotals()

	local modeText = "Current"
	local modeShort = "C"
	local shownTime = ManaGainedLiteDB.currentTime or 0
	local maxBars = self:GetMaxVisibleBars()

	if ManaGainedLiteDB.mode == "total" then
		modeText = "Total"
		modeShort = "T"
		shownTime = ManaGainedLiteDB.totalTime or 0
	end

	if HeaderText then
		HeaderText:SetText("Mana Gained - "..modeText.." ["..self:FormatTime(shownTime).."]")
	end

	if MeterFrame and MeterFrame.modeBtn and MeterFrame.modeBtn.text then
		MeterFrame.modeBtn.text:SetText(modeShort)
	end

	for i = 1, table.getn(BarFrames) do
		local bar = BarFrames[i]
		local row = nil

		if i <= maxBars then
			row = rows[i]
		end

		bar:SetWidth(MeterFrame:GetWidth() - 18)

		if row and grandTotal > 0 then
			local r, g, b = self:GetBarColor(row.name)

			bar:SetMinMaxValues(0, grandTotal)
			bar.targetValue = row.total
			bar:SetStatusBarColor(r, g, b)

			bar.name:SetText(i..". "..row.name)
			bar.value:SetText(MGL_CommaValue(row.total))
			bar.playerName = row.name

			bar:Show()
		else
			bar.targetValue = 0
			bar.playerName = nil
			bar.name:SetText("")
			bar.value:SetText("")
			bar:Hide()
		end
	end
end

---------------------------------------------------
-- Lock func
---------------------------------------------------

function ManaGainedLite:ApplyLockState()
	if not MeterFrame then return end

	if ManaGainedLiteDB.locked then
		MeterFrame:RegisterForDrag()
		MeterFrame:SetResizable(false)
		if MeterFrame.resizeBtn then
			MeterFrame.resizeBtn:EnableMouse(false)
			if MeterFrame.resizeBtn.text then
				MeterFrame.resizeBtn.text:SetTextColor(0.3, 0.3, 0.3)
			end
		end
	else
		MeterFrame:RegisterForDrag("LeftButton")
		MeterFrame:SetResizable(true)
		if MeterFrame.resizeBtn then
			MeterFrame.resizeBtn:EnableMouse(true)
			if MeterFrame.resizeBtn.text then
				MeterFrame.resizeBtn.text:SetTextColor(0.7, 0.7, 0.7)
			end
		end
	end
end

---------------------------------------------------
-- Slash commands
---------------------------------------------------

SLASH_MGL1 = "/mgl"

SlashCmdList["MGL"] = function(msg)
	local player = UnitName("player")
	msg = msg or ""

	local cmd, arg = string.match(msg, "^(%S*)%s*(.-)$")
	cmd = string.lower(cmd or "")
	arg = string.lower(arg or "")
	
	if cmd == "" then
		local combatState = "on"
		if not ManaGainedLiteDB.combatOnly then
			combatState = "off"
		end

		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite commands:")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl show|cff33ff99 - show meter")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl hide|cff33ff99 - hide meter")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl reset|cff33ff99 - reset current and total data")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl lock|cff33ff99 - toggle lock/unlock window")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl unlock|cff33ff99 - unlock window")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl scale|cff33ff99 - scale <0.80 - 1.15>")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl defaultsize|cff33ff99 - reset window width/height/scale")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl say|cff33ff99 - report to say")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl party|cff33ff99 - report to party")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl raid|cff33ff99 - report to raid")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl total|cff33ff99 - print total spell breakdown")
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00/mgl combatonlycollection on|off|cff33ff99 - current: "..combatState)
		return
	end

	if cmd == "reset" then
		ManaGainedLiteDB.total = {}
		ManaGainedLiteDB.current = {}
		ManaGainedLiteDB.currentTime = 0
		ManaGainedLiteDB.totalTime = 0
		TimerUpdateElapsed = 0

		ManaGainedLite:UpdateWindow()
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: data reset.")
		return
	end

	if cmd == "say" then
		ManaGainedLite:SendReport("SAY")
		return
	end

	if cmd == "party" then
		ManaGainedLite:SendReport("PARTY")
		return
	end

	if cmd == "raid" then
		ManaGainedLite:SendReport("RAID")
		return
	end

	if cmd == "hide" then
		if MeterFrame then MeterFrame:Hide() end
		return
	end

	if cmd == "show" then
		if MeterFrame then MeterFrame:Show() end
		ManaGainedLite:UpdateWindow()
		return
	end
	
	if cmd == "lock" then
		ManaGainedLiteDB.locked = not ManaGainedLiteDB.locked
		ManaGainedLite:ApplyLockState()

		if ManaGainedLiteDB.locked then
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: window locked.")
		else
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: window unlocked.")
		end
		return
	end

	if cmd == "unlock" then
		ManaGainedLiteDB.locked = false
		ManaGainedLite:ApplyLockState()
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: window unlocked.")
		return
	end
	
	if cmd == "scale" then
		local s = tonumber(arg)

		if not s then
			local currentScale = ManaGainedLiteDB.window.scale or 1
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Usage: /mgl scale <0.80 - 1.15>")
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Current scale: "..string.format("%.2f", currentScale))
			return
		end

		if s < 0.80 then s = 0.80 end
		if s > 1.15 then s = 1.15 end

		ManaGainedLiteDB.window.scale = s

		if MeterFrame then
			MeterFrame:SetScale(s)
		end

		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: scale set to "..string.format("%.2f", s)..".")
		return
	end
	
	if cmd == "defaultsize" then
		if not MeterFrame then return end

		local w = 240
		local h = 120
		local s = 1

		MeterFrame:SetWidth(w)
		MeterFrame:SetHeight(h)
		MeterFrame:SetScale(s)

		ManaGainedLiteDB.window.width = w
		ManaGainedLiteDB.window.height = h
		ManaGainedLiteDB.window.scale = s

		ManaGainedLite:UpdateWindow()

		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: window reset to 240x120 1.0x scale.")
		return
	end

	if cmd == "combatonlycollection" then
		if arg == "on" then
			ManaGainedLiteDB.combatOnly = true
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: combat-only collection enabled.")
		elseif arg == "off" then
			ManaGainedLiteDB.combatOnly = false
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ManaGainedLite: combat-only collection disabled.")
		else
			local state = "off"
			if ManaGainedLiteDB.combatOnly then
				state = "on"
			end
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Usage: /mgl combatonlycollection on|off")
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Current setting: "..state)
		end
		return
	end

	if cmd == "total" then
		ManaGainedLite:PrintBreakdown(true)
		return
	end

	-- default = current combat breakdown in chat frame
	ManaGainedLite:PrintBreakdown(false)
end

---------------------------------------------------
-- Event handler
---------------------------------------------------

function ManaGainedLite:OnEvent()
	if event == "PLAYER_ENTERING_WORLD" then
		self:UpdateRoster()
		self:CreateWindow()
		self:ApplyLockState()
		self:UpdateWindow()
		return
	end

	if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
		self:UpdateRoster()
		self:UpdateWindow()
		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		InCombat = true
		TimerUpdateElapsed = 0
		ManaGainedLiteDB.current = {}
		ManaGainedLiteDB.currentTime = 0
		self:UpdateWindow()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		InCombat = false
		TimerUpdateElapsed = 0
		self:UpdateWindow()
		return
	end

	if arg1 and string.find(arg1, "Mana from") then
		self:ParseMana(arg1)
	end
end

---------------------------------------------------
-- Register events
---------------------------------------------------

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")
frame:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
frame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
frame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")

frame:SetScript("OnEvent", function()
	ManaGainedLite:OnEvent()
end)

frame:SetScript("OnUpdate", function()
	ManaGainedLite:OnUpdate(arg1)
end)