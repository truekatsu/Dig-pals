--!strict
-- Helper script to register and organize Chick Pet model once imported via Studio 3D Importer

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local PetAssets = ReplicatedStorage:WaitForChild("PetAssets")
local PetModels = PetAssets:WaitForChild("PetModels")
local MeshTemplates = PetAssets:WaitForChild("MeshTemplates")

local ProcessImportedPetChick = {}

local TARGET_HEIGHT_STUDS = 1.8 -- Cute compact companion scale (height 1.8 studs)

local function findImportedChick(): (Instance?, MeshPart?)
	local names = {
		"DigPals_MinerChick_Rig",
		"DPM_MinerChick_Mesh",
		"pet_chick",
		"PetChick",
		"Chick",
		"DPM_Chick_Rig",
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
		if ch.Name ~= "ClientPetVisuals" and ch.Name ~= "ClientBasePetVisuals" and ch.Name:lower():find("chick") then
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

function ProcessImportedPetChick.Run(): (boolean, string)
	local rootObj, meshPart = findImportedChick()
	if not rootObj or not meshPart then
		return false, "No candidate Pet Chick model found in workspace root. Please import DigPals_MinerChick_Rig.fbx using 3D Importer."
	end

	local oldModel = PetModels:FindFirstChild("Chick")
	if oldModel then
		oldModel:Destroy()
	end

	local model: Model
	local chickMesh: MeshPart

	if rootObj:IsA("Model") and rootObj ~= meshPart then
		model = rootObj:Clone()
		model.Name = "Chick"
		local pl = model:FindFirstChild("PackageLink")
		if pl then
			pl:Destroy()
		end
		local ip = model:FindFirstChild("InitialPoses")
		if ip then
			ip:Destroy()
		end
		chickMesh = model:FindFirstChildWhichIsA("MeshPart", true) :: MeshPart
	else
		model = Instance.new("Model")
		model.Name = "Chick"
		chickMesh = meshPart:Clone()
		chickMesh.Name = "PetChick"
		chickMesh.Parent = model
	end

	chickMesh.Color = Color3.fromRGB(255, 205, 70)
	chickMesh.Material = Enum.Material.SmoothPlastic
	chickMesh.CanCollide = false
	chickMesh.CanTouch = false
	chickMesh.CanQuery = false
	chickMesh.CastShadow = true
	chickMesh.Anchored = false
	chickMesh.Massless = true

	local currentHeight = chickMesh.Size.Y
	local scaleFactor = if currentHeight > 0 then (TARGET_HEIGHT_STUDS / currentHeight) else 1
	model:ScaleTo(scaleFactor)

	local rootPart = model:FindFirstChild("RootPart") :: BasePart?
	if not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = "RootPart"
		rootPart.Size = Vector3.new(1.4, TARGET_HEIGHT_STUDS, 1.4)
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.CanTouch = false
		rootPart.CanQuery = false
		rootPart.Anchored = true
		rootPart.CFrame = chickMesh.CFrame
		rootPart.Parent = model
	end
	model.PrimaryPart = rootPart

	local weld = rootPart:FindFirstChildOfClass("WeldConstraint")
	if not weld then
		weld = Instance.new("WeldConstraint")
		weld.Name = "MeshWeld"
		weld.Part0 = rootPart
		weld.Part1 = chickMesh
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

	-- Connect RBX_ANIMSAVES keyframes
	local rbxAnimSaves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
	local chickSaves = rbxAnimSaves and rbxAnimSaves:FindFirstChild("Chick")
	local animsFolder = model:FindFirstChild("Animations")
	if not animsFolder then
		animsFolder = Instance.new("Folder")
		animsFolder.Name = "Animations"
		animsFolder.Parent = model
	end

	if chickSaves then
		for _, mapping in ipairs({
			{ Name = "Idle", Key = "Chick_Idle" },
			{ Name = "Walk", Key = "Chick_Walk" },
			{ Name = "Digging", Key = "Chick_Digging" },
		}) do
			local kfs = chickSaves:FindFirstChild(mapping.Key)
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

	local oldTemplate = MeshTemplates:FindFirstChild("PetChick")
	if oldTemplate then
		oldTemplate:Destroy()
	end
	local tMesh = chickMesh:Clone()
	tMesh.Name = "PetChick"
	tMesh.Parent = MeshTemplates

	if rootObj and rootObj.Parent == workspace then
		rootObj:Destroy()
	end

	return true, string.format("Chick Pet model successfully registered into ReplicatedStorage.PetAssets.PetModels.Chick (Height: %.2f studs)!", chickMesh.Size.Y)
end

return ProcessImportedPetChick
