--!nonstrict
-- Slots 1-3 are reserved. This service owns the six inventory shortcuts and their equipped Tool.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=RS.Shared
local Remotes=require(Shared.Util.Remotes)
local State=require(script.Parent.PlayerState)
local Builder=require(Shared.CarryModelBuilder)
local Items=require(Shared.Config.Items).All
local Eggs=require(Shared.Config.Eggs).All
local Pets=require(Shared.Config.Pets).Species
local Service={}
local slotsByPlayer={}
local eggKeys=setmetatable({}, {__mode="k"})
local started=false
local function fail(message) return {Success=false,Message=message} end
local function valid(player,e)
	local p=State.Get(player)
	if not p then return false end
	if e.Kind=="Items" then return (p.Items[e.Id] or 0)>0 end
	if e.Kind=="Pet" then return p.Pets[e.Key]~=nil and p.Pets[e.Key].Species==e.Id end
	if e.Kind=="Eggs" then for _,egg in p.EggBag do if egg==e.Egg then return true end end end
	return false
end
function Service.GetHeld(player)
	local c=player.Character
	local tool=c and c:FindFirstChildOfClass("Tool")
	if not tool or not tool:GetAttribute("DigPalsCarryTool") then return nil end
	local slots=slotsByPlayer[player] or {}
	local e=slots[tool:GetAttribute("CarrySlot")]
	return if e and e.Key==tool:GetAttribute("CarryKey") and valid(player,e) then e else nil
end
function Service.Snapshot(player)
	local result={Slots={},ActiveSlot=0}
	for slot,e in slotsByPlayer[player] or {} do
		if valid(player,e) then result.Slots[tostring(slot)]={Slot=slot,Kind=e.Kind,Id=e.Id,Key=e.Key,Name=e.Name,Rarity=e.Rarity,Variant=e.Variant} end
	end
	local held=Service.GetHeld(player)
	if held then result.ActiveSlot=held.Slot end
	return result
end
local function send(player) Remotes.GetEvent("CarryHotbarState"):FireClient(player,Service.Snapshot(player)) end
function Service.Select(player,slot)
	local c=player.Character local h=c and c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health<=0 then return fail("Character unavailable.") end
	local current=Service.GetHeld(player)
	local e=(slotsByPlayer[player] or {})[slot]
	if slot~=0 and (slot<4 or slot>9 or not e or not valid(player,e)) then return fail("This slot is empty.") end
	local toggle=current and current.Slot==slot
	for _,container in {c,player:FindFirstChildOfClass("Backpack")} do if container then for _,t in container:GetChildren() do if t:IsA("Tool") and t:GetAttribute("DigPalsCarryTool") then t:Destroy() end end end end
	if slot==0 or toggle then send(player) return {Success=true,State=Service.Snapshot(player)} end
	require(script.Parent.ShovelInventoryService).SetToolActive(player,false)
	h:UnequipTools()
	local tool=Builder.Tool(e) tool.Parent=player:FindFirstChildOfClass("Backpack") h:EquipTool(tool)
	if e.Kind=="Pet" then
		State.Mutate(player,function(p)
			for _,list in {p.EquippedPets,p.BasePets} do
				local index=table.find(list,e.Key) if index then table.remove(list,index) end
			end
		end)
		require(script.Parent.ShovelInventoryService).SendStateSync(player)
		require(script.Parent.DataService).SavePlayer(player)
	end
	send(player)
	return {Success=true,State=Service.Snapshot(player)}
end
function Service.Assign(player,kind,id,reference)
	local p=State.Get(player) if not p then return fail("Inventory loading.") end
	local cfg,key,egg,variant
	if kind=="Items" then cfg=Items[id] key=id if not cfg or (p.Items[id] or 0)<1 then return fail("Item not owned.") end
	elseif kind=="Pet" then local pet=p.Pets[reference] if not pet or pet.Species~=id then return fail("Pet not owned.") end cfg=Pets[id] key=reference variant=pet.Variant
	elseif kind=="Eggs" then egg=p.EggBag[tonumber(reference)] if not egg or egg.Id~=id then return fail("Egg no longer available. Reopen Eggs.") end cfg=Eggs[id] key=eggKeys[egg] or game.HttpService:GenerateGUID(false) eggKeys[egg]=key
	else return fail("Invalid category.") end
	if not cfg then return fail("Unknown item.") end
	local slots=slotsByPlayer[player] or {} slotsByPlayer[player]=slots
	for slot,e in slots do if not valid(player,e) then slots[slot]=nil end end
	for slot,e in slots do if e.Kind==kind and e.Key==key then
		local held=Service.GetHeld(player)
		if held and held.Slot==slot then return {Success=true,Slot=slot,State=Service.Snapshot(player)} end
		return Service.Select(player,slot)
	end end
	local slot=9 for i=4,9 do if slots[i]==nil then slot=i break end end
	slots[slot]={Slot=slot,Kind=kind,Id=id,Key=key,Egg=egg,Variant=variant,Name=cfg.DisplayName or id,Rarity=egg and egg.Rarity or cfg.Rarity}
	-- Replacement of slot 9 equips the new object rather than toggling the old one off.
	local c=player.Character if c then for _,t in c:GetChildren() do if t:IsA("Tool") and t:GetAttribute("DigPalsCarryTool") then t:Destroy() end end end
	return Service.Select(player,slot)
end
-- The pet can occupy only one mode: held/inventory, base income, or follower.
function Service.DeployPetInProfile(profile,guid,toBase)
	local petService=require(script.Parent.PetService)
	return if toBase then petService.AssignBasePetInProfile(profile,guid) else petService.EquipPetInProfile(profile,guid)
end
function Service.PlacePet(player,x,y,z)
	for _,v in {x,y,z} do if type(v)~="number" or v~=v or math.abs(v)>100000 then return fail("Invalid position.") end end
	local held=Service.GetHeld(player)
	if not held or held.Kind~="Pet" then return fail("Pegang pet terlebih dahulu.") end
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local point=Vector3.new(x,y,z)
	if not root or not humanoid or humanoid.Health<=0 or (root.Position-point).Magnitude>60 then return fail("Dekati lokasi penempatan pet.") end
	local base=require(script.Parent.BaseService)
	local toBase=false
	local plots=workspace:FindFirstChild("BasePlots")
	if plots then for _,plot in plots:GetChildren() do
		local ground=base.GetPlotGround(plot)
		if ground then
			local p=ground.CFrame:PointToObjectSpace(point)
			if math.abs(p.X)<=ground.Size.X/2 and math.abs(p.Z)<=ground.Size.Z/2 then
				if plot:GetAttribute("OwnerUserId")~=player.UserId then return fail("Pet hanya bisa ditaruh di base milikmu.") end
				if math.abs(p.Y-ground.Size.Y/2)>2 then return fail("Taruh pet di lantai base.") end
				toBase=true break
			end
		end
	end end
	local profile=State.Get(player) local pet=profile and profile.Pets[held.Key]
	if not pet then return fail("Pet tidak ditemukan.") end
	if not toBase then
		local stats=require(script.Parent.PetService).GetEffectiveStats(pet.Species,pet.Variant,pet.Level)
		if (Vector2.new(x,z)-Vector2.new(root.Position.X,root.Position.Z)).Magnitude>stats.Range then return fail("Lokasi di luar stat jarak pet. Pilih lebih dekat.") end
	end
	local result
	local mutated=State.Mutate(player,function(p) result=Service.DeployPetInProfile(p,held.Key,toBase) end)
	if not mutated or not result then return fail("Penempatan pet gagal.") end
	if result.Success then
		Service.Select(player,0)
		require(script.Parent.ShovelInventoryService).SendStateSync(player)
		require(script.Parent.DataService).SavePlayer(player)
		result.Mode=if toBase then "Base" else "Follow"
	end
	return result
end
function Service.Start()
	if started then return end started=true
	Remotes.OnServerInvoke("AssignCarrySlot",Service.Assign)
	Remotes.OnServerInvoke("SelectCarrySlot",Service.Select)
	Remotes.OnServerInvoke("GetCarryHotbar",function(player) return Service.Snapshot(player) end)
	Remotes.OnServerInvoke("PlaceCarriedPet",Service.PlacePet)
	Players.PlayerRemoving:Connect(function(player) slotsByPlayer[player]=nil end)
	local elapsed=0
	RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt if elapsed<.5 then return end elapsed=0
		for player,slots in slotsByPlayer do
			for slot,e in slots do if not valid(player,e) then slots[slot]=nil end end
			local c=player.Character
			if c then for _,t in c:GetChildren() do if t:IsA("Tool") and t:GetAttribute("DigPalsCarryTool") and not Service.GetHeld(player) then t:Destroy() end end end
			send(player)
		end
	end)
end
return Service
