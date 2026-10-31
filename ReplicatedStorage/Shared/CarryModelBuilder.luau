--!nonstrict
-- Shared display geometry for hotbar previews, equipped loot, pets and placed eggs.
local RS = game:GetService("ReplicatedStorage")
local ItemsConfig = require(RS.Shared.Config.Items)
local Items = ItemsConfig.All
local Eggs = require(RS.Shared.Config.Eggs).All
local Pets = require(RS.Shared.Config.Pets).Species
local Builder = {}
local colors = {Common=Color3.fromRGB(155,139,114),Uncommon=Color3.fromRGB(88,183,126),Rare=Color3.fromRGB(75,154,216),Epic=Color3.fromRGB(174,107,216),Legendary=Color3.fromRGB(255,199,66)}

function Builder.Display(kind, id, variant, weight)
	local cfg = (kind == "Eggs" and Eggs or kind == "Pet" and Pets or Items)[id] or {}
	local model = Instance.new("Model")
	model.Name = id
	local color = colors[cfg.Rarity] or colors.Common
	local function part(name, size, pos, shade, shape, material)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame = name, size, CFrame.new(pos)
		p.Color, p.Material = shade or color, material or Enum.Material.SmoothPlastic
		p.Shape = shape or Enum.PartType.Block
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = true, false, false, false, true
		p.Parent = model
		return p
	end
	if kind == "Eggs" then
		local assets = RS:FindFirstChild("EggAssets")
		local templates = assets and assets:FindFirstChild("EggModels")
		local template = templates and templates:FindFirstChild((cfg.Rarity or "Common") .. "Egg")
		if template and template:IsA("Model") then
			model:Destroy() model = template:Clone()
			if cfg.Rarity == "Uncommon" then model:PivotTo(model:GetPivot() * CFrame.Angles(math.pi/2,0,0)) end
		else
			part("Shell", Vector3.new(1.4,1.9,1.4), Vector3.zero, Color3.fromRGB(255,237,192), Enum.PartType.Ball)
			for i=1,5 do local a=i*math.pi*2/5 part("Spot",Vector3.new(.35,.4,.16),Vector3.new(math.sin(a)*.61,math.cos(a)*.5,-.56),color,Enum.PartType.Ball) end
		end
	elseif kind == "Pet" then
		color = if variant == "Golden" then colors.Legendary elseif variant == "Shiny" then colors.Epic else color
		part("Body",Vector3.new(1.4,1.1,1.5),Vector3.new(0,0,.1),color)
		part("Head",Vector3.new(1.45,1.15,1.15),Vector3.new(0,.5,-.6),color)
		for _,x in {-.5,.5} do
			part("Ear",Vector3.new(.35,id:lower():find("bunny") and .9 or .5,.35),Vector3.new(x,1.25,-.55),color)
			part("Eye",Vector3.new(.16,.2,.1),Vector3.new(x*.7,.65,-1.2),Color3.fromRGB(22,33,42))
			part("Paw",Vector3.new(.4,.3,.5),Vector3.new(x,-.6,-.35),color)
		end
		part("Nose",Vector3.new(.18,.14,.12),Vector3.new(0,.35,-1.22),Color3.fromRGB(63,43,42))
		part("Tail",Vector3.new(.35,.4,.85),Vector3.new(0,.1,1.05),color)
	else
		local lower=id:lower()
		if lower:find("coin") or lower:find("cap") then
			part("Coin",Vector3.new(.16,1.1,1.1),Vector3.zero,Color3.fromRGB(199,151,65),Enum.PartType.Cylinder,Enum.Material.Metal)
		elseif lower:find("nail") or lower:find("root") then
			part("Stem",Vector3.new(.17,1.5,.17),Vector3.zero,Color3.fromRGB(118,76,48),Enum.PartType.Cylinder,Enum.Material.Wood)
			part("Tip",Vector3.new(.55,.12,.3),Vector3.new(0,.7,0),Color3.fromRGB(114,89,65))
		else
			local p=part("Find",Vector3.new(1.05,.85,.95),Vector3.zero,color,Enum.PartType.Ball,Enum.Material.Slate)
			if lower:find("shard") or lower:find("gem") or lower:find("crystal") then p.Shape=Enum.PartType.Block p.Material=Enum.Material.Glass p.CFrame=CFrame.Angles(0,.4,.55) end
		end
	end
	for _,v in model:GetDescendants() do
		if v:IsA("LuaSourceContainer") or v:IsA("JointInstance") or v:IsA("WeldConstraint") or v:IsA("ProximityPrompt") then v:Destroy()
		elseif v:IsA("BasePart") then v.Anchored=true v.CanCollide=false v.CanTouch=false v.CanQuery=false v.Massless=true end
	end
	local size=model:GetExtentsSize()
	model:ScaleTo(model:GetScale() * 2 / math.max(size.X,size.Y,size.Z))
	if kind == "Items" then model:ScaleTo(model:GetScale() * ItemsConfig.GetModelScale(id, weight)) end
	local box=model:GetBoundingBox()
	for _,p in model:GetDescendants() do if p:IsA("BasePart") then p.CFrame=CFrame.new(-box.Position)*p.CFrame end end
	model.WorldPivot=CFrame.identity
	return model
end

function Builder.Tool(entry)
	local tool=Instance.new("Tool")
	tool.Name=entry.Name or entry.Id
	tool.CanBeDropped=false
	tool:SetAttribute("DigPalsCarryTool",true)
	tool:SetAttribute("CarryKind",entry.Kind)
	tool:SetAttribute("CarryKey",entry.Key)
	tool:SetAttribute("CarrySlot",entry.Slot)
	if entry.Kind=="Items" then
		tool:SetAttribute("DigPalsLootTool",true) tool:SetAttribute("ItemId",entry.Id)
		tool:SetAttribute("ItemWeight",entry.Weight) tool:SetAttribute("ItemSellPrice",entry.SellPrice)
		tool:SetAttribute("ItemModelScale",entry.ModelScale)
	end
	local handle=Instance.new("Part")
	handle.Name="Handle" handle.Size=Vector3.new(.2,.2,.2) handle.Transparency=1
	handle.CanCollide=false handle.CanTouch=false handle.CanQuery=false handle.Massless=true handle.Parent=tool
	local model=Builder.Display(entry.Kind,entry.Id,entry.Variant,entry.Weight)
	for _,p in model:GetDescendants() do if p:IsA("BasePart") then
		p.CFrame=CFrame.new(0,-.15,-.65)*p.CFrame p.Anchored=false p.Parent=tool
		local weld=Instance.new("WeldConstraint") weld.Part0=handle weld.Part1=p weld.Parent=p
	end end
	model:Destroy()
	return tool
end
return Builder
