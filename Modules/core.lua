--------------------------------------------------------------------------------
-- core.lua (UPDATED for single-step teleport, exit prompt, and performance)
-- Update by DeVaughnDawn

-- 1. Made use of local variables, and stored a reference to our main mod table (InsideStation)
-- 2. Added a short "teleport_cooldown" so we don't re-trigger area checks 
-- immediately after teleport (in case final pos is still within r_1).
-- 3. Added robust in-line comments to ensure all changes are clear for future updating.
--------------------------------------------------------------------------------

-- Import external and internal modules
local Cron = require('External/Cron.lua')
local Data = require("Tools/data.lua")
local Def = require('Tools/def.lua')
local HUD = require('Modules/hud.lua')
local Log = require("Tools/log.lua") -- [ADDED] Imported as a local variable to avoid global namespace pollution

-- Debugging: Check if Log is loaded
if not Log then
    print("[Error] Failed to load Log module in core.lua.")
else
    print("[Debug] Log module loaded successfully in core.lua.")
end

local Core = {}
Core.__index = Core

function Core:New(modRef)
    local obj = {}
    setmetatable(obj, self)

    ----------------------------------------------------------------------------
    -- [CHANGE] Store a reference to your main mod table (InsideStation),
    -- so we can call self.insideStationRef:SetActive(...) instead of using a global.
    ----------------------------------------------------------------------------
    obj.insideStationRef = modRef
    obj.log_obj = Log:New() -- [FIXED] Using local Log instead of global

    -- Debugging: Check if log_obj is created
    if not obj.log_obj then
        print("[Error] Failed to create log_obj in Core:New.")
    else
        print("[Debug] log_obj created successfully in Core:New.")
    end

    obj.log_obj:SetLevel(Log.LogLevel.Info, "Core") -- Assuming LogLevel is defined within log.lua
    obj.hud_obj = HUD:New()

    ----------------------------------------------------------------------------
    -- [CHANGE] Increase area_check_interval to 1.0 (instead of 0.2) to reduce
    -- CPU load near the station. This means we only do area checks once per second.
    ----------------------------------------------------------------------------
    obj.area_check_interval = 1.0  
    obj.mappin_check_interval = 10.0 -- keep as is or adjust
    obj.teleport_delay = 0.3         -- short glitch effect delay

    ----------------------------------------------------------------------------
    -- Removed old step-based fields (teleport_resolution, teleport_division_num)
    -- since we are now doing a single-step immediate teleport.
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Variables to track the entry/exit indices.
    ----------------------------------------------------------------------------
    obj.entry_area_index = 0
    obj.exit_area_index = 0

    ----------------------------------------------------------------------------
    -- [CHANGE] We'll add a short "teleport_cooldown" to skip area checks 
    -- immediately after teleport, preventing re-trigger if we remain inside r_1.
    ----------------------------------------------------------------------------
    obj.teleport_cooldown = false

    ----------------------------------------------------------------------------
    -- Cron IDs if needed
    ----------------------------------------------------------------------------
    obj.area_check_cron_id = nil
    obj.mappin_cron_id = nil

    return obj
end

function Core:Initialize()
    self.hud_obj:Initialize()

    ----------------------------------------------------------------------------
    -- Observers: register them once on init
    ----------------------------------------------------------------------------
    Observe("PlayerPuppet", "OnAction", function(this, action, consumer)
        local action_name = action:GetName(action).value
        local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        self.log_obj:Debug(
            "Action Name: " .. action_name ..
            " Type: " .. action_type ..
            " Value: " .. action_value
        )

        if not self:IsInChoiceArea() then
            return
        end

        -- If the user pressed "ChoiceApply," do an immediate teleport.
        -- Only do so if not on cooldown (to avoid re-teleports).
        if action_name == "ChoiceApply" and action_type == "BUTTON_PRESSED" then
            if not self.teleport_cooldown then
                self:Teleport()
            end
        end
    end)

    Observe("DataTerm", "OnAreaEnter", function(this, evt)
        self.log_obj:Info("DataTerm OnAreaEnter")
        this:OpenSubwayGate()
    end)

    Observe("DataTerm", "OnAreaExit", function(this, evt)
        self.log_obj:Info("DataTerm OnAreaExit")
        this:CloseSubwayGate()
    end)

    ----------------------------------------------------------------------------
    -- Cron-based tasks: area checks + mappin updates
    ----------------------------------------------------------------------------
    -- These tasks run frequently only while mod is "active." 
    ----------------------------------------------------------------------------

    -- [CHANGE] area_check_cron every 1.0s instead of 0.2s to reduce performance impact.
    self.area_check_cron_id = Cron.Every(self.area_check_interval, { tick = 1 }, function()
        -- If we're on a cooldown after teleport, skip area check to avoid re-trigger.
        if self.teleport_cooldown then
            return
        end

        local area_code = self:CheckTeleportAreaType()
        if area_code == Def.TeleportAreaType.EntranceChoice then
            self.hud_obj:ShowChoice(Def.ChoiceVariation.Enter, 1)
            self.insideStationRef:SetActive(true)

        elseif area_code == Def.TeleportAreaType.PlatformChoice then
            self.hud_obj:ShowChoice(Def.ChoiceVariation.Exit, 1)
            self.insideStationRef:SetActive(true)

        else
            self.hud_obj:HideChoice()
            self.insideStationRef:SetActive(false)
        end
    end)

    self.mappin_cron_id = Cron.Every(self.mappin_check_interval, { tick = 1 }, function()
        self.hud_obj:UpdateMappins()
    end)
end

------------------------------------------------------------------------------
-- CheckTeleportAreaType
-- Returns the TeleportAreaType or sets it to None if none found.
-- Also a good place to decide if we're too far from any station overall.
------------------------------------------------------------------------------
function Core:CheckTeleportAreaType()
    ----------------------------------------------------------------------------
    -- If we just teleported, skip area checks briefly so we don't re-trigger.
    ----------------------------------------------------------------------------
    if self.teleport_cooldown then
        return Def.TeleportAreaType.None
    end

    local player = Game.GetPlayer()
    if not player then
        self.log_obj:Debug("Player is nil")
        return Def.TeleportAreaType.None
    end

    local player_pos = player:GetWorldPosition()
    local active_station_id = self:GetStationID()

    if not active_station_id or active_station_id == 0 then
        self.hud_obj:SetTeleportAreaType(Def.TeleportAreaType.None)
        return Def.TeleportAreaType.None
    end

    -- Attempt to find a matching EntryArea
    for index, area_info in ipairs(Data.EntryArea) do
        if active_station_id == area_info.st_id then
            local distance = Vector4.Distance(player_pos, Vector4.new(area_info.pos.x, area_info.pos.y, area_info.pos.z, 1))
            if distance < area_info.r_1 then
                if area_info.is_choice_ui then
                    self.entry_area_index = index
                    self.exit_area_index = 0
                    self.hud_obj:SetTeleportAreaType(Def.TeleportAreaType.EntranceChoice)
                    return Def.TeleportAreaType.EntranceChoice
                elseif self.hud_obj:GetTeleportAreaType() ~= Def.TeleportAreaType.EntranceImmediately then
                    self.entry_area_index = index
                    self.exit_area_index = 0
                    self.hud_obj:SetTeleportAreaType(Def.TeleportAreaType.EntranceImmediately)

                    -- Single-step teleport from code below
                    if not self.teleport_cooldown then
                        self:Teleport()
                    end
                    return Def.TeleportAreaType.EntranceImmediately
                end
            end
        end
    end

    -- Attempt to find a matching ExitArea
    for index, area_info in ipairs(Data.ExitArea) do
        if active_station_id == area_info.st_id then
            local distance = Vector4.Distance(player_pos, Vector4.new(area_info.pos.x, area_info.pos.y, area_info.pos.z, 1))
            if distance < area_info.r_1 then
                if area_info.is_choice_ui then
                    self.entry_area_index = 0
                    self.exit_area_index = index
                    self.hud_obj:SetTeleportAreaType(Def.TeleportAreaType.PlatformChoice)
                    return Def.TeleportAreaType.PlatformChoice
                elseif self.hud_obj:GetTeleportAreaType() ~= Def.TeleportAreaType.PlatformImmediately then
                    self.entry_area_index = 0
                    self.exit_area_index = index
                    self.hud_obj:SetTeleportAreaType(Def.TeleportAreaType.PlatformImmediately)

                    if not self.teleport_cooldown then
                        self:Teleport()
                    end
                    return Def.TeleportAreaType.PlatformImmediately
                end
            end
        end
    end

    self.hud_obj:SetTeleportAreaType(Def.TeleportAreaType.None)
    return Def.TeleportAreaType.None
end

------------------------------------------------------------------------------
-- Teleport
-- Single-step immediate teleport with optional glitch effect.
------------------------------------------------------------------------------
function Core:Teleport()
    local player = Game.GetPlayer()
    if not player then
        self.log_obj:Critical("No player to teleport!")
        return
    end

    -- We'll gather the final position/angle from the current entry/exit indexes
    local new_pos, new_angle = self:GetTeleportDestination()
    if not new_pos or not new_angle then
        self.log_obj:Debug("No valid teleport destination found.")
        return
    end

    self:PlayFTEffect()

    ----------------------------------------------------------------------------
    -- [CHANGE] We'll add a short "teleport_cooldown" so we don't re-trigger area checks 
    -- immediately after teleport (in case final pos is still within r_1).
    ----------------------------------------------------------------------------
    self.teleport_cooldown = true

    Cron.After(self.teleport_delay, function()
        Game.GetTeleportationFacility():Teleport(player, new_pos, new_angle)

        -- After the teleport, wait a second or two to avoid re-trigger
        Cron.After(0.5, function()
            self.teleport_cooldown = false
        end)
    end)
end

------------------------------------------------------------------------------
-- Retrieve single-step teleport destination
------------------------------------------------------------------------------
function Core:GetTeleportDestination()
    -- If we're an entry scenario
    if self.entry_area_index ~= 0 and self.exit_area_index == 0 then
        local data = Data.EntryArea[self.entry_area_index]
        if data then
            local pos = data.telepos
            local ang = data.tele_angle
            local new_pos = Vector4.new(pos.x, pos.y, pos.z, 1)
            local new_angle = EulerAngles.new(ang.roll, ang.pitch, ang.yaw)
            return new_pos, new_angle
        end

    -- If we're an exit scenario
    elseif self.entry_area_index == 0 and self.exit_area_index ~= 0 then
        local data = Data.ExitArea[self.exit_area_index]
        if data then
            local pos = data.telepos
            local ang = data.tele_angle
            local new_pos = Vector4.new(pos.x, pos.y, pos.z, 1)
            local new_angle = EulerAngles.new(ang.roll, ang.pitch, ang.yaw)
            return new_pos, new_angle
        end
    end

    return nil, nil
end

------------------------------------------------------------------------------
-- Optional glitch effect
------------------------------------------------------------------------------
function Core:PlayFTEffect()
    local player = Game.GetPlayer()
    if player then
        GameObjectEffectHelper.StartEffectEvent(player, "fast_travel_glitch", true, worldEffectBlackboard.new())
    end
end

------------------------------------------------------------------------------
-- Utility
------------------------------------------------------------------------------
function Core:GetStationID()
    return Game.GetQuestsSystem():GetFact(CName.new("ue_metro_active_station"))
end

function Core:IsInChoiceArea()
    return (
        self.hud_obj.teleport_area_type == Def.TeleportAreaType.EntranceChoice or
        self.hud_obj.teleport_area_type == Def.TeleportAreaType.PlatformChoice
    )
end

return Core
