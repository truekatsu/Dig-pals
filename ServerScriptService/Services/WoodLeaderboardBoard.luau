--!strict
-- Physical presentation only: no prompts, remotes, or persistence side effects.
local Board = {}
local dark = Color3.fromRGB(65, 40, 25)
local cream = Color3.fromRGB(255, 240, 198)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame = name, size, cf
	p.Color, p.Material = color, material or Enum.Material.Wood
	p.Anchored, p.CanCollide = true, true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function text(parent: Instance, name: string, value: string, pos: UDim2, size: UDim2, fontSize: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Position, t.Size = name, value, pos, size
	t.BackgroundTransparency = 1
	t.Font, t.TextSize, t.TextColor3 = Enum.Font.FredokaOne, fontSize, color
	t.Parent = parent
	return t
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

function Board.Build(parent: Instance, name: string, cf: CFrame, title: string, category: string, limit: number): SurfaceGui
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("LeaderboardCategory", category)
	model:SetAttribute("BoardStyle", "Woodland")
	for _, side in { -1, 1 } do
		local post = part(model, "LogPost", Vector3.new(13.6, 1.1, 1.1), cf * CFrame.new(side * 4.95, 6.8, .15) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(98, 64, 38))
		post.Shape = Enum.PartType.Cylinder
		local cut = part(model, "LogEnd", Vector3.new(.08, 1.02, 1.02), cf * CFrame.new(side * 4.95, 13.64, .15) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(186, 143, 85))
		cut.Shape = Enum.PartType.Cylinder
		part(model, "TimberFoot", Vector3.new(1.65, .35, 2.4), cf * CFrame.new(side * 4.95, .18, .2), Color3.fromRGB(93, 58, 34))
	end
	local stand = part(model, "BoardStand", Vector3.new(8.6, 11, .5), cf * CFrame.new(0, 6.25, 0), Color3.fromRGB(144, 101, 60), Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		part(model, "SideFrame", Vector3.new(.32, 11.3, .7), cf * CFrame.new(side * 4.38, 6.25, -.12), dark)
		part(model, "CrossRail", Vector3.new(9.15, .35, .75), cf * CFrame.new(0, 6.25 + side * 5.62, -.12), Color3.fromRGB(103, 65, 36))
	end
	local banner = part(model, "BannerFront", Vector3.new(10.25, 1.45, .7), cf * CFrame.new(0, 12.72, -.13) * CFrame.Angles(0, 0, math.rad(-1.2)), Color3.fromRGB(120, 77, 42), Enum.Material.WoodPlanks)
	for _, x in { -4.65, 4.65 } do
		local peg = part(model, "WoodenPeg", Vector3.new(.15, .15, .12), banner.CFrame * CFrame.new(x, 0, -.4), Color3.fromRGB(60, 39, 26))
		peg.Shape = Enum.PartType.Ball
	end
	local heading = Instance.new("SurfaceGui")
	heading.Name, heading.Face = "BannerGui", Enum.NormalId.Front
	heading.CanvasSize, heading.LightInfluence = Vector2.new(1025, 145), .1
	heading.Parent = banner
	local headingText = text(heading, "BoardTitle", title, UDim2.new(), UDim2.fromScale(1, 1), 46, cream)
	headingText.TextStrokeColor3, headingText.TextStrokeTransparency = dark, .15
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face = "LeaderboardDisplay", Enum.NormalId.Front
	gui.CanvasSize, gui.LightInfluence = Vector2.new(860, 1140), .1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.Parent = stand
	local bg = Instance.new("Frame")
	bg.Name, bg.Position, bg.Size = "BackgroundFrame", UDim2.fromOffset(14, 14), UDim2.new(1, -28, 1, -28)
	bg.BackgroundColor3, bg.BackgroundTransparency, bg.BorderSizePixel = Color3.fromRGB(232, 209, 160), .04, 0
	bg.Parent = gui
	corner(bg, 8)
	local columns = text(bg, "Columns", "RANK       PEMAIN", UDim2.fromOffset(18, 15), UDim2.new(1, -250, 0, 48), 25, dark)
	columns.TextXAlignment = Enum.TextXAlignment.Left
	local scoreColumn = text(bg, "ScoreColumn", if category == "CurrentCoins" then "SALDO" else "TOTAL WAKTU", UDim2.new(1, -230, 0, 15), UDim2.fromOffset(210, 48), 24, dark)
	scoreColumn.TextXAlignment = Enum.TextXAlignment.Right
	local rows = Instance.new("Frame")
	rows.Name, rows.Position, rows.Size = "RowsContainer", UDim2.fromOffset(14, 80), UDim2.new(1, -28, 1, -142)
	rows.BackgroundTransparency = 1
	rows.Parent = bg
	local layout = Instance.new("UIListLayout")
	layout.Padding, layout.SortOrder = UDim.new(0, 8), Enum.SortOrder.LayoutOrder
	layout.Parent = rows
	for rank = 1, limit do
		local row = Instance.new("Frame")
		row.Name, row.Size, row.LayoutOrder = "Row_" .. rank, UDim2.new(1, 0, 0, 88), rank
		row.BackgroundColor3 = if rank <= 3 then Color3.fromRGB(255, 236, 183) elseif rank % 2 == 0 then Color3.fromRGB(208, 179, 128) else Color3.fromRGB(221, 195, 147)
		row.BorderSizePixel = 0
		row.Parent = rows
		corner(row, 6)
		local rankText = text(row, "RankLabel", tostring(rank), UDim2.fromOffset(12, 0), UDim2.fromOffset(48, 88), 32, if rank == 1 then Color3.fromRGB(157, 101, 25) else dark)
		local avatar = Instance.new("ImageLabel")
		avatar.Name, avatar.Position, avatar.Size = "AvatarImage", UDim2.fromOffset(65, 13), UDim2.fromOffset(62, 62)
		avatar.BackgroundColor3, avatar.BorderSizePixel = Color3.fromRGB(183, 151, 100), 0
		avatar.Image = ""
		avatar.Visible = false
		avatar.Parent = row
		corner(avatar, 8)
		local username = text(row, "PlayerName", "---", UDim2.fromOffset(144, 0), UDim2.new(1, -360, 1, 0), 26, dark)
		username.TextXAlignment, username.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd
		local score = text(row, "ScoreLabel", "---", UDim2.new(1, -202, 0, 0), UDim2.fromOffset(188, 88), 27, if category == "CurrentCoins" then Color3.fromRGB(48, 111, 43) else Color3.fromRGB(110, 77, 40))
		score.TextXAlignment = Enum.TextXAlignment.Right
	end
	model.Parent = parent
	return gui
end

return Board
