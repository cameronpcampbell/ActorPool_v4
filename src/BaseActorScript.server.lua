--> [ SERVICES ] -------------------------------------------------------------
local SharedTableRegistry = game:GetService("SharedTableRegistry")
------------------------------------------------------------------------------


--> [ VARIABLES ] ------------------------------------------------------------
local Mod, DoneEvent, Guid
------------------------------------------------------------------------------


if script.Parent:IsA("Actor")  then
	script.Parent:BindToMessageParallel("ActorPool", function()
	if not Mod then task.synchronize(); Mod = require(script.Parent:FindFirstChildWhichIsA("ModuleScript")); task.desynchronize() end
	if not DoneEvent then DoneEvent = script.Parent.DoneEvent end
	if not Guid then Guid = script.Parent:GetAttribute("Guid") end

	Mod( SharedTableRegistry:GetSharedTable(`ActorPoolv4.1/{Guid}`) )
	DoneEvent:Fire()
	end)
end
