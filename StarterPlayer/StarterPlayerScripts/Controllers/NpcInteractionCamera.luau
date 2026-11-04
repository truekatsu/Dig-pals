--!strict
-- One camera session across NPC dialogue -> shop handoffs, with cancellable restoration.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local CameraFocus = {}
type SavedCamera = {
	Camera: Camera, Type: Enum.CameraType, Subject: Instance?,
	Frame: CFrame, Focus: CFrame, Fov: number, RootPosition: Vector3?,
}
local saved: SavedCamera? = nil
local activeOwner: string? = nil
local activeTarget: BasePart? = nil
local activeTween: Tween? = nil
local revision = 0

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function cancelTween()
	revision += 1
	if activeTween then activeTween:Cancel(); activeTween = nil end
end

local function resolveNpcAnchor(target: BasePart): BasePart
	if target:FindFirstChildWhichIsA("ProximityPrompt", true) then return target end
	local best, distance = target, 25
	if target.Parent then
		for _, candidate in target.Parent:GetDescendants() do
			if candidate:IsA("BasePart") and candidate:FindFirstChildWhichIsA("ProximityPrompt", true)
				and (candidate:GetAttribute("DigPalsMerchantNode") or candidate:GetAttribute("DigPalsShovelShopNode")) then
				local d = (candidate.Position - target.Position).Magnitude
				if d < distance then best, distance = candidate, d end
			end
		end
	end
	return best
end

function CameraFocus.Begin(target: BasePart?, owner: string)
	if not target or not target.Parent then return end
	target = resolveNpcAnchor(target)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if activeOwner == owner and activeTarget == target then return end
	cancelTween()
	if not saved then
		saved = {Camera = camera, Type = camera.CameraType, Subject = camera.CameraSubject,
			Frame = camera.CFrame, Focus = camera.Focus, Fov = camera.FieldOfView, RootPosition = rootPosition()}
	end
	activeOwner, activeTarget = owner, target
	local focusPoint = target.Position - Vector3.new(0, 0.65, 0)
	-- Frame the NPC from its front so side approaches do not face a shop wall.
	local forward = Vector3.new(target.CFrame.LookVector.X, 0, target.CFrame.LookVector.Z)
	if forward.Magnitude < 0.01 then forward = Vector3.new(0, 0, -1) end
	local position = focusPoint + forward.Unit * 10 + Vector3.new(0, 1.6, 0)
	if (focusPoint - position).Magnitude < 0.1 then return end
	camera.CameraType = Enum.CameraType.Scriptable
	activeTween = TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.lookAt(position, focusPoint),
		Focus = CFrame.new(focusPoint),
		FieldOfView = math.max(35, saved.Fov - 8),
	})
	activeTween:Play()
end

function CameraFocus.End(owner: string?)
	if owner and owner ~= activeOwner then return end
	if not saved then return end
	cancelTween()
	activeOwner, activeTarget = nil, nil
	local snapshot = saved
	local camera = snapshot.Camera
	if camera ~= workspace.CurrentCamera then saved = nil; return end
	local currentPosition = rootPosition()
	local delta = if currentPosition and snapshot.RootPosition then currentPosition - snapshot.RootPosition else Vector3.zero
	local stamp = revision
	local tween = TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		CFrame = snapshot.Frame + delta, Focus = snapshot.Focus + delta, FieldOfView = snapshot.Fov,
	})
	activeTween = tween
	tween.Completed:Connect(function(state)
		if state ~= Enum.PlaybackState.Completed or revision ~= stamp then return end
		camera.CameraSubject = snapshot.Subject
		camera.CameraType = snapshot.Type
		activeTween, saved = nil, nil
	end)
	tween:Play()
end

player:GetAttributeChangedSignal("ActiveShopModal"):Connect(function()
	if activeOwner and player:GetAttribute("ActiveShopModal") ~= activeOwner then
		CameraFocus.End(activeOwner)
	end
end)
player.CharacterRemoving:Connect(function()
	cancelTween()
	local snapshot = saved
	activeOwner, activeTarget, saved = nil, nil, nil
	if snapshot and snapshot.Camera == workspace.CurrentCamera then
		snapshot.Camera.FieldOfView = snapshot.Fov
		snapshot.Camera.CameraType = snapshot.Type
		snapshot.Camera.CameraSubject = snapshot.Subject
	end
end)
return CameraFocus
