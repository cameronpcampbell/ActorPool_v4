--!strict
local Pool = {}; Pool.__index = Pool
local PoolConn = {}; PoolConn.__index = PoolConn


--> [ SERVICES ] -------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local SharedTableRegistry = game:GetService("SharedTableRegistry")
------------------------------------------------------------------------------


--> [ DEPENDENCIES ] ---------------------------------------------------------
local Promise = require(script.Packages.promise)
------------------------------------------------------------------------------


--> [ VARIABLES ] ------------------------------------------------------------
local CurrentVersion = "4.1"
local BaseActorScript = script.BaseActorScript

-- Types
type Pool = typeof(setmetatable({}, Pool))
type PoolConn = typeof(setmetatable({}, PoolConn))
type PoolConfig = {
	baseModule: ModuleScript,
	poolFolder: Folder,
	min: number,
	max: number?,
	retries: number?,
	retriesInterval: number?,
}
------------------------------------------------------------------------------


--> [ HELPERS ] --------------------------------------------------------------
local function CreateGuid()
	return `{HttpService:GenerateGUID(false)}-{HttpService:GenerateGUID(false)}`
end

local function CreateActor(baseActor:Actor, poolFolder:Folder, available) : PoolConn
	local guid = CreateGuid()
	local newActor: Actor = baseActor:Clone()
	newActor:SetAttribute("Guid", guid)
	newActor.Name = `Actor_{guid}`
	newActor.Parent = poolFolder

	return setmetatable({
		guid = guid,
		actor = newActor,
		available = available,
		autoPutBack = false,
		outOfPool = false,
		doingWork = false,
		sharedStorage = nil
	}, PoolConn)
end
------------------------------------------------------------------------------


--> [ POOL ] -----------------------------------------------------------------
function Pool:take(autoPutBack: boolean?): PoolConn
	local retries, retriesInterval = self.retries, self.retriesInterval

	for _ = 1, retries do
		local connCount: number, max: number = self.connCount, self.max
		local atMaxConns = max and connCount >= max or false

		local conn: PoolConn? = table.remove(self.available)
		if (not conn) and (not atMaxConns) then
			conn = CreateActor(self.baseActor, self.poolFolder, self.available) :: any
			self.connCount += conn and 1 or 0
		end

		if not conn then task.wait(retriesInterval); continue end

		(conn :: any).autoPutBack = autoPutBack;
		(conn :: any).outOfPool = true
		return conn :: any
	end

	return warn("could not get actor") :: any
end
------------------------------------------------------------------------------


--> [ POOL CONN ] ------------------------------------------------------------
-- RUN ------------------------------------------------------------
function PoolConn:run()
	assert(self.outOfPool, "You may not use this actor connection at the moment as it is not currently taken from the pool!")
	assert(not self.doingWork, "You may not use this actor connection at the moment as it is already busy with another task!")

	self.doingWork = true
	self.actor:SendMessage("ActorPool")
	self.actor.DoneEvent.Event:Wait()
	self.doingWork = false

	if self.autoPutBack then self:putBack() end
	return self
end

function PoolConn:runAsync()
	assert(self.outOfPool, "You may not use this actor connection at the moment as it is not currently taken from the pool!")
	assert(not self.doingWork, "You may not use this actor connection at the moment as it is already busy with another task!")

	self.doingWork = true
	return Promise.new(function(resolve, reject, onCancel)
		self.actor:SendMessage("ActorPool")
        self.actor.DoneEvent.Event:Wait()
		resolve(self)
	end)
	:finally(function()
		self.doingWork = false
		if self.autoPutBack then self:putBack() end
	end)
end
-------------------------------------------------------------------

-- WAIT UNTIL FREE ------------------------------------------------
function PoolConn:waitUntilFree()
	repeat task.wait() until self.doingWork == false

	assert(self.outOfPool, "You may not use this actor connection at the moment as it is not currently taken from the pool!")
end

function PoolConn:waitUntilFreeAsync()
	return Promise.new(function(resolve, reject, onCancel)
		repeat task.wait() until self.doingWork == false

		if not self.outOfPool then reject("You may not use this actor connection at the moment as it is not currently taken from the pool!") end
		resolve(self)
	end)
end
-------------------------------------------------------------------

function PoolConn:putBack()
	assert(not self.doingWork, "This actor is currently doing work so it may not be put back in the pool at this moment!")

	if self.sharedTable then
		self.sharedTable = nil
		SharedTableRegistry:SetSharedTable(`ActorPoolv{CurrentVersion}/{self.guid}`, nil)
	end

	self.autoPutBack = false
	self.outOfPool = false

	table.insert(self.available, self)
end


function PoolConn:setSharedTable(tble): typeof(SharedTable.new())
	assert(tble, "You need to provide a table to create a SharedTable from!")

	local sharedTble = SharedTable.new(tble)
	SharedTableRegistry:SetSharedTable(`ActorPoolv{CurrentVersion}/{self.guid}`, sharedTble)
	self.sharedTable = sharedTble
	return sharedTble
end
------------------------------------------------------------------------------


local function New(config: PoolConfig)
	local baseModule, poolFolder, min, max = config.baseModule, config.poolFolder, config.min, config.max

	assert(baseModule and typeof(baseModule) == "Instance" and baseModule:IsA("ModuleScript"),
		"You need to define a 'baseModule' ModuleScript instance in your config")

	local baseActor = Instance.new("Actor")
	baseActor.Name = "BaseActor"
	local doneEvent = Instance.new("BindableEvent")
	doneEvent.Name = "DoneEvent"
	doneEvent.Parent = baseActor
	local actorScript = BaseActorScript:Clone()
	actorScript.Disabled = false
	actorScript.Parent = baseActor
	baseModule:Clone().Parent = baseActor


	local available = table.create(max or min)
	for _ = 1, min do
		table.insert(available, CreateActor(baseActor, poolFolder, available))
	end

	return setmetatable({
		baseActor = baseActor,
		poolFolder = poolFolder,
		min = min,
		max = max,
		available = available,
		connCount = min,
		retries = config.retries or 10,
		retriesInterval = config.retriesInterval or 0.5
	}, Pool)
end


local function Quick(baseModule: ModuleScript)
	local actorsFolder = Instance.new("Folder")
	actorsFolder.Name = "ActorPool.quick_ActorsFolder"
	actorsFolder.Parent = workspace

	local quickPool : Pool = New {
		baseModule = baseModule,
		poolFolder = actorsFolder,
		min = 25,
	}

	return function()
		quickPool:take(true):run()
	end
end


return {
	new = New,
	quick = Quick,
	currentVersion = CurrentVersion
}
