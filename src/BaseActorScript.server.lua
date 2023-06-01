local Mod, DoneEvent

script.Parent:BindToMessage("ActorPool", function(...)
	if not Mod then Mod = require(script.Parent:FindFirstChildWhichIsA("ModuleScript")) end
	if not DoneEvent then DoneEvent = script.Parent.DoneEvent end
	task.desynchronize()
	
	Mod(...)
	DoneEvent:Fire()
end)
