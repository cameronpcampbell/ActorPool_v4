# ActorPool

These docs assume that you are already familiar with Parallel Lua, specifically [SharedTables](https://create.roblox.com/docs/reference/engine/datatypes/SharedTable#new).

ActorPool is a utility module that makes working with [Actors](https://create.roblox.com/docs/reference/engine/classes/Actor) easy.

In the API below the term `Actor` refers to an Actor instance whilst the term `Actor Connection` refers to a metatable object that contains methods and an Actor instance.

- - -

# API

## Creating A Pool Of Actors
Creates and returns a new actor pool with the specified config. 
```
ActorPool.new(config: PoolConfig) -> Pool
```
__**PoolConfig**__

`baseModule: ModuleScript` = A module that returns a function that actors in your pool will be able to run.

`poolFolder: Folder` = A folder **that must be attached to the DataModel** where all actors that are in your pool will be parented to.

`min: number` = The minimum amount of actor connections. When your pool is first created this is the amount of connections it will initially have.

`max: number [optional]` = The maximum amount of actor connections. If this is omitted then the pool will have no cap on how many connections it can have. 

`retries: number [optional] [default = 10]` = how many times to retry getting a connection from the pool before throwing an error. 

`retriesInterval: number [optional] [default = .5]` = The amount of time to wait in between retries (see above).

- - - 

## Taking An Actor From The Pool
Takes an actor connection from the pool.
```
Pool:take(autoPutBack: boolean [optional] [default = false]) -> PoolConnection
```
`autoPutBack` = If this is true then after `:run()` is called on the actor connection, said connection will automatically be returned to the pool.
- - -

## Running Code From The Actors Script
Each actor has its own copy of the `baseModule` and when `:run` is called on the actor connection then the code from the module is ran in parallel. (this is a yielding function).
```
PoolConnection:run(...) -> self
```

`...` = The arguements to send to the actors module.

<details>
<summary>Example</summary>

```lua
local NumsToAdd = SharedTable.new { 2, 4, 6, 8 }
PoolConnection:run(NumsToAdd)
print(NumsToAdd["total"]) -- PRINTS: 20
```

`baseModule` code:
```lua
return function(NumsToAdd)
	local total = 0
	for _,num in NumsToAdd do total += num end
	NumsToAdd["total"] = total
end
```

</details>

- - -

## Running Code From The Actors Script (Promise)
Works similar to `:run()` except it returns a promise instead of yielding.

```
PoolConnection:runAsync(...) -> Promise
```

`...` = The arguements to send to the actors module.

<details>
<summary>Example</summary>

```lua
local NumsToAdd = SharedTable.new { 2, 4, 6, 8 }
PoolConnection:runAsync(NumsToAdd):andThen(function()
	print(NumsToAdd["total"])  -- PRINTS: 20
end)
```

`baseModule` code:
```lua
return function(NumsToAdd)
	local total = 0
	for _,num in NumsToAdd do total += num end
	NumsToAdd["total"] = total
end
```

</details>

- - -

## Returning An Actor To The Pool

```lua
PoolConnection:putBack()
```

- - -

## Waiting For An Actor Connection To Be Free

waits until the actor connection is no longer busy with whatever work they were doing. (this is a yielding function).

```lua
PoolConnection:waitUntilFree()
```

- - -

## Waiting For An Actor To Be Free (Promise)

Works similar to `:waituntilFree()` except it returns a promise instead of yielding.

```lua
myActorFromPool:waitUntilFreeAsync() -> Promise
```

<details>
<summary>Example</summary>

```lua
PoolConnection:waitUntilFreeAsync():andThen(function(self)
	local NumsToAdd = SharedTable.new { 2, 4, 6, 8 }
	self:runAsync(NumsToAdd):andThen(function() print(NumsToAdd["total"]) end) -- PRINTS: 20
end)
```

</details>

- - - 

# Reusing Actor Connections

DISCLAIMER: In most circumstances using a different connection (actor) from the pool is preferred over using the same connection.

If you are not using promises then reusing actor connections is simple:

```lua
local PoolConnection = Pool:take()

local nums = SharedTable.new { 2, 4, 6, 8 }
PoolConnection:run(nums)
print(nums["total"]) -- PRINTS: 20

local nums2 = SharedTable.new { 8, 16, 24, 32 }
PoolConnection:run(nums2)
print(nums2["total"]) -- PRINTS: 80
```

However if you are using promises then you need to make sure that you use the `:waitUntilFree()` method to make sure that the actor/connection is available to do more work:

```lua
local PoolConnection = Pool:take()

local nums = SharedTable.new { 2, 4, 6, 8 }
PoolConnection:runAsync(nums):andThen(function() print(nums["total"]) end) -- PRINTS: 20

PoolConnection:waitUntilFree()

local nums2 = SharedTable.new { 8, 16, 24, 32 }
PoolConnection:runAsync(nums2):andThen(function() print(nums2["total"]) end) -- PRINTS: 80
```

The above approach yields which may not be desirable in all cases, so a different approach would use the `:waitUntilFreeAsync()` method instead:

```lua
local PoolConnection = Pool:take()

local nums = SharedTable.new { 2, 4, 6, 8 }
PoolConnection:runAsync(nums):andThen(function() print(nums["total"]) end) -- PRINTS: 20

PoolConnection:waitUntilFreeAsync():andThen(function()
	local nums2 = SharedTable.new { 8, 16, 24, 32 }
	PoolConnection:runAsync(nums2):andThen(function() print(nums2["total"]) end) -- PRINTS: 80
end)
```
