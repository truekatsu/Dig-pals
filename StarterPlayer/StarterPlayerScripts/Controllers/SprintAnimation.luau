--!strict
-- Procedural run cycles, evaluated before the shared shovel arm overlay on every client.
-- https://create.roblox.com/docs/reference/engine/classes/Motor6D#Transform
local Config = require(game:GetService("ReplicatedStorage").Shared.Config.Sprint)
type State = {weight: number, carry: number, phase: number, joints: {[string]: Motor6D}, originals: {[Motor6D]: CFrame}}
local states: {[Model]: State} = {}
local Animation = {}

function Animation.Restore()
	-- Remove last frame's pose before Animator runs, including joints not animated by an avatar pack.
	for character, state in states do
		for joint, pose in state.originals do
			if joint.Parent then joint.Transform = pose end
		end
		table.clear(state.originals)
		if not character.Parent then states[character] = nil end
	end
end

function Animation.Step(character: Model, humanoid: Humanoid?, holding: boolean, dt: number)
	if not humanoid then return end
	local state = states[character]
	if not state then
		state = {weight = 0, carry = 0, phase = 0, joints = {}, originals = {}}
		for _, item in character:GetDescendants() do
			if item:IsA("Motor6D") then state.joints[item.Name] = item end
		end
		states[character] = state
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local hstate = humanoid:GetState()
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		and (hstate == Enum.HumanoidStateType.Running or hstate == Enum.HumanoidStateType.RunningNoPhysics)
	local running = character:GetAttribute("SprintEnabled") == true and humanoid.Health > 0
		and not humanoid.Sit and grounded and speed > Config.MinimumAnimationSpeed
	local blend = 1 - math.exp(-Config.BlendSpeed * dt)
	state.weight += ((if running then 1 else 0) - state.weight) * blend
	state.carry += ((if holding then 1 else 0) - state.carry) * blend
	if state.weight < 0.001 then return end
	state.phase += dt * math.pi * 2 * Config.CyclesPerSecond * math.clamp(speed / Config.RunSpeed, 0.4, 1.35)
	local wave = math.sin(state.phase)
	local carry = state.carry
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local function pose(name: string, rotation: CFrame, lift: number?)
		local joint = state.joints[name]
		-- CharacterAdded can precede the avatar's joints arriving on this client.
		if not joint or not joint.Parent then
			local found = character:FindFirstChild(name, true)
			if found and found:IsA("Motor6D") then joint = found state.joints[name] = found end
		end
		if not joint or not joint.Parent then return end
		local original = joint.Transform
		state.originals[joint] = original
		local basis = joint.C0.Rotation
		local target = basis:Inverse() * (CFrame.new(0, lift or 0, 0) * rotation) * basis
		joint.Transform = original:Lerp(target, state.weight)
	end
	local function angle(x: number, y: number?, z: number?): CFrame
		return CFrame.Angles(math.rad(x), math.rad(y or 0), math.rad(z or 0))
	end
	local stride = 49 - carry * 9
	pose(if r15 then "Root" else "RootJoint", angle(-9 + carry * 3, wave * (3 - carry * 2), wave * 1.8), math.abs(math.cos(state.phase)) * 0.055)
	pose("Waist", angle(-4 + carry * 2, -wave * (5 - carry * 3)))
	pose("Neck", angle(6 - carry * 2, wave * 2))
	pose(if r15 then "RightHip" else "Right Hip", angle(wave * stride))
	pose(if r15 then "LeftHip" else "Left Hip", angle(-wave * stride))
	if r15 then
		pose("RightKnee", angle(math.max(0, -wave) * 70 + 8))
		pose("LeftKnee", angle(math.max(0, wave) * 70 + 8))
		pose("RightAnkle", angle(-math.max(0, -wave) * 18))
		pose("LeftAnkle", angle(-math.max(0, wave) * 18))
	end
	-- The carry overlay owns both arms when holding a shovel. No changes to Tool.Grip.
	if not holding then
		pose(if r15 then "RightShoulder" else "Right Shoulder", angle(-wave * 42 - 12, 0, 7))
		pose(if r15 then "LeftShoulder" else "Left Shoulder", angle(wave * 42 - 12, 0, -7))
		pose("RightElbow", angle(-65 + wave * 12))
		pose("LeftElbow", angle(-65 - wave * 12))
	end
end

return Animation
