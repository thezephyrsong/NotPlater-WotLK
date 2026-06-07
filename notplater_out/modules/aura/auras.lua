if not NotPlater then
	return
end

local Auras = {}
NotPlater.Auras = Auras
local AuraTracker = NotPlater.AuraTracker

local DEFAULT_TRACKED_UNITS = {"target", "focus", "mouseover"}
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY_TABLE = {}

local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitHealth = UnitHealth
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsPlayer = UnitIsPlayer
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GameTooltip = GameTooltip
local DebuffTypeColor = DebuffTypeColor
local GetSpellInfo = GetSpellInfo
local tinsert = table.insert
local ipairs = ipairs
local pairs = pairs
local unpack = unpack
local tostring = tostring
local format = string.format
local floor = math.floor
local huge = math.huge
local DEFAULT_AURA_BORDER_STYLE = "SQUARE"
local FALLBACK_AURA_BORDER_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MAX_ICON_ZOOM = 0.1
local math_max = math.max
local math_floor = math.floor
local math_min = math.min
local math_ceil = math.ceil

local DEFAULT_COOLDOWN_STYLE = "vertical"

local function GetAuraAnchorVertical(anchor)
	if not anchor then
		return "CENTER"
	end
	if anchor:find("TOP") then
		return "TOP"
	end
	if anchor:find("BOTTOM") then
		return "BOTTOM"
	end
	return "CENTER"
end

local function GetAuraLayoutAnchor(anchor, growDirection, invertVertical)
	local vertical = GetAuraAnchorVertical(anchor)
	if invertVertical then
		if vertical == "TOP" then
			vertical = "BOTTOM"
		elseif vertical == "BOTTOM" then
			vertical = "TOP"
		end
	end
	local grow = growDirection or "RIGHT"
	if grow == "LEFT" then
		if vertical == "TOP" then
			return "TOPRIGHT"
		elseif vertical == "BOTTOM" then
			return "BOTTOMRIGHT"
		end
		return "RIGHT"
	elseif grow == "CENTER" then
		if vertical == "TOP" then
			return "TOP"
		elseif vertical == "BOTTOM" then
			return "BOTTOM"
		end
		return "CENTER"
	end
	if vertical == "TOP" then
		return "TOPLEFT"
	elseif vertical == "BOTTOM" then
		return "BOTTOMLEFT"
	end
	return "LEFT"
end

local function SafeUnit(unit)
	return unit and UnitExists(unit) and not UnitIsDeadOrGhost(unit)
end

local function RunWithAuraProfile(profile, func, ...)
	if not profile or not NotPlater or not NotPlater.db then
		return func(...)
	end
	local original = NotPlater.db.profile
	NotPlater.db.profile = profile
	Auras:RefreshConfig()
	local results = {func(...)}
	NotPlater.db.profile = original
	Auras:RefreshConfig()
	return unpack(results)
end

local function ToGUID(candidate)
	if not candidate then
		return nil
	end
	if candidate:match("^%x%x%x%x%x%x%x%x%-") then
		return candidate
	end
	return UnitGUID(candidate)
end

function Auras:AttachTracker()
	self.tracker = self.tracker or AuraTracker or NotPlater.AuraTracker
	if self.tracker and self.tracker.EnsureInit then
		self.tracker:EnsureInit()
	end
	if self.tracker and self.tracker.RegisterListener and not self.trackerListener then
		self.tracker:RegisterListener(self)
		self.trackerListener = true
	end
end

function Auras:DetachTracker()
	if self.tracker and self.tracker.UnregisterListener and self.trackerListener then
		self.tracker:UnregisterListener(self)
	end
	self.trackerListener = false
end

function Auras:EnsureInit()
	if self.initialized then
		return
	end
	self:AttachTracker()
	self:Init()
end

function Auras:Init()
	if self.initialized then
		return
	end
	self.frames = {}
	self.guidToFrame = {}
	self.unitToFrame = {}
	self.activeIcons = {}
	self.pendingUpdates = {}
	self.pendingUpdateAll = false
	self.elapsed = 0
	self.playerGUID = UnitGUID("player")
	self.updater = CreateFrame("Frame")
	self.updater:SetScript("OnUpdate", function(_, elapsed)
		self:OnUpdate(elapsed)
	end)
	self.updater:Hide()
	self.eventFrame = CreateFrame("Frame")
	self.eventFrame:SetScript("OnEvent", function(_, event, ...)
		self:HandleEvent(event, ...)
	end)
	self.mouseoverWatcher = CreateFrame("Frame")
	self.mouseoverWatcher:SetScript("OnUpdate", function(_, elapsed)
		self:OnMouseoverUpdate(elapsed)
	end)
	self.mouseoverWatcher:Hide()
	self.mouseoverWatcherActive = false
	self.mouseoverElapsed = 0
	self.initialized = true
end

local function ResolveCooldownProvider(style)
	if style == "richsteini" and NotPlater.AuraCooldownRichSteini then
		return NotPlater.AuraCooldownRichSteini
	end
	if style == "swirl" and NotPlater.AuraCooldownSwirl then
		return NotPlater.AuraCooldownSwirl
	end
	if NotPlater.AuraCooldownVertical then
		return NotPlater.AuraCooldownVertical
	end
	return NotPlater.AuraCooldownSwirl
end

function Auras:GetCooldownProvider()
	local style = (self.swipe and self.swipe.style) or DEFAULT_COOLDOWN_STYLE
	return ResolveCooldownProvider(style)
end

function Auras:EnsureIconCooldownProvider(icon)
	local provider = self:GetCooldownProvider()
	if icon.cooldownProvider ~= provider then
		if icon.cooldownProvider and icon.cooldownProvider.Detach then
			icon.cooldownProvider:Detach(icon)
		end
		if provider and provider.Attach then
			provider:Attach(icon, self, self.swipe)
		end
		icon.cooldownProvider = provider
	end
	return provider
end

function Auras:ResetIconCooldown(icon)
	if icon.cooldownProvider and icon.cooldownProvider.Reset then
		icon.cooldownProvider:Reset(icon)
	end
end

function Auras:UpdateIconCooldown(icon)
	if icon.cooldownProvider and icon.cooldownProvider.Update then
		icon.cooldownProvider:Update(icon, self.swipe, self)
	end
end


function Auras:RegisterEvents()
	if not self.eventFrame then
		return
	end
	self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	self.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
	self.eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
	self.eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	self.eventFrame:RegisterEvent("UNIT_AURA")
	self.eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
end

function Auras:UnregisterEvents()
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	end
end

function Auras:HandleEvent(event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		self:OnPlayerEnteringWorld()
	elseif event == "UNIT_AURA" then
		self:UNIT_AURA(...)
	elseif event == "ARENA_OPPONENT_UPDATE" then
		self:OnArenaOpponentUpdate(...)
	else
		self:OnTrackedUnitEvent()
	end
end

function Auras:Enable()
	self:EnsureInit()
	if self.enabled then
		self:ApplyProfile()
		return
	end
	self.enabled = true
	self:AttachTracker()
	if self.tracker and self.tracker.Enable then
		self.tracker:Enable()
	end
	self.playerGUID = UnitGUID("player")
	self:RefreshConfig()
	self:RegisterEvents()
	self.updater:Show()
	self:UpdateAllFrames()
end

function Auras:Disable()
	if not self.enabled then
		return
	end
	self.enabled = false
	self:DetachTracker()
	if self.tracker and self.tracker.Disable then
		self.tracker:Disable()
	end
	self:HideAllFrames()
	self:UnregisterEvents()
	self.updater:Hide()
	if self.mouseoverWatcher then
		self.mouseoverWatcher:Hide()
		self.mouseoverWatcherActive = false
	end
end

function Auras:OnUpdate(elapsed)
	self:ProcessQueuedUpdates()
	if not self.general or not self.general.enable then
		return
	end
	self.elapsed = self.elapsed + elapsed
	if self.elapsed < 0.05 then
		return
	end
	self.elapsed = 0
	for icon in pairs(self.activeIcons) do
		self:UpdateIconTimer(icon)
		self:UpdateIconCooldown(icon)
	end
end

function Auras:QueueAuraUpdate(guid)
	if not self.enabled then
		return
	end
	if not guid then
		self.pendingUpdateAll = true
		return
	end
	if not self.guidToFrame or not self.guidToFrame[guid] then
		return
	end
	self.pendingUpdates[guid] = true
end

function Auras:ProcessQueuedUpdates()
	if not self.enabled then
		return
	end
	if self.pendingUpdateAll then
		self.pendingUpdateAll = false
		for guid in pairs(self.pendingUpdates) do
			self.pendingUpdates[guid] = nil
		end
		self:UpdateAllFrames()
		return
	end
	if not next(self.pendingUpdates) then
		return
	end
	for guid in pairs(self.pendingUpdates) do
		self.pendingUpdates[guid] = nil
		local frame = self.guidToFrame[guid]
		if frame then
			self:UpdateFrameAuras(frame, nil, true)
		end
	end
end

function Auras:RefreshConfig()
	self:EnsureInit()
	self.db = NotPlater.db and NotPlater.db.profile and NotPlater.db.profile.buffs or {}
	self.general = self.db.general or {}
	self.general.showAnimations = self.general.showAnimations ~= false
	self.db.auraFrame1 = self.db.auraFrame1 or {}
	self.db.auraFrame2 = self.db.auraFrame2 or {}
	self.auraFrameConfig = {
		[1] = self.db.auraFrame1 or {},
		[2] = self.db.auraFrame2 or {},
	}
	self.stackCounter = self.db.stackCounter or {}
	self.auraTimer = self.db.auraTimer or {}
	self.swipe = self.db.swipeAnimation or {}
	self.borderColors = self.db.borderColors or {}
	self.border = self.db.border or {}
	self.tracking = self.db.tracking or {}
	self.tracking.mode = self.tracking.mode or "AUTOMATIC"
	self.tracking.automatic = self.tracking.automatic or {}
	self.tracking.lists = self.tracking.lists or {}
	self.swipe.showSwipe = self.swipe.showSwipe ~= false
	self.swipe.invertSwipe = self.swipe.invertSwipe == true
	self.swipe.style = self.swipe.style or DEFAULT_COOLDOWN_STYLE
	self.border.style = self.border.style or DEFAULT_AURA_BORDER_STYLE
	if self.tracker and self.tracker.ApplySettings then
		self.tracker:ApplySettings()
	end
	if NotPlater and NotPlater.SetTrackedMatchUnits and self.tracker and self.tracker.trackedUnitList then
		NotPlater:SetTrackedMatchUnits(self.tracker.trackedUnitList)
		if NotPlater.UpdateAllFrameMatches then
			NotPlater:UpdateAllFrameMatches()
		end
	end
	self:UpdateMouseoverWatcher()
	self:RebuildLists()
end

function Auras:RegisterListEntry(target, entry)
	if not target or not entry then
		return
	end
	if entry.spellID and entry.spellID ~= 0 then
		target[entry.spellID] = true
	end
	if entry.name and entry.name ~= "" then
		target[entry.name:lower()] = true
	end
end

function Auras:IsAuraListed(list, aura)
	if not list or not aura then
		return false
	end
	if aura.spellID and list[aura.spellID] then
		return true
	end
	if aura.name and list[aura.name:lower()] then
		return true
	end
	return false
end

function Auras:RebuildLists()
	self.blacklist = {
		buffs = {},
		debuffs = {},
	}
	self.whitelist = {
		buffs = {},
		debuffs = {},
	}
	local lists = self.tracking.lists
	for _, entry in ipairs(lists.blacklistBuffs or EMPTY_TABLE) do
		self:RegisterListEntry(self.blacklist.buffs, entry)
	end
	for _, entry in ipairs(lists.blacklistDebuffs or EMPTY_TABLE) do
		self:RegisterListEntry(self.blacklist.debuffs, entry)
	end
	for _, entry in ipairs(lists.extraBuffs or EMPTY_TABLE) do
		self:RegisterListEntry(self.whitelist.buffs, entry)
	end
	for _, entry in ipairs(lists.extraDebuffs or EMPTY_TABLE) do
		self:RegisterListEntry(self.whitelist.debuffs, entry)
	end
end

function Auras:ApplyProfile()
	self:EnsureInit()
	self:RefreshConfig()
	for frame in pairs(self.frames) do
		if frame.npAuras then
			self:ConfigureFrame(frame)
			self:UpdateFrameAuras(frame)
		end
	end
end

function Auras:AttachToFrame(frame)
	self:EnsureInit()
	if self.frames[frame] then
		return
	end
	self.frames[frame] = true
	frame.npAuras = frame.npAuras or {}
	frame.npAuras.frames = frame.npAuras.frames or {}
	if not frame.npAuras.frames[1] then
		frame.npAuras.frames[1] = self:CreateContainer(frame, 1)
	end
	if not frame.npAuras.frames[2] then
		frame.npAuras.frames[2] = self:CreateContainer(frame, 2)
	end
	self:ConfigureFrame(frame)
end

function Auras:CreateContainer(frame, index)
	local anchor = frame.healthBar or frame
	local container = CreateFrame("Frame", nil, frame)
	container.index = index
	container.icons = {}
	local baseLevel = (anchor and anchor:GetFrameLevel()) or (frame and frame:GetFrameLevel()) or 0
	container:SetFrameLevel(baseLevel + 10 + index)
	local parentStrata = (anchor and anchor:GetFrameStrata()) or (frame and frame:GetFrameStrata()) or "MEDIUM"
	if parentStrata == "UNKNOWN" or not parentStrata then
		parentStrata = "HIGH"
	end
	container:SetFrameStrata(parentStrata)
	container.npVisibilityAnchor = frame.healthBar
	container:Hide()
	return container
end

function Auras:OnPlateShow(frame)
	self:SetFrameGUID(frame, nil)
	self:SetFrameUnit(frame, nil)
	self:UpdateFrameAuras(frame)
end

function Auras:OnPlateHide(frame)
	self:SetFrameGUID(frame, nil)
	self:SetFrameUnit(frame, nil)
	self:HideContainers(frame)
end

function Auras:HideContainers(frame)
	if not frame.npAuras then
		return
	end
	for _, container in ipairs(frame.npAuras.frames) do
		if container then
			self:HideContainer(container)
		end
	end
end

function Auras:HideContainer(container)
	for _, icon in ipairs(container.icons) do
		self:HideIcon(icon)
	end
	container:Hide()
end

function Auras:HideIcon(icon)
	self.activeIcons[icon] = nil
	icon:Hide()
	icon.currentSpellID = nil
	icon.currentApplied = nil
	if icon.showAnimation then
		icon.showAnimation:Stop()
	end
	icon:SetScale(1)
	self:ResetIconCooldown(icon)
end

function Auras:EnsureIconAnimation(icon)
	if icon.showAnimation then
		return
	end
	local group = CreateAnimationGroup(icon)
	group.width = group:CreateAnimation("Width")
	group.width:SetDuration(0.15)
	group.height = group:CreateAnimation("Height")
	group.height:SetDuration(0.15)
	icon.showAnimation = group
end

function Auras:PlayIconAnimation(icon)
	if not icon or not self.general.showAnimations then
		return
	end
	self:EnsureIconAnimation(icon)
	if icon.showAnimation then
		--icon.showAnimation:Stop()
		local iconWidth = icon:GetWidth()
		local iconHeight = icon:GetHeight()
		icon:SetWidth(iconWidth * 0.2)
		icon:SetHeight(iconHeight * 0.7)
		icon.showAnimation.width:SetChange(iconWidth)
		icon.showAnimation.height:SetChange(iconHeight)
		icon.showAnimation:Play()
	end
end

function Auras:GetFrameSignature(frame)
	if not frame then
		return nil
	end
	local nameText = frame.defaultNameText or frame.nameText
	local levelText = frame.levelText
	if (not nameText or not levelText) and NotPlater and NotPlater.GetFrameTexts then
		nameText, levelText = NotPlater:GetFrameTexts(frame)
	end
	local name = nameText and nameText:GetText()
	if not name or name == "" then
		return nil
	end
	local level = levelText and levelText:GetText()
	return name, level
end

function Auras:IsFrameSignatureValid(frame)
	if not frame or not frame.npGUIDName then
		return true
	end
	local name, level = self:GetFrameSignature(frame)
	if not name then
		return true
	end
	if frame.npGUIDName ~= name then
		return false
	end
	if frame.npGUIDLevel and level and frame.npGUIDLevel ~= level then
		return false
	end
	return true
end

function Auras:SetFrameGUID(frame, guid)
	if frame.npGUID == guid then
		return
	end
	if frame.npGUID and self.guidToFrame[frame.npGUID] == frame then
		self.guidToFrame[frame.npGUID] = nil
	end
	frame.npGUID = guid
	if guid then
		self.guidToFrame[guid] = frame
		local name, level = self:GetFrameSignature(frame)
		frame.npGUIDName = name
		frame.npGUIDLevel = level
	else
		frame.npGUIDName = nil
		frame.npGUIDLevel = nil
	end
end

function Auras:SetFrameUnit(frame, unit)
	if frame.npUnit == unit then
		return
	end
	if frame.npUnit and self.unitToFrame[frame.npUnit] == frame then
		self.unitToFrame[frame.npUnit] = nil
	end
	frame.npUnit = unit
	if unit then
		self.unitToFrame[unit] = frame
	end
end

function Auras:OnPlayerEnteringWorld()
	self.playerGUID = UnitGUID("player")
	self:UpdateAllFrames()
end

function Auras:OnTrackedUnitEvent()
	self:UpdateAllFrames()
end

function Auras:OnArenaOpponentUpdate(unit, state)
	if not unit or not self.tracker or not self.tracker:IsTrackedUnit(unit) then
		self:OnTrackedUnitEvent()
		return
	end
	if state == "seen" or state == "destroyed" or state == "cleared" then
		self:UpdateByUnit(unit)
	else
		self:OnTrackedUnitEvent()
	end
end

function Auras:UpdateMouseoverWatcher()
	if not self.mouseoverWatcher then
		return
	end
	local shouldWatch = self.general and self.general.enable and self.tracker and self.tracker.IsTrackedUnit and self.tracker:IsTrackedUnit("mouseover") and self.tracker.enableCombatLogTracking == false
	if shouldWatch then
		self.mouseoverWatcherActive = true
		self.mouseoverElapsed = 0
		self.mouseoverLastExists = UnitExists("mouseover") and true or false
		self.mouseoverWatcher:Show()
	else
		self.mouseoverWatcherActive = false
		self.mouseoverElapsed = 0
		self.mouseoverLastExists = nil
		self.mouseoverWatcher:Hide()
	end
end

function Auras:OnMouseoverUpdate(elapsed)
	if not self.mouseoverWatcherActive then
		return
	end
	self.mouseoverElapsed = (self.mouseoverElapsed or 0) + (elapsed or 0)
	if self.mouseoverElapsed < 0.1 then
		return
	end
	self.mouseoverElapsed = 0
	local exists = UnitExists("mouseover")
	if exists then
		self.mouseoverLastExists = true
		return
	end
	if self.mouseoverLastExists then
		self.mouseoverLastExists = false
		self:HandleMouseoverCleared()
	end
end

function Auras:HandleMouseoverCleared()
	if not (self.tracker and self.tracker.enableCombatLogTracking == false) then
		return
	end
	local frame = self.unitToFrame and self.unitToFrame["mouseover"]
	if not frame then
		return
	end
	self:UpdateFrameAuras(frame)
end

function Auras:UNIT_AURA(unit)
	if not unit then
		return
	end
	if self.tracker and self.tracker:IsTrackedUnit(unit) then
		self:UpdateByUnit(unit)
	end
end

function Auras:UpdateByUnit(unit)
	local frame = self.unitToFrame[unit]
	if frame then
		self:UpdateFrameAuras(frame, unit)
	else
		self:UpdateAllFrames()
	end
end

function Auras:OnAuraTrackerUpdate(guid)
	if not guid then
		self:QueueAuraUpdate(nil)
		return
	end
	self:QueueAuraUpdate(guid)
end

function Auras:UpdateAllFrames()
	self:EnsureInit()
	for frame in pairs(self.frames) do
		self:UpdateFrameAuras(frame)
	end
end

function Auras:HideAllFrames()
	self:EnsureInit()
	for frame in pairs(self.frames) do
		self:HideContainers(frame)
		self:SetFrameGUID(frame, nil)
		self:SetFrameUnit(frame, nil)
	end
end

function Auras:ConfigureFrame(frame)
	if not frame.npAuras then
		return
	end
	for index, container in ipairs(frame.npAuras.frames) do
		local cfg = self.auraFrameConfig[index] or EMPTY_TABLE
		container.config = cfg
		container:ClearAllPoints()
		local anchor = cfg.anchor or "TOP"
		local growDirection = cfg.growDirection or "RIGHT"
		local relativeAnchor = GetAuraLayoutAnchor(anchor, growDirection, true)
		local baseAnchor = frame.healthBar or frame
		local relativeFrame = NotPlater:GetAnchorTargetFrame(baseAnchor, cfg.anchorTarget, nil)
		if relativeFrame == container then
			relativeFrame = nil
		end
		if not relativeFrame then
			relativeFrame = baseAnchor
		end
		if index > 1 then
			local previous = frame.npAuras.frames[index - 1]
			if previous and not cfg.anchorTarget then
				relativeFrame = previous
				relativeAnchor = GetAuraLayoutAnchor(anchor, growDirection, true)
			end
		end
		container:SetPoint(relativeAnchor, relativeFrame, anchor, cfg.xOffset or 0, cfg.yOffset or 0)
		container:SetAlpha(self.general.alpha or 1)
		self:ConfigureIcons(container, index)
	end
end

function Auras:ConfigureIcons(container, index)
	for _, icon in ipairs(container.icons) do
		self:ConfigureIconFonts(icon)
		self:ApplyIconSize(icon, index)
	end
end

function Auras:ConfigureIconFonts(icon)
	local stackConfig = self.stackCounter
	local timerConfig = self.auraTimer
	if icon.stackText then
		self:ApplyFont(icon.stackText, stackConfig)
		if stackConfig.position then
			icon.stackText:ClearAllPoints()
			local anchor = stackConfig.position.anchor
			local relativeAnchor = NotPlater.oppositeAnchors[anchor] or anchor
			local anchorFrame = NotPlater:GetAnchorTargetFrame(icon, stackConfig.position.anchorTarget, icon)
			if anchorFrame == icon.stackText then
				anchorFrame = icon
			end
			icon.stackText:SetPoint(relativeAnchor, anchorFrame, anchor, stackConfig.position.xOffset or -1, stackConfig.position.yOffset or 1)
		end
	end
	if icon.timerText then
		self:ApplyFont(icon.timerText, timerConfig)
		if timerConfig.position then
			icon.timerText:ClearAllPoints()
			local anchor = timerConfig.position.anchor
			local relativeAnchor = NotPlater.oppositeAnchors[anchor] or anchor
			local anchorFrame = NotPlater:GetAnchorTargetFrame(icon, timerConfig.position.anchorTarget, icon)
			if anchorFrame == icon.timerText then
				anchorFrame = icon
			end
			icon.timerText:SetPoint(relativeAnchor, anchorFrame, anchor, timerConfig.position.xOffset or 0, timerConfig.position.yOffset or 0)
		end
	end
end

function Auras:ApplyFont(fontString, config)
	if not fontString or not config or not config.general then
		return
	end
	local general = config.general
	if general.name and NotPlater.SML then
		fontString:SetFont(NotPlater.SML:Fetch(NotPlater.SML.MediaType.FONT, general.name), general.size or 10, general.border or "")
	elseif general.name then
		fontString:SetFont(general.name, general.size or 10, general.border or "")
	end
	if general.color then
		fontString:SetTextColor(general.color[1] or 1, general.color[2] or 1, general.color[3] or 1, general.color[4] or 1)
	end
	if config.shadow and config.shadow.enable then
		fontString:SetShadowOffset(config.shadow.xOffset or 0, config.shadow.yOffset or 0)
		fontString:SetShadowColor(config.shadow.color and config.shadow.color[1] or 0, config.shadow.color and config.shadow.color[2] or 0, config.shadow.color and config.shadow.color[3] or 0, config.shadow.color and config.shadow.color[4] or 1)
	else
		fontString:SetShadowColor(0, 0, 0, 0)
	end
end

function Auras:GetSizeConfig(index)
	return self.auraFrameConfig[index] or EMPTY_TABLE
end

function Auras:GetBorderThickness(size)
	local style = self.border and self.border.style or DEFAULT_AURA_BORDER_STYLE
	if style == "NONE" then
		return 0
	end
	return size and size.borderThickness or 1
end

function Auras:GetBorderTexture(style)
	if NotPlater.SML and style and style ~= "" then
		local resolved = NotPlater.SML:Fetch(NotPlater.SML.MediaType.BORDER, style)
		if resolved then
			return resolved
		end
	end
	return FALLBACK_AURA_BORDER_TEXTURE
end

function Auras:ApplyIconSize(icon, index)
	local size = self:GetSizeConfig(index)
	local width = size.width or 22
	local height = size.height or 22
	-- Own auras are shown at 50% size (25% smaller)
	if icon.npIsOwnAura == true then
		-- own auras: 50% of configured size
		width  = math_floor(width  * 0.5 + 0.5)
		height = math_floor(height * 0.5 + 0.5)
	elseif icon.npIsOwnAura == false then
		-- other players' auras: 50% smaller than configured size
		width  = math_floor(width  * 0.5 + 0.5)
		height = math_floor(height * 0.5 + 0.5)
	end
	-- Other players' auras keep full size (square border distinguishes them instead)
	NotPlater:SetSize(icon, width, height)
	if icon.borderFrame then
		local thickness = self:GetBorderThickness(size)
		icon.borderFrame:ClearAllPoints()
		icon.borderFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -thickness, thickness)
		icon.borderFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", thickness, -thickness)
	end
	if icon.borderTexture then
		local thickness = self:GetBorderThickness(size)
		icon.borderTexture:ClearAllPoints()
		icon.borderTexture:SetPoint("TOPLEFT", icon, "TOPLEFT", -thickness, thickness)
		icon.borderTexture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", thickness, -thickness)
	end
end

function Auras:ApplyIconZoom(icon, size)
	if not icon or not icon.icon then
		return
	end
	local zoom = size and size.iconZoom or 0
	if zoom <= 0 then
		icon.icon:SetTexCoord(0, 1, 0, 1)
		return
	end
	local inset = (zoom / 100) * MAX_ICON_ZOOM
	icon.icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

function Auras:GetAurasPerRow(index, defaultWidth)
	local config = self.auraFrameConfig[index] or EMPTY_TABLE
	local fallback = 10
	return config.rowCount or fallback
end

function Auras:UpdateFrameAuras(frame, forcedUnit, skipUnitScan)
	if frame and frame.npTemplateProfile and not frame.npAuraProfileContext then
		return RunWithAuraProfile(frame.npTemplateProfile, function()
			frame.npAuraProfileContext = true
			local results = {self:UpdateFrameAuras(frame, forcedUnit, skipUnitScan)}
			frame.npAuraProfileContext = nil
			return unpack(results)
		end)
	end
	if not self.general.enable then
		self:HideContainers(frame)
		return
	end
	if forcedUnit and not SafeUnit(forcedUnit) then
		forcedUnit = nil
	end
	local matchedUnit = frame.lastUnitMatch
	if matchedUnit and not self:VerifyUnit(frame, matchedUnit) then
		if NotPlater and NotPlater.ClearFrameMatch then
			NotPlater:ClearFrameMatch(frame)
		else
			frame.lastUnitMatch = nil
			frame.lastGuidMatch = nil
		end
		matchedUnit = nil
	end
	local unit = forcedUnit or (matchedUnit and SafeUnit(matchedUnit) and matchedUnit) or nil
	if unit then
		self:SetFrameUnit(frame, unit)
	else
		self:SetFrameUnit(frame, nil)
	end
	local guid = nil
	if unit then
		guid = UnitGUID(unit)
	else
		guid = frame.lastGuidMatch or frame.npGUID
		if guid and not self:IsFrameSignatureValid(frame) then
			self:SetFrameGUID(frame, nil)
			guid = nil
		end
	end
	if guid then
		self:SetFrameGUID(frame, guid)
	end
	if not guid and not (self.tracker and self.tracker.enableCombatLogTracking) then
		self:HideContainers(frame)
		return
	end
	local targetIsPlayer = false
	if guid then
		targetIsPlayer = self:IsPlayerGUID(guid)
	elseif unit then
		targetIsPlayer = UnitIsPlayer(unit)
	end
	frame.npIsPlayer = targetIsPlayer
	local scanUnit = unit
	if skipUnitScan and not forcedUnit then
		scanUnit = nil
	end
	local auras = self:CollectAuras(scanUnit, frame.npGUID)
	if not auras or #auras == 0 then
		self:HideContainers(frame)
		return
	end
	local filtered
	if frame.npSimulatedAuras then
		filtered = auras
	else
		filtered = self:FilterAuras(auras, targetIsPlayer)
	end
	if #filtered == 0 then
		self:HideContainers(frame)
		return
	end
	self:DisplayAuras(frame, filtered)
end

function Auras:IdentifyUnit(frame)
	local matched = frame.lastUnitMatch
	if matched and SafeUnit(matched) then
		return matched
	end
	return nil
end

function Auras:VerifyUnit(frame, unit)
	if not SafeUnit(unit) then
		return false
	end
	local nameText = frame.defaultNameText or frame.nameText
	local levelText = frame.levelText
	local plateName = nameText and nameText:GetText()
	local plateLevel = levelText and levelText:GetText()
	if plateName ~= UnitName(unit) then
		return false
	end
	local level = UnitLevel(unit)
	local levelString = level and tostring(level) or plateLevel
	if plateLevel ~= levelString then
		return false
	end
	local health = frame.healthBar:GetValue()
	if health ~= UnitHealth(unit) then
		return false
	end
	return true
end

function Auras:IsPlayerGUID(guid)
	if not guid then
		return false
	end
	if guid == self.playerGUID then
		return true
	end
	if self.tracker then
		if self.tracker.GetUnitTypeFromGUID then
			return self.tracker:GetUnitTypeFromGUID(guid) == "player"
		end
		if self.tracker.IsPlayerGUID then
			return self.tracker:IsPlayerGUID(guid)
		end
	end
	return false
end

function Auras:CollectAuras(unit, guid)
	if not self.tracker then
		return nil
	end
	return self.tracker:CollectAuras(unit, guid)
end


function Auras:FilterAuras(candidates, targetIsPlayer)
	local filtered = {}
	local manual = self.tracking.mode == "MANUAL"
	for _, aura in ipairs(candidates) do
		aura.sourceIsPlayer = aura.sourceIsPlayer ~= nil and aura.sourceIsPlayer or self:IsPlayerGUID(aura.casterGUID)
		aura.isEnrage = aura.dispelType == "Enrage"
		aura.isDispellable = aura.dispelType and aura.dispelType ~= "" and aura.dispelType ~= "none"
		aura.remaining = aura.expirationTime and math_max(0, aura.expirationTime - GetTime()) or 0
		if self:PassesFilters(aura, targetIsPlayer, manual) then
			aura.priority = self:GetPriority(aura)
			aura.borderKey = self:GetBorderKey(aura)
			tinsert(filtered, aura)
		end
	end
	if self.general.sortAuras then
		local myGUID = self.playerGUID
		table.sort(filtered, function(a, b)
			if a.priority ~= b.priority then
				return a.priority > b.priority
			end
			-- Own auras always before other players' auras at the same priority
			local aOwn = (a.casterGUID == myGUID) and 1 or 0
			local bOwn = (b.casterGUID == myGUID) and 1 or 0
			if aOwn ~= bOwn then
				return aOwn > bOwn
			end
			local aExp = a.expirationTime or huge
			local bExp = b.expirationTime or huge
			if aExp ~= bExp then
				return aExp < bExp
			end
			if a.spellID ~= b.spellID then
				return (a.spellID or 0) < (b.spellID or 0)
			end
			return (a.casterGUID or "") < (b.casterGUID or "")
		end)
	end
	if self.general.stackSimilarAuras then
		return self:CollapseStacks(filtered)
	end
	return filtered
end

function Auras:PassesFilters(aura, targetIsPlayer, manualMode)
	if aura.isDebuff and self:IsAuraListed(self.blacklist.debuffs, aura) then
		return false
	end
	if aura.isBuff and self:IsAuraListed(self.blacklist.buffs, aura) then
		return false
	end
	local forced = (aura.isDebuff and self:IsAuraListed(self.whitelist.debuffs, aura)) or (aura.isBuff and self:IsAuraListed(self.whitelist.buffs, aura))
	if manualMode then
		return forced and true or false
	end
	if forced then
		return true
	end
	local auto = self.tracking.automatic or EMPTY_TABLE
	if aura.sourceIsPlayer then
		if aura.casterGUID == self.playerGUID then
			if auto.showPlayerAuras == false then
				return false
			end
		-- other players's auras are always shown
		end
	else
		if auto.showOtherNPCAuras == false then
			return false
		end
	end
	if aura.isBuff and not targetIsPlayer and auto.showNpcBuffs == false then
		return false
	end
	if aura.isDebuff and not targetIsPlayer and auto.showNpcDebuffs == false then
		return false
	end
	if aura.isCrowdControl then
		return auto.showCrowdControl ~= false
	end
	if aura.isEnrage then
		return auto.showEnrageBuffs ~= false
	end
	if aura.isBuff and aura.dispelType == "Magic" and auto.showMagicBuffs == false then
		return false
	end
	if aura.isBuff and aura.isDispellable then
		if auto.showDispellableBuffs == false then
			return false
		end
		if auto.onlyShortDispellableOnPlayers and targetIsPlayer and aura.duration and aura.duration > 10 then
			return false
		end
	end
	return true
end

function Auras:GetPriority(aura)
	if aura.isCrowdControl then
		return 6
	end
	if aura.isEnrage then
		return 5
	end
	if aura.isDispellable then
		return 4
	end
	if aura.isBuff then
		return 2
	end
	return 1
end

function Auras:GetBorderKey(aura)
	if aura.isCrowdControl then
		return "crowdControl"
	end
	if aura.isEnrage then
		return "enrage"
	end
	if aura.isDispellable then
		return "dispellable"
	end
	if aura.isBuff and aura.sourceIsPlayer then
		return "offensiveCD"
	end
	if aura.isBuff and aura.casterGUID == aura.targetGUID then
		return "defensiveCD"
	end
	if aura.isBuff then
		return "buff"
	end
	return "default"
end

function Auras:CollapseStacks(auras)
	local collapsed = {}
	local tracker = {}
	for _, aura in ipairs(auras) do
		local key = aura.spellID .. (aura.isDebuff and ":D" or ":B")
		local existing = tracker[key]
		if not existing then
			tracker[key] = aura
			tinsert(collapsed, aura)
		else
			existing.count = math_max(existing.count or 0, aura.count or 0)
			if self.general.showShortestStackTime then
				if aura.expirationTime < existing.expirationTime then
					existing.expirationTime = aura.expirationTime
					existing.duration = aura.duration
				end
			else
				if aura.expirationTime > existing.expirationTime then
					existing.expirationTime = aura.expirationTime
					existing.duration = aura.duration
				end
			end
		end
	end
	return collapsed
end

function Auras:DisplayAuras(frame, auras)
	if not frame.npAuras then
		return
	end
	local assignments = {
		[1] = {},
		[2] = {},
	}
	if self.db.auraFrame2 and self.db.auraFrame2.enable then
		for _, aura in ipairs(auras) do
			if aura.isDebuff then
				tinsert(assignments[1], aura)
			else
				tinsert(assignments[2], aura)
			end
		end
	else
		assignments[1] = auras
	end
	for index, container in ipairs(frame.npAuras.frames) do
		self:DisplayContainer(frame, container, assignments[index])
	end
end

function Auras:DisplayContainer(frame, container, auras)
	if not container then
		return
	end
	local defaultWidth = frame.healthBar:GetWidth()
	if not auras or #auras == 0 then
		self:HideContainer(container)
		return
	end
	container:Show()
	local perRow = self:GetAurasPerRow(container.index, defaultWidth)
	local spacing = self.general.iconSpacing or 0
	local rowSpacing = self.general.rowSpacing or 0
	local grow = (container.config and container.config.growDirection) or "RIGHT"
	local size = self:GetSizeConfig(container.index)
	local iconWidth = (size and size.width or 22)
	local iconHeight = (size and size.height or 22)
	local rows = math_max(1, math_ceil(#auras / perRow))
	local border = self:GetBorderThickness(size)
	local effectiveSpacing = spacing + border * 2
	local effectiveRowSpacing = rowSpacing + border * 2
	local containerWidth = perRow * iconWidth + effectiveSpacing * math_max(0, perRow - 1)
	local containerHeight = rows * iconHeight + effectiveRowSpacing * math_max(0, rows - 1)
	NotPlater:SetSize(container, containerWidth, containerHeight)
	for i, aura in ipairs(auras) do
		local icon = self:AcquireIcon(container, i)
		self:SetupIcon(icon, aura, size, container.index)
		self:PositionIcon(container, icon, i, perRow, #auras, grow, size, spacing, rowSpacing)
		icon:Show()
		self.activeIcons[icon] = true
	end
	for i = #auras + 1, #container.icons do
		self:HideIcon(container.icons[i])
	end
end

function Auras:AcquireIcon(container, index)
	if not container.icons[index] then
		container.icons[index] = self:CreateIcon(container)
	end
	self:ConfigureIconFonts(container.icons[index])
	self:ApplyIconSize(container.icons[index], container.index)
	return container.icons[index]
end

function Auras:CreateIcon(container)
	local icon = CreateFrame("Frame", nil, container)
	NotPlater:SetSize(icon, 24, 24)
	icon:SetScale(1)
	icon.icon = icon:CreateTexture(nil, "OVERLAY")
	icon.icon:SetAllPoints()
	icon.borderFrame = CreateFrame("Frame", nil, icon)
	icon.borderFrame:SetAllPoints(icon)
	icon.borderFrame:SetFrameLevel(icon:GetFrameLevel() + 1)
	icon.borderTexture = icon:CreateTexture(nil, "ARTWORK")
	icon.stackText = icon:CreateFontString(nil, "OVERLAY")
	icon.timerText = icon:CreateFontString(nil, "OVERLAY")
	icon:EnableMouse(true)
	icon:SetScript("OnEnter", function(frameIcon)
		if self.general.showTooltip and frameIcon.spellID then
			GameTooltip:SetOwner(frameIcon, "ANCHOR_BOTTOMRIGHT")
			GameTooltip:SetSpellByID(frameIcon.spellID)
		end
	end)
	icon:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return icon
end

function Auras:SetupIcon(icon, aura, size, index)
	icon.spellID = aura.spellID
	icon.aura = aura
	local appliedTime = nil
	if aura.expirationTime and aura.duration and aura.duration > 0 then
		appliedTime = aura.expirationTime - aura.duration
	elseif aura.expirationTime then
		appliedTime = aura.expirationTime
	end
	local isNewAssignment = icon.currentSpellID ~= aura.spellID or icon.currentApplied ~= appliedTime
	icon.currentSpellID = aura.spellID
	icon.currentApplied = appliedTime
	icon.icon:SetTexture(aura.icon or DEFAULT_ICON)
	self:ApplyIconZoom(icon, size)
	self:ApplyIconSize(icon, index)
	self:SetIconBorder(icon, aura, size)
	-- Tag whether this icon belongs to the player — used for size and timer
	icon.npIsOwnAura = (aura.casterGUID == self.playerGUID)
	if aura.count and aura.count > 1 and self.stackCounter.general and self.stackCounter.general.enable then
		icon.stackText:SetText(aura.count)
		icon.stackText:Show()
	else
		icon.stackText:SetText("")
		icon.stackText:Hide()
	end
	-- Show timer ONLY on own auras; hide it on other players' auras
	local wantTimer = icon.npIsOwnAura
		and self.auraTimer.general and self.auraTimer.general.enable
		and aura.duration and aura.duration > 0 and aura.expirationTime < huge
	if wantTimer then
		icon.timerText:Show()
	else
		icon.timerText:SetText("")
		icon.timerText:Hide()
	end
	local hasCooldown = aura.duration and aura.duration > 0 and aura.expirationTime < huge
	if hasCooldown and self.swipe.showSwipe then
		local provider = self:EnsureIconCooldownProvider(icon)
		if provider and provider.Setup then
			provider:Setup(icon, aura, self.swipe, self)
		end
	else
		self:ResetIconCooldown(icon)
	end
	aura.remaining = aura.expirationTime and math_max(0, aura.expirationTime - GetTime()) or 0
	self:UpdateIconTimer(icon)
	if isNewAssignment then
		self:PlayIconAnimation(icon)
	end
end

function Auras:SetIconBorder(icon, aura, size)
	-- Other players' auras always get a square border so they're visually distinct
	local style = (icon.npIsOwnAura == false) and "SQUARE"
		or (self.border and self.border.style or DEFAULT_AURA_BORDER_STYLE)
	if style == "NONE" then
		if icon.borderFrame then
			icon.borderFrame:Hide()
		end
		if icon.borderTexture then
			icon.borderTexture:Hide()
		end
		return
	end
	local thickness = self:GetBorderThickness(size)
	if thickness <= 0 then
		if icon.borderFrame then
			icon.borderFrame:Hide()
		end
		if icon.borderTexture then
			icon.borderTexture:Hide()
		end
		return
	end
	local color = self:GetBorderColor(aura)
	if style == "SQUARE" then
		if icon.borderFrame then
			icon.borderFrame:Hide()
		end
		if icon.borderTexture then
			icon.borderTexture:SetTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
			icon.borderTexture:Show()
		end
		return
	end
	if icon.borderTexture then
		icon.borderTexture:Hide()
	end
	if not icon.borderFrame then
		return
	end
	local texture = self:GetBorderTexture(style)
	icon.borderFrame:SetBackdrop({
		edgeFile = texture,
		edgeSize = thickness,
	})
	icon.borderFrame:SetBackdropBorderColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
	icon.borderFrame:Show()
end

function Auras:GetBorderColor(aura)
	if aura.isDispellable and self.borderColors.useTypeColors and aura.dispelType and DebuffTypeColor[aura.dispelType] then
		local c = DebuffTypeColor[aura.dispelType]
		return {c.r, c.g, c.b, 1}
	end
	local color = self.borderColors[aura.borderKey] or self.borderColors.default or {0, 0, 0, 1}
	return color
end

function Auras:PositionIcon(container, icon, index, perRow, totalAuras, growDirection, size, spacing, rowSpacing)
	local iconWidth = (size and size.width or 22)
	local iconHeight = (size and size.height or 22)
	local border = self:GetBorderThickness(size)
	local effectiveSpacing = spacing + border * 2
	local effectiveRowSpacing = rowSpacing + border * 2
	local stepX = iconWidth + effectiveSpacing
	local stepY = iconHeight + effectiveRowSpacing
	local row = floor((index - 1) / perRow)
	local column = (index - 1) % perRow
	local totalRows = math_max(1, math_ceil(totalAuras / perRow))
	local isLastRow = (row == totalRows - 1)
	local iconsInRow = isLastRow and math_max(1, totalAuras - row * perRow) or perRow
	local anchor = container.config and container.config.anchor or "TOP"
	local baseAnchor = GetAuraLayoutAnchor(anchor, growDirection, true)
	local vertical = GetAuraAnchorVertical(anchor)
	local rowDirection = (vertical == "TOP") and 1 or -1
	icon:ClearAllPoints()
	if growDirection == "LEFT" then
		icon:SetPoint(baseAnchor, container, baseAnchor, -(column * stepX), row * stepY * rowDirection)
	elseif growDirection == "CENTER" then
		local offset = column - ((iconsInRow - 1) / 2)
		icon:SetPoint(baseAnchor, container, baseAnchor, offset * stepX, row * stepY * rowDirection)
	else
		icon:SetPoint(baseAnchor, container, baseAnchor, column * stepX, row * stepY * rowDirection)
	end
end

function Auras:UpdateIconTimer(icon)
	if not icon.timerText or not icon.aura then
		return
	end
	if not (self.auraTimer.general and self.auraTimer.general.enable) then
		return
	end
	local aura = icon.aura
	if not aura.expirationTime or aura.expirationTime == huge or not aura.duration or aura.duration == 0 then
		icon.timerText:SetText("")
		return
	end
	local remaining = aura.expirationTime - GetTime()
	if remaining <= 0 then
		icon.timerText:SetText("")
		self.activeIcons[icon] = nil
		return
	end
	if remaining >= 60 then
		icon.timerText:SetText(format("%dm", math_ceil(remaining / 60)))
	elseif self.auraTimer.general.showDecimals and remaining < 10 then
		icon.timerText:SetText(format("%.1f", remaining))
	else
		icon.timerText:SetText(format("%d", remaining))
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CLASS-FILTERED OTHER-PLAYER AURAS
--
-- When another player casts a debuff on a mob, we only show it if that spell
-- belongs to the *local player's* class.  This keeps the nameplate clean:
-- a Warrior sees Sunder/Demo Shout; a Hunter sees Serpent Sting; etc.
--
-- Spell IDs are for WoW 3.3.5 (Wrath of the Lich King).
-- ─────────────────────────────────────────────────────────────────────────────

local NP_CLASS_SPELLS = {
    WARRIOR = {
        -- Sunder Armor (all ranks)
        [7386]=true,[7405]=true,[8380]=true,[11596]=true,[11597]=true,[25225]=true,[47467]=true,[47498]=true,
        -- Demoralizing Shout (all ranks)
        [1160]=true,[6190]=true,[11554]=true,[11555]=true,[11556]=true,[25202]=true,[25203]=true,[47437]=true,
        -- Thunder Clap (all ranks)
        [6343]=true,[8198]=true,[8204]=true,[8205]=true,[11580]=true,[11581]=true,[25264]=true,[47501]=true,[47502]=true,
        -- Rend (all ranks)
        [772]=true,[6546]=true,[6547]=true,[6548]=true,[11572]=true,[11573]=true,[11574]=true,[25208]=true,[47465]=true,
        -- Deep Wounds
        [12834]=true,[12835]=true,[12836]=true,
        -- Hamstring (all ranks)
        [1715]=true,[7372]=true,[7373]=true,[25212]=true,[50725]=true,
        -- Mortal Strike healing reduction
        [12294]=true,[21551]=true,[21552]=true,[21553]=true,[25248]=true,[30330]=true,[43441]=true,[43442]=true,
        -- Trauma (arms)
        [46845]=true,
        -- Bladestorm bleed
        [50622]=true,
    },
    PALADIN = {
        -- Judgement of Light
        [20185]=true,[20344]=true,[20345]=true,[20346]=true,[27163]=true,[20271]=true,
        -- Judgement of Wisdom
        [20186]=true,[20354]=true,[20355]=true,[27164]=true,
        -- Judgement of Justice
        [20184]=true,[53407]=true,
        -- Consecration (dot on mob)
        [26573]=true,[20924]=true,[20925]=true,[27173]=true,[58597]=true,[48818]=true,
        -- Seal of Corruption / Vengeance stacks
        [53742]=true,[31803]=true,
    },
    HUNTER = {
        -- Serpent Sting (all ranks)
        [1978]=true,[13549]=true,[13550]=true,[13551]=true,[13552]=true,[13553]=true,[13554]=true,[13555]=true,[25295]=true,[49000]=true,[49001]=true,
        -- Hunter's Mark
        [1130]=true,[14323]=true,[14324]=true,[14325]=true,[53338]=true,
        -- Scorpid Sting
        [3043]=true,[14276]=true,[14277]=true,
        -- Viper Sting
        [3034]=true,[14279]=true,[14280]=true,[65877]=true,
        -- Wyvern Sting
        [19386]=true,[24132]=true,[24133]=true,[27068]=true,[49011]=true,[49012]=true,
        -- Concussive Shot
        [5116]=true,
        -- Aimed Shot healing reduction
        [13812]=true,[14314]=true,[14315]=true,[20736]=true,[47613]=true,[47614]=true,
        -- Explosive Shot dot
        [53301]=true,[60053]=true,
        -- Black Arrow
        [3674]=true,[63667]=true,
    },
    ROGUE = {
        -- Hemorrhage
        [16511]=true,[17347]=true,[17348]=true,[26864]=true,[48660]=true,
        -- Garrote bleed
        [703]=true,[8631]=true,[8632]=true,[8633]=true,[11289]=true,[11290]=true,[26839]=true,[26884]=true,[48675]=true,[48676]=true,
        -- Rupture bleed
        [1943]=true,[8639]=true,[8640]=true,[11273]=true,[11274]=true,[11275]=true,[25300]=true,[49800]=true,[49801]=true,
        -- Wound Poison healing reduction
        [13218]=true,[13222]=true,[13223]=true,[13224]=true,[27189]=true,[57975]=true,
        -- Expose Armor
        [8647]=true,[8649]=true,[8650]=true,[11197]=true,[11198]=true,[26866]=true,
        -- Blind
        [2094]=true,
        -- Crippling Poison slow
        [3409]=true,[11201]=true,
    },
    PRIEST = {
        -- Shadow Word: Pain (all ranks)
        [589]=true,[594]=true,[970]=true,[992]=true,[2767]=true,[10892]=true,[10893]=true,[10894]=true,[25367]=true,[25368]=true,[48124]=true,[48125]=true,
        -- Devouring Plague (all ranks)
        [2944]=true,[19276]=true,[19277]=true,[19278]=true,[19279]=true,[19280]=true,[25467]=true,[48299]=true,
        -- Vampiric Embrace
        [15286]=true,[15290]=true,
        -- Vampiric Touch
        [34914]=true,[34916]=true,[34917]=true,[48159]=true,[48160]=true,
        -- Mind Flay slow
        [15407]=true,[17311]=true,[17312]=true,[17313]=true,[17314]=true,[18807]=true,[25387]=true,[48154]=true,[48155]=true,
        -- Weakened Soul
        [6788]=true,
    },
    SHAMAN = {
        -- Flame Shock (all ranks)
        [8050]=true,[8052]=true,[8053]=true,[10447]=true,[10448]=true,[25457]=true,[29228]=true,[49232]=true,[49233]=true,
        -- Frost Shock slow
        [8056]=true,[8058]=true,[10472]=true,[10473]=true,[25464]=true,[49235]=true,[49236]=true,
        -- Earth Shock
        [8042]=true,[8044]=true,[8045]=true,[8046]=true,[10412]=true,[10413]=true,[10414]=true,[25454]=true,[49230]=true,[49231]=true,
        -- Stormstrike
        [17364]=true,[32175]=true,[32176]=true,
        -- Lightning Shield charges on mob (from static shock)
        [26364]=true,[26365]=true,
        -- Lava Burst dot
        [77451]=true,
    },
    MAGE = {
        -- Frostbolt slow / Frostbite
        [12486]=true,[12489]=true,[12490]=true,
        -- Fire Blast dot (ignite)
        [12654]=true,[12846]=true,[12847]=true,[12848]=true,[12849]=true,[12850]=true,
        -- Living Bomb
        [44457]=true,[55359]=true,[55360]=true,
        -- Frost Nova
        [122]=true,[865]=true,[6131]=true,[10230]=true,[27088]=true,[42917]=true,
        -- Slow
        [31589]=true,
        -- Winter's Chill
        [12579]=true,
        -- Scorch / Fire Vulnerability
        [22959]=true,[22960]=true,[22961]=true,[22962]=true,[22963]=true,[12873]=true,[28526]=true,
        -- Deep Freeze
        [44572]=true,
    },
    WARLOCK = {
        -- Corruption (all ranks)
        [172]=true,[6222]=true,[6223]=true,[7648]=true,[11671]=true,[11672]=true,[25311]=true,[27216]=true,[47812]=true,[47813]=true,
        -- Curse of Agony (all ranks)
        [980]=true,[1014]=true,[6217]=true,[11711]=true,[11712]=true,[11713]=true,[25258]=true,[27218]=true,[47863]=true,[47864]=true,
        -- Curse of the Elements
        [1490]=true,[11721]=true,[11722]=true,[27228]=true,[47865]=true,
        -- Curse of Weakness
        [702]=true,[1108]=true,[6205]=true,[7646]=true,[11707]=true,[11708]=true,[27224]=true,[50511]=true,
        -- Curse of Exhaustion slow
        [18223]=true,[18466]=true,[18467]=true,[27274]=true,
        -- Immolate (all ranks)
        [348]=true,[707]=true,[1094]=true,[2941]=true,[11665]=true,[11667]=true,[11668]=true,[25309]=true,[27215]=true,[47810]=true,[47811]=true,
        -- Unstable Affliction
        [30108]=true,[30404]=true,[30405]=true,[47841]=true,[47843]=true,
        -- Haunt
        [48181]=true,[59161]=true,
        -- Bane of Doom / Curse of Doom
        [603]=true,[30385]=true,[47867]=true,
        -- Conflagrate dot
        [17962]=true,
        -- Shadowflame
        [47960]=true,[61291]=true,
        -- Seed of Corruption
        [27243]=true,[47832]=true,[47833]=true,
    },
    DRUID = {
        -- Moonfire (all ranks)
        [8921]=true,[8924]=true,[8925]=true,[8926]=true,[8927]=true,[8928]=true,[8929]=true,[9833]=true,[9834]=true,[9835]=true,[26987]=true,[26988]=true,[48462]=true,[48463]=true,
        -- Insect Swarm (all ranks)
        [5570]=true,[24974]=true,[24975]=true,[24976]=true,[24977]=true,[27013]=true,[48467]=true,
        -- Rake bleed
        [1822]=true,[1823]=true,[1824]=true,[9904]=true,[27003]=true,[48573]=true,
        -- Rip bleed
        [1079]=true,[9492]=true,[9493]=true,[9752]=true,[9894]=true,[9896]=true,[27008]=true,[48671]=true,[49800]=true,
        -- Faerie Fire (all ranks)
        [770]=true,[778]=true,[9749]=true,[9907]=true,[26993]=true,[48477]=true,
        -- Lacerate bleed
        [33745]=true,[48567]=true,
        -- Entangling Roots
        [339]=true,[1062]=true,[5195]=true,[5196]=true,[9852]=true,[9853]=true,[26989]=true,[53308]=true,
        -- Demoralizing Roar
        [99]=true,[1735]=true,[9490]=true,[9747]=true,[9898]=true,[26998]=true,[48559]=true,
    },
    DEATHKNIGHT = {
        -- Blood Plague
        [55078]=true,[55607]=true,
        -- Frost Fever
        [55095]=true,[59921]=true,
        -- Death and Decay (dot)
        [43265]=true,[49936]=true,[49937]=true,[49938]=true,
        -- Chains of Ice slow
        [45524]=true,[55078]=true,
        -- Icy Touch slow (frost fever)
        [45477]=true,
        -- Necrotic Strike
        [73975]=true,
        -- Strangulate
        [47476]=true,[49913]=true,
        -- Ebon Plague
        [51161]=true,[51162]=true,[51163]=true,
        -- Scarlet Fever (demo shout equiv)
        [81132]=true,
        -- Heart Strike bleed
        [55050]=true,
        -- Scourge Strike shadow
        [55078]=true,
    },
}

-- Cache player class at load time; refreshed on login/reload
local NP_PLAYER_CLASS = nil
local function NP_GetPlayerClass()
    if not NP_PLAYER_CLASS then
        NP_PLAYER_CLASS = select(2, UnitClass("player"))
    end
    return NP_PLAYER_CLASS
end

-- Returns true if spellID is in the local player's class spell list
local function NP_IsClassSpell(spellID)
    if not spellID then return false end
    local class = NP_GetPlayerClass()
    if not class then return true end -- unknown class: show everything
    local list = NP_CLASS_SPELLS[class]
    if not list then return true end  -- class not in table: show everything
    return list[spellID] == true
end

-- Patch PassesFilters: for other players' auras, only show if it's a class spell
local _origPassesFilters = Auras.PassesFilters
function Auras:PassesFilters(aura, targetIsPlayer, manualMode)
    -- If it's another player's aura (not ours), gate on class spell list
    if aura.sourceIsPlayer and aura.casterGUID ~= self.playerGUID then
        if not NP_IsClassSpell(aura.spellID) then
            return false
        end
    end
    return _origPassesFilters(self, aura, targetIsPlayer, manualMode)
end
