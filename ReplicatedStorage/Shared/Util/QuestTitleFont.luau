--!strict
-- Super Waffles by fsuarez913. Rendered atlas licensed free for commercial use.
-- Source and font license: Assets/Fonts/SuperWaffles/FONT-LICENSE.txt.
local ContentProvider = game:GetService("ContentProvider")
local FontAtlas = {}
local IMAGE = "rbxassetid://83862457630007"
local SOURCE_SIZE = 64
type Glyph = {Advance: number, Rect: Vector2?, Size: Vector2?, Offset: Vector2?}
local GLYPHS: {[string]: Glyph} = {
	["0"] = {Advance = 37.375, Rect = Vector2.new(618, 114), Size = Vector2.new(41, 51), Offset = Vector2.new(-2, 12)},
	["1"] = {Advance = 25.75, Rect = Vector2.new(720, 114), Size = Vector2.new(30, 52), Offset = Vector2.new(-2, 12)},
	["2"] = {Advance = 37.656, Rect = Vector2.new(822, 114), Size = Vector2.new(42, 52), Offset = Vector2.new(-2, 12)},
	["3"] = {Advance = 34.688, Rect = Vector2.new(924, 114), Size = Vector2.new(39, 51), Offset = Vector2.new(-2, 12)},
	["4"] = {Advance = 38.188, Rect = Vector2.new(6, 216), Size = Vector2.new(42, 52), Offset = Vector2.new(-2, 12)},
	["5"] = {Advance = 35.094, Rect = Vector2.new(108, 216), Size = Vector2.new(39, 51), Offset = Vector2.new(-2, 12)},
	["6"] = {Advance = 35.25, Rect = Vector2.new(210, 215), Size = Vector2.new(39, 52), Offset = Vector2.new(-2, 11)},
	["7"] = {Advance = 36.219, Rect = Vector2.new(312, 216), Size = Vector2.new(40, 52), Offset = Vector2.new(-2, 12)},
	["8"] = {Advance = 36.75, Rect = Vector2.new(414, 216), Size = Vector2.new(41, 52), Offset = Vector2.new(-2, 12)},
	["9"] = {Advance = 35.25, Rect = Vector2.new(516, 215), Size = Vector2.new(39, 52), Offset = Vector2.new(-2, 11)},
	[" "] = {Advance = 15.875},
	["!"] = {Advance = 19.719, Rect = Vector2.new(108, 11), Size = Vector2.new(24, 52), Offset = Vector2.new(-2, 11)},
	["\""] = {Advance = 22.625, Rect = Vector2.new(210, 12), Size = Vector2.new(27, 25), Offset = Vector2.new(-2, 12)},
	["#"] = {Advance = 48.062, Rect = Vector2.new(312, 12), Size = Vector2.new(52, 51), Offset = Vector2.new(-2, 12)},
	["$"] = {Advance = 33.969, Rect = Vector2.new(414, 7), Size = Vector2.new(38, 62), Offset = Vector2.new(-2, 7)},
	["%"] = {Advance = 49, Rect = Vector2.new(516, 12), Size = Vector2.new(53, 51), Offset = Vector2.new(-2, 12)},
	["&"] = {Advance = 44.781, Rect = Vector2.new(618, 12), Size = Vector2.new(49, 52), Offset = Vector2.new(-2, 12)},
	["'"] = {Advance = 12.281, Rect = Vector2.new(720, 12), Size = Vector2.new(16, 25), Offset = Vector2.new(-2, 12)},
	["("] = {Advance = 25.562, Rect = Vector2.new(822, 7), Size = Vector2.new(30, 61), Offset = Vector2.new(-2, 7)},
	[")"] = {Advance = 25.562, Rect = Vector2.new(924, 7), Size = Vector2.new(29, 61), Offset = Vector2.new(-2, 7)},
	["*"] = {Advance = 23.656, Rect = Vector2.new(6, 114), Size = Vector2.new(28, 27), Offset = Vector2.new(-2, 12)},
	["+"] = {Advance = 33.844, Rect = Vector2.new(108, 121), Size = Vector2.new(38, 37), Offset = Vector2.new(-2, 19)},
	[","] = {Advance = 16.375, Rect = Vector2.new(210, 147), Size = Vector2.new(20, 28), Offset = Vector2.new(-2, 45)},
	["-"] = {Advance = 33.844, Rect = Vector2.new(312, 136), Size = Vector2.new(38, 17), Offset = Vector2.new(-2, 34)},
	["."] = {Advance = 15.594, Rect = Vector2.new(414, 147), Size = Vector2.new(20, 18), Offset = Vector2.new(-2, 45)},
	["/"] = {Advance = 28.688, Rect = Vector2.new(516, 114), Size = Vector2.new(33, 51), Offset = Vector2.new(-2, 12)},
	[":"] = {Advance = 18.719, Rect = Vector2.new(620, 227), Size = Vector2.new(19, 40), Offset = Vector2.new(0, 23)},
	[";"] = {Advance = 19.5, Rect = Vector2.new(722, 227), Size = Vector2.new(20, 50), Offset = Vector2.new(0, 23)},
	["<"] = {Advance = 33.062, Rect = Vector2.new(822, 227), Size = Vector2.new(37, 30), Offset = Vector2.new(-2, 23)},
	["="] = {Advance = 33.844, Rect = Vector2.new(924, 227), Size = Vector2.new(38, 29), Offset = Vector2.new(-2, 23)},
	[">"] = {Advance = 33.062, Rect = Vector2.new(6, 329), Size = Vector2.new(37, 30), Offset = Vector2.new(-2, 23)},
	["?"] = {Advance = 31.312, Rect = Vector2.new(108, 318), Size = Vector2.new(35, 51), Offset = Vector2.new(-2, 12)},
	["@"] = {Advance = 51.5, Rect = Vector2.new(210, 322), Size = Vector2.new(55, 54), Offset = Vector2.new(-2, 16)},
	["A"] = {Advance = 32.969, Rect = Vector2.new(311, 318), Size = Vector2.new(37, 52), Offset = Vector2.new(-3, 12)},
	["B"] = {Advance = 31.406, Rect = Vector2.new(414, 318), Size = Vector2.new(36, 51), Offset = Vector2.new(-2, 12)},
	["C"] = {Advance = 30.75, Rect = Vector2.new(516, 318), Size = Vector2.new(35, 51), Offset = Vector2.new(-2, 12)},
	["D"] = {Advance = 33.969, Rect = Vector2.new(619, 318), Size = Vector2.new(37, 51), Offset = Vector2.new(-1, 12)},
	["E"] = {Advance = 29, Rect = Vector2.new(720, 318), Size = Vector2.new(34, 51), Offset = Vector2.new(-2, 12)},
	["F"] = {Advance = 27.438, Rect = Vector2.new(823, 318), Size = Vector2.new(33, 52), Offset = Vector2.new(-1, 12)},
	["G"] = {Advance = 35.562, Rect = Vector2.new(924, 318), Size = Vector2.new(40, 51), Offset = Vector2.new(-2, 12)},
	["H"] = {Advance = 36.562, Rect = Vector2.new(6, 420), Size = Vector2.new(41, 52), Offset = Vector2.new(-2, 12)},
	["I"] = {Advance = 18.562, Rect = Vector2.new(109, 420), Size = Vector2.new(21, 52), Offset = Vector2.new(-1, 12)},
	["J"] = {Advance = 29.75, Rect = Vector2.new(209, 420), Size = Vector2.new(35, 51), Offset = Vector2.new(-3, 12)},
	["K"] = {Advance = 36.812, Rect = Vector2.new(312, 420), Size = Vector2.new(42, 52), Offset = Vector2.new(-2, 12)},
	["L"] = {Advance = 30.656, Rect = Vector2.new(414, 419), Size = Vector2.new(36, 53), Offset = Vector2.new(-2, 11)},
	["M"] = {Advance = 47.281, Rect = Vector2.new(516, 420), Size = Vector2.new(51, 51), Offset = Vector2.new(-2, 12)},
	["N"] = {Advance = 42.219, Rect = Vector2.new(618, 420), Size = Vector2.new(47, 52), Offset = Vector2.new(-2, 12)},
	["O"] = {Advance = 42.531, Rect = Vector2.new(719, 420), Size = Vector2.new(48, 52), Offset = Vector2.new(-3, 12)},
	["P"] = {Advance = 35.469, Rect = Vector2.new(822, 420), Size = Vector2.new(41, 52), Offset = Vector2.new(-2, 12)},
	["Q"] = {Advance = 41.125, Rect = Vector2.new(923, 420), Size = Vector2.new(47, 53), Offset = Vector2.new(-3, 12)},
	["R"] = {Advance = 37.812, Rect = Vector2.new(6, 522), Size = Vector2.new(43, 52), Offset = Vector2.new(-2, 12)},
	["S"] = {Advance = 34.969, Rect = Vector2.new(108, 521), Size = Vector2.new(39, 54), Offset = Vector2.new(-2, 11)},
	["T"] = {Advance = 31.656, Rect = Vector2.new(208, 521), Size = Vector2.new(42, 53), Offset = Vector2.new(-4, 11)},
	["U"] = {Advance = 37.781, Rect = Vector2.new(312, 522), Size = Vector2.new(42, 52), Offset = Vector2.new(-2, 12)},
	["V"] = {Advance = 36.688, Rect = Vector2.new(414, 521), Size = Vector2.new(42, 53), Offset = Vector2.new(-2, 11)},
	["W"] = {Advance = 52.875, Rect = Vector2.new(516, 522), Size = Vector2.new(57, 52), Offset = Vector2.new(-2, 12)},
	["X"] = {Advance = 41.094, Rect = Vector2.new(618, 521), Size = Vector2.new(47, 53), Offset = Vector2.new(-2, 11)},
	["Y"] = {Advance = 34.781, Rect = Vector2.new(719, 521), Size = Vector2.new(43, 54), Offset = Vector2.new(-3, 11)},
	["Z"] = {Advance = 37.188, Rect = Vector2.new(821, 521), Size = Vector2.new(43, 53), Offset = Vector2.new(-3, 11)},
	["["] = {Advance = 28.438, Rect = Vector2.new(924, 517), Size = Vector2.new(32, 62), Offset = Vector2.new(-2, 7)},
	["\\"] = {Advance = 28.688, Rect = Vector2.new(6, 624), Size = Vector2.new(33, 51), Offset = Vector2.new(-2, 12)},
	["]"] = {Advance = 28.438, Rect = Vector2.new(108, 619), Size = Vector2.new(32, 62), Offset = Vector2.new(-2, 7)},
	["^"] = {Advance = 23.281, Rect = Vector2.new(210, 623), Size = Vector2.new(27, 29), Offset = Vector2.new(-2, 11)},
	["_"] = {Advance = 30.406, Rect = Vector2.new(312, 668), Size = Vector2.new(34, 15), Offset = Vector2.new(-2, 56)},
	["`"] = {Advance = 16.688, Rect = Vector2.new(414, 618), Size = Vector2.new(21, 20), Offset = Vector2.new(-2, 6)},
	["a"] = {Advance = 35.906, Rect = Vector2.new(516, 634), Size = Vector2.new(40, 42), Offset = Vector2.new(-2, 22)},
	["b"] = {Advance = 37.594, Rect = Vector2.new(618, 624), Size = Vector2.new(42, 52), Offset = Vector2.new(-2, 12)},
	["c"] = {Advance = 33.125, Rect = Vector2.new(720, 634), Size = Vector2.new(38, 42), Offset = Vector2.new(-2, 22)},
	["d"] = {Advance = 38.188, Rect = Vector2.new(822, 624), Size = Vector2.new(42, 51), Offset = Vector2.new(-2, 12)},
	["e"] = {Advance = 34.312, Rect = Vector2.new(924, 634), Size = Vector2.new(39, 42), Offset = Vector2.new(-2, 22)},
	["f"] = {Advance = 25.406, Rect = Vector2.new(5, 725), Size = Vector2.new(36, 53), Offset = Vector2.new(-3, 11)},
	["g"] = {Advance = 39.062, Rect = Vector2.new(107, 736), Size = Vector2.new(44, 55), Offset = Vector2.new(-3, 22)},
	["h"] = {Advance = 37.719, Rect = Vector2.new(210, 726), Size = Vector2.new(42, 52), Offset = Vector2.new(-2, 12)},
	["i"] = {Advance = 20.094, Rect = Vector2.new(312, 725), Size = Vector2.new(24, 52), Offset = Vector2.new(-2, 11)},
	["j"] = {Advance = 20.969, Rect = Vector2.new(405, 725), Size = Vector2.new(34, 67), Offset = Vector2.new(-11, 11)},
	["k"] = {Advance = 35.812, Rect = Vector2.new(516, 726), Size = Vector2.new(41, 51), Offset = Vector2.new(-2, 12)},
	["l"] = {Advance = 17.625, Rect = Vector2.new(619, 725), Size = Vector2.new(22, 53), Offset = Vector2.new(-1, 11)},
	["m"] = {Advance = 54.969, Rect = Vector2.new(720, 736), Size = Vector2.new(59, 41), Offset = Vector2.new(-2, 22)},
	["n"] = {Advance = 40.062, Rect = Vector2.new(822, 736), Size = Vector2.new(44, 41), Offset = Vector2.new(-2, 22)},
	["o"] = {Advance = 35.969, Rect = Vector2.new(924, 736), Size = Vector2.new(40, 42), Offset = Vector2.new(-2, 22)},
	["p"] = {Advance = 38.656, Rect = Vector2.new(6, 838), Size = Vector2.new(43, 54), Offset = Vector2.new(-2, 22)},
	["q"] = {Advance = 37.562, Rect = Vector2.new(107, 838), Size = Vector2.new(42, 54), Offset = Vector2.new(-3, 22)},
	["r"] = {Advance = 36.594, Rect = Vector2.new(210, 838), Size = Vector2.new(42, 41), Offset = Vector2.new(-2, 22)},
	["s"] = {Advance = 34.75, Rect = Vector2.new(311, 837), Size = Vector2.new(41, 43), Offset = Vector2.new(-3, 21)},
	["t"] = {Advance = 28.281, Rect = Vector2.new(412, 830), Size = Vector2.new(36, 49), Offset = Vector2.new(-4, 14)},
	["u"] = {Advance = 39.281, Rect = Vector2.new(516, 839), Size = Vector2.new(43, 40), Offset = Vector2.new(-2, 23)},
	["v"] = {Advance = 38.625, Rect = Vector2.new(618, 838), Size = Vector2.new(44, 41), Offset = Vector2.new(-2, 22)},
	["w"] = {Advance = 52.281, Rect = Vector2.new(720, 838), Size = Vector2.new(56, 41), Offset = Vector2.new(-2, 22)},
	["x"] = {Advance = 38, Rect = Vector2.new(821, 838), Size = Vector2.new(45, 42), Offset = Vector2.new(-3, 22)},
	["y"] = {Advance = 38.062, Rect = Vector2.new(924, 839), Size = Vector2.new(42, 56), Offset = Vector2.new(-2, 23)},
	["z"] = {Advance = 36.312, Rect = Vector2.new(5, 940), Size = Vector2.new(44, 42), Offset = Vector2.new(-3, 22)},
	["{"] = {Advance = 34.812, Rect = Vector2.new(108, 925), Size = Vector2.new(39, 62), Offset = Vector2.new(-2, 7)},
	["|"] = {Advance = 39.75, Rect = Vector2.new(223, 925), Size = Vector2.new(18, 61), Offset = Vector2.new(11, 7)},
	["}"] = {Advance = 34.812, Rect = Vector2.new(312, 925), Size = Vector2.new(39, 62), Offset = Vector2.new(-2, 7)},
	["~"] = {Advance = 31.875, Rect = Vector2.new(414, 946), Size = Vector2.new(36, 19), Offset = Vector2.new(-2, 28)},
	["·"] = {Advance = 13.719, Rect = Vector2.new(516, 947), Size = Vector2.new(18, 17), Offset = Vector2.new(-2, 29)},
	["…"] = {Advance = 58.281, Rect = Vector2.new(618, 963), Size = Vector2.new(62, 18), Offset = Vector2.new(-2, 45)},
}
local ready = false
local pending: {[TextLabel]: () -> ()} = {}

function FontAtlas.Apply(label: TextLabel, pixelSize: number?)
	local layer = Instance.new("Frame")
	layer.Name = "SuperWafflesText"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ClipsDescendants = true
	layer.ZIndex = label.ZIndex
	layer.Parent = label
	local nativeTransparency, nativeStroke = label.TextTransparency, label.TextStrokeTransparency
	local function render()
		if not label.Parent then return end
		if not ready then return end
		local glyphs: {Glyph} = {}
		local top, bottom = math.huge, -math.huge
		for _, codepoint in utf8.codes(label.Text) do
			local glyph = GLYPHS[utf8.char(codepoint)]
			if not glyph then
				layer.Visible = false
				label.TextTransparency, label.TextStrokeTransparency = nativeTransparency, nativeStroke
				label:SetAttribute("SuperWafflesReady", false)
				return
			end
			table.insert(glyphs, glyph)
			if glyph.Offset and glyph.Size then
				top = math.min(top, glyph.Offset.Y)
				bottom = math.max(bottom, glyph.Offset.Y + glyph.Size.Y)
			end
		end
		layer:ClearAllChildren()
		if top == math.huge then top, bottom = 0, SOURCE_SIZE end
		local height = math.max(1, bottom - top)
		local scale = math.min((pixelSize or label.TextSize) / SOURCE_SIZE, label.AbsoluteSize.Y / height)
		if scale <= 0 then return end
		local width = math.max(0, label.AbsoluteSize.X - 2)
		local totalWidth = 0
		for _, glyph in glyphs do totalWidth += glyph.Advance * scale end
		local ellipsis = GLYPHS["…"]
		local truncated = totalWidth > width
		local limit = width - (if truncated then ellipsis.Advance * scale else 0)
		local cursor = 2
		local y = (label.AbsoluteSize.Y - height * scale) * 0.5 - top * scale
		local function draw(glyph: Glyph)
			if glyph.Rect and glyph.Size and glyph.Offset then
				local image = Instance.new("ImageLabel")
				image.Name = "Glyph"
				image.BackgroundTransparency = 1
				image.Image = IMAGE
				image.ImageRectOffset = glyph.Rect
				image.ImageRectSize = glyph.Size
				image.ImageColor3 = label.TextColor3
				image.ImageTransparency = nativeTransparency
				image.Position = UDim2.fromOffset(cursor + glyph.Offset.X * scale, y + glyph.Offset.Y * scale)
				image.Size = UDim2.fromOffset(glyph.Size.X * scale, glyph.Size.Y * scale)
				image.ZIndex = label.ZIndex
				image.Parent = layer
			end
			cursor += glyph.Advance * scale
		end
		for _, glyph in glyphs do
			if truncated and cursor + glyph.Advance * scale > limit then draw(ellipsis); break end
			draw(glyph)
		end
		layer.Visible = true
		label.TextTransparency, label.TextStrokeTransparency = 1, 1
		label:SetAttribute("SuperWafflesReady", true)
	end
	label:GetPropertyChangedSignal("Text"):Connect(render)
	label:GetPropertyChangedSignal("TextColor3"):Connect(render)
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(render)
	label.Destroying:Connect(function() pending[label] = nil end)
	if ready then render() else pending[label] = render end
end

task.spawn(function()
	local success = false
	local preloadImage = Instance.new("ImageLabel")
	preloadImage.Image = IMAGE
	local ok = pcall(function()
		ContentProvider:PreloadAsync({preloadImage}, function(_, status)
			if status == Enum.AssetFetchStatus.Success then success = true end
		end)
	end)
	preloadImage:Destroy()
	ready = ok and success
	if ready then
		for label, render in pending do if label.Parent then render() end end
	end
	table.clear(pending)
end)

return FontAtlas
