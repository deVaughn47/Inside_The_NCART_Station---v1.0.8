--------------------------------------------------------------------------------
-- debug.lua (UPDATED to avoid referencing global 'InsideStation')
-- Update by DeVaughnDawn
--------------------------------------------------------------------------------

-- Import external and internal modules
local Debug = {}
Debug.__index = Debug
local Data = require("Tools/data.lua")
local Def = require('Tools/def.lua')
local Log = require("Tools/log.lua") -- [ADDED] Imported as a local variable to avoid global namespace pollution


--------------------------------------------------------------------------------
-- We accept both 'core_obj' and an optional 'modRef' (InsideStation).
-- That way we can unify references if needed.
--------------------------------------------------------------------------------
function Debug:New(core_obj, modRef)
    local obj = {}
    setmetatable(obj, self)

    ----------------------------------------------------------------------------
    -- Store references
    ----------------------------------------------------------------------------
    obj.core_obj = core_obj             -- The 'core.lua' object
    obj.insideStationRef = modRef or {} -- The entire mod table if needed

    ----------------------------------------------------------------------------
    -- Debug feature toggles
    ----------------------------------------------------------------------------
    obj.is_im_gui_player_local = false
    obj.is_set_observer = false
    obj.is_im_gui_line_info = false
    obj.is_im_gui_station_info = false
    obj.is_im_gui_measurement = false
    obj.is_im_gui_ristrict = false

    return obj
end

--------------------------------------------------------------------------------
-- ImGuiMain
--------------------------------------------------------------------------------
function Debug:ImGuiMain()
    ImGui.Begin("InsideStation DEBUG WINDOW")
    ImGui.Text("Debug Mode : On")

    self:SetObserver()
    self:SetLogLevel()
    self:SelectPrintDebug()
    self:ImGuiPlayerPosition()
    self:ImGuiLineInfo()
    self:ImGuiStationInfo()
    self:ImGuiMeasurement()
    self:ImGuiExecuteFunction()

    ImGui.End()
end

--------------------------------------------------------------------------------
-- SetObserver
--------------------------------------------------------------------------------
function Debug:SetObserver()
    if not self.is_set_observer then
        -- Example reserved code
        -- Observe("DataTerm", "OnAreaEnter", function(...) end)
    end
    self.is_set_observer = true

    if self.is_set_observer then
        ImGui.SameLine()
        ImGui.Text("Observer : On")
    end
end

--------------------------------------------------------------------------------
-- SetLogLevel
--------------------------------------------------------------------------------
function Debug:SetLogLevel()
    local function GetKeyFromValue(table_, target_value)
        for key, value in pairs(table_) do
            if value == target_value then
                return key
            end
        end
        return nil
    end

    local function GetKeys(table_)
        local keys = {}
        for key, _ in pairs(table_) do
            table.insert(keys, key)
        end
        return keys
    end

    local selectedKey = GetKeyFromValue(LogLevel, MasterLogLevel)
    if ImGui.BeginCombo("LogLevel", selectedKey or "Unknown") then
        for _, key in ipairs(GetKeys(LogLevel)) do
            local isSelected = (selectedKey == key)
            if ImGui.Selectable(key, isSelected) then
                MasterLogLevel = LogLevel[key]
            end
            if isSelected then
                ImGui.SetItemDefaultFocus()
            end
        end
        ImGui.EndCombo()
    end
end

--------------------------------------------------------------------------------
-- SelectPrintDebug
--------------------------------------------------------------------------------
function Debug:SelectPrintDebug()
    PrintDebugMode = ImGui.Checkbox("Print Debug Mode", PrintDebugMode)
end

--------------------------------------------------------------------------------
-- ImGuiPlayerPosition
--------------------------------------------------------------------------------
function Debug:ImGuiPlayerPosition()
    self.is_im_gui_player_local = ImGui.Checkbox("[ImGui] Player Info", self.is_im_gui_player_local)
    if self.is_im_gui_player_local then
        local player = Game.GetPlayer()
        if not player then
            return
        end
        local player_pos = player:GetWorldPosition()
        local x_lo = string.format("%.2f", player_pos.x)
        local y_lo = string.format("%.2f", player_pos.y)
        local z_lo = string.format("%.2f", player_pos.z)
        ImGui.Text("Player World Pos : " .. x_lo .. ", " .. y_lo .. ", " .. z_lo)

        local player_quot = player:GetWorldOrientation()
        local player_angle = player_quot:ToEulerAngles()
        local roll = string.format("%.2f", player_angle.roll)
        local pitch = string.format("%.2f", player_angle.pitch)
        local yaw = string.format("%.2f", player_angle.yaw)

        ImGui.Text("Player World Angle : " .. roll .. ", " .. pitch .. ", " .. yaw)
        ImGui.Text("Player world Quot : "
            .. player_quot.i .. ", "
            .. player_quot.j .. ", "
            .. player_quot.k .. ", "
            .. player_quot.r)
    end
end

--------------------------------------------------------------------------------
-- ImGuiLineInfo
--------------------------------------------------------------------------------
function Debug:ImGuiLineInfo()
    self.is_im_gui_line_info = ImGui.Checkbox("[ImGui] Line Info", self.is_im_gui_line_info)
    if self.is_im_gui_line_info then
        local active_station = Game.GetQuestsSystem():GetFact(CName.new("ue_metro_active_station"))
        local next_station = Game.GetQuestsSystem():GetFact(CName.new("ue_metro_next_station"))
        local line = Game.GetQuestsSystem():GetFact(CName.new("ue_metro_track_selected"))

        ImGui.Text("Activate Station : " .. active_station)
        ImGui.Text("Next Station : " .. next_station)
        ImGui.Text("Line : " .. line)
    end
end

--------------------------------------------------------------------------------
-- ImGuiStationInfo
--------------------------------------------------------------------------------
function Debug:ImGuiStationInfo()
    self.is_im_gui_station_info = ImGui.Checkbox("[ImGui] Station Info", self.is_im_gui_station_info)
    if self.is_im_gui_station_info then
        if self.core_obj and self.core_obj.hud_obj then
            local telep_area_type = self.core_obj.hud_obj.teleport_area_type
            ImGui.Text("Teleport Area Type : " .. tostring(telep_area_type))
        else
            ImGui.Text("No HUD or core_obj available.")
        end
    end
end

--------------------------------------------------------------------------------
-- ImGuiMeasurement
--------------------------------------------------------------------------------
function Debug:ImGuiMeasurement()
    self.is_im_gui_measurement = ImGui.Checkbox("[ImGui] Measurement", self.is_im_gui_measurement)

    if self.is_im_gui_measurement then
        local res_x, res_y = GetDisplayResolution()
        if not res_x or not res_y then
            return
        end

        ImGui.SetNextWindowPos((res_x / 2) - 20, (res_y / 2) - 20)
        ImGui.SetNextWindowSize(40, 40)
        ImGui.SetNextWindowSizeConstraints(40, 40, 40, 40)

        ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 10)
        ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 5)

        ImGui.Begin("Crosshair",
            ImGuiWindowFlags.NoMove
            + ImGuiWindowFlags.NoCollapse
            + ImGuiWindowFlags.NoTitleBar
            + ImGuiWindowFlags.NoResize
        )
        ImGui.End()

        ImGui.PopStyleVar(2)
        ImGui.PopStyleColor(1)

        local player = Game.GetPlayer()
        if player then
            local look_at_pos = Game.GetTargetingSystem():GetLookAtPosition(player)
            local player_forward = player:GetWorldForward()
            if look_at_pos and player_forward then
                local pos_x = string.format("%.2f", look_at_pos.x)
                local pos_y = string.format("%.2f", look_at_pos.y)
                local pos_z = string.format("%.2f", look_at_pos.z)
                ImGui.Text("[LookAt]X:" .. pos_x .. ", Y:" .. pos_y .. ", Z:" .. pos_z)

                local const_ = 0.5
                local pos_back = Vector4.new(
                    look_at_pos.x - const_ * player_forward.x,
                    look_at_pos.y - const_ * player_forward.y,
                    look_at_pos.z - const_ * player_forward.z,
                    1
                )
                ImGui.Text("[Back]X:" .. string.format("%.2f", pos_back.x)
                    .. ", Y:" .. string.format("%.2f", pos_back.y)
                    .. ", Z:" .. string.format("%.2f", pos_back.z))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- ImGuiExecuteFunction
--------------------------------------------------------------------------------
function Debug:ImGuiExecuteFunction()
    if ImGui.Button("TF1") then
        local player = Game.GetPlayer()
        if player then
            local look_at_obj = Game.GetTargetingSystem():GetLookAtObject(player)
            if look_at_obj then
                print(look_at_obj:GetClassName())
                if look_at_obj:IsA("DataTerm") then
                    local comp = look_at_obj:FindComponentByName(CName.new("collider"))
                    if comp ~= nil then
                        print("collider")
                    end
                end
                print("Execute Test Function 1")
            else
                print("No valid 'look at' object.")
            end
        else
            print("Player is nil.")
        end
    end

    ImGui.SameLine()

    if ImGui.Button("TF2") then
        -- Instead of referencing 'InsideStation' global, reference 'self.insideStationRef'
        if self.insideStationRef and self.insideStationRef.core_obj
           and self.insideStationRef.core_obj.hud_obj then
            self.insideStationRef.core_obj.hud_obj:SetChoice(Def.ChoiceVariation.Enter)
            print("Execute Test Function 2: SetChoice -> Enter")
        else
            print("No insideStationRef.core_obj.hud_obj available.")
        end
    end
end

return Debug
