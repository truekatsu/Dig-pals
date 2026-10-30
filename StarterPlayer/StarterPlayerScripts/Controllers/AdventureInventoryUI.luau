--!nonstrict
-- Expedition journal skin and live inventory adapter. Server remains authoritative.
local UI = {}
local MenuIcons = require(script.Parent:WaitForChild("MenuIcons"))
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Tween = game:GetService("TweenService")
local Ink = Color3.fromRGB(26, 44, 49)
local Cream = Color3.fromRGB(255, 245, 215)
local Green = Color3.fromRGB(52, 166, 139)
local Gold = Color3.fromRGB(255, 196, 65)
local function make(class, parent, props)
	local o = Instance.new(class)
	for k,v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, radius)
	make("UICorner",o,{CornerRadius=UDim.new(0,radius or 12)})
end
local function stroke(o, color, thickness)
	return make("UIStroke",o,{Color=color or Ink,Thickness=thickness or 3,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
end
local function label(parent, text, pos, size, fontSize, color)
	return make("TextLabel",parent,{Text=text,Position=pos,Size=size,BackgroundTransparency=1,Font=Enum.Font.FredokaOne,TextSize=fontSize or 20,TextColor3=color or Ink,ZIndex=40})
end
local function button(parent,text,pos,size,color)
	local b=make("TextButton",parent,{Text=text,Position=pos,Size=size,BackgroundColor3=color or Green,TextColor3=Cream,Font=Enum.Font.FredokaOne,TextSize=18,AutoButtonColor=false,BorderSizePixel=0,ZIndex=41})
	round(b,10) stroke(b)
	make("UIGradient",b,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(192,203,190))})
	b.MouseEnter:Connect(function() Tween:Create(b,TweenInfo.new(.1),{BackgroundColor3=(color or Green):Lerp(Color3.new(1,1,1),.15)}):Play() end)
	b.MouseLeave:Connect(function() Tween:Create(b,TweenInfo.new(.1),{BackgroundColor3=color or Green}):Play() end)
	return b
end
local rarityColors={Common=Color3.fromRGB(127,151,145),Uncommon=Green,Rare=Color3.fromRGB(66,151,214),Epic=Color3.fromRGB(166,104,208),Legendary=Gold}
function UI.Mount(controller, gui, shovels)
	local player=Players.LocalPlayer
	local Remotes=require(RS.Shared.Util.Remotes)
	local configs={Items=require(RS.Shared.Config.Items).All, Eggs=require(RS.Shared.Config.Eggs).All, Shovel=require(RS.Shared.Config.Shovels).All}
	local snapshot={}
	local busy=false
	local loaded=false
	local errorText=nil
	local panel=gui.InventoryPanel
	local bar=gui.HotbarContainer
	local nav=panel.NavigationBar
	local content=panel.ContentArea
	panel.ClipsDescendants=false
	panel.Size=UDim2.fromOffset(900,478)
	panel.BackgroundColor3=Cream
	panel.BackgroundTransparency=0
	content.BackgroundTransparency=0
	panel.BorderTrim.Visible=false
	nav.Position=UDim2.fromOffset(22,18)
	nav.Size=UDim2.new(1,-112,0,52)
	content.Position=UDim2.fromOffset(22,82)
	content.Size=UDim2.new(1,-44,1,-138)
	content.BackgroundColor3=Color3.fromRGB(240,225,188)
	local close=panel:FindFirstChild("CloseButton")
	if close then close.Visible=false end
	-- Existing button names can differ between saved UI versions.
	for _,v in panel:GetChildren() do if v:IsA("ImageButton") then v.Visible=false end end
	local x=button(panel,"X",UDim2.new(1,-70,0,20),UDim2.fromOffset(48,48),Color3.fromRGB(221,83,70))
	x.Name="CloseInventoryButton"
	x.Activated:Connect(controller.CloseInventory)
	local status=label(panel,"",UDim2.new(0,25,1,-42),UDim2.new(1,-280,0,24),15,Color3.fromRGB(170,57,48))
	status.Name="InventoryError"
	status.TextXAlignment=Enum.TextXAlignment.Left
	status.Visible=false
	local count=label(panel,"",UDim2.new(1,-245,1,-42),UDim2.fromOffset(220,24),15)
	count.TextXAlignment=Enum.TextXAlignment.Right
	-- Compact, numbered nine-pocket tool belt.
	for i=1,3 do
		local b=bar:FindFirstChild(i==1 and "Slot1_EquippedShovel" or i==2 and "Slot2_Shovel" or "Slot3_Items")
		b.UICorner.CornerRadius=UDim.new(0,12)
		b.SlotIcon.Size=UDim2.fromOffset(48,47)
		b.SlotIcon.Position=UDim2.fromScale(.5,.40)
		if i > 1 then
			b.SlotIcon.Size=UDim2.fromOffset(46,46)
			b.SlotIcon.Position=UDim2.fromScale(.5,.42)
		end
		b.SlotName.Size=UDim2.new(1,-4,0,23)
		b.SlotName.Position=UDim2.new(.5,0,1,-4)
		b.SlotName.Font=Enum.Font.FredokaOne
		b.SlotName.TextSize=11
		b.SlotName.TextScaled=true
		make("UITextSizeConstraint",b.SlotName,{MinTextSize=8,MaxTextSize=12})
		b.NumberBadge.Position=UDim2.fromOffset(3,3)
		b.NumberBadge.Size=UDim2.fromOffset(19,20)
		b.NumberBadge.BadgeNumber.TextSize=13
		b.NumberBadge.ZIndex=16
		b.NumberBadge.BadgeNumber.ZIndex=17
		b.NumberBadge.BadgeNumber.Font=Enum.Font.FredokaOne
		b.NumberBadge.BadgeNumber.TextColor3=Cream
		b.SelectionGlow.UIStroke.Transparency=.1
		b.SlotName.UIStroke.Thickness=1.2
	end
	for i=4,9 do
		local b=make("ImageButton",bar,{Name="Slot"..i.."_Empty",Size=UDim2.fromOffset(76,82),LayoutOrder=i,Image="",AutoButtonColor=false,BackgroundColor3=Color3.fromRGB(49,74,81),BackgroundTransparency=.12,BorderSizePixel=0,ZIndex=11})
		b.Activated:Connect(function() controller.SelectHotbarSlot(i) end)
		round(b,12) stroke(b)
		local n=label(b,tostring(i),UDim2.fromOffset(6,3),UDim2.fromOffset(16,20),13,Cream) n.ZIndex=15
	end
	require(script.Parent.CarryHotbarController).Mount(bar)
	local function render()
		local cat=controller.GetActiveCategory()
		local shovelMode=cat=="Shovel"
		for _,name in {"Items","Shovel","Eggs","Pet"} do
			local tab=nav:FindFirstChild(name.."Tab")
			if tab then
				tab.Visible=(name=="Shovel")==shovelMode
				tab.TabLabel.Font=Enum.Font.FredokaOne
				tab.TabLabel.Text=name=="Pet" and "PETS" or string.upper(name)
				if tab:FindFirstChild("ActiveGlow") then tab.ActiveGlow.Visible=false end
			end
		end
		local scroll=content:FindFirstChild(cat.."Content")
		if not scroll then return end
		for _,v in scroll:GetChildren() do if not v:IsA("UIPadding") then v:Destroy() end end
		local entries={}
		if cat=="Items" then
			for id,quantity in pairs(snapshot.Items or {}) do if quantity>0 then table.insert(entries,{id=id,quantity=quantity}) end end
		elseif cat=="Eggs" then
			for index,egg in ipairs(snapshot.EggBag or {}) do table.insert(entries,{id=type(egg)=="table" and egg.Id or egg,rarity=type(egg)=="table" and egg.Rarity or nil,index=index}) end
		elseif cat=="Shovel" then
			for _,id in ipairs(snapshot.OwnedShovels or {}) do table.insert(entries,{id=id}) end
		elseif cat=="Pet" then
			for guid,pet in pairs(snapshot.Pets or {}) do table.insert(entries,{id=pet.Species,guid=guid,pet=pet,rarity=pet.Rarity}) end
		end
		table.sort(entries,function(a,b) return tostring(a.id)..tostring(a.guid)<tostring(b.id)..tostring(b.guid) end)
		count.Text=#entries..(cat=="Shovel" and " TOOLS OWNED" or " FINDS")
		status.Text=errorText or ""
		status.Visible=errorText~=nil
		if #entries==0 then
			local empty=label(scroll,loaded and "Empty..." or "Loading...",UDim2.fromScale(0,.36),UDim2.new(1,0,0,55),32,Color3.fromRGB(154,137,98))
			empty.Name="EmptyState"
			scroll.CanvasSize=UDim2.new()
			return
		end
		local grid=make("UIGridLayout",scroll,{CellSize=UDim2.fromOffset(150,172),CellPadding=UDim2.fromOffset(14,14),SortOrder=Enum.SortOrder.LayoutOrder})
		scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
		for order,entry in ipairs(entries) do
			local cfg=(configs[cat] or {})[entry.id] or {}
			local rarity=entry.rarity or cfg.Rarity or "Common"
			local accent=rarityColors[rarity] or Green
			local active=cat=="Shovel" and snapshot.EquippedShovel==entry.id or cat=="Pet" and table.find(snapshot.EquippedPets or {},entry.guid)~=nil
			local card=button(scroll,"",UDim2.new(),UDim2.fromOffset(150,172),Color3.fromRGB(255,249,227))
			card.LayoutOrder=order
			local band=make("Frame",card,{Size=UDim2.new(1,-12,0,80),Position=UDim2.fromOffset(6,6),BackgroundColor3=accent,BackgroundTransparency=.62,BorderSizePixel=0,ZIndex=42}) round(band,8)
			if cat=="Shovel" and shovels[entry.id] then
				make("ImageLabel",band,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Image=shovels[entry.id].Icon,ScaleType=Enum.ScaleType.Fit,ZIndex=43})
			elseif cat=="Eggs" then
				make("ImageLabel",band,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(66,66),BackgroundTransparency=1,Image=MenuIcons.Eggs,ScaleType=Enum.ScaleType.Fit,ZIndex=43})
			else
				-- Native toy-like tokens avoid missing/unpublished image assets.
				local token=make("Frame",band,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=cat=="Eggs" and UDim2.fromOffset(40,54) or UDim2.fromOffset(49,44),BackgroundColor3=accent,Rotation=cat=="Items" and 25 or 0,BorderSizePixel=0,ZIndex=43}) round(token,cat=="Eggs" and 24 or 12) stroke(token,Ink,2)
				if cat=="Pet" then
					for _,px in {.3,.7} do make("Frame",token,{Size=UDim2.fromOffset(5,7),Position=UDim2.fromScale(px,.4),BackgroundColor3=Ink,BorderSizePixel=0,ZIndex=44}) end
				else label(token,cat=="Eggs" and "?" or "✦",UDim2.new(),UDim2.fromScale(1,1),25,Cream).ZIndex=44 end
			end
			local name=label(card,cfg.DisplayName or tostring(entry.id),UDim2.fromOffset(6,92),UDim2.new(1,-12,0,35),16)
			name.TextWrapped=true name.ZIndex=44
			label(card,active and "EQUIPPED" or entry.quantity and "x"..entry.quantity or cat=="Pet" and "LV. "..tostring(entry.pet.Level or 1) or string.upper(rarity),UDim2.fromOffset(6,132),UDim2.new(1,-12,0,26),13,active and Green or Ink).ZIndex=44
			card.Activated:Connect(function()
if busy then return end
				if cat~="Shovel" then
					busy=true
					local result=require(script.Parent.CarryHotbarController).Assign(cat,entry.id,entry.guid or entry.index or entry.id)
					busy=false
					if result.Success then controller.CloseInventory() end
					return
				end
				busy=true errorText=nil
local remote=cat=="Items" and "HoldItem" or cat=="Shovel" and "EquipShovel" or active and "UnequipPet" or "EquipPet"
				local ok,result=pcall(function() return Remotes.GetFunction(remote):InvokeServer(entry.guid or entry.id) end)
				if not ok or not result or not result.Success then errorText=type(result)=="table" and result.Message or "Unable to equip. Please try again." end
				if ok and result and result.Success and cat=="Shovel" then snapshot.EquippedShovel=entry.id controller.SyncEquippedShovel(entry.id) end
				busy=false
				if ok and result and result.Success and cat=="Items" then controller.CloseInventory() end
				render()
			end)
		end
	end
	-- Keep rendering independent of optional integration hooks.
	controller.RefreshCollection = render
	local navigate=make("BindableFunction",gui,{Name="NavigateInventory"})
	navigate.OnInvoke=function(category)
		if category=="Items" or category=="Eggs" or category=="Pet" or category=="Shovel" then
			controller.OpenInventory(category)
		end
	end
	local function apply(data)
		if type(data)~="table" then return end
		for k,v in pairs(data) do snapshot[k]=v end
		loaded=true
		if snapshot.EquippedShovel then controller.SyncEquippedShovel(snapshot.EquippedShovel) end
		if controller.IsOpen() then render() end
	end
	Remotes.GetEvent("StateSync").OnClientEvent:Connect(apply)
	task.spawn(function()
		local ok,data=pcall(function() return Remotes.GetFunction("GetInventoryState"):InvokeServer() end)
		if ok then apply(data) else loaded=true errorText="Inventory unavailable. Reopen to retry." render() end
	end)
	player:GetAttributeChangedSignal("ActiveShopModal"):Connect(function()
		local modal=player:GetAttribute("ActiveShopModal")
		if modal~="Inventory" and modal~="" and controller.IsOpen() then controller.CloseInventory() end
	end)
	render()
end
return UI
