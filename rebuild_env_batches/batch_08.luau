local MATS = {
{Color3.fromRGB(248,246,241),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(69,215,242),Enum.Material.Neon,0.0,0.0},
{Color3.fromRGB(39,217,154),Enum.Material.Neon,0.0,0.0},
{Color3.fromRGB(255,234,118),Enum.Material.Neon,0.0,0.0},
{Color3.fromRGB(191,162,124),Enum.Material.Ground,0.0,0.0},
{Color3.fromRGB(248,111,129),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(124,197,134),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(105,177,111),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(144,215,153),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(231,184,76),Enum.Material.Metal,0.0,0.15},
{Color3.fromRGB(153,211,124),Enum.Material.LeafyGrass,0.0,0.0},
{Color3.fromRGB(162,221,134),Enum.Material.LeafyGrass,0.0,0.0},
{Color3.fromRGB(255,243,170),Enum.Material.Neon,0.0,0.0},
{Color3.fromRGB(218,221,225),Enum.Material.Metal,0.0,0.2},
{Color3.fromRGB(241,105,111),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(249,249,246),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(118,179,234),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(236,134,118),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(239,226,188),Enum.Material.Sand,0.0,0.0},
{Color3.fromRGB(231,231,231),Enum.Material.WoodPlanks,0.0,0.0},
{Color3.fromRGB(140,138,131),Enum.Material.Slate,0.0,0.0},
{Color3.fromRGB(94,98,95),Enum.Material.SmoothPlastic,0.0,0.0},
{Color3.fromRGB(206,203,197),Enum.Material.Cobblestone,0.0,0.0},
{Color3.fromRGB(218,215,209),Enum.Material.Cobblestone,0.0,0.0},
{Color3.fromRGB(61,171,176),Enum.Material.Glass,0.12,0.25},
{Color3.fromRGB(173,137,97),Enum.Material.WoodPlanks,0.0,0.0},
{Color3.fromRGB(139,108,80),Enum.Material.Wood,0.0,0.0},
{Color3.fromRGB(215,184,149),Enum.Material.WoodPlanks,0.0,0.0}
}
local env = workspace.Plain:FindFirstChild("Environment")
if not env then
    env = Instance.new("Folder")
    env.Name = "Environment"
    env.Parent = workspace.Plain
end


local container = Instance.new("Model")
local RAW = [=[
0;10;7;0;0;;145;1.23;-70;-0.866;0;-0.5;0;-1;0;2.74;2.46;4.74
0;10;7;0;0;;145;1.23;-70;-0.866;0;0.5;0;-1;0;2.74;2.46;4.74
0;10;7;0;0;;145;1.23;-70;0;0;1;0;-1;0;2.74;2.46;4.74
]=]
local lines = string.split(RAW, "\n")
local count = 0
for idx, line in ipairs(lines) do
    if #line > 0 then
        local t = string.split(line, ";")
        local cls = tonumber(t[1])
        local mIdx = tonumber(t[3])
        local col = (t[4] == "1")
        local nm = t[6]
        local px, py, pz = tonumber(t[7]), tonumber(t[8]), tonumber(t[9])
        local xx, xy, xz = tonumber(t[10]), tonumber(t[11]), tonumber(t[12])
        local yx, yy, yz = tonumber(t[13]), tonumber(t[14]), tonumber(t[15])
        local sx, sy, sz = tonumber(t[16]), tonumber(t[17]), tonumber(t[18])
        local vX = Vector3.new(xx, xy, xz)
        local vY = Vector3.new(yx, yy, yz)
        local vZ = vX:Cross(vY)
        local inst = Instance.new(cls == 1 and "WedgePart" or "Part")
        if nm ~= "" then inst.Name = nm else inst.Name = (cls == 1 and "Wedge" or "Part") end
        inst.Anchored = true
        inst.CanCollide = col
        inst.CanQuery = col
        inst.TopSurface = Enum.SurfaceType.Smooth
        inst.BottomSurface = Enum.SurfaceType.Smooth
        local m = MATS[mIdx]
        inst.Color = m[1]
        inst.Material = m[2]
        inst.Transparency = m[3]
        inst.Reflectance = m[4]
        inst.Size = Vector3.new(sx, sy, sz)
        inst.CFrame = CFrame.fromMatrix(Vector3.new(px, py, pz), vX, vY, vZ)
        inst.Parent = container
        count += 1
    end
end
for _, ch in ipairs(container:GetChildren()) do
    ch.Parent = env
end
container:Destroy()
return {chunk = 8, built = count, envTotal = #env:GetChildren()}
