--!strict
-- Helper script to register and organize Dog Pet model once imported via Studio 3D Importer

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local PetAssets = ReplicatedStorage:WaitForChild("PetAssets")
local PetModels = PetAssets:WaitForChild("PetModels")
local MeshTemplates = PetAssets:WaitForChild("MeshTemplates")

local ProcessImportedPetDog = {}

local TARGET_HEIGHT_STUDS = 2.0 -- Cute companion scale (height 2.0 studs)

local function findImportedDog(): (Instance?, MeshPart?)
	local names = {
		"DigPals_CometMinerDog_Rig",
		"DPM_CometMinerDog_Mesh",
		"pet_dog",
		"PetDog",
		"Dog",
		"DPM_Dog_Rig",
	}
	for _, name in ipairs(names) do
		local found = workspace:FindFirstChild(name)
		if found and found.Name ~= "ClientPetVisuals" and found.Name ~= "ClientBasePetVisuals" then
			if found:IsA("MeshPart") then
				return found, found
			elseif found:IsA("Model") then
				local mp = found:FindFirstChildWhichIsA("MeshPart", true)
				if mp then
					return found, mp
				end
			end
		end
	end

	for _, ch in ipairs(workspace:GetChildren()) do
		if ch.Name ~= "ClientPetVisuals" and ch.Name ~= "ClientBasePetVisuals" and ch.Name:lower():find("dog") then
			if ch:IsA("MeshPart") then
				return ch, ch
			elseif ch:IsA("Model") then
				local mp = ch:FindFirstChildWhichIsA("MeshPart", true)
				if mp then
					return ch, mp
				end
			end
		end
	end

	return nil, nil
end

function ProcessImportedPetDog.Run(): (boolean, string)
	local rootObj, meshPart = findImportedDog()
	if not rootObj or not meshPart then
		return false, "No candidate Pet Dog model found in workspace root. Please import DigPals_CometMinerDog_Rig.fbx using 3D Importer."
	end

	local oldModel = PetModels:FindFirstChild("Dog")
	if oldModel then
		oldModel:Destroy()
	end

	local model: Model
	local dogMesh: MeshPart

	if rootObj:IsA("Model") and rootObj ~= meshPart then
		model = rootObj:Clone()
		model.Name = "Dog"
		local pl = model:FindFirstChild("PackageLink")
		if pl then
			pl:Destroy()
		end
		local ip = model:FindFirstChild("InitialPoses")
		if ip then
			ip:Destroy()
		end
		dogMesh = model:FindFirstChildWhichIsA("MeshPart", true) :: MeshPart
	else
		model = Instance.new("Model")
		model.Name = "Dog"
		dogMesh = meshPart:Clone()
		dogMesh.Name = "PetDog"
		dogMesh.Parent = model
	end

	dogMesh.Color = Color3.fromRGB(15, 30, 60)
	dogMesh.Material = Enum.Material.SmoothPlastic
	dogMesh.CanCollide = false
	dogMesh.CanTouch = false
	dogMesh.CanQuery = false
	dogMesh.CastShadow = true
	dogMesh.Anchored = false
	dogMesh.Massless = true

	local currentHeight = dogMesh.Size.Y
	local scaleFactor = if currentHeight > 0 then (TARGET_HEIGHT_STUDS / currentHeight) else 1
	model:ScaleTo(scaleFactor)

	local rootPart = model:FindFirstChild("RootPart") :: BasePart?
	if not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = "RootPart"
		rootPart.Size = Vector3.new(1.6, TARGET_HEIGHT_STUDS, 1.6)
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.CanTouch = false
		rootPart.CanQuery = false
		rootPart.Anchored = true
		rootPart.CFrame = dogMesh.CFrame
		rootPart.Parent = model
	end
	model.PrimaryPart = rootPart

	local weld = rootPart:FindFirstChildOfClass("WeldConstraint")
	if not weld then
		weld = Instance.new("WeldConstraint")
		weld.Name = "MeshWeld"
		weld.Part0 = rootPart
		weld.Part1 = dogMesh
		weld.Parent = rootPart
	end

	local animController = model:FindFirstChildOfClass("AnimationController")
	if not animController then
		animController = Instance.new("AnimationController")
		animController.Parent = model
	end
	local animator = animController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animController
	end

	-- Connect RBX_ANIMSAVES keyframes if available
	local rbxAnimSaves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
	local dogSaves = rbxAnimSaves and rbxAnimSaves:FindFirstChild("Dog")
	local animsFolder = model:FindFirstChild("Animations")
	if not animsFolder then
		animsFolder = Instance.new("Folder")
		animsFolder.Name = "Animations"
		animsFolder.Parent = model
	end

	if dogSaves then
		for _, mapping in ipairs({
			{ Name = "Idle", Key = "Dog_Idle" },
			{ Name = "Walk", Key = "Dog_Walk" },
			{ Name = "Digging", Key = "Dog_Digging" },
		}) do
			local kfs = dogSaves:FindFirstChild(mapping.Key)
			if kfs and kfs:IsA("KeyframeSequence") then
				local existingAnim = animsFolder:FindFirstChild(mapping.Name) :: Animation?
				if not existingAnim then
					existingAnim = Instance.new("Animation")
					existingAnim.Name = mapping.Name
					existingAnim.Parent = animsFolder
				end
				local url = KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
				existingAnim.AnimationId = url
			end
		end
	end

	model.Parent = PetModels

	local oldTemplate = MeshTemplates:FindFirstChild("PetDog")
	if oldTemplate then
		oldTemplate:Destroy()
	end
	local tMesh = dogMesh:Clone()
	tMesh.Name = "PetDog"
	tMesh.Parent = MeshTemplates

	if rootObj and rootObj.Parent == workspace then
		rootObj:Destroy()
	end

	return true, string.format("Dog Pet model successfully registered into ReplicatedStorage.PetAssets.PetModels.Dog (Height: %.2f studs)!", dogMesh.Size.Y)
end

return ProcessImportedPetDog
