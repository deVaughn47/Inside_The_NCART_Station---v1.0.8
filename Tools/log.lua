---@enum LogLevel
local LogLevel = {
    Critical = 0,
    Error = 1,
    Warning = 2,
    Info = 3,
    Trace = 4,
    Debug = 5,
    Nothing = 6
}

-- Force the log level to be the same for all instances
local MasterLogLevel = LogLevel.Error
-- Print debug messages to the console
local PrintDebugMode = false

local Log = {}
Log.__index = Log

-- Attempt to require 'spdlog'. If unavailable, define a fallback.
local spdlog
local success, err = pcall(function()
    spdlog = require("spdlog")
end)

if not success then
    -- Define a simple fallback logger using print statements
    spdlog = {
        info = function(message) print("[INFO] " .. message) end,
        debug = function(message) print("[DEBUG] " .. message) end,
        error = function(message) print("[ERROR] " .. message) end,
        critical = function(message) print("[CRITICAL] " .. message) end
    }
    print("[Warning] 'spdlog' module not found. Using fallback logger.")
end

-- Expose LogLevel via the Log module
Log.LogLevel = LogLevel

function Log:New()
    local obj = {}
    setmetatable(obj, self)
    obj.setting_level = LogLevel.Info -- Corrected case from INFO to Info
    obj.setting_file_name = "No Setting"
    return obj
end

---@param level LogLevel
---@param file_name string
---@return boolean
function Log:SetLevel(level, file_name)
    -- Validate the provided level
    if level < LogLevel.Critical or level > LogLevel.Debug or MasterLogLevel ~= LogLevel.Nothing then
        self.setting_level = MasterLogLevel
        self.setting_file_name = "[" .. (file_name or "Unknown") .. "]"
        return false
    else
        self.setting_level = level
        self.setting_file_name = "[" .. (file_name or "Unknown") .. "]"
        return true
    end
end

---@param level LogLevel
---@param message string
function Log:Record(level, message)
    -- Determine the effective log level
    local effective_level = self.setting_level
    if MasterLogLevel < effective_level then
        effective_level = MasterLogLevel
    end

    -- If the message's level is higher (less critical) than the effective level, do not log
    if level > effective_level then
        return
    end

    -- Determine the log level name based on the level
    local level_name = "UNKNOWN"
    if level <= LogLevel.Critical then
        level_name = "CRITICAL"
    elseif level <= LogLevel.Error then
        level_name = "ERROR"
    elseif level <= LogLevel.Warning then
        level_name = "WARNING"
    elseif level <= LogLevel.Info then
        level_name = "INFO"
    elseif level <= LogLevel.Trace then
        level_name = "TRACE"
    elseif level <= LogLevel.Debug then
        level_name = "DEBUG"
    end

    -- Construct the log message
    local log_message = self.setting_file_name .. "[" .. level_name .. "] " .. message

    -- Log the message using spdlog or the fallback
    if level_name == "INFO" then
        spdlog.info(log_message)
    elseif level_name == "DEBUG" then
        spdlog.debug(log_message)
    elseif level_name == "ERROR" then
        spdlog.error(log_message)
    elseif level_name == "CRITICAL" then
        spdlog.critical(log_message)
    else
        -- Default to info if level is unknown
        spdlog.info(log_message)
    end

    -- Optionally print the log message to the console for debugging
    if PrintDebugMode then
        print(log_message)
    end
end

-- Convenience methods for different log levels
function Log:Info(message)
    self:Record(LogLevel.Info, message)
end

function Log:Debug(message)
    self:Record(LogLevel.Debug, message)
end

function Log:Error(message)
    self:Record(LogLevel.Error, message)
end

function Log:Critical(message)
    self:Record(LogLevel.Critical, message)
end

return Log
