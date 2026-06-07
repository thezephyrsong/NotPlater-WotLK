if not NotPlater then return end

-- NotPlater Spread: automatically offsets nameplates that overlap so they
-- fan out and are individually readable.
--
-- How it works:
--   The game engine controls nameplate FRAME positions; we cannot move those.
--   However the healthBar (and everything parented to it) is positioned inside
--   the nameplate frame via SetPoint("TOP", 0, yOffset).
--   When frames overlap we shift that inner Y offset so the bars visually spread
--   apart from each other while their clickable frames stay in place.

local floor  = math.floor
local abs    = math.abs
local sort   = table.sort
local GetTime = GetTime

-- How often (seconds) we recheck overlaps
local CHECK_INTERVAL   = 0.15
-- Two frames are "overlapping" when their screen centres are within this many
-- pixels of each other on both axes
local OVERLAP_X        = 120   -- nameplates are ~120 px wide
local OVERLAP_Y        = 22    -- roughly one bar height
-- How many pixels to push each overlapping bar away from its neighbours
local SPREAD_STEP      = 20
-- Smooth lerp speed (higher = snappier)
local LERP_SPEED       = 8

-- Internal state per nameplate frame
-- frame.npSpread = { targetY, currentY, baseY }

local function GetFrameScreenCenter(frame)
    local left  = frame:GetLeft()
    local top   = frame:GetTop()
    local right = frame:GetRight()
    local bot   = frame:GetBottom()
    if not left then return nil, nil end
    return (left + right) * 0.5, (top + bot) * 0.5
end

-- Returns the base Y offset the healthBar should sit at when NOT spread
local function GetBaseY(frame)
    if frame.npSpread then
        return frame.npSpread.baseY
    end
    return 0
end

-- Apply the current smooth Y offset to the healthBar
local function ApplyOffset(frame, y)
    if not frame.healthBar then return end
    local stackY = NotPlater:GetStackingSettings().margin.yStacking or 0
    frame.healthBar:ClearAllPoints()
    frame.healthBar:SetPoint("TOP", 0, stackY + y)
end

-- Tick: recompute target offsets and lerp toward them
local lastCheck = 0
local tickFrame = CreateFrame("Frame")
tickFrame:Hide()

tickFrame:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    if now - lastCheck < CHECK_INTERVAL then return end
    lastCheck = now

    local spreadConfig = NotPlater.db and
                         NotPlater.db.profile and
                         NotPlater.db.profile.spread
    if not spreadConfig or not spreadConfig.enable then
        -- Disabled: snap everything back to zero offset
        if NotPlater.frames then
            for frame in pairs(NotPlater.frames) do
                if frame.npSpread then
                    frame.npSpread.targetY  = 0
                    frame.npSpread.currentY = 0
                    ApplyOffset(frame, 0)
                end
            end
        end
        return
    end

    if not NotPlater.frames then return end

    -- Collect visible frames with screen positions
    local visible = {}
    for frame in pairs(NotPlater.frames) do
        if frame:IsShown() and frame.healthBar then
            local cx, cy = GetFrameScreenCenter(frame)
            if cx and cy then
                -- Initialise npSpread state
                if not frame.npSpread then
                    frame.npSpread = { targetY = 0, currentY = 0, baseY = 0 }
                end
                visible[#visible + 1] = { frame = frame, cx = cx, cy = cy }
            end
        end
    end

    if #visible == 0 then return end

    -- Sort top-to-bottom so the topmost nameplate gets offset +0, +1*step, etc.
    sort(visible, function(a, b) return a.cy > b.cy end)

    -- Reset all targets to 0 first
    for i = 1, #visible do
        visible[i].frame.npSpread.targetY = 0
    end

    -- Find groups of overlapping frames (same approximate screen position)
    -- and spread them out
    local processed = {}
    for i = 1, #visible do
        if not processed[i] then
            -- Build a cluster: all frames within OVERLAP_X/OVERLAP_Y of frame i
            local cluster = { i }
            for j = i + 1, #visible do
                if not processed[j] then
                    if abs(visible[i].cx - visible[j].cx) < OVERLAP_X and
                       abs(visible[i].cy - visible[j].cy) < OVERLAP_Y then
                        cluster[#cluster + 1] = j
                        processed[j] = true
                    end
                end
            end
            processed[i] = true

            if #cluster > 1 then
                -- Spread the cluster symmetrically around the centre
                local count  = #cluster
                local total  = (count - 1) * SPREAD_STEP
                local startY = total * 0.5   -- top bar pushed up by this amount
                for k = 1, count do
                    local offset = startY - (k - 1) * SPREAD_STEP
                    visible[cluster[k]].frame.npSpread.targetY = offset
                end
            end
        end
    end
end)

-- Smooth lerp via each frame's own OnUpdate
-- We piggy-back onto the healthBar's existing update or hook the nameplate OnUpdate.
-- To avoid touching other OnUpdate hooks, we use a single master lerp frame.
local lerpFrame = CreateFrame("Frame")
lerpFrame:Hide()
lerpFrame:SetScript("OnUpdate", function(self, elapsed)
    if not NotPlater.frames then return end
    local spreadConfig = NotPlater.db and
                         NotPlater.db.profile and
                         NotPlater.db.profile.spread
    local enabled = spreadConfig and spreadConfig.enable

    for frame in pairs(NotPlater.frames) do
        if frame.npSpread and frame:IsShown() and frame.healthBar then
            local s    = frame.npSpread
            local tgt  = enabled and s.targetY or 0
            local diff = tgt - s.currentY
            if abs(diff) < 0.5 then
                if s.currentY ~= tgt then
                    s.currentY = tgt
                    ApplyOffset(frame, tgt)
                end
            else
                s.currentY = s.currentY + diff * math.min(1, LERP_SPEED * elapsed)
                ApplyOffset(frame, s.currentY)
            end
        end
    end
end)

-- Public API -------------------------------------------------------------------

function NotPlater:SpreadEnable()
    local cfg = self.db and self.db.profile and self.db.profile.spread
    if not cfg then return end
    cfg.enable = true
    tickFrame:Show()
    lerpFrame:Show()
end

function NotPlater:SpreadDisable()
    local cfg = self.db and self.db.profile and self.db.profile.spread
    if cfg then cfg.enable = false end
    -- Frames will be snapped back by the tick/lerp loops above
end

function NotPlater:SpreadToggle()
    local cfg = self.db and self.db.profile and self.db.profile.spread
    if not cfg then return end
    if cfg.enable then
        self:SpreadDisable()
    else
        self:SpreadEnable()
    end
end

function NotPlater:SpreadOnAddonLoaded()
    -- Ensure config key exists
    if self.db and self.db.profile then
        if self.db.profile.spread == nil then
            self.db.profile.spread = { enable = true }
        end
    end
    if self.db and self.db.profile and self.db.profile.spread and
       self.db.profile.spread.enable then
        tickFrame:Show()
        lerpFrame:Show()
    end
    -- Register slash command: /npspread
    if self.RegisterChatCommand then
        self:RegisterChatCommand("npspread", function()
            NotPlater:SpreadToggle()
            local state = NotPlater.db.profile.spread.enable and "|cff00ff00ON|r" or "|cffff4444OFF|r"
            DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00NotPlater Spread:|r " .. state)
        end)
    end
end

-- Reset a single frame's offset (e.g. when it hides)
function NotPlater:SpreadResetFrame(frame)
    if frame.npSpread then
        frame.npSpread.targetY  = 0
        frame.npSpread.currentY = 0
        ApplyOffset(frame, 0)
    end
end
