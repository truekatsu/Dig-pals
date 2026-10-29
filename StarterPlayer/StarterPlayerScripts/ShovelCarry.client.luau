--!strict
-- Procedural two-hand carry overlay for every player, after Animator updates.
-- Arms blend in/out; legs, locomotion and the normal character Animator keep running.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Carry = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ShovelCarry"))
local ikStates: {[Model]: {tool: Tool, controls: {IKControl}, targets: {Attachment}}} = {}
local tracked: {[Model]: {weight: number, joints: {[Motor6D]: CFrame}}} = {}
local function bind(character: Model)
 tracked[character] = {weight = 0, joints = {}}
end
local function playerAdded(player: Player)
 player.CharacterAdded:Connect(bind)
 if player.Character then bind(player.Character) end
end
Players.PlayerAdded:Connect(playerAdded)
for _, player in Players:GetPlayers() do playerAdded(player) end

local function pointArm(joint: Motor6D, target: Vector3, weight: number)
 local p0, arm = joint.Part0, joint.Part1
 if not p0 or not arm then return end
 local shoulder = (p0.CFrame * joint.C0).Position
 local y = (shoulder - target).Unit
 local z = p0.CFrame.LookVector * -1
 local x = y:Cross(z).Unit
 z = x:Cross(y).Unit
 local armFrame = CFrame.fromMatrix(shoulder - y * arm.Size.Y * 0.5, x, y, z)
 local pose = joint.C0:Inverse() * p0.CFrame:ToObjectSpace(armFrame) * joint.C1
 joint.Transform = joint.Transform:Lerp(pose, weight)
end
RunService.PreSimulation:Connect(function(dt)
 for character, state in tracked do
  if not character.Parent then
   local oldIK = ikStates[character]
   if oldIK then
    for _, control in oldIK.controls do control:Destroy() end
    for _, target in oldIK.targets do target:Destroy() end
    ikStates[character] = nil
   end
   tracked[character] = nil
   continue
  end
  local held: Tool? = nil
  for _, child in character:GetChildren() do
   if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") then held = child break end
  end
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  local handle = held and held:FindFirstChild("Handle")
  local active = handle and handle:IsA("BasePart") and humanoid and humanoid.Health > 0
  state.weight += ((if active then 1 else 0) - state.weight) * (1 - math.exp(-Carry.BlendSpeed * dt))
  local ikState = ikStates[character]
  if ikState and (not active or ikState.tool ~= held) then
   for _, control in ikState.controls do control:Destroy() end
   for _, target in ikState.targets do target:Destroy() end
   ikStates[character] = nil
   ikState = nil
  end
  if active and humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 and handle and handle:IsA("BasePart") then
   if not ikState then
    local controls: {IKControl} = {}
    local targets: {Attachment} = {}
    for _, side in {"Right", "Left"} do
     local upper = character:FindFirstChild(side .. "UpperArm")
     local hand = character:FindFirstChild(side .. "Hand")
     if upper and hand then
      local target = Instance.new("Attachment")
      target.Name = side .. "ShovelHandTarget"
      target.Position = Vector3.new(0, if side == "Right" then Carry.RightHandY else Carry.LeftHandY, 0)
      target.Parent = handle
      local ik = Instance.new("IKControl")
      ik.Name = side .. "ShovelCarryIK"
      ik.Type = Enum.IKControlType.Position
      ik.ChainRoot = upper
      ik.EndEffector = hand
      ik.Target = target
      ik.Priority = 2
      ik.SmoothTime = 0.08
      ik.Parent = humanoid
      table.insert(controls, ik)
      table.insert(targets, target)
     end
    end
    ikState = {tool = held :: Tool, controls = controls, targets = targets}
    ikStates[character] = ikState
   end
   for _, control in ikState.controls do control.Weight = state.weight end
  elseif active and handle and handle:IsA("BasePart") then
   for _, side in {"Right", "Left"} do
    local joint = character:FindFirstChild(side .. " Shoulder", true) or character:FindFirstChild(side .. "Shoulder", true)
    if joint and joint:IsA("Motor6D") then
     local target = handle.CFrame:PointToWorldSpace(Vector3.new(0, if side == "Right" then Carry.RightHandY else Carry.LeftHandY, 0))
     -- R6 uses straight block arms. R15 also bends the elbow towards the shaft.
     pointArm(joint, target, state.weight)
     state.joints[joint] = joint.Transform
     local elbow = character:FindFirstChild(side .. "Elbow", true)
     if elbow and elbow:IsA("Motor6D") then
      elbow.Transform = elbow.Transform:Lerp(CFrame.Angles(math.rad(-65), 0, 0), state.weight)
      state.joints[elbow] = elbow.Transform
     end
    end
   end
  elseif state.weight > 0.001 then
   for joint, pose in state.joints do
    if joint.Parent then joint.Transform = joint.Transform:Lerp(pose, state.weight) end
   end
  else
   table.clear(state.joints)
  end
 end
end)
