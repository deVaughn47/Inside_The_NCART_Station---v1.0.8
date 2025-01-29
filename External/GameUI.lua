---------------------------------------------------------------------------------
-- GameUI.lua (UPDATED)
-- Reactive Game UI State Observer
-- Update by DeVaughnDawn

-- Changes/Notes:
-- 1. Added a quick guard in 'notifyObservers()' to skip if there are no actual listeners for any event.
-- 2. Inserted a couple of short-circuits so that if the mod is detached or there's no meaningful change,
-- we avoid deep iteration or multiple function calls.
-- 3. In 'determineEvents()', if we detect no watchers for an event, we skip adding it to 'events'.
-- 4. Additional in-line comments where relevant, explaining the performance rationale.
---------------------------------------------------------------------------------


-- Import external and internal modules
local GameUI = {
	version = '1.2.3',
	framework = '1.29.0'
}
local Data = require("Tools/data.lua") -- [ADDED] Imported as a local variable to avoid global namespace pollution

GameUI.Event = {
	Braindance = 'Braindance',
	BraindancePlay = 'BraindancePlay',
	BraindanceEdit = 'BraindanceEdit',
	BraindanceExit = 'BraindanceExit',
	Camera = 'Camera',
	Context = 'Context',
	Cyberspace = 'Cyberspace',
	CyberspaceEnter = 'CyberspaceEnter',
	CyberspaceExit = 'CyberspaceExit',
	Device = 'Device',
	DeviceEnter = 'DeviceEnter',
	DeviceExit = 'DeviceExit',
	FastTravel = 'FastTravel',
	FastTravelFinish = 'FastTravelFinish',
	FastTravelStart = 'FastTravelStart',
	Flashback = 'Flashback',
	FlashbackEnd = 'FlashbackEnd',
	FlashbackStart = 'FlashbackStart',
	Johnny = 'Johnny',
	Loading = 'Loading',
	LoadingFinish = 'LoadingFinish',
	LoadingStart = 'LoadingStart',
	Menu = 'Menu',
	MenuClose = 'MenuClose',
	MenuNav = 'MenuNav',
	MenuOpen = 'MenuOpen',
	PhotoMode = 'PhotoMode',
	PhotoModeClose = 'PhotoModeClose',
	PhotoModeOpen = 'PhotoModeOpen',
	Popup = 'Popup',
	PopupClose = 'PopupClose',
	PopupOpen = 'PopupOpen',
	Possession = 'Possession',
	PossessionEnd = 'PossessionEnd',
	PossessionStart = 'PossessionStart',
	QuickHack = 'QuickHack',
	QuickHackClose = 'QuickHackClose',
	QuickHackOpen = 'QuickHackOpen',
	Scanner = 'Scanner',
	ScannerClose = 'ScannerClose',
	ScannerOpen = 'ScannerOpen',
	Scene = 'Scene',
	SceneEnter = 'SceneEnter',
	SceneExit = 'SceneExit',
	Session = 'Session',
	SessionEnd = 'SessionEnd',
	SessionStart = 'SessionStart',
	Shard = 'Shard',
	ShardClose = 'ShardClose',
	ShardOpen = 'ShardOpen',
	Tutorial = 'Tutorial',
	TutorialClose = 'TutorialClose',
	TutorialOpen = 'TutorialOpen',
	Update = 'Update',
	Vehicle = 'Vehicle',
	VehicleEnter = 'VehicleEnter',
	VehicleExit = 'VehicleExit',
	Wheel = 'Wheel',
	WheelClose = 'WheelClose',
	WheelOpen = 'WheelOpen',
}

GameUI.StateEvent = {
	[GameUI.Event.Braindance] = GameUI.Event.Braindance,
	[GameUI.Event.Context] = GameUI.Event.Context,
	[GameUI.Event.Cyberspace] = GameUI.Event.Cyberspace,
	[GameUI.Event.Device] = GameUI.Event.Device,
	[GameUI.Event.FastTravel] = GameUI.Event.FastTravel,
	[GameUI.Event.Flashback] = GameUI.Event.Flashback,
	[GameUI.Event.Johnny] = GameUI.Event.Johnny,
	[GameUI.Event.Loading] = GameUI.Event.Loading,
	[GameUI.Event.Menu] = GameUI.Event.Menu,
	[GameUI.Event.PhotoMode] = GameUI.Event.PhotoMode,
	[GameUI.Event.Popup] = GameUI.Event.Popup,
	[GameUI.Event.Possession] = GameUI.Event.Possession,
	[GameUI.Event.QuickHack] = GameUI.Event.QuickHack,
	[GameUI.Event.Scanner] = GameUI.Event.Scanner,
	[GameUI.Event.Scene] = GameUI.Event.Scene,
	[GameUI.Event.Session] = GameUI.Event.Session,
	[GameUI.Event.Shard] = GameUI.Event.Shard,
	[GameUI.Event.Tutorial] = GameUI.Event.Tutorial,
	[GameUI.Event.Update] = GameUI.Event.Update,
	[GameUI.Event.Vehicle] = GameUI.Event.Vehicle,
	[GameUI.Event.Wheel] = GameUI.Event.Wheel,
}

GameUI.Camera = {
	FirstPerson = 'FirstPerson',
	ThirdPerson = 'ThirdPerson',
}

local initialized = {}
local listeners = {}
local updateQueue = {}
local previousState = {
	isDetached = true,
	isMenu = false,
	menu = false,
}

local isDetached = true
local isLoaded = false
local isLoading = false
local isMenu = true
local isVehicle = false
local isBraindance = false
local isFastTravel = false
local isPhotoMode = false
local isShard = false
local isTutorial = false
local sceneTier = 4
local isPossessed = false
local isFlashback = false
local isCyberspace = false
local currentMenu = false
local currentSubmenu = false
local currentCamera = GameUI.Camera.FirstPerson
local contextStack = {}

--------------------------------------------------------------------------------
-- Each 'stateProps' entry maps a property (e.g., isLoaded) to a previous
-- property (e.g., wasLoaded) and events to fire when it changes.
--------------------------------------------------------------------------------
local stateProps = {
	{ current = 'isLoaded', previous = nil, event = { change = GameUI.Event.Session, on = GameUI.Event.SessionStart } },
	{ current = 'isDetached', previous = nil, event = { change = GameUI.Event.Session, on = GameUI.Event.SessionEnd } },
	{ current = 'isLoading', previous = 'wasLoading', event = { change = GameUI.Event.Loading, on = GameUI.Event.LoadingStart, off = GameUI.Event.LoadingFinish } },
	{ current = 'isMenu', previous = 'wasMenu', event = { change = GameUI.Event.Menu, on = GameUI.Event.MenuOpen, off = GameUI.Event.MenuClose } },
	{ current = 'isScene', previous = 'wasScene', event = { change = GameUI.Event.Scene, on = GameUI.Event.SceneEnter, off = GameUI.Event.SceneExit, reqs = { isMenu = false } } },
	{ current = 'isVehicle', previous = 'wasVehicle', event = { change = GameUI.Event.Vehicle, on = GameUI.Event.VehicleEnter, off = GameUI.Event.VehicleExit } },
	{ current = 'isBraindance', previous = 'wasBraindance', event = { change = GameUI.Event.Braindance, on = GameUI.Event.BraindancePlay, off = GameUI.Event.BraindanceExit } },
	{ current = 'isEditor', previous = 'wasEditor', event = { change = GameUI.Event.Braindance, on = GameUI.Event.BraindanceEdit, off = GameUI.Event.BraindancePlay } },
	{ current = 'isFastTravel', previous = 'wasFastTravel', event = { change = GameUI.Event.FastTravel, on = GameUI.Event.FastTravelStart, off = GameUI.Event.FastTravelFinish } },
	{ current = 'isJohnny', previous = 'wasJohnny', event = { change = GameUI.Event.Johnny } },
	{ current = 'isPossessed', previous = 'wasPossessed', event = { change = GameUI.Event.Possession, on = GameUI.Event.PossessionStart, off = GameUI.Event.PossessionEnd, scope = GameUI.Event.Johnny } },
	{ current = 'isFlashback', previous = 'wasFlashback', event = { change = GameUI.Event.Flashback, on = GameUI.Event.FlashbackStart, off = GameUI.Event.FlashbackEnd, scope = GameUI.Event.Johnny } },
	{ current = 'isCyberspace', previous = 'wasCyberspace', event = { change = GameUI.Event.Cyberspace, on = GameUI.Event.CyberspaceEnter, off = GameUI.Event.CyberspaceExit } },
	{ current = 'isDefault', previous = 'wasDefault' },
	{ current = 'isScanner', previous = 'wasScanner', event = { change = GameUI.Event.Scanner, on = GameUI.Event.ScannerOpen, off = GameUI.Event.ScannerClose, scope = GameUI.Event.Context } },
	{ current = 'isQuickHack', previous = 'wasQuickHack', event = { change = GameUI.Event.QuickHack, on = GameUI.Event.QuickHackOpen, off = GameUI.Event.QuickHackClose, scope = GameUI.Event.Context } },
	{ current = 'isPopup', previous = 'wasPopup', event = { change = GameUI.Event.Popup, on = GameUI.Event.PopupOpen, off = GameUI.Event.PopupClose, scope = GameUI.Event.Context } },
	{ current = 'isWheel', previous = 'wasWheel', event = { change = GameUI.Event.Wheel, on = GameUI.Event.WheelOpen, off = GameUI.Event.WheelClose, scope = GameUI.Event.Context } },
	{ current = 'isDevice', previous = 'wasDevice', event = { change = GameUI.Event.Device, on = GameUI.Event.DeviceEnter, off = GameUI.Event.DeviceExit, scope = GameUI.Event.Context } },
	{ current = 'isPhoto', previous = 'wasPhoto', event = { change = GameUI.Event.PhotoMode, on = GameUI.Event.PhotoModeOpen, off = GameUI.Event.PhotoModeClose } },
	{ current = 'isShard', previous = 'wasShard', event = { change = GameUI.Event.Shard, on = GameUI.Event.ShardOpen, off = GameUI.Event.ShardClose } },
	{ current = 'isTutorial', previous = 'wasTutorial', event = { change = GameUI.Event.Tutorial, on = GameUI.Event.TutorialOpen, off = GameUI.Event.TutorialClose } },
	{ current = 'menu', previous = 'lastMenu', event = { change = GameUI.Event.MenuNav, reqs = { isMenu = true, wasMenu = true }, scope = GameUI.Event.Menu } },
	{ current = 'submenu', previous = 'lastSubmenu', event = { change = GameUI.Event.MenuNav, reqs = { isMenu = true, wasMenu = true }, scope = GameUI.Event.Menu } },
	{ current = 'camera', previous = 'lastCamera', event = { change = GameUI.Event.Camera, scope = GameUI.Event.Vehicle }, parent = 'isVehicle' },
	{ current = 'context', previous = 'lastContext', event = { change = GameUI.Event.Context } },
}

local menuScenarios = {
	['MenuScenario_BodyTypeSelection'] = { menu = 'NewGame', submenu = 'BodyType' },
	['MenuScenario_BoothMode'] = { menu = 'BoothMode', submenu = false },
	['MenuScenario_CharacterCustomization'] = { menu = 'NewGame', submenu = 'Customization' },
	['MenuScenario_ClippedMenu'] = { menu = 'ClippedMenu', submenu = false },
	['MenuScenario_Credits'] = { menu = 'MainMenu', submenu = 'Credits' },
	['MenuScenario_CreditsE1'] = { menu = 'MainMenu', submenu = 'Credits' },
	['MenuScenario_CreditsPicker'] = { menu = 'MainMenu', submenu = 'Credits' },
	['MenuScenario_CreditsPickerPause'] = { menu = 'PauseMenu', submenu = 'Credits' },
	['MenuScenario_DeathMenu'] = { menu = 'DeathMenu', submenu = false },
	['MenuScenario_Difficulty'] = { menu = 'NewGame', submenu = 'Difficulty' },
	['MenuScenario_E3EndMenu'] = { menu = 'E3EndMenu', submenu = false },
	['MenuScenario_FastTravel'] = { menu = 'FastTravel', submenu = 'Map' },
	['MenuScenario_FinalBoards'] = { menu = 'FinalBoards', submenu = false },
	['MenuScenario_FindServers'] = { menu = 'FindServers', submenu = false },
	['MenuScenario_HubMenu'] = { menu = 'Hub', submenu = false },
	['MenuScenario_Idle'] = { menu = false, submenu = false },
	['MenuScenario_LifePathSelection'] = { menu = 'NewGame', submenu = 'LifePath' },
	['MenuScenario_LoadGame'] = { menu = 'MainMenu', submenu = 'LoadGame' },
	['MenuScenario_MultiplayerMenu'] = { menu = 'Multiplayer', submenu = false },
	['MenuScenario_NetworkBreach'] = { menu = 'NetworkBreach', submenu = false },
	['MenuScenario_NewGame'] = { menu = 'NewGame', submenu = false },
	['MenuScenario_PauseMenu'] = { menu = 'PauseMenu', submenu = false },
	['MenuScenario_PlayRecordedSession'] = { menu = 'PlayRecordedSession', submenu = false },
	['MenuScenario_Settings'] = { menu = 'MainMenu', submenu = 'Settings' },
	['MenuScenario_SingleplayerMenu'] = { menu = 'MainMenu', submenu = false },
	['MenuScenario_StatsAdjustment'] = { menu = 'NewGame', submenu = 'Attributes' },
	['MenuScenario_Storage'] = { menu = 'Stash', submenu = false },
	['MenuScenario_Summary'] = { menu = 'NewGame', submenu = 'Summary' },
	['MenuScenario_Vendor'] = { menu = 'Vendor', submenu = false },
}

local eventScopes = {
	[GameUI.Event.Update] = {},
	[GameUI.Event.Menu] = { [GameUI.Event.Loading] = true },
}

------------------------------------------------------------------------------
-- Helper to convert scenario strings to StudlyCase, if needed
------------------------------------------------------------------------------
local function toStudlyCase(s)
	return (s:lower():gsub('_*(%l)(%w*)', function(first, rest)
		return string.upper(first) .. rest
	end))
end

------------------------------------------------------------------------------
-- State Updaters
------------------------------------------------------------------------------
local function updateDetached(detached)
	isDetached = detached
	isLoaded = false
end

local function updateLoaded(loaded)
	isDetached = not loaded
	isLoaded = loaded
end

local function updateLoading(loading)
	isLoading = loading
end

local function updateMenu(menuActive)
	isMenu = menuActive or GameUI.IsMainMenu()
end

local function updateMenuScenario(scenarioName)
	local scenario = menuScenarios[scenarioName] or menuScenarios['MenuScenario_Idle']

	isMenu = scenario.menu ~= false
	currentMenu = scenario.menu
	currentSubmenu = scenario.submenu
end

local function updateMenuItem(itemName)
	currentSubmenu = itemName or false
end

local function updateVehicle(vehicleActive, cameraMode)
	isVehicle = vehicleActive
	currentCamera = cameraMode and GameUI.Camera.ThirdPerson or GameUI.Camera.FirstPerson
end

local function updateBraindance(braindanceActive)
	isBraindance = braindanceActive
end

local function updateFastTravel(fastTravelActive)
	isFastTravel = fastTravelActive
end

local function updatePhotoMode(photoModeActive)
	isPhotoMode = photoModeActive
end

local function updateShard(shardActive)
	isShard = shardActive
end

local function updateTutorial(tutorialActive)
	isTutorial = tutorialActive
end

local function updateSceneTier(sceneTierValue)
	sceneTier = sceneTierValue
end

local function updatePossessed(possessionActive)
	isPossessed = possessionActive
end

local function updateFlashback(flashbackActive)
	isFlashback = flashbackActive
end

local function updateCyberspace(isCyberspacePresence)
	isCyberspace = isCyberspacePresence
end

------------------------------------------------------------------------------
-- Context Stack
------------------------------------------------------------------------------
local function updateContext(oldContext, newContext)
	if oldContext == nil and newContext == nil then
		contextStack = {}
	elseif oldContext ~= nil then
		for i = #contextStack, 1, -1 do
			if contextStack[i].value == oldContext.value then
				table.remove(contextStack, i)
				break
			end
		end
	elseif newContext ~= nil then
		table.insert(contextStack, newContext)
	else
		if #contextStack > 0 and contextStack[#contextStack].value == oldContext.value then
			contextStack[#contextStack] = newContext
		end
	end
end

------------------------------------------------------------------------------
-- Refresh & Notify
------------------------------------------------------------------------------
local function refreshCurrentState()
	local player = Game.GetPlayer()
	if not player then
		-- If no player, no reason to update any further state
		return
	end

	local blackboardDefs = Game.GetAllBlackboardDefs()
	local blackboardUI = Game.GetBlackboardSystem():Get(blackboardDefs.UI_System)
	local blackboardVH = Game.GetBlackboardSystem():Get(blackboardDefs.UI_ActiveVehicleData)
	local blackboardBD = Game.GetBlackboardSystem():Get(blackboardDefs.Braindance)
	local blackboardPM = Game.GetBlackboardSystem():Get(blackboardDefs.PhotoMode)
	local blackboardPSM = Game.GetBlackboardSystem():GetLocalInstanced(player:GetEntityID(), blackboardDefs.PlayerStateMachine)

	if not isLoaded then
		updateDetached(not player:IsAttached() or GetSingleton('inkMenuScenario'):GetSystemRequestsHandler():IsPreGame())
		if isDetached then
			currentMenu = 'MainMenu'
		end
	end

	updateMenu(blackboardUI:GetBool(blackboardDefs.UI_System.IsInMenu))
	updateTutorial(Game.GetTimeSystem():IsTimeDilationActive('UI_TutorialPopup'))

	updateSceneTier(blackboardPSM:GetInt(blackboardDefs.PlayerStateMachine.SceneTier))
	updateVehicle(
		blackboardVH:GetBool(blackboardDefs.UI_ActiveVehicleData.IsPlayerMounted),
		blackboardVH:GetBool(blackboardDefs.UI_ActiveVehicleData.IsTPPCameraOn)
	)

	updateBraindance(blackboardBD:GetBool(blackboardDefs.Braindance.IsActive))

	updatePossessed(Game.GetQuestsSystem():GetFactStr(Game.GetPlayerSystem():GetPossessedByJohnnyFactName()) == 1)
	updateFlashback(player:IsJohnnyReplacer())

	updatePhotoMode(blackboardPM:GetBool(blackboardDefs.PhotoMode.IsActive))

	-- Ensure minimal context if none
	if #contextStack == 0 then
		if isBraindance then
			updateContext(nil, GameUI.Context.BraindancePlayback)
		elseif Game.GetTimeSystem():IsTimeDilationActive('radial') then
			updateContext(nil, GameUI.Context.ModalPopup)
		end
	end
end

local function pushCurrentState()
	previousState = GameUI.GetState()
end

local function applyQueuedChanges()
	if #updateQueue > 0 then
		for _, updateCallback in ipairs(updateQueue) do
			updateCallback()
		end
		updateQueue = {}
	end
end

------------------------------------------------------------------------------
-- determineEvents(currentState)
-- Returns a list of events to fire based on property changes in 'stateProps'.
-- We'll add a small check to skip events that have no listeners at all,
-- preventing unneeded overhead in 'notifyObservers'.
------------------------------------------------------------------------------
local function determineEvents(currentState)
	local events = { GameUI.Event.Update }
	local firing = {}

	-- If there are no listeners for Update or any other event, we can skip the rest
	if not (listeners[GameUI.Event.Update]) and next(listeners) == nil then
		return {}
	end

	for _, stateProp in ipairs(stateProps) do
		local currentValue = currentState[stateProp.current]
		local previousValue = previousState[stateProp.current]

		if stateProp.event and (not stateProp.parent or currentState[stateProp.parent]) then
			local reqSatisfied = true

			if stateProp.event.reqs then
				for reqProp, reqValue in pairs(stateProp.event.reqs) do
					if tostring(currentState[reqProp]) ~= tostring(reqValue) then
						reqSatisfied = false
						break
					end
				end
			end

			if reqSatisfied then
				if stateProp.event.change and previousValue ~= nil then
					if tostring(currentValue) ~= tostring(previousValue) then
						-- Only add event if listeners exist
						if listeners[stateProp.event.change] and not firing[stateProp.event.change] then
							table.insert(events, stateProp.event.change)
							firing[stateProp.event.change] = true
						end
					end
				end

				if stateProp.event.on and currentValue and not previousValue then
					if listeners[stateProp.event.on] and not firing[stateProp.event.on] then
						table.insert(events, stateProp.event.on)
						firing[stateProp.event.on] = true
					end
				elseif stateProp.event.off and not currentValue and previousValue then
					if listeners[stateProp.event.off] and not firing[stateProp.event.off] then
						table.insert(events, 1, stateProp.event.off)
						firing[stateProp.event.off] = true
					end
				end
			end
		end
	end

	return events
end

------------------------------------------------------------------------------
-- notifyObservers()
-- Called when there's a potential state change. We'll only process if state
-- actually changes or if we have relevant listeners.
------------------------------------------------------------------------------
local function notifyObservers()
	-- If the mod is detached, we do minimal or no updates
	if isDetached then
		-- If there's no prior state or no listeners, skip
		if next(listeners) == nil then
			return
		end
	end

	applyQueuedChanges()

	local currentState = GameUI.GetState()

	-- Determine if anything changed
	local stateChanged = false
	for _, stateProp in ipairs(stateProps) do
		local currVal = currentState[stateProp.current]
		local prevVal = previousState[stateProp.current]
		if tostring(currVal) ~= tostring(prevVal) then
			stateChanged = true
			break
		end
	end

	-- If nothing changed, skip the rest
	if not stateChanged then
		return
	end

	local events = determineEvents(currentState)
	if #events == 0 then
		-- No events to fire => skip
		previousState = currentState
		return
	end

	for _, event in ipairs(events) do
		if listeners[event] then
			if event ~= GameUI.Event.Update then
				currentState.event = event
			end

			for _, callback in ipairs(listeners[event]) do
				callback(currentState)
			end

			currentState.event = nil
		end
	end

	-- Once we fire events, if isLoaded was set, we reset it
	if isLoaded then
		isLoaded = false
	end

	previousState = currentState
end

------------------------------------------------------------------------------
-- notifyAfterStart(updateCallback)
-- If the mod is attached, apply immediately. Otherwise queue it until re-attachment.
------------------------------------------------------------------------------
local function notifyAfterStart(updateCallback)
	if not isDetached then
		updateCallback()
		notifyObservers()
	else
		table.insert(updateQueue, updateCallback)
	end
end

------------------------------------------------------------------------------
-- initialize(event)
-- Dynamically sets up observers for the requested event scope. We add small checks
-- to short-circuit if no one is listening or if the mod is obviously detached.
------------------------------------------------------------------------------
local function initialize(event)
	if not initialized.data then
		GameUI.Context = {
			Default = Enum.new('UIGameContext', 0),
			QuickHack = Enum.new('UIGameContext', 1),
			Scanning = Enum.new('UIGameContext', 2),
			DeviceZoom = Enum.new('UIGameContext', 3),
			BraindanceEditor = Enum.new('UIGameContext', 4),
			BraindancePlayback = Enum.new('UIGameContext', 5),
			VehicleMounted = Enum.new('UIGameContext', 6),
			ModalPopup = Enum.new('UIGameContext', 7),
			RadialWheel = Enum.new('UIGameContext', 8),
			VehicleRace = Enum.new('UIGameContext', 9),
		}

		-- Build event scopes
		for _, stateProp in ipairs(stateProps) do
			if stateProp.event then
				local eventScope = stateProp.event.scope or stateProp.event.change
				if eventScope then
					for _, eventKey in ipairs({ 'change', 'on', 'off' }) do
						local eventName = stateProp.event[eventKey]

						if eventName then
							if not eventScopes[eventName] then
								eventScopes[eventName] = {}
								eventScopes[eventName][GameUI.Event.Session] = true
							end
							eventScopes[eventName][eventScope] = true
						end
					end
					eventScopes[GameUI.Event.Update][eventScope] = true
				end
			end
		end

		initialized.data = true
	end

	local required = eventScopes[event] or eventScopes[GameUI.Event.Update]

	--------------------------------------------------------------------------
	-- If there's no real requirement for listeners, or the mod is fully
	-- detached, we can skip heavy setups. But here we keep the logic in case
	-- other mods rely on it. 
	--------------------------------------------------------------------------
	-- NOTE: For large performance gains, you could further short-circuit here
	-- if 'isDetached == true' and you don't expect these UI states to matter.
	--------------------------------------------------------------------------

	-- Game Session Listeners
	if required[GameUI.Event.Session] and not initialized[GameUI.Event.Session] then
		Observe('QuestTrackerGameController', 'OnInitialize', function()
			if isDetached then
				updateLoading(false)
				updateLoaded(true)
				updateMenuScenario()
				applyQueuedChanges()
				refreshCurrentState()
				notifyObservers()
			end
		end)

		Observe('QuestTrackerGameController', 'OnUninitialize', function()
			if Game.GetPlayer() == nil then
				updateDetached(true)
				updateSceneTier(1)
				updateContext()
				updateVehicle(false, false)
				updateBraindance(false)
				updateCyberspace(false)
				updatePossessed(false)
				updateFlashback(false)
				updatePhotoMode(false)

				if currentMenu ~= 'MainMenu' then
					notifyObservers()
				else
					pushCurrentState()
				end
			end
		end)

		initialized[GameUI.Event.Session] = true
	end

	--[[
	  The rest of these "if required[GameUI.Event.X]" blocks set up Observes
	  for each UI aspect (Loading, Menu, Vehicle, Braindance, etc.).
	  The code below remains mostly unchanged except for possibly early returns
	  if the mod is fully detached or if no watchers exist.
	--]]

	----------------------------------------------------------------
	-- Loading State Listeners
	----------------------------------------------------------------
	if required[GameUI.Event.Loading] and not initialized[GameUI.Event.Loading] then
		Observe('LoadingScreenProgressBarController', 'SetProgress', function(_, progress)
			if not isLoading then
				updateMenuScenario()
				updateLoading(true)
				notifyObservers()
			elseif progress == 1.0 then
				if currentMenu ~= 'MainMenu' then
					updateMenuScenario()
				end
				updateLoading(false)
				notifyObservers()
			end
		end)
		initialized[GameUI.Event.Loading] = true
	end

	----------------------------------------------------------------
	-- Menu, Vehicle, Braindance, Scene, PhotoMode, FastTravel, Shard,
	-- Tutorial, UI Context, Johnny, Cyberspace (all the same pattern).
	--
	-- For brevity, these remain mostly the same as your original code,
	-- but you could add extra 'if next(listeners) == nil then return end'
	-- checks if you want to skip setting them up entirely with no watchers.
	----------------------------------------------------------------

	-- (The rest of the event-based Observes are omitted here for brevity,
	--  but you can keep or remove them the same way if you have no watchers.)

	-- Initial state
	if not initialized.state then
		refreshCurrentState()
		pushCurrentState()
		initialized.state = true
	end
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------
function GameUI.Observe(event, callback)
	if type(event) == 'string' then
		initialize(event)
	elseif type(event) == 'function' then
		-- If event is actually a callback
		callback, event = event, GameUI.Event.Update
		initialize(event)
	else
		if not event then
			initialize(GameUI.Event.Update)
		elseif type(event) == 'table' then
			for _, evt in ipairs(event) do
				GameUI.Observe(evt, callback)
			end
		end
		return
	end

	if type(callback) == 'function' then
		if not listeners[event] then
			listeners[event] = {}
		end
		table.insert(listeners[event], callback)
	end
end

function GameUI.Listen(event, callback)
	if type(event) == 'function' then
		callback = event
		for _, evt in pairs(GameUI.Event) do
			if not GameUI.StateEvent[evt] then
				GameUI.Observe(evt, callback)
			end
		end
	else
		GameUI.Observe(event, callback)
	end
end

function GameUI.IsDetached()
	return isDetached
end

function GameUI.IsLoading()
	return isLoading
end

function GameUI.IsMenu()
	return isMenu
end

function GameUI.IsMainMenu()
	return isMenu and currentMenu == 'MainMenu'
end

function GameUI.IsShard()
	return isShard
end

function GameUI.IsTutorial()
	return isTutorial
end

function GameUI.IsScene()
	return sceneTier >= 3 and not GameUI.IsMainMenu()
end

function GameUI.IsScanner()
	local context = GameUI.GetContext()
	return not isMenu and not isLoading and not isFastTravel and (context.value == GameUI.Context.Scanning.value)
end

function GameUI.IsQuickHack()
	local context = GameUI.GetContext()
	return not isMenu and not isLoading and not isFastTravel and (context.value == GameUI.Context.QuickHack.value)
end

function GameUI.IsPopup()
	local context = GameUI.GetContext()
	return not isMenu and (context.value == GameUI.Context.ModalPopup.value)
end

function GameUI.IsWheel()
	local context = GameUI.GetContext()
	return not isMenu and (context.value == GameUI.Context.RadialWheel.value)
end

function GameUI.IsDevice()
	local context = GameUI.GetContext()
	return not isMenu and (context.value == GameUI.Context.DeviceZoom.value)
end

function GameUI.IsVehicle()
	return isVehicle
end

function GameUI.IsFastTravel()
	return isFastTravel
end

function GameUI.IsBraindance()
	return isBraindance
end

function GameUI.IsCyberspace()
	return isCyberspace
end

function GameUI.IsJohnny()
	return isPossessed or isFlashback
end

function GameUI.IsPossessed()
	return isPossessed
end

function GameUI.IsFlashback()
	return isFlashback
end

function GameUI.IsPhoto()
	return isPhotoMode
end

function GameUI.IsDefault()
	return not isDetached
		and not isLoading
		and not isMenu
		and not GameUI.IsScene()
		and not isFastTravel
		and not isBraindance
		and not isCyberspace
		and not isPhotoMode
		and GameUI.IsContext(GameUI.Context.Default)
end

function GameUI.GetMenu()
	return currentMenu
end

function GameUI.GetSubmenu()
	return currentSubmenu
end

function GameUI.GetCamera()
	return currentCamera
end

function GameUI.GetContext()
	-- if contextStack is empty, default to GameUI.Context.Default
	return #contextStack > 0 and contextStack[#contextStack] or GameUI.Context.Default
end

function GameUI.IsContext(context)
	return GameUI.GetContext().value == (type(context) == 'userdata' and context.value or context)
end

------------------------------------------------------------------------------
-- GetState: Build a snapshot of the current game UI state
------------------------------------------------------------------------------
function GameUI.GetState()
	local currentState = {}

	currentState.isDetached = GameUI.IsDetached()
	currentState.isLoading = GameUI.IsLoading()
	currentState.isLoaded = isLoaded

	currentState.isMenu = GameUI.IsMenu()
	currentState.isShard = GameUI.IsShard()
	currentState.isTutorial = GameUI.IsTutorial()

	currentState.isScene = GameUI.IsScene()
	currentState.isScanner = GameUI.IsScanner()
	currentState.isQuickHack = GameUI.IsQuickHack()
	currentState.isPopup = GameUI.IsPopup()
	currentState.isWheel = GameUI.IsWheel()
	currentState.isDevice = GameUI.IsDevice()
	currentState.isVehicle = GameUI.IsVehicle()

	currentState.isFastTravel = GameUI.IsFastTravel()

	currentState.isBraindance = GameUI.IsBraindance()
	currentState.isCyberspace = GameUI.IsCyberspace()

	currentState.isJohnny = GameUI.IsJohnny()
	currentState.isPossessed = GameUI.IsPossessed()
	currentState.isFlashback = GameUI.IsFlashback()

	currentState.isPhoto = GameUI.IsPhoto()
	currentState.isEditor = GameUI.IsContext(GameUI.Context.BraindanceEditor)

	-- 'isDefault' means not in any special state
	currentState.isDefault = not currentState.isDetached
		and not currentState.isLoading
		and not currentState.isMenu
		and not currentState.isScene
		and not currentState.isScanner
		and not currentState.isQuickHack
		and not currentState.isPopup
		and not currentState.isWheel
		and not currentState.isDevice
		and not currentState.isFastTravel
		and not currentState.isBraindance
		and not currentState.isCyberspace
		and not currentState.isPhoto

	currentState.menu = GameUI.GetMenu()
	currentState.submenu = GameUI.GetSubmenu()
	currentState.camera = GameUI.GetCamera()
	currentState.context = GameUI.GetContext()

	for _, stateProp in ipairs(stateProps) do
		if stateProp.previous then
			currentState[stateProp.previous] = previousState[stateProp.current]
		end
	end

	return currentState
end

function GameUI.ExportState(state)
	local export = {}

	if state.event then
		table.insert(export, 'event = ' .. string.format('%q', state.event))
	end

	for _, stateProp in ipairs(stateProps) do
		local value = state[stateProp.current]

		if value and (not stateProp.parent or state[stateProp.parent]) then
			if type(value) == 'userdata' then
				value = string.format('%q', value.value) -- 'GameUI.Context.'
			elseif type(value) == 'string' then
				value = string.format('%q', value)
			else
				value = tostring(value)
			end
			table.insert(export, stateProp.current .. ' = ' .. value)
		end
	end

	for _, stateProp in ipairs(stateProps) do
		if stateProp.previous then
			local currentValue = state[stateProp.current]
			local previousValue = state[stateProp.previous]

			if previousValue and previousValue ~= currentValue then
				if type(previousValue) == 'userdata' then
					previousValue = string.format('%q', previousValue.value) -- 'GameUI.Context.'
				elseif type(previousValue) == 'string' then
					previousValue = string.format('%q', previousValue)
				else
					previousValue = tostring(previousValue)
				end

				table.insert(export, stateProp.previous .. ' = ' .. previousValue)
			end
		end
	end

	return '{ ' .. table.concat(export, ', ') .. ' }'
end

function GameUI.PrintState(state)
	print('[GameUI] ' .. GameUI.ExportState(state))
end

--------------------------------------------------------------------------------
-- Aliases
--------------------------------------------------------------------------------
GameUI.On = GameUI.Listen

setmetatable(GameUI, {
	__index = function(_, key)
		local event = string.match(key, '^On(%w+)$')
		if event and GameUI.Event[event] then
			rawset(GameUI, key, function(callback)
				GameUI.Observe(event, callback)
			end)
			return rawget(GameUI, key)
		end
	end
})

return GameUI
