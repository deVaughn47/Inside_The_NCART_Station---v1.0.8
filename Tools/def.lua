--------------------------------------------------------------------------------
-- def.lua (UPDATED)
-- Update by DeVaughnDawn
--------------------------------------------------------------------------------

---@class Def
Def = {}
Def.__index = Def

-- Enumeration for Choice Variations
Def.ChoiceVariation = {
    Enter = 0, -- Represents the 'Enter' choice (0-based index)
    Exit = 1   -- Represents the 'Exit' choice (1-based index)
}

-- Enumeration for Teleport Area Types
Def.TeleportAreaType = {
    None = 0,                    -- No teleportation area
    EntranceImmediately = 1,     -- Immediate teleport upon entrance
    EntranceChoice = 2,          -- Choice-based teleport upon entrance
    PlatformImmediately = 3,     -- Immediate teleport upon reaching the platform
    PlatformChoice = 4            -- Choice-based teleport upon reaching the platform
}

-- Added: TeleportAreaTypeNames
-- This table maps each TeleportAreaType enumeration value to a descriptive string.
-- It's used primarily for logging and debugging purposes to provide readable output.
Def.TeleportAreaTypeNames = {
    [Def.TeleportAreaType.None] = "None",
    [Def.TeleportAreaType.EntranceImmediately] = "EntranceImmediately",
    [Def.TeleportAreaType.EntranceChoice] = "EntranceChoice",
    [Def.TeleportAreaType.PlatformImmediately] = "PlatformImmediately",
    [Def.TeleportAreaType.PlatformChoice] = "PlatformChoice"
}

-- Optional: TeleportAreaTypeVerboseNames
-- If you require more descriptive names for logging or UI purposes, you can define them here.
-- This is useful for providing clearer context in logs or user interfaces.
Def.TeleportAreaTypeVerboseNames = {
    [Def.TeleportAreaType.None] = "No Teleport Area",
    [Def.TeleportAreaType.EntranceImmediately] = "Immediate Entrance Teleport",
    [Def.TeleportAreaType.EntranceChoice] = "Entrance Choice Teleport",
    [Def.TeleportAreaType.PlatformImmediately] = "Immediate Platform Teleport",
    [Def.TeleportAreaType.PlatformChoice] = "Platform Choice Teleport"
}

return Def
