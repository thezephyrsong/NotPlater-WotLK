if( not NotPlater ) then return end

local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitExists = UnitExists
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local FAILED = FAILED
local INTERRUPTED = INTERRUPTED
local slen = string.len
local ssub = string.sub

function NotPlater:SetCastBarNameText(frame, text)
	local configMaxLength = NotPlater.db.profile.castBar.spellNameText.general.maxLetters
	if text and slen(text) > configMaxLength then
		frame.castBar.spellNameText:SetText(ssub(text, 1, configMaxLength) .. "...")
	else
		frame.castBar.spellNameText:SetText(text)
	end
end

function NotPlater:CastBarOnUpdate(elapsed)
    local castBarConfig = NotPlater.db.profile.castBar
	if not self.casting and not self.channeling then
		self:Hide()
		return
	elseif self.casting then
		self.value = self.value + elapsed
		if self.value >= self.maxValue then
			self:SetValue(self.maxValue)
			self:Hide()
			self.casting = nil
			return
		end
		self:SetValue(self.value)

        if castBarConfig.spellTimeText.general.displayType == "crtmax" then
            self.spellTimeText:SetFormattedText("%.1f / %.1f", self.value, self.maxValue)
        elseif castBarConfig.spellTimeText.general.displayType == "crt" then
            self.spellTimeText:SetFormattedText("%.1f", self.value)
        elseif castBarConfig.spellTimeText.general.displayType == "percent" then
            self.spellTimeText:SetFormattedText("%d%%", self.value / self.maxValue * 100)
        elseif castBarConfig.spellTimeText.general.displayType == "timeleft" then
            self.spellTimeText:SetFormattedText("%.1f", self.maxValue - self.value)
        else
            self.spellTimeText:SetText("")
        end
	elseif self.channeling then
		self.value = self.value - elapsed
		if self.value <= 0 then
			self:Hide()
			self.channeling = nil
			return
		end
		self:SetValue(self.value)

        if castBarConfig.spellTimeText.general.displayType == "crtmax" then
            self.spellTimeText:SetFormattedText("%.1f / %.1f", self.value, self.maxValue)
        elseif castBarConfig.spellTimeText.general.displayType == "crt" then
            self.spellTimeText:SetFormattedText("%.1f", self.value)
        elseif castBarConfig.spellTimeText.general.displayType == "percent" then
            self.spellTimeText:SetFormattedText("%d%%", self.value / self.maxValue * 100)
        elseif castBarConfig.spellTimeText.general.displayType == "timeleft" then
            self.spellTimeText:SetFormattedText("%.1f", self.value - self.maxValue)
        else
            self.spellTimeText:SetText("")
        end
	else
		self:Hide()
	end
	self.lastUpdate = GetTime()
end

function NotPlater:CastBarOnCast(frame, event, unit)
	local castBarConfig = self.db.profile.castBar
	if not castBarConfig.statusBar.general.enable then return end

	frame.castBar.lastUpdate = GetTime()
	if unit then
		if not event then
			if UnitChannelInfo(unit) then
				event = "UNIT_SPELLCAST_CHANNEL_START"
			elseif UnitCastingInfo(unit) then
				event = "UNIT_SPELLCAST_START"
			end
		end
	elseif frame.castBar:IsShown() then
		frame.castBar:Hide()
	end

	if event == "UNIT_SPELLCAST_START" then
		local name, _, _, texture, startTime, endTime = UnitCastingInfo(unit)
		if not name then
			frame.castBar:Hide()
			return
		end

		NotPlater:SetCastBarNameText(frame, name)
		frame.castBar.value = (GetTime() - (startTime / 1000))
		frame.castBar.maxValue = (endTime - startTime) / 1000
		frame.castBar:SetMinMaxValues(0, frame.castBar.maxValue)
		frame.castBar:SetValue(frame.castBar.value)

		if frame.castBar.icon then
			frame.castBar.icon.texture:SetTexture(texture)
		end

		frame.castBar.casting = true
		frame.castBar.channeling = nil

		frame.castBar:Show()
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if not frame.castBar:IsVisible() then
			frame.castBar:Hide()
		end
		if (frame.castBar.casting and event == "UNIT_SPELLCAST_STOP") or (frame.castBar.channeling and event == "UNIT_SPELLCAST_CHANNEL_STOP") then

			frame.castBar:SetValue(frame.castBar.maxValue)
			if event == "UNIT_SPELLCAST_STOP" then
				frame.castBar.casting = nil
			else
				frame.castBar.channeling = nil
			end

			frame.castBar:Hide()
		end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		if frame.castBar:IsShown() then
			frame.castBar:SetValue(frame.castBar.maxValue)

			if event == "UNIT_SPELLCAST_FAILED" then
				NotPlater:SetCastBarNameText(frame, FAILED)
			else
				NotPlater:SetCastBarNameText(frame, INTERRUPTED)
			end
			frame.castBar.casting = nil
			frame.castBar.channeling = nil
		end
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		if frame:IsShown() then
			local name, _, _, _, startTime, endTime = UnitCastingInfo(unit)
			if not name then
				-- if there is no name, there is no bar
				frame.castBar:Hide()
				return
			end

			NotPlater:SetCastBarNameText(frame, name)
			frame.castBar.value = (GetTime() - (startTime / 1000))
			frame.castBar.maxValue = (endTime - startTime) / 1000
			frame.castBar:SetMinMaxValues(0, frame.castBar.maxValue)

			if not frame.castBar.casting then
				frame.castBar.casting = true
				frame.castBar.channeling = nil
			end
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local name, _, _, texture, startTime, endTime = UnitChannelInfo(unit)
		if not name then
			frame.castBar:Hide()
			return
		end

		NotPlater:SetCastBarNameText(frame, name)
		frame.castBar.value = (endTime / 1000) - GetTime()
		frame.castBar.maxValue = (endTime - startTime) / 1000
		frame.castBar:SetMinMaxValues(0, frame.castBar.maxValue)
		frame.castBar:SetValue(frame.castBar.value)

		if frame.castBar.icon then
			frame.castBar.icon.texture:SetTexture(texture)
		end

		frame.castBar.casting = nil
		frame.castBar.channeling = true

		frame.castBar:Show()
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		if frame.castBar:IsShown() then
			local name, _, _, _, startTime, endTime = UnitChannelInfo(unit)
			if not name then
				frame.castBar:Hide()
				return
			end

			NotPlater:SetCastBarNameText(frame, name)
			frame.castBar.value = ((endTime / 1000) - GetTime())
			frame.castBar.maxValue = (endTime - startTime) / 1000
			frame.castBar:SetMinMaxValues(0, frame.castBar.maxValue)
			frame.castBar:SetValue(frame.castBar.value)
		end
	end
end

--[[ function NotPlater:CastCheck(frame)
	if frame.castBar.casting or frame.castBar.channeling then
		frame.castBar:Show()
	else
		self:CastBarOnCast(frame, "UNIT_SPELLCAST_START", "target")
		if not frame.castBar.casting then
			self:CastBarOnCast(frame, "UNIT_SPELLCAST_CHANNEL_START", "target")
		end
	end
end]]

function NotPlater:CastCheck(frame)
    local unit = frame.lastUnitMatch

    if frame.castBar.casting or frame.castBar.channeling then
        frame.castBar:Show()
    elseif unit then
        self:CastBarOnCast(frame, "UNIT_SPELLCAST_START", unit)

        if not frame.castBar.casting then
            self:CastBarOnCast(frame, "UNIT_SPELLCAST_CHANNEL_START", unit)
        end
    end
end

function NotPlater:ScaleCastBar(castFrame, isTarget)
	local scaleConfig = self.db.profile.target.scale
	if scaleConfig.castBar then
		local scalingFactor = isTarget and scaleConfig.scalingFactor or 1
    	local castBarConfig = self.db.profile.castBar
		self:ScaleGeneralisedStatusBar(castFrame, scalingFactor, castBarConfig.statusBar)
		self:ScaleIcon(castFrame.icon, scalingFactor, castBarConfig.spellIcon)
		self:ScaleGeneralisedText(castFrame.spellNameText, scalingFactor, castBarConfig.spellNameText)
		self:ScaleGeneralisedText(castFrame.spellTimeText, scalingFactor, castBarConfig.spellTimeText)
	end
end

function NotPlater:CastBarOnShow(frame)
	local castFrame = frame.castBar
	--castFrame.casting = nil
	--castFrame.channeling = nil
	--NotPlater:CastCheck(frame)
	
	if not castFrame.casting and not castFrame.channeling then
    NotPlater:CastCheck(frame)
	end
	-- Tried to make it reappear, but this does not really work since you can't track whether something was interrupted
	--if castFrame.casting or castFrame.channeling then
		--if castFrame.lastUpdate then
			--castFrame.helper = self.CastBarOnUpdate
			--castFrame:helper(GetTime() - castFrame.lastUpdate)
		--end
		--castFrame:Show()
	--end
end

function NotPlater:ConfigureCastBar(frame)
    local castBarConfig = self.db.profile.castBar
	local castFrame = frame.castBar

    -- Set background
	self:ConfigureGeneralisedPositionedStatusBar(castFrame, frame.healthBar, castBarConfig.statusBar)
	castFrame:SetStatusBarColor(self:GetColor(castBarConfig.statusBar.general.color))

	-- Set castbar icon
	self:ConfigureIcon(castFrame.icon, castFrame, castBarConfig.spellIcon)
	
    -- Set text
	self:ConfigureGeneralisedText(castFrame.spellTimeText, castFrame, castBarConfig.spellTimeText)
	self:ConfigureGeneralisedText(castFrame.spellNameText, castFrame, castBarConfig.spellNameText)
end

function NotPlater:ConstructCastBar(frame)
	local castFrame = CreateFrame("StatusBar", "$parentCastBar", frame)
	castFrame:SetScript("OnUpdate", NotPlater.CastBarOnUpdate)

    -- Create the icon
	self:ConstructIcon(castFrame)

    -- Create cast time text and set font
    castFrame.spellTimeText = castFrame:CreateFontString(nil, "ARTWORK")

    -- Create cast name text and set font
    castFrame.spellNameText = castFrame:CreateFontString(nil, "ARTWORK")

    -- Create and set background
	self:ConstructGeneralisedStatusBar(castFrame)

	frame.castBar = castFrame
	castFrame:Hide()
end

function NotPlater:RegisterCastBarEvents(frame)
	if not frame.npCastBarEventsHooked then
		frame.npCastBarEventsHooked = true
		frame:SetScript("OnEvent", function(self, event, unit)
			if not unit or not UnitExists(unit) then
				return
			end
			local matchedFrame = NotPlater:GetMatchedFrameForUnit(unit)
			if matchedFrame then
				NotPlater:CastBarOnCast(matchedFrame, event, unit)
			end
		end)
	end
	frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
	frame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
	frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
	frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	frame:RegisterEvent("UNIT_SPELLCAST_START")
	frame:RegisterEvent("UNIT_SPELLCAST_STOP")
	frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
end

function NotPlater:UnregisterCastBarEvents(frame)
	frame:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
	frame:UnregisterEvent("UNIT_SPELLCAST_DELAYED")
	frame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	frame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
	frame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	frame:UnregisterEvent("UNIT_SPELLCAST_START")
	frame:UnregisterEvent("UNIT_SPELLCAST_STOP")
	frame:UnregisterEvent("UNIT_SPELLCAST_FAILED")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- NON-TARGET CAST BAR via COMBAT_LOG_EVENT_UNFILTERED
--
-- In WoW 3.3.5, UNIT_SPELLCAST_* only fires for "target", "focus", "party1-4".
-- For all other mobs we use the combat log which fires for every mob nearby.
--
-- SPELL_CAST_START  → show cast bar, count up from 0
-- SPELL_CAST_SUCCESS / SPELL_CAST_FAILED / SPELL_INTERRUPT → hide cast bar
-- SPELL_CHANNEL_START → show channel bar, count up from 0
-- SPELL_CHANNEL_STOP  → hide channel bar
--
-- We don't have exact duration for non-targeted mobs, so we count up and let
-- SPELL_CAST_SUCCESS hide it (which fires essentially when the cast finishes).
-- If the mob becomes the target mid-cast, the normal UNIT_SPELLCAST_* handler
-- takes over and corrects the bar with exact timing.
-- ─────────────────────────────────────────────────────────────────────────────

-- guid → nameplate frame  (our local registry, separate from matchTracker's)
local npGuidToFrame = {}
local npFrameToGuid = {}

-- Score a candidate nameplate frame against a known GUID + name.
-- Higher = better match.  Returns nil if name doesn't match at all.
local function NP_ScoreFrame(frame, guid, name)
    if not frame:IsShown() then return nil end

    local score = 0

    -- ── 1. Name must match (hard requirement) ──────────────────────────────
    local nt = frame.defaultNameText
    local plateName = nt and nt:GetText()
    if plateName ~= name then return nil end
    score = score + 50  -- name match

    -- ── 2. matchTracker already pinned this GUID to this frame ─────────────
    --    This is the most reliable signal: matchTracker uses health+name+level
    --    to bind target/focus/mouseover GUIDs. Trust it completely.
    if frame.lastGuidMatch == guid then
        return score + 10000  -- authoritative, skip all other candidates
    end

    -- ── 3. This frame is not already claimed by a DIFFERENT guid ───────────
    --    Avoid stealing a frame whose GUID is already known and pinned.
    if frame.lastGuidMatch and frame.lastGuidMatch ~= guid then
        score = score - 200  -- penalise: this plate belongs to someone else
    end
    -- Also penalise if our own registry already pinned this frame to a different guid
    local existingGuid = npFrameToGuid[frame]
    if existingGuid and existingGuid ~= guid then
        score = score - 200
    end

    -- ── 4. Screen-position heuristic ───────────────────────────────────────
    --    Among same-name mobs the one closer to the screen centre is more
    --    likely to be in melee/casting range of the player.
    local cx, cy = frame:GetCenter()
    if cx and cy then
        local sw = GetScreenWidth()
        local sh = GetScreenHeight()
        local dx = cx - sw * 0.5
        local dy = cy - sh * 0.5
        local dist = math.sqrt(dx * dx + dy * dy)
        -- Give up to +30 for being close to centre (dist=0 → +30, far → ~0)
        local proximity = math.max(0, 30 - dist * 0.05)
        score = score + proximity
    end

    -- ── 5. Health bar value heuristic ──────────────────────────────────────
    --    A mob that is damaged is more likely to be in active combat
    --    (and thus the one casting).  Full-health plates are penalised slightly.
    local hb = frame.healthBar
    if hb then
        local hp = hb:GetValue()
        local _, hpMax = hb:GetMinMaxValues()
        if hpMax and hpMax > 0 and hp < hpMax then
            score = score + 10  -- damaged = probably in combat
        end
    end

    return score
end

-- Find (or refresh) the best nameplate frame for a given guid+name.
local function NP_FindBestFrame(guid, name)
    if not guid or not name then return nil end

    -- Fast path: already have a live mapping
    local existing = npGuidToFrame[guid]
    if existing and existing:IsShown() then
        -- Verify it still has the right name (the plate may have been reused)
        local nt = existing.defaultNameText
        if nt and nt:GetText() == name then
            return existing
        end
        -- Stale — release it
        npFrameToGuid[existing] = nil
        npGuidToFrame[guid] = nil
    end

    -- Also check matchTracker's authoritative map first
    local mtFrame = NotPlater.matchGuidToFrame and NotPlater.matchGuidToFrame[guid]
    if mtFrame and mtFrame:IsShown() then
        local nt = mtFrame.defaultNameText
        if nt and nt:GetText() == name then
            -- Register in our map too
            local old = npFrameToGuid[mtFrame]
            if old then npGuidToFrame[old] = nil end
            npGuidToFrame[guid] = mtFrame
            npFrameToGuid[mtFrame] = guid
            return mtFrame
        end
    end

    -- Scored search across all visible NotPlater frames
    local frames = NotPlater.frames
    if not frames then return nil end

    local bestFrame = nil
    local bestScore = -math.huge

    for frame in pairs(frames) do
        local s = NP_ScoreFrame(frame, guid, name)
        if s and s > bestScore then
            bestScore = s
            bestFrame = frame
        end
    end

    if bestFrame then
        -- Commit this mapping
        local old = npFrameToGuid[bestFrame]
        if old and old ~= guid then npGuidToFrame[old] = nil end
        npGuidToFrame[guid] = bestFrame
        npFrameToGuid[bestFrame] = guid
    end

    return bestFrame
end

local function NP_GetFrame(guid)
    if not guid then return nil end
    local frame = npGuidToFrame[guid]
    if frame and frame:IsShown() then return frame end
    if frame then
        npFrameToGuid[frame] = nil
        npGuidToFrame[guid] = nil
    end
    return nil
end

-- npFromCombatLog[frame] = true means we (combat log layer) are driving this bar.
-- This lets NP_HideCastBar avoid stomping on bars driven by UNIT_SPELLCAST_*.
local npFromCombatLog = {}

local function NP_ShowCastBar(frame, spellName, spellId, isChannel)
    local castBarConfig = NotPlater.db.profile.castBar
    if not castBarConfig.statusBar.general.enable then return end

    -- If UNIT_SPELLCAST_* already drives this bar (mob is targeted/focused),
    -- it has exact timing — don't touch it.
    if frame.castBar:IsShown() and not npFromCombatLog[frame] then return end

    -- Get real cast duration from spell data.
    -- GetSpellInfo returns: name, rank, icon, cost, isFunnel, powerType, castTime(ms), minRange, maxRange
    local castTimeMs = 0
    if spellId and spellId > 0 then
        local _, _, _, _, _, _, ct = GetSpellInfo(spellId)
        if ct and ct > 0 then
            castTimeMs = ct
        end
    end

    local duration = castTimeMs / 1000
    if duration <= 0 then
        -- Unknown duration — fall back to a very long sentinel so the bar
        -- stays up until SPELL_CAST_SUCCESS hides it.
        duration = 60
    end

    NotPlater:SetCastBarNameText(frame, spellName or "")
    frame.castBar.value = 0
    frame.castBar.maxValue = duration
    frame.castBar:SetMinMaxValues(0, duration)
    frame.castBar:SetValue(0)
    if isChannel then
        frame.castBar.casting = nil
        frame.castBar.channeling = true
    else
        frame.castBar.casting = true
        frame.castBar.channeling = nil
    end
    npFromCombatLog[frame] = true
    frame.castBar:Show()
end

local function NP_HideCastBar(frame)
    if not frame.castBar:IsShown() then return end
    if not npFromCombatLog[frame] then return end  -- UNIT_SPELLCAST_* owns this bar
    frame.castBar.casting = nil
    frame.castBar.channeling = nil
    npFromCombatLog[frame] = nil
    frame.castBar:Hide()
end

-- Combat log event frame (one global, set up once)
local npCombatLogFrame = CreateFrame("Frame")
local npCombatLogSetup = false

local function NP_SetupCombatLog()
    if npCombatLogSetup then return end
    npCombatLogSetup = true

    npCombatLogFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    npCombatLogFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    npCombatLogFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Wipe registry when leaving combat
            for g in pairs(npGuidToFrame) do npGuidToFrame[g] = nil end
            for f in pairs(npFrameToGuid) do npFrameToGuid[f] = nil end
            for f in pairs(npFromCombatLog) do npFromCombatLog[f] = nil end
            return
        end

        -- COMBAT_LOG_EVENT_UNFILTERED
        -- 3.3.5 args: timestamp, subevent, sourceGUID, sourceName, sourceFlags,
        --             destGUID, destName, destFlags [, spellId, spellName, ...]
        local timestamp, subevent, sourceGUID, sourceName, sourceFlags,
              destGUID, destName, destFlags, spellId, spellName = ...

        if not subevent then return end

        -- Only act on non-player sources
        local playerGUID = UnitGUID("player")
        if sourceGUID == playerGUID then return end

        -- Always try to register dest GUIDs too (we might be hit by casts)
        -- but only act on the source for SPELL_CAST events
        if subevent == "SPELL_CAST_START" then
            local frame = NP_FindBestFrame(sourceGUID, sourceName)
            if frame then NP_ShowCastBar(frame, spellName, spellId, false) end
        elseif subevent == "SPELL_CHANNEL_START" then
            local frame = NP_FindBestFrame(sourceGUID, sourceName)
            if frame then NP_ShowCastBar(frame, spellName, spellId, true) end
        elseif subevent == "SPELL_CAST_SUCCESS"
            or subevent == "SPELL_CAST_FAILED"
            or subevent == "SPELL_INTERRUPT"
            or subevent == "SPELL_CHANNEL_STOP" then
            local frame = NP_GetFrame(sourceGUID)
            if frame then NP_HideCastBar(frame) end
        else
            -- For all other events, opportunistically register both GUIDs
            -- so we have them ready when a SPELL_CAST_START arrives
            if sourceGUID and sourceName then NP_FindBestFrame(sourceGUID, sourceName) end
            if destGUID and destName and destGUID ~= playerGUID then
                NP_FindBestFrame(destGUID, destName)
            end
        end
    end)
end

-- Patch RegisterCastBarEvents to also start the combat log listener
local _origRegisterCastBarEvents = NotPlater.RegisterCastBarEvents
function NotPlater:RegisterCastBarEvents(frame)
    _origRegisterCastBarEvents(self, frame)
    NP_SetupCombatLog()
end

-- Clean up guid registry when a nameplate hides
local _origOnHide = NotPlater.MatchTrackerOnHide
-- We hook via the existing OnHide in PrepareFrame by patching CastBarOnHide
function NotPlater:CastBarOnHide(frame)
    local guid = npFrameToGuid[frame]
    if guid then
        npGuidToFrame[guid] = nil
        npFrameToGuid[frame] = nil
    end
    npFromCombatLog[frame] = nil
    if frame.castBar then
        frame.castBar.casting = nil
        frame.castBar.channeling = nil
        frame.castBar:Hide()
    end
end
