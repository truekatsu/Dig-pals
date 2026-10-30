--!nonstrict
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Remotes=require(RS.Shared.Util.Remotes)
local Builder=require(RS.Shared.CarryModelBuilder)
local Notify=require(script.Parent.NotificationController)
local player=Players.LocalPlayer
local Controller={}
local state={Slots={},ActiveSlot=0}
local buttons={}
local refs={}
local busy=false
local mounted=false
local ghost=nil
local ghostKey=nil
local candidate=nil
local function preview(parent,e)
	local viewport=Instance.new("ViewportFrame") viewport.Name="CarryPreview" viewport.Size=UDim2.new(1,-10,0,51) viewport.Position=UDim2.fromOffset(5,8) viewport.BackgroundTransparency=1 viewport.ZIndex=12 viewport.Ambient=Color3.fromRGB(210,210,210) viewport.LightColor=Color3.new(1,1,1) viewport.Parent=parent
	local model=Builder.Display(e.Kind,e.Id,e.Variant) model.Parent=viewport
	local cam=Instance.new("Camera") cam.FieldOfView=32 cam.CFrame=CFrame.lookAt(Vector3.new(3,1.7,4),Vector3.zero) cam.Parent=viewport viewport.CurrentCamera=cam
end
local function apply(snapshot)
	if type(snapshot)~="table" then return end state=snapshot
	for i=4,9 do
		local b=buttons[i] if not b then continue end
		local e=state.Slots[tostring(i)]
		local key=e and e.Kind..e.Key or ""
		if refs[i]~=key then
			refs[i]=key
			local old=b:FindFirstChild("CarryPreview") if old then old:Destroy() end
			local label=b:FindFirstChild("CarryName") if label then label:Destroy() end
			if e then
				preview(b,e)
				label=Instance.new("TextLabel") label.Name="CarryName" label.BackgroundTransparency=1 label.Size=UDim2.new(1,-6,0,20) label.Position=UDim2.new(0,3,1,-23) label.Font=Enum.Font.FredokaOne label.TextSize=10 label.TextScaled=true label.TextColor3=Color3.fromRGB(255,245,215) label.Text=e.Name label.ZIndex=13 label.Parent=b
				local limit=Instance.new("UITextSizeConstraint") limit.MinTextSize=8 limit.MaxTextSize=11 limit.Parent=label
			end
		end
		b.BackgroundColor3=if state.ActiveSlot==i then Color3.fromRGB(231,159,38) else Color3.fromRGB(49,74,81)
	end
end
function Controller.Assign(kind,id,reference)
	if busy then return {Success=false} end busy=true
	local ok,result=pcall(function() return Remotes.GetFunction("AssignCarrySlot"):InvokeServer(kind,id,tostring(reference or id)) end)
	busy=false
	if ok and result.Success then apply(result.State) else Notify.ShowAlert(ok and result.Message or "Unable to select item.","Error") end
	return ok and result or {Success=false}
end
function Controller.Select(slot)
	if busy then return end busy=true
	local ok,result=pcall(function() return Remotes.GetFunction("SelectCarrySlot"):InvokeServer(slot) end) busy=false
	if ok and result.Success then apply(result.State) end
end
local function ground()
	local plots=workspace:FindFirstChild("BasePlots") local name=player:GetAttribute("AssignedPlot") local plot=plots and name and plots:FindFirstChild(name)
	return plot and plot:FindFirstChild(name.."_Ground")
end
local function rayAt(position)
	local g=ground() local cam=workspace.CurrentCamera if not g or not cam then return nil end
	local ray=cam:ScreenPointToRay(position.X,position.Y)
	local params=RaycastParams.new() params.FilterType=Enum.RaycastFilterType.Include params.FilterDescendantsInstances={g}
	return workspace:Raycast(ray.Origin,ray.Direction*500,params)
end
local function petRayAt(position)
	local cam=workspace.CurrentCamera if not cam then return nil end
	local ray=cam:ScreenPointToRay(position.X,position.Y)
	local ignore={}
	for _,p in Players:GetPlayers() do if p.Character then table.insert(ignore,p.Character) end end
	for _,name in {"ClientPetVisuals","ClientBasePetVisuals","ClientMounds"} do local f=workspace:FindFirstChild(name) if f then table.insert(ignore,f) end end
	if ghost then table.insert(ignore,ghost) end
	local params=RaycastParams.new() params.FilterType=Enum.RaycastFilterType.Exclude params.FilterDescendantsInstances=ignore
	return workspace:Raycast(ray.Origin,ray.Direction*500,params)
end
local function place(position)
	if busy or player:GetAttribute("DigMinigameActive") or (player:GetAttribute("ActiveShopModal") or "")~="" then return end
	local e=state.Slots[tostring(state.ActiveSlot)] if not e or (e.Kind~="Eggs" and e.Kind~="Pet") then return end
	local hit=if e.Kind=="Pet" then petRayAt(position) else rayAt(position) if not hit then return end
	busy=true
	local p=hit.Position
	local remote=if e.Kind=="Pet" then "PlaceCarriedPet" else "PlaceCarriedEgg"
	local ok,result=pcall(function() return Remotes.GetFunction(remote):InvokeServer(p.X,p.Y,p.Z) end) busy=false
	if not ok or not result.Success then Notify.ShowAlert(ok and result.Message or "Unable to place.","Error")
	elseif e.Kind=="Pet" then
		Notify.ShowAlert(if result.Mode=="Base" then "Pet ditugaskan di base untuk passive income." else "Pet mengikuti dan membantu menggali dalam batas stat jaraknya.","Success")
	end
end
function Controller.Mount(bar)
	if mounted then return end mounted=true
	for i=4,9 do buttons[i]=bar:FindFirstChild("Slot"..i.."_Empty") end
	Remotes.GetEvent("CarryHotbarState").OnClientEvent:Connect(apply)
	task.spawn(function() local ok,s=pcall(function() return Remotes.GetFunction("GetCarryHotbar"):InvokeServer() end) if ok then apply(s) end end)
	UIS.InputBegan:Connect(function(input,processed) if not processed and input.UserInputType==Enum.UserInputType.MouseButton1 then place(UIS:GetMouseLocation()) end end)
	UIS.TouchTapInWorld:Connect(function(position,processed) if not processed then place(position) end end)
	RunService.RenderStepped:Connect(function()
		local e=state.Slots[tostring(state.ActiveSlot)]
		local c=player.Character local tool=c and c:FindFirstChildOfClass("Tool")
		local active=e and e.Kind=="Eggs" and tool and tool:GetAttribute("CarryKey")==e.Key and not player:GetAttribute("DigMinigameActive") and (player:GetAttribute("ActiveShopModal") or "")==""
		local hit=active and rayAt(UIS:GetMouseLocation())
		if not hit then if ghost then ghost:Destroy() ghost=nil ghostKey=nil end candidate=nil return end
		if not ghost or ghostKey~=e.Key then
			if ghost then ghost:Destroy() end ghost=Builder.Display("Eggs",e.Id) ghost.Name="EggPlacementPreview" ghostKey=e.Key
			for _,v in ghost:GetDescendants() do if v:IsA("BasePart") then v.Transparency=math.max(.5,v.Transparency) end end
			local highlight=Instance.new("Highlight") highlight.Name="ValidPlacement" highlight.FillColor=Color3.fromRGB(80,230,135) highlight.OutlineColor=Color3.fromRGB(80,230,135) highlight.Parent=ghost ghost.Parent=workspace
		end
		local g=ground() local p=g.CFrame:PointToObjectSpace(hit.Position)
		local valid=math.abs(p.X)<=g.Size.X/2-1.5 and math.abs(p.Z)<=g.Size.Z/2-1.5
		local h=ghost.ValidPlacement h.FillColor=if valid then Color3.fromRGB(80,230,135) else Color3.fromRGB(255,80,70) h.OutlineColor=h.FillColor
		ghost:PivotTo(CFrame.new(hit.Position+Vector3.new(0,ghost:GetExtentsSize().Y/2,0))) candidate=hit.Position
	end)
end
return Controller
