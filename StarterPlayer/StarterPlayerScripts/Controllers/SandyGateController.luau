--!strict
-- Client controller for Sandy Gate portcullis animations, padlock visual, and signboard state (Step 14)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local SandyGateController = {}

local isUnlocked: boolean = false
local started: boolean = false

local function findGateParts(): (BasePart?, BasePart?, BasePart?, SurfaceGui?)
	local plain = workspace:FindFirstChild("Plain")
	if not plain then
		return nil, nil, nil, nil
	end
	local gateFolder = plain:FindFirstChild("SandyGate")
	if not gateFolder then
		return nil, nil, nil, nil
	end

	local portcullis = gateFolder:FindFirstChild("SandyGate_Portcullis") :: BasePart?
	local padlock = gateFolder:FindFirstChild("SandyGate_Padlock") :: BasePart?
	local signboard = gateFolder:FindFirstChild("GateSign_Board") :: BasePart?
	local sGui = signboard and signboard:FindFirstChild("GateSignDisplay") :: SurfaceGui?

	return portcullis, padlock, signboard, sGui
end

local function applyGateState(animate: boolean)
	local portcullis, padlock, _, sGui = findGateParts()

	if isUnlocked then
		-- Gate is unlocked: open portcullis & hide padlock
		if portcullis then
			portcullis.CanCollide = false
			local targetCFrame = CFrame.new(portcullis.Position.X, 21.5, portcullis.Position.Z)
			if animate then
				TweenService:Create(
					portcullis,
					TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = targetCFrame, Transparency = 0.4 }
				):Play()
			else
				portcullis.CFrame = targetCFrame
				portcullis.Transparency = 0.4
			end
		end

		if padlock then
			padlock.CanCollide = false
			padlock.Transparency = 1
			local prompt = padlock:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = false
			end
		end

		if sGui then
			local frame = sGui:FindFirstChild("Frame")
			local statusLbl = frame and frame:FindFirstChild("StatusLabel") :: TextLabel?
			if statusLbl then
				statusLbl.TextColor3 = Color3.fromRGB(80, 225, 120)
				statusLbl.Text = "[TERBUKA] Silakan Masuk ke Area Sand!"
			end
		end
	else
		-- Gate is locked: portcullis down & solid
		if portcullis then
			portcullis.CanCollide = true
			portcullis.Transparency = 0
			portcullis.CFrame = CFrame.new(portcullis.Position.X, 7.5, portcullis.Position.Z)
		end

		if padlock then
			padlock.CanCollide = true
			padlock.Transparency = 0
			local prompt = padlock:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = true
			end
		end

		if sGui then
			local frame = sGui:FindFirstChild("Frame")
			local statusLbl = frame and frame:FindFirstChild("StatusLabel") :: TextLabel?
			if statusLbl then
				statusLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
				statusLbl.Text = "[TERKUNCI] Dekati Padlock untuk Buka"
			end
		end
	end
end

function SandyGateController.IsUnlocked(): boolean
	return isUnlocked
end

function SandyGateController.Start()
	if started then
		return
	end
	started = true

	local attr = LocalPlayer:GetAttribute("SandyGateUnlocked")
	if type(attr) == "boolean" then
		isUnlocked = attr
	end

	applyGateState(false)

	LocalPlayer:GetAttributeChangedSignal("SandyGateUnlocked"):Connect(function()
		local val = LocalPlayer:GetAttribute("SandyGateUnlocked")
		if type(val) == "boolean" and val ~= isUnlocked then
			isUnlocked = val
			applyGateState(true)
		end
	end)

	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
	Remotes.GetEvent("StateSync").OnClientEvent:Connect(function(snapshot: any)
		if type(snapshot) == "table" and type(snapshot.SandyGateUnlocked) == "boolean" then
			if snapshot.SandyGateUnlocked ~= isUnlocked then
				isUnlocked = snapshot.SandyGateUnlocked
				applyGateState(true)
			end
		end
	end)
end

return SandyGateController
