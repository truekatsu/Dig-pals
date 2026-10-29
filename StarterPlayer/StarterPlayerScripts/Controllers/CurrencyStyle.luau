--!strict
local CurrencyStyle = {}
CurrencyStyle.Green = Color3.fromRGB(115, 239, 0)

function CurrencyStyle.Apply(label: TextLabel, transparent: boolean?)
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
	label.TextColor3 = CurrencyStyle.Green
	label.TextStrokeTransparency = 1
	if transparent then label.BackgroundTransparency = 1 end
	if not label:FindFirstChild("CurrencyOutline") then
		local outline = Instance.new("UIStroke")
		outline.Name = "CurrencyOutline"
		outline.Color = Color3.fromRGB(9, 22, 7)
		outline.Thickness = 1.5
		outline.LineJoinMode = Enum.LineJoinMode.Round
		outline.Parent = label
	end
end

function CurrencyStyle.Balance(label: TextLabel)
	CurrencyStyle.Apply(label, true)
	label.TextScaled = true
	local size = Instance.new("UITextSizeConstraint")
	size.MinTextSize = 10
	size.MaxTextSize = 18
	size.Parent = label
end

return table.freeze(CurrencyStyle)
