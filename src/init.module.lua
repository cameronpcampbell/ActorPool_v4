--!strict
local Pool = {}; Pool.__index = Pool
local PoolConn = {}; PoolConn.__index = PoolConn

local Promise = require(script.Promise)

type PoolConfig = {
	baseModule: ModuleScript,
	poolFolder: Folder,
	min: number,
	max: number?,
	retries: number?,
	retriesInterval: number?,
}

type Pool = {
	run: (any) -> any,
	runAsync: (any) -> any,
	waitUntilFree: (any) -> any,
	waitUntilFreeAsync: (any) -> any
}

local BaseActorScript = script.BaseActorScript

--> [ HELPERS ] --------------------------------------------------------------
local function CreateActor(baseActor:Actor, poolFolder:Folder, available, count)
	local newActor: Actor = baseActor:Clone()
	newActor.Parent = poolFolder
	newActor.Name = `Actor_{count}`

	return setmetatable({
		actor = newActor,
		available = available,
		autoPutBack = false,
		outOfPool = false,
		doingWork = false
	}, PoolConn)
end
------------------------------------------------------------------------------

--> [ POOL ] -----------------------------------------------------------------
function Pool:take(autoPutBack: boolean?): Pool
	local retries, retriesInterval = self.retries, self.retriesInterval

	for _ = 1, retries do
		local atMaxConns = self.max and self.connCount >= self.max or false

		local actor = table.remove(self.available)
		if not actor then
			actor = ((not atMaxConns) and CreateActor(self.baseActor, self.poolFolder, self.available, self.connCount+1))
			self.connCount += actor and 1 or 0
		end

		if not actor then
			task.wait(retriesInterval)
			continue
		end

		actor.autoPutBack = autoPutBack
		actor.outOfPool = true
		return actor
	end

	return warn("could not get actor")
end
------------------------------------------------------------------------------

--> [ POOL CONN ] ------------------------------------------------------------
-- RUN ------------------------------------------------------------
function PoolConn:run(...)
	assert(self.outOfPool, "You may not use this actor connection at the moment as it is not currently taken from the pool!")
	assert(not self.doingWork, "You may not use this actor connection at the moment as it is already busy with another task!")

	self.doingWork = true
	self.actor:SendMessage("ActorPool", ...)
	self.actor.DoneEvent.Event:Wait()
	self.doingWork = false

	if self.autoPutBack then self:putBack() end
	return self
end

function PoolConn:runAsync(...)
	assert(self.outOfPool, "You may not use this actor connection at the moment as it is not currently taken from the pool!")
	assert(not self.doingWork, "You may not use this actor connection at the moment as it is already busy with another task!")

	local args = { ... }

	self.doingWork = true
	return Promise.new(function(resolve, reject, onCancel)
		self.actor:SendMessage("ActorPool", table.unpack(args))
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
	self.autoPutBack = false
	self.outOfPool = false
	table.insert(self.available, self)
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


	local available, connCount: number = table.create(max or min), 0
	for _ = 1, min do
		table.insert(available, CreateActor(baseActor, poolFolder, available, connCount+1))
		connCount += 1
	end

	return setmetatable({
		baseActor = baseActor,
		poolFolder = poolFolder,
		min = min,
		max = max,
		available = available,
		connCount = connCount,
		retries = config.retries or 10,
		retriesInterval = config.retriesInterval or 0.5
	}, Pool)
end

return {
	new = New,

	quick = function(baseModule)
		local actorsFolder = Instance.new("Folder")
		actorsFolder.Name = "ActorPool.quick_ActorsFolder"
		actorsFolder.Parent = workspace

		local quickPool = New {
			baseModule = baseModule,
			poolFolder = actorsFolder,
			min = 25,
		}

		return function(...)
			quickPool:take(true):run(...)
		end
	end,
}
