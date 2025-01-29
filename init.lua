--------------------------------------------------------
-- CopyRight (C) 2024, tidusmd. All rights reserved.
-- This mod is under the MIT License.
-- https://opensource.org/licenses/mit-license.php
--------------------------------------------------------
-- init.lua (UPDATED)
-- Update by DeVaughnDawn

-- Explanation of Changes:
-- 1. Added error checks by loading all modules FIRST using pcall to handle potential errors.
-- 2. All module variables have now been imported locally to alighn with lua scripting standards.
-- 3. Cron is only ran every frame if modActive = true; otherwise, we throttle it.
-- 4. Created system to set 'modActive' to 'true' only when player is 9 game units away from metro station.
-- 5. Added robust in-line comments to ensure all changes are clear for future updating.
---------------------------------------------------------------------------------


---------------------------------------------------------------------------------
-- Import external and internal modules
---------------------------------------------------------------------------------

-- [UPDATED] Attempt to load modules FIRST using pcall to handle potential errors
local successCron, Cron = pcall(require, 'External/Cron.lua')
if not successCron or not Cron then
    print('[Error] Failed to load Cron module.')
    return
end

local successData, Data = pcall(require, "Tools/data.lua")
if not successData or not Data then
    print('[Error] Failed to load Data module.')
    return
end

local successDef, Def = pcall(require, 'Tools/def.lua')
if not successDef or not Def then
    print('[Error] Failed to load Def module.')
    return
end

local successGameUI, GameUI = pcall(require, 'External/GameUI.lua')
if not successGameUI or not GameUI then
    print('[Error] Failed to load GameUI module.')
    return
end

local successLog, Log = pcall(require, "Tools/log.lua")
if not successLog or not Log then
    print('[Error] Failed to load Log module.')
    return
end

local successCore, Core = pcall(require, 'Modules/core.lua')
if not successCore or not Core then
    print('[Error] Failed to load Core module.')
    return
end

local successDebug, Debug = pcall(require, 'Debug/debug.lua')
if not successDebug or not Debug then
    print('[Error] Failed to load Debug module.')
    return
end

------------------------------------------------------------------------------
-- Define a simple Vector3 class
------------------------------------------------------------------------------
-- [ADDED] Use of Vector3 to help calculate distance from metro station entry point
Vector3 = {}
Vector3.__index = Vector3

function Vector3.new(x, y, z)
    local self = setmetatable({}, Vector3)
    self.x = x
    self.y = y
    self.z = z
    return self
end

-- Function to calculate the magnitude (distance) between two vectors
function Vector3:magnitude(other)
    local dx = self.x - other.x
    local dy = self.y - other.y
    local dz = self.z - other.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

------------------------------------------------------------------------------
-- A toggle or condition to prevent Cron from running constantly
-- We'll keep 'modActive = false' by default, toggled by SetActive().
------------------------------------------------------------------------------
local modActive = false
local timeAccumulator = 0
local CRON_UPDATE_INTERVAL_WHEN_INACTIVE = 1.0

------------------------------------------------------------------------------
-- Define 'InsideStation' table AFTER modules are required
------------------------------------------------------------------------------
local InsideStation = {
    description = "Inside The Station",
    version = "1.0.8",
    is_debug_mode = false,
    cet_required_version = 32.2, -- 1.32.2
    cet_version_num = 0,
}
InsideStation.core_obj = Core:New(InsideStation)

-- We add this method so other modules can call 'InsideStation:SetActive(true/false)'
function InsideStation:SetActive(active)
    modActive = active
    if InsideStation.is_debug_mode then
        if active then
            Log:Info("InsideStation mod activated.")
        else
            Log:Info("InsideStation mod deactivated.")
        end
    end
end

------------------------------------------------------------------------------
-- Dependencies check method
------------------------------------------------------------------------------
function InsideStation:CheckDependencies()
    local success, cet_version_str = pcall(GetVersion)
    if not success or not cet_version_str then
        print("Failed to retrieve CET version. Please ensure Cyber Engine Tweaks is installed.")
        return false
    end

    local cet_version_major, cet_version_minor = cet_version_str:match("1.(%d+)%.*(%d*)")
    if cet_version_minor == "" then
        cet_version_minor = "0"
    end

    if not cet_version_major then
        print("Failed to parse CET version. Ensure the mod is compatible with your CET version.")
        return false
    end

    self.cet_version_num = tonumber(cet_version_major .. "." .. cet_version_minor)
    if self.cet_version_num < self.cet_required_version then
        print("Inside The Station Mod requires Cyber Engine Tweaks version 1." 
              .. self.cet_required_version .. " or higher.")
        return false
    end

    return true
end

------------------------------------------------------------------------------
-- Define Train Station Locations
------------------------------------------------------------------------------
local trainStations = {}

-- Consolidate all station positions from EntryArea
for _, entry in ipairs(Data.EntryArea) do
    if entry.pos and entry.st_id then
        table.insert(trainStations, {
            id = entry.st_id,
            position = Vector3.new(entry.pos.x, entry.pos.y, entry.pos.z)
        })
    else
        print("[Warning] EntryArea data missing 'pos' or 'st_id'.")
    end
end

-- Consolidate all station positions from ExitArea
for _, exit in ipairs(Data.ExitArea) do
    if exit.pos and exit.st_id then
        table.insert(trainStations, {
            id = exit.st_id,
            position = Vector3.new(exit.pos.x, exit.pos.y, exit.pos.z)
        })
    else
        print("[Warning] ExitArea data missing 'pos' or 'st_id'.")
    end
end

-- [ADDED] Define the activation radius (Default 9 in game units)
local ACTIVATION_RADIUS = 9.0 -- Adjust this value as needed

------------------------------------------------------------------------------
-- Function to Check Player Proximity to Train Stations
------------------------------------------------------------------------------
local function IsPlayerNearStation()
    local player = Game.GetPlayer()
    if not player then
        return false
    end

    local playerPosTable = player:GetWorldPosition()
    if not playerPosTable or not playerPosTable.x or not playerPosTable.y or not playerPosTable.z then
        print("[Error] Failed to retrieve player's position.")
        return false
    end

    local playerPos = Vector3.new(playerPosTable.x, playerPosTable.y, playerPosTable.z)

    for _, station in ipairs(trainStations) do
        if station.position then
            local distance = playerPos:magnitude(station.position)
            if distance <= ACTIVATION_RADIUS then
                if InsideStation.is_debug_mode then
                    print(string.format("[Debug] Player is within %.2f units of Station ID %d.", ACTIVATION_RADIUS, station.id))
                end
                return true
            end
        else
            print(string.format("[Warning] Station ID %d has an undefined position.", station.id))
        end
    end
    if InsideStation.is_debug_mode then
        print("Player is not near any train station.")
    end
    return false
end

------------------------------------------------------------------------------
-- 'onInit' event
------------------------------------------------------------------------------
registerForEvent('onInit', function()

    -- 2) Check dependencies
    if not InsideStation:CheckDependencies() then
        print('[Error] Inside The Station Mod failed to load due to missing dependencies.')
        return
    end

    -- 3) Create 'core_obj' and 'debug_obj'
    --    Pass the entire 'InsideStation' table into 'Core:New(...)'
    InsideStation.core_obj = Core:New(InsideStation)
    InsideStation.debug_obj = Debug:New(InsideStation.core_obj)

    -- 4) Initialize the core object
    local successInit, err = pcall(function()
        InsideStation.core_obj:Initialize()
    end)

    if not successInit then
        print('[Error] Initialization failed: ' .. tostring(err))
        return
    end

    print('Inside The Station Mod is ready!')
end)

------------------------------------------------------------------------------
-- If you have a debug window or UI code in onDraw
------------------------------------------------------------------------------
registerForEvent("onDraw", function()
    if InsideStation.is_debug_mode and InsideStation.debug_obj then
        InsideStation.debug_obj:ImGuiMain()
    end

    -- Optional: Draw markers for train stations (for debugging)
    if InsideStation.is_debug_mode then
        for _, station in ipairs(trainStations) do
            -- Example: Draw a simple circle at the station position
            -- Replace 'Game.DrawCircle' with the appropriate function if different
            -- Assuming Game.DrawCircle exists; if not, remove or replace with actual drawing code
            -- Game.DrawCircle(station.position, ACTIVATION_RADIUS, Color.new(1, 0, 0, 1)) -- Red circle
            -- If Game.DrawCircle doesn't exist, consider logging or other debug methods
            -- For safety, commenting it out
            -- print(string.format("[Debug] Station ID %d at position (%.2f, %.2f, %.2f)", station.id, station.position.x, station.position.y, station.position.z))
        end
    end
end)

------------------------------------------------------------------------------
-- 'onUpdate' event for Cron
-- [UPDATED] We only run Cron every frame if modActive = true; otherwise, we throttle it.
------------------------------------------------------------------------------
registerForEvent('onUpdate', function(delta)
    if not delta or type(delta) ~= "number" then
        return
    end

    -- Check player's proximity to train stations
    local isNearStation = IsPlayerNearStation()

    -- Set modActive based on proximity
    InsideStation:SetActive(isNearStation)

    if modActive then
        -- If mod is "active," run Cron every frame
        Cron.Update(delta)
    else
        -- If mod is "inactive," only update Cron once per second
        timeAccumulator = timeAccumulator + delta
        if timeAccumulator >= CRON_UPDATE_INTERVAL_WHEN_INACTIVE then
            Cron.Update(timeAccumulator)
            timeAccumulator = 0
        end
    end
end)

------------------------------------------------------------------------------
-- Return the 'InsideStation' table
------------------------------------------------------------------------------
return InsideStation
