--!strict
-- All new shovel models inherit these defaults. Model local +Y points to grip.
return table.freeze({
 Version = "DiagonalCarryV1",
 Height = 5.4,
 IdleGrip = CFrame.identity,
 SwingGrip = CFrame.new(0, -0.25, -0.35) * CFrame.Angles(math.rad(-45), 0, math.rad(12)),
 Held = CFrame.new(0.15, 0.35, -1.05) * CFrame.Angles(0, 0, math.rad(-48)),
 Stowed = CFrame.new(0, -0.05, 0.8) * CFrame.Angles(0, math.pi, math.rad(38)),
 BlendSpeed = 14,
 RightHandY = 0.65,
 LeftHandY = -0.7,
})
