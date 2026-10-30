--!strict
-- Auto-register Pet models when imported into Workspace

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local function checkAndProcess(child: Instance)
	local lower = child.Name:lower()
	if lower:find("cat") or lower:find("cosmic") then
		local procModule = ServerStorage:FindFirstChild("ProcessImportedPetCat")
		if procModule then
			local proc = require(procModule :: ModuleScript) :: any
			task.wait(0.5)
			pcall(function() proc.Run() end)
		end
	elseif lower:find("dog") or lower:find("comet") then
		local procModule = ServerStorage:FindFirstChild("ProcessImportedPetDog")
		if procModule then
			local proc = require(procModule :: ModuleScript) :: any
			task.wait(0.5)
			pcall(function() proc.Run() end)
		end
	elseif lower:find("bunny") or lower:find("rabbit") then
		local procModule = ServerStorage:FindFirstChild("ProcessImportedPetBunny")
		if procModule then
			local proc = require(procModule :: ModuleScript) :: any
			task.wait(0.5)
			pcall(function() proc.Run() end)
		end
	elseif lower:find("chick") or lower:find("chicken") then
		local procModule = ServerStorage:FindFirstChild("ProcessImportedPetChick")
		if procModule then
			local proc = require(procModule :: ModuleScript) :: any
			task.wait(0.5)
			pcall(function() proc.Run() end)
		end
	elseif lower:find("mole") then
		local procModule = ServerStorage:FindFirstChild("ProcessImportedPetMole")
		if procModule then
			local proc = require(procModule :: ModuleScript) :: any
			task.wait(0.5)
			pcall(function() proc.Run() end)
		end
	end
end

Workspace.ChildAdded:Connect(checkAndProcess)

for _, child in ipairs(Workspace:GetChildren()) do
	checkAndProcess(child)
end
