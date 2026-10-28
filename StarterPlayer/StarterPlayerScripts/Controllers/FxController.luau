--!strict
-- Visual Effects Controller for Dig Pals (Step 15)
-- Handles Perfect strike flash, rare drop/egg auras per rarity, egg hatch burst, pet level up, and base upgrade celebration.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))

local LocalPlayer = Players.LocalPlayer

local FxController = {}
local started = false

local function getRarityColor(rarityName: string?): Color3
	local info = (RarityConfig.ById :: any)[rarityName or "Common"]
	if info and info.Color then
		return info.Color
	end
	return Color3.fromRGB(220, 225, 235)
end

function FxController.PlayPerfectStrikeFx(worldPos: Vector3?)
	local pos = worldPos
	if not pos then
		local char = LocalPlayer.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			pos = (char.HumanoidRootPart :: BasePart).Position + Vector3.new(0, 2, 0)
		else
			pos = Vector3.new(0, 5, 0)
		end
	end

	-- 1. Floating 3D Billboard
	local part = Instance.new("Part")
	part.Name = "Fx_PerfectStrike"
	part.Transparency = 1
	part.CanCollide = false
	part.Anchored = true
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = pos + Vector3.new(0, 1.5, 0)
	part.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Name = "PerfectBillboard"
	bb.Adornee = part
	bb.Size = UDim2.fromOffset(220, 60)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = true
	bb.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(255, 225, 60)
	label.TextStrokeColor3 = Color3.fromRGB(160, 95, 10)
	label.TextStrokeTransparency = 0.1
	label.Text = "PERFECT! +100%"
	label.Parent = bb

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.5
	uiScale.Parent = label

	-- Scale up pop
	TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.25,
	}):Play()

	-- Float up
	TweenService:Create(part, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = part.Position + Vector3.new(0, 3.5, 0),
	}):Play()

	-- Fade out
	task.delay(0.55, function()
		if label and label.Parent then
			TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end)

	-- 2. Golden sparkle burst
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 40)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Speed = NumberRange.new(5, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Rate = 0
	emitter.Parent = part

	emitter:Emit(25)
	Debris:AddItem(part, 1.2)
end

function FxController.PlayRareSpawnFx(worldPos: Vector3, rarity: string)
	local color = getRarityColor(rarity)

	local anchor = Instance.new("Part")
	anchor.Name = "Fx_RareSpawn_" .. rarity
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Position = worldPos + Vector3.new(0, 0.5, 0)
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Parent = workspace

	-- Visual light burst
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = if rarity == "Legendary" then 22 elseif rarity == "Epic" then 18 else 14
	light.Brightness = if rarity == "Legendary" then 5.0 elseif rarity == "Epic" then 3.5 else 2.5
	light.Parent = anchor

	TweenService:Create(light, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Brightness = 0,
		Range = 0,
	}):Play()

	-- Expanding Aura Ring
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Position = worldPos + Vector3.new(0, 0.2, 0)
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.CanCollide = false
	ring.Anchored = true
	ring.Parent = workspace

	local targetRadius = if rarity == "Legendary" then 14 elseif rarity == "Epic" then 10 else 7
	TweenService:Create(ring, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, targetRadius, targetRadius),
		Transparency = 1,
	}):Play()

	-- Particle Burst per rarity
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if rarity == "Legendary" then 1.0 else 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Speed = NumberRange.new(if rarity == "Legendary" then 12 else 6, if rarity == "Legendary" then 24 else 14)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Lifetime = NumberRange.new(0.6, 1.2)
	particles.Rate = 0
	particles.Parent = anchor

	local emitCount = if rarity == "Legendary" then 60 elseif rarity == "Epic" then 40 else 25
	particles:Emit(emitCount)

	Debris:AddItem(ring, 1.2)
	Debris:AddItem(anchor, 1.5)
end

function FxController.PlayEggHatchFx(screenCenter: Vector2?, rarity: string?)
	local color = getRarityColor(rarity)
	local char = LocalPlayer.Character
	local worldPos = if char and char:FindFirstChild("HumanoidRootPart")
		then (char.HumanoidRootPart :: BasePart).Position + Vector3.new(0, 1.5, 0)
		else Vector3.new(0, 5, 0)

	-- World Shockwave Ring
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Position = worldPos
	ring.Size = Vector3.new(0.2, 1.5, 1.5)
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.CanCollide = false
	ring.Anchored = true
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 12, 12),
		Transparency = 1,
	}):Play()

	-- Confetti / Shell Sparks
	local anchor = Instance.new("Part")
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Position = worldPos
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, color),
		ColorSequenceKeypoint.new(1, color),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Speed = NumberRange.new(8, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.6, 1.0)
	emitter.Rate = 0
	emitter.Parent = anchor

	emitter:Emit(45)

	Debris:AddItem(ring, 1.2)
	Debris:AddItem(anchor, 1.5)
end

function FxController.PlayLevelUpFx(character: Model?)
	local targetChar = character or LocalPlayer.Character
	if not targetChar then
		return
	end
	local hrp = targetChar:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	-- Floating Billboard "LEVEL UP!"
	local bbPart = Instance.new("Part")
	bbPart.Transparency = 1
	bbPart.CanCollide = false
	bbPart.Anchored = true
	bbPart.Position = hrp.Position + Vector3.new(0, 3.5, 0)
	bbPart.Size = Vector3.new(0.2, 0.2, 0.2)
	bbPart.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Name = "LevelUpBillboard"
	bb.Adornee = bbPart
	bb.Size = UDim2.fromOffset(240, 60)
	bb.AlwaysOnTop = true
	bb.Parent = bbPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 24
	label.TextColor3 = Color3.fromRGB(255, 220, 50)
	label.TextStrokeColor3 = Color3.fromRGB(180, 100, 20)
	label.TextStrokeTransparency = 0.15
	label.Text = "LEVEL UP!"
	label.Parent = bb

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label

	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.3,
	}):Play()

	TweenService:Create(bbPart, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = bbPart.Position + Vector3.new(0, 4, 0),
	}):Play()

	task.delay(0.7, function()
		if label and label.Parent then
			TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end)

	-- Rising Golden Ring
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Position = hrp.Position - Vector3.new(0, 2.5, 0)
	ring.Size = Vector3.new(0.15, 4.5, 4.5)
	ring.Color = Color3.fromRGB(255, 215, 50)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.CanCollide = false
	ring.Anchored = true
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = ring.Position + Vector3.new(0, 6, 0),
		Transparency = 1,
	}):Play()

	Debris:AddItem(bbPart, 1.4)
	Debris:AddItem(ring, 1.0)
end

function FxController.PlayBaseUpgradeFx(plotPos: Vector3)
	-- Expanding Celebration Ring over Plot
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Position = plotPos + Vector3.new(0, 0.3, 0)
	ring.Size = Vector3.new(0.2, 4, 4)
	ring.Color = Color3.fromRGB(80, 220, 140)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.CanCollide = false
	ring.Anchored = true
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 36, 36),
		Transparency = 1,
	}):Play()

	-- Celebration particles
	local anchor = Instance.new("Part")
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Position = plotPos + Vector3.new(0, 2, 0)
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 70)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 220, 140)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 170, 255)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Speed = NumberRange.new(10, 25)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.8, 1.5)
	emitter.Rate = 0
	emitter.Parent = anchor

	emitter:Emit(60)

	Debris:AddItem(ring, 1.5)
	Debris:AddItem(anchor, 1.8)
end

function FxController.Start()
	if started then
		return
	end
	started = true
end

return FxController
