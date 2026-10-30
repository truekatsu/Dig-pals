--!nonstrict
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Remotes=require(RS.Shared.Util.Remotes)
local Builder=require(RS.Shared.CarryModelBuilder)
local State=require(script.Parent.PlayerState)
local Carry=require(script.Parent.CarryHotbarService)
local Base=require(script.Parent.BaseService)
local Eggs=require(script.Parent.EggService)
local Data=require(script.Parent.DataService)
local Service={}
local visuals={}
local function fail(text) return {Success=false,Message=text} end
local function surface(ground,x,z) return ground.CFrame:PointToWorldSpace(Vector3.new(x,ground.Size.Y/2,z)) end
local function hatch(player,slot)
	local profile=State.Get(player) local entry=profile and profile.Incubators[slot]
	local plot=Base.GetAssignedPlotFolder(player) local ground=plot and Base.GetPlotGround(plot)
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not entry or not ground or not root then return end
	local pos=entry.Placement or {X=0,Z=0}
	if (root.Position-surface(ground,pos.X,pos.Z)).Magnitude>14 then return end
	local result
	State.Mutate(player,function(p) result=Eggs.HatchIncubatorInProfile(p,slot) end)
	if result and result.Success then
		if result.Species then
			require(script.Parent.IndexService).RegisterPetDiscovery(player,profile,result.Species)
			require(script.Parent.TutorialService).OnEggHatched(player,profile,result.Species)
			require(script.Parent.DebugService).OnFirstHatch(player,profile,result.Species)
			if result.Rarity=="Legendary" then require(script.Parent.DebugService).OnLegendaryObtained(player,profile,"Egg",result.Species) end
		end
		require(script.Parent.QuestService).RecordProgress(player,"EggHatched",1)
		require(script.Parent.ShovelInventoryService).SendStateSync(player)
		Data.SavePlayer(player)
	end
end
function Service.Place(player,x,y,z)
	for _,v in {x,y,z} do if v~=v or math.abs(v)>100000 then return fail("Invalid position.") end end
	local held=Carry.GetHeld(player)
	if not held or held.Kind~="Eggs" then return fail("Hold an egg first.") end
	local plot=Base.GetAssignedPlotFolder(player) local ground=plot and Base.GetPlotGround(plot)
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not ground or plot:GetAttribute("OwnerUserId")~=player.UserId or not root or not humanoid or humanoid.Health<=0 then return fail("Use your own base.") end
	local p=ground.CFrame:PointToObjectSpace(Vector3.new(x,y,z))
	if math.abs(p.X)>ground.Size.X/2-1.5 or math.abs(p.Z)>ground.Size.Z/2-1.5 then return fail("Place eggs inside your base.") end
	local world=surface(ground,p.X,p.Z)
	if math.abs(world.Y-y)>1 or (root.Position-world).Magnitude>60 then return fail("Move closer to your base.") end
	local profile=State.Get(player)
	for oldSlot,entry in profile.Incubators do
		local q=entry.Placement or {X=(oldSlot-1)*3,Z=0}
		if Vector2.new(q.X-p.X,q.Z-p.Z).Magnitude<2.6 then return fail("Leave space between eggs.") end
	end
	local slot for i=1,Eggs.GetMaxIncubatorSlots(profile.BaseLevel) do if not profile.Incubators[i] then slot=i break end end
	if not slot then return fail("Your base has no free egg capacity.") end
	local index=table.find(profile.EggBag,held.Egg)
	if not index then return fail("Egg no longer available.") end
	local result
	State.Mutate(player,function(prof)
		result=Eggs.PlaceEggInIncubatorInProfile(prof,index,slot)
		if result.Success then prof.Incubators[slot].Placement={X=p.X,Z=p.Z} end
	end)
	if result and result.Success then
		Carry.Select(player,0)
		require(script.Parent.ShovelInventoryService).SendStateSync(player)
		Data.SavePlayer(player)
	end
	return result or fail("Unable to place egg.")
end
local function refresh(player)
	local p=State.Get(player) local plot=Base.GetAssignedPlotFolder(player) local ground=plot and Base.GetPlotGround(plot)
	if not p or not ground then return end
	local folder=visuals[player]
	if not folder or folder.Parent~=plot then
		if folder then folder:Destroy() end
		folder=Instance.new("Folder") folder.Name="PlacedEggs" folder.Parent=plot visuals[player]=folder
	end
	for _,model in folder:GetChildren() do
		local entry=p.Incubators[model:GetAttribute("EggSlot")]
		if not entry or model:GetAttribute("ReadyAt")~=entry.ReadyAt or model:GetAttribute("EggId")~=entry.Id then model:Destroy() end
	end
	for slot,entry in p.Incubators do
		local name="Egg"..slot
		local model=folder:FindFirstChild(name)
		local placement=entry.Placement or {X=(slot-1)*3,Z=0}
		if not model then
			model=Builder.Display("Eggs",entry.Id)
			model.Name=name model:SetAttribute("EggSlot",slot) model:SetAttribute("EggId",entry.Id) model:SetAttribute("ReadyAt",entry.ReadyAt)
			local anchor=Instance.new("Part") anchor.Name="EggInteraction" anchor.Size=Vector3.new(.2,.2,.2) anchor.Transparency=1 anchor.Anchored=true anchor.CanCollide=false anchor.CanTouch=false anchor.CanQuery=false anchor.Parent=model
			local prompt=Instance.new("ProximityPrompt") prompt.Name="HatchPlacedEgg" prompt.ActionText="Hatch" prompt.ObjectText="Egg" prompt.MaxActivationDistance=10 prompt.RequiresLineOfSight=false prompt:SetAttribute("OwnerUserId",player.UserId) prompt.Parent=anchor
			prompt.Triggered:Connect(function(who) if who==player then hatch(player,slot) end end)
			local bill=Instance.new("BillboardGui") bill.Name="Timer" bill.Adornee=anchor bill.Size=UDim2.fromOffset(160,36) bill.StudsOffsetWorldSpace=Vector3.new(0,1.7,0) bill.MaxDistance=60 bill.AlwaysOnTop=true bill.Parent=anchor
			local text=Instance.new("TextLabel") text.Size=UDim2.fromScale(1,1) text.BackgroundTransparency=1 text.Font=Enum.Font.FredokaOne text.TextSize=18 text.TextColor3=Color3.fromRGB(255,241,185) text.TextStrokeTransparency=.2 text.Parent=bill
			model.Parent=folder
		end
		local height=model:GetExtentsSize().Y
		model:PivotTo(CFrame.new(surface(ground,placement.X,placement.Z)+Vector3.new(0,height/2,0)))
		local remaining=math.max(0,entry.ReadyAt-os.time())
		model.EggInteraction.Timer.TextLabel.Text=if remaining==0 then "Ready to hatch!" else string.format("%d:%02d",math.floor(remaining/60),remaining%60)
		model.EggInteraction.HatchPlacedEgg.Enabled=remaining==0
	end
end
function Service.Start()
	Remotes.OnServerInvoke("PlaceCarriedEgg",Service.Place)
	Players.PlayerRemoving:Connect(function(player) if visuals[player] then visuals[player]:Destroy() end visuals[player]=nil end)
	task.spawn(function() while true do task.wait(.5) for _,player in Players:GetPlayers() do refresh(player) end end end)
end
return Service
