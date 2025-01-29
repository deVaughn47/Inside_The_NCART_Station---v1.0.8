--------------------------------------------------------------------------------
-- hud.lua (UPDATED)
-- Update by DeVaughnDawn
--------------------------------------------------------------------------------

-- Explanation of Changes:
-- 1. Changed string.format specifier from %d to %s and converted mappin_id to string to handle userdata.
-- 2. Added comments to explain changes and ensure clarity.
-- 3. Ensured consistency with updated def.lua definitions.
-- 4. Enhanced logging for better debugging.

-- Import external and internal modules
local Data = require("Tools/data.lua")
local Def = require('Tools/def.lua')
local Log = require("Tools/log.lua") -- Imported as a local variable to avoid global namespace pollution
local HUD = {}
HUD.__index = HUD

function HUD:New()
    local obj = {}
    setmetatable(obj, self)

    -- Initialize logging
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(Log.LogLevel.Info, "HUD")

    -- Mappin offset
    obj.mappin_pos_offset_z = 2.0

    -- Interaction UI references
    obj.interaction_ui_base = nil
    obj.interaction_hub = nil
    obj.selected_choice_index = 1
    obj.teleport_area_type = Def.TeleportAreaType.None
    obj.is_showing_choice = false -- Initialize as false

    -- Track all registered mappins so we can remove them later
    obj.mappin_id_list = {}

    return obj
end

function HUD:Initialize()
    -- Capture 'self' in a local variable 'hud' to use within override functions
    local hud = self

    ----------------------------------------------------------------------------
    -- Observers for Interaction UI. Capture references to 'interaction_ui_base'
    -- so we can inject our custom choice UI data.
    ----------------------------------------------------------------------------
    Observe("InteractionUIBase", "OnInitialize", function(this)
        hud.interaction_ui_base = this
        hud.log_obj:Debug("interaction_ui_base initialized.")
    end)

    Observe("InteractionUIBase", "OnDialogsData", function(this)
        hud.interaction_ui_base = this
        hud.log_obj:Debug("interaction_ui_base received OnDialogsData.")
    end)

    ----------------------------------------------------------------------------
    -- Override: OnDialogsData
    -- If we're in a "choice area," we append our custom 'interaction_hub' to
    -- the existing choice hubs. Otherwise, we pass the data through unmodified.
    ----------------------------------------------------------------------------
    Override("InteractionUIBase", "OnDialogsData", function(_, value, wrapped_method)
        -- Only override if we have a valid UI base and the choice UI is enabled
        if hud.interaction_ui_base and hud:IsEnableChoiceUI() then
            hud.log_obj:Debug("Overriding OnDialogsData with custom interaction_hub.")

            local data = FromVariant(value)
            local hubs = data.choiceHubs

            -- Ensure 'hubs' is a valid table
            if type(hubs) == "table" then
                table.insert(hubs, hud.interaction_hub)
                data.choiceHubs = hubs
            else
                hud.log_obj:Error("choiceHubs is not a table.")
            end

            wrapped_method(ToVariant(data))
        else
            wrapped_method(value)
        end
    end)

    ----------------------------------------------------------------------------
    -- Override: OnDialogsSelectIndex
    ----------------------------------------------------------------------------
    Override("InteractionUIBase", "OnDialogsSelectIndex", function(_, index, wrapped_method)
        hud.log_obj:Debug("Overriding OnDialogsSelectIndex.")

        if hud:IsEnableChoiceUI() then
            hud.log_obj:Debug(string.format("Forcing selected index to %d.", hud.selected_choice_index - 1))
            wrapped_method(hud.selected_choice_index - 1)
        else
            hud.selected_choice_index = index + 1
            hud.log_obj:Debug(string.format("Selected index updated to %d.", hud.selected_choice_index))
            wrapped_method(index)
        end
    end)

    ----------------------------------------------------------------------------
    -- Override: OnDialogsActivateHub
    -- Prevent the game's default logic from overwriting our custom hub if the
    -- choice UI is enabled.
    ----------------------------------------------------------------------------
    Override("dialogWidgetGameController", "OnDialogsActivateHub", function(_, id, wrapped_method)
        hud.log_obj:Debug("Overriding OnDialogsActivateHub.")

        if hud:IsEnableChoiceUI() then
            local id_
            if hud.interaction_hub == nil then
                id_ = id
                hud.log_obj:Debug("interaction_hub is nil. Using original hub ID.")
            else
                id_ = hud.interaction_hub.id
                hud.log_obj:Debug(string.format("Using custom hub ID: %d.", id_))
            end
            wrapped_method(id_)
        else
            wrapped_method(id)
        end
    end)
end

------------------------------------------------------------------------------
-- Teleport Area Type Helpers
------------------------------------------------------------------------------

function HUD:SetTeleportAreaType(area_type)
    self.teleport_area_type = area_type
    -- Safely access TeleportAreaTypeNames, provide fallback if nil
    local area_type_name = "Unknown"
    if Def.TeleportAreaTypeNames and Def.TeleportAreaTypeNames[area_type] then
        area_type_name = Def.TeleportAreaTypeNames[area_type]
    end
    self.log_obj:Debug(string.format("Teleport area type set to %s.", area_type_name))
end

function HUD:GetTeleportAreaType()
    return self.teleport_area_type
end

function HUD:IsEnableChoiceUI()
    return (
        self.teleport_area_type == Def.TeleportAreaType.EntranceChoice or
        self.teleport_area_type == Def.TeleportAreaType.PlatformChoice
    )
end

------------------------------------------------------------------------------
-- Choice UI Setup
------------------------------------------------------------------------------

function HUD:SetChoice(variation)
    local tmp_list = {}

    local hub = gameinteractionsvisListChoiceHubData.new()
    hub.title = GetLocalizedText("LocKey#83821")
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
    hub.hubPriority = 1

    -- Use a unique ID for the hub to prevent conflicts
    hub.id = 69420 + math.random(10000, 99999)

    ----------------------------------------------------------------------------
    -- Build the single choice option (Enter or Exit)
    ----------------------------------------------------------------------------
    local icon = TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceCaptionParts.GetInIcon")
    local caption_part = gameinteractionsChoiceCaption.new()
    local choice_type = gameinteractionsChoiceTypeWrapper.new()

    if icon then
        caption_part:AddPartFromRecord(icon)
    else
        self.log_obj:Error("Failed to retrieve ChoiceCaptionParts.GetInIcon.")
    end

    choice_type:SetType(gameinteractionsChoiceType.Selected)

    local choice = gameinteractionsvisListChoiceData.new()
    choice.inputActionName = CName.new("None")
    choice.captionParts = caption_part
    choice.type = choice_type

    if variation == Def.ChoiceVariation.Enter then
        choice.localizedName = GetLocalizedText("LocKey#36926") -- "Enter"
    elseif variation == Def.ChoiceVariation.Exit then
        choice.localizedName = GetLocalizedText("LocKey#36500") -- "Exit"
    else
        self.log_obj:Error("Invalid ChoiceVariation provided to SetChoice.")
    end

    table.insert(tmp_list, choice)

    hub.choices = tmp_list
    self.interaction_hub = hub

    self.log_obj:Debug(string.format("Custom choice hub created with ID %d.", hub.id))
end

function HUD:ShowChoice(variation, selected_index)
    -- If we're already showing the choice, skip
    if self.is_showing_choice then
        self.log_obj:Debug("Attempted to show choice, but already showing.")
        return
    end
    self.is_showing_choice = true
    self.log_obj:Debug("Showing choice UI.")

    -- Set the internal index and build the hub
    self.selected_choice_index = selected_index
    self:SetChoice(variation)

    -- If no valid UI base, skip any further logic
    if not self.interaction_ui_base then
        self.log_obj:Record(LogLevel.Warning, "interaction_ui_base is nil in ShowChoice")
        self.is_showing_choice = false -- Reset flag since we can't show choice
        return
    end

    ----------------------------------------------------------------------------
    -- Update blackboard so the game "sees" our custom hub
    ----------------------------------------------------------------------------
    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)

    interaction_blackboard:SetInt(ui_interaction_define.ActiveChoiceHubID, self.interaction_hub.id)
    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)

    -- Force the UI to show our new choice
    self.interaction_ui_base:OnDialogsSelectIndex(selected_index - 1)
    self.interaction_ui_base:OnDialogsData(data)
    self.interaction_ui_base:OnInteractionsChanged()
    self.interaction_ui_base:UpdateListBlackboard()
    self.interaction_ui_base:OnDialogsActivateHub(self.interaction_hub.id)

    self.log_obj:Debug("Choice UI displayed successfully.")
end

function HUD:HideChoice()
    -- If we're not showing a choice, do nothing
    if not self.is_showing_choice then
        self.log_obj:Debug("Attempted to hide choice, but no choice is being shown.")
        return
    end
    self.is_showing_choice = false
    self.log_obj:Debug("Hiding choice UI.")

    -- Clear the reference to our hub
    self.interaction_hub = nil

    -- If no valid UI base, skip
    if not self.interaction_ui_base then
        self.log_obj:Debug("interaction_ui_base is nil in HideChoice.")
        return
    end

    ----------------------------------------------------------------------------
    -- Re-apply the blackboard data minus our custom hub
    ----------------------------------------------------------------------------
    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)
    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)

    self.interaction_ui_base:OnDialogsData(data)

    self.log_obj:Debug("Choice UI hidden successfully.")
end

------------------------------------------------------------------------------
-- Mappin Management
------------------------------------------------------------------------------

function HUD:UpdateMappins()
    self.log_obj:Debug("Updating mappins.")
    self:RemoveMappins()

    -- If no player, skip
    local player = Game.GetPlayer()
    if not player then
        self.log_obj:Debug("Player not found. Skipping mappin update.")
        return
    end

    -- Retrieve station ID once; skip multiple calls to self:GetStationID()
    local stationID = self:GetStationID()
    if not stationID or stationID == 0 then
        self.log_obj:Debug("No active station ID found. Skipping mappin update.")
        return
    end

    ----------------------------------------------------------------------------
    -- Add mappins for nearby EntryArea points
    ----------------------------------------------------------------------------
    for _, area_info in ipairs(Data.EntryArea) do
        if stationID == area_info.st_id then
            local position = Vector4.new(
                area_info.pos.x,
                area_info.pos.y,
                area_info.pos.z + self.mappin_pos_offset_z,
                1
            )
            local distance = Vector4.Distance(player:GetWorldPosition(), position)

            -- Only register a mappin if within r_2 distance
            if distance < area_info.r_2 then
                local mappin_data = MappinData.new()
                mappin_data.mappinType = TweakDBID.new('Mappins.InteractionMappinDefinition')
                mappin_data.variant = gamedataMappinVariant.GetInVariant
                mappin_data.visibleThroughWalls = true

                local mappin_id = Game.GetMappinSystem():RegisterMappin(mappin_data, position)
                table.insert(self.mappin_id_list, mappin_id)

                self.log_obj:Debug(string.format("Registered mappin for EntryArea ID %d at position (%.2f, %.2f, %.2f).", 
                    area_info.st_id, position.x, position.y, position.z))
            else
                self.log_obj:Debug(string.format("EntryArea ID %d is beyond r_2 distance (%.2f).", area_info.st_id, distance))
            end
        end
    end

    ----------------------------------------------------------------------------
    -- Add mappins for nearby ExitArea points
    ----------------------------------------------------------------------------
    for _, area_info in ipairs(Data.ExitArea) do
        if stationID == area_info.st_id then
            local position = Vector4.new(
                area_info.pos.x,
                area_info.pos.y,
                area_info.pos.z + self.mappin_pos_offset_z,
                1
            )
            local distance = Vector4.Distance(player:GetWorldPosition(), position)

            if distance < area_info.r_2 then
                local mappin_data = MappinData.new()
                mappin_data.mappinType = TweakDBID.new('Mappins.InteractionMappinDefinition')
                mappin_data.variant = gamedataMappinVariant.GetInVariant
                mappin_data.visibleThroughWalls = true

                local mappin_id = Game.GetMappinSystem():RegisterMappin(mappin_data, position)
                table.insert(self.mappin_id_list, mappin_id)

                self.log_obj:Debug(string.format("Registered mappin for ExitArea ID %d at position (%.2f, %.2f, %.2f).", 
                    area_info.st_id, position.x, position.y, position.z))
            else
                self.log_obj:Debug(string.format("ExitArea ID %d is beyond r_2 distance (%.2f).", area_info.st_id, distance))
            end
        end
    end
end

function HUD:RemoveMappins()
    -- If there are any existing mappins, unregister them
    if #self.mappin_id_list > 0 then
        for _, mappin_id in ipairs(self.mappin_id_list) do
            Game.GetMappinSystem():UnregisterMappin(mappin_id)
            -- Changed %d to %s and used tostring(mappin_id) to handle userdata
            self.log_obj:Debug(string.format("Unregistered mappin ID %s.", tostring(mappin_id)))
        end
        self.mappin_id_list = {}
    else
        self.log_obj:Debug("No mappins to remove.")
    end
end

------------------------------------------------------------------------------
-- Utility
------------------------------------------------------------------------------

function HUD:GetStationID()
    return Game.GetQuestsSystem():GetFact(CName.new("ue_metro_active_station"))
end

return HUD
