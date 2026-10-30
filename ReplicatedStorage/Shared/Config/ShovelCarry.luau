--!strict
-- All new shovel models inherit these defaults. Model local +Y points to grip.
local Carry = {
 Version = "DiagonalCarryV4",
 Height = 5.4,
 IdleGrip = CFrame.identity,
 SwingGrip = CFrame.new(0, -0.25, -0.35) * CFrame.Angles(math.rad(-45), 0, math.rad(12)),
 -- Reference pose: grip by the right shoulder, blade down across the body.
 Held = CFrame.new(-0.36, -0.4, -0.85) * CFrame.Angles(0, 0, math.rad(-52)),
 Stowed = CFrame.new(0, -0.05, 0.8) * CFrame.Angles(0, math.pi, math.rad(38)),
 BlendSpeed = 14,
 -- Keep the same shaft contact points, mirrored between the hands.
 RightHandY = 1.6,
 LeftHandY = -0.55,
}

-- Lower the whole shovel until the upper contact point meets the shoulder.
-- R15 and R6 use the same pose and hand targets, with their own shoulder height.
function Carry.GetHeldCFrame(torso: BasePart): CFrame
 local attachment = torso:FindFirstChild("RightShoulderRigAttachment")
 local joint = torso:FindFirstChild("Right Shoulder")
 local shoulderY = if attachment and attachment:IsA("Attachment") then attachment.Position.Y
  elseif joint and joint:IsA("Motor6D") then joint.C0.Position.Y
  else torso.Size.Y * 0.3
 local handY = Carry.Held:PointToWorldSpace(Vector3.new(0, Carry.RightHandY, 0)).Y
 return Carry.Held + Vector3.new(0, shoulderY - handY, 0)
end

return table.freeze(Carry)
