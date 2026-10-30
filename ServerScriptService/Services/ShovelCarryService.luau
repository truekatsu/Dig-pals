--!strict
-- Server-visible carry attachment and cosmetic back display. Never a second Tool.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Carry = require(Shared.Config.ShovelCarry)
local Builder = require(Shared.ShovelModelBuilder)
local Service = {}

function Service.BindCharacter(player: Player, character: Model)
 if character:GetAttribute("ShovelCarryBound") then return end
 character:SetAttribute("ShovelCarryBound", true)
 local connections: {RBXScriptConnection} = {}
 local activeTool: Tool? = nil
 local gripConnection: RBXScriptConnection? = nil
 local queued = false
 local dead = false
 local refresh: () -> ()
 local function queue()
  if queued or dead then return end
  queued = true
  task.defer(function() queued = false if not dead then refresh() end end)
 end
 refresh = function()
  if not character.Parent or player.Character ~= character then return end
  local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if not torso or not torso:IsA("BasePart") or not humanoid then return end
  local held: Tool? = nil
  if humanoid.Health > 0 then
   for _, child in character:GetChildren() do
    if child:IsA("Tool") and child:GetAttribute("DigPalsShovelTool") then held = child break end
   end
  end
  local back = character:FindFirstChild("StowedShovel")
  if held then
   if back then back:Destroy() end
   local handle = held:FindFirstChild("Handle")
   if not handle or not handle:IsA("BasePart") then return end
   -- Native RightGrip must not fight the shared torso carry joint.
   for _, joint in character:GetDescendants() do
    if joint.Name == "RightGrip" and joint:IsA("JointInstance") and joint.Part1 == handle then joint:Destroy() end
   end
   local joint = handle:FindFirstChild("ShovelCarryJoint") :: Motor6D?
   if not joint then
    joint = Instance.new("Motor6D")
    joint.Name = "ShovelCarryJoint"
    joint.Part0 = torso
    joint.Part1 = handle
    joint.C0 = Carry.GetHeldCFrame(torso) * held.Grip
    joint.Parent = handle
    local tool = held
    local motor = joint
    if gripConnection then gripConnection:Disconnect() end
    gripConnection = tool:GetPropertyChangedSignal("Grip"):Connect(function()
     if motor.Parent then motor.C0 = Carry.GetHeldCFrame(torso) * tool.Grip end
    end)
    -- Tool destruction disconnects its property signal automatically.

   end
   activeTool = held
  else
   if activeTool then
    if gripConnection then gripConnection:Disconnect() gripConnection = nil end
    local handle = activeTool:FindFirstChild("Handle")
    local joint = handle and handle:FindFirstChild("ShovelCarryJoint")
    if joint then joint:Destroy() end
    activeTool = nil
   end
   local id = player:GetAttribute("EquippedShovel")
   if humanoid.Health <= 0 or typeof(id) ~= "string" then
    if back then back:Destroy() end
    return
   end
   if back and back:GetAttribute("ShovelId") == id then return end
   if back then back:Destroy() end
   local model = Builder.ClonePreviewModel(id)
   model.Name = "StowedShovel"
   model:SetAttribute("ShovelId", id)
   model:SetAttribute("CosmeticOnly", true)
   model:ScaleTo(model:GetScale() * Carry.Height / model:GetExtentsSize().Y)
   local box = model:GetBoundingBox()
   local target = torso.CFrame * Carry.Stowed
   for _, part in model:GetDescendants() do
    if part:IsA("BasePart") then
     part.CFrame = target * box:ToObjectSpace(part.CFrame)
     part.Anchored = false
     part.Massless = true
     part.CanCollide = false
     part.CanQuery = false
     part.CanTouch = false
     local weld = Instance.new("WeldConstraint")
     weld.Part0 = torso
     weld.Part1 = part
     weld.Parent = part
    end
   end
   model.Parent = character
  end
 end
 table.insert(connections, character.ChildAdded:Connect(queue))
 table.insert(connections, character.ChildRemoved:Connect(queue))
 table.insert(connections, character.DescendantAdded:Connect(function(v)
  if v.Name == "RightGrip" then queue() end
 end))
 table.insert(connections, player:GetAttributeChangedSignal("EquippedShovel"):Connect(queue))
 task.spawn(function()
  local humanoid = character:WaitForChild("Humanoid", 10)
  if humanoid and humanoid:IsA("Humanoid") then
   table.insert(connections, humanoid.Died:Connect(queue))
  end
  queue()
 end)
 character.Destroying:Once(function()
  dead = true
  if gripConnection then gripConnection:Disconnect() end
  for _, c in connections do c:Disconnect() end
 end)
 queue()
end
return Service
