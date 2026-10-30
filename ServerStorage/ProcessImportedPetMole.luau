--!strict
-- Helper script to register and organize Mole Pet model once imported via Studio 3D Importer

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local PetAssets = ReplicatedStorage:WaitForChild("PetAssets")
local PetModels = PetAssets:WaitForChild("PetModels")
local MeshTemplates = PetAssets:WaitForChild("MeshTemplates")

local ProcessImportedPetMole = {}

local TARGET_HEIGHT_STUDS = 1.8 -- Cute low-ground digging companion scale (height 1.8 studs)

local function findImportedMole(): (Instance?, MeshPart?)
	local names = {
		"DigPals_MinerMole_Rig",
		"DPM_MinerMole_Mesh",
		"pet_mole",
		"PetMole",
		"Mole",
		"DPM_Mole_Rig",
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
		if ch.Name ~= "ClientPetVisuals" and ch.Name ~= "ClientBasePetVisuals" and ch.Name:lower():find("mole") then
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

function ProcessImportedPetMole.Run(): (boolean, string)
	local rootObj, meshPart = findImportedMole()
	if not rootObj or not meshPart then
		return false, "No candidate Pet Mole model found in workspace root. Please import DigPals_MinerMole_Rig.fbx using 3D Importer."
	end

	local oldModel = PetModels:FindFirstChild("Mole")
	if oldModel then
		oldModel:Destroy()
	end

	local model: Model
	local moleMesh: MeshPart

	if rootObj:IsA("Model") and rootObj ~= meshPart then
		model = rootObj:Clone()
		model.Name = "Mole"
		local pl = model:FindFirstChild("PackageLink")
		if pl then
			pl:Destroy()
		end
		local ip = model:FindFirstChild("InitialPoses")
		if ip then
			ip:Destroy()
		end
		moleMesh = model:FindFirstChildWhichIsA("MeshPart", true) :: MeshPart
	else
		model = Instance.new("Model")
		model.Name = "Mole"
		moleMesh = meshPart:Clone()
		moleMesh.Name = "PetMole"
		moleMesh.Parent = model
	end

	moleMesh.Color = Color3.fromRGB(115, 65, 38)
	moleMesh.Material = Enum.Material.SmoothPlastic
	moleMesh.CanCollide = false
	moleMesh.CanTouch = false
	moleMesh.CanQuery = false
	moleMesh.CastShadow = true
	moleMesh.Anchored = false
	moleMesh.Massless = true

	local currentHeight = moleMesh.Size.Y
	local scaleFactor = if currentHeight > 0 then (TARGET_HEIGHT_STUDS / currentHeight) else 1
	model:ScaleTo(scaleFactor)

	local rootPart = model:FindFirstChild("RootPart") :: BasePart?
	if not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = "RootPart"
		rootPart.Size = Vector3.new(1.6, TARGET_HEIGHT_STUDS, 1.8)
		rootPart.Transparency = 1
		rootPart.CanCollide = false
		rootPart.CanTouch = false
		rootPart.CanQuery = false
		rootPart.Anchored = true
		rootPart.CFrame = moleMesh.CFrame
		rootPart.Parent = model
	end
	model.PrimaryPart = rootPart

	local weld = rootPart:FindFirstChildOfClass("WeldConstraint")
	if not weld then
		weld = Instance.new("WeldConstraint")
		weld.Name = "MeshWeld"
		weld.Part0 = rootPart
		weld.Part1 = moleMesh
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
	local moleSaves = rbxAnimSaves and rbxAnimSaves:FindFirstChild("Mole")
	local animsFolder = model:FindFirstChild("Animations")
	if not animsFolder then
		animsFolder = Instance.new("Folder")
		animsFolder.Name = "Animations"
		animsFolder.Parent = model
	end

	if moleSaves then
		for _, mapping in ipairs({
			{ Name = "Idle", Key = "Mole_Idle" },
			{ Name = "Walk", Key = "Mole_Walk" },
			{ Name = "Digging", Key = "Mole_Digging" },
		}) do
			local kfs = moleSaves:FindFirstChild(mapping.Key)
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

	local oldTemplate = MeshTemplates:FindFirstChild("PetMole")
	if oldTemplate then
		oldTemplate:Destroy()
	end
	local tMesh = moleMesh:Clone()
	tMesh.Name = "PetMole"
	tMesh.Parent = MeshTemplates

	if rootObj and rootObj.Parent == workspace then
		rootObj:Destroy()
	end

	return true, string.format("Mole Pet model successfully registered into ReplicatedStorage.PetAssets.PetModels.Mole (Height: %.2f studs)!", moleMesh.Size.Y)
end

return ProcessImportedPetMole
