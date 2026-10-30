--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config.Sprint)
local Remotes = require(Shared.Util.Remotes)
local DigService = require(script.Parent.DigService)
local SharedMoundService = require(script.Parent.SharedMoundService)

type State = {character: Model?, humanoid: Humanoid?, baseSpeed: number, appliedSpeed: number?, requested: boolean}
local states: {[Player]: State} = {}
local Service = {}
local started = false

local function update(player: Player, state: State)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character ~= state.character or humanoid ~= state.humanoid then
		state.character, state.humanoid = character, humanoid
		state.baseSpeed = if humanoid then humanoid.WalkSpeed else 16
		state.appliedSpeed, state.requested = nil, false
	end
	if not character or not humanoid then return end
	-- Respect another system's speed change (for example a stun or movement lock).
	if state.appliedSpeed and humanoid.WalkSpeed ~= state.appliedSpeed then
		state.baseSpeed, state.appliedSpeed = humanoid.WalkSpeed, nil
		state.requested = false
	elseif not state.appliedSpeed then
		state.baseSpeed = humanoid.WalkSpeed
	end
	local blocked = humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand
		or state.baseSpeed <= 0 or character:GetAttribute("MovementLocked") == true
		or DigService.GetSession(player.UserId) ~= nil or SharedMoundService.HasSession(player.UserId)
	if blocked then state.requested = false end
	local enabled = state.requested and not blocked
	local speed = if enabled then math.max(state.baseSpeed, Config.RunSpeed) else state.baseSpeed
	if humanoid.WalkSpeed ~= speed then humanoid.WalkSpeed = speed end
	state.appliedSpeed = if enabled then speed else nil
	if character:GetAttribute("SprintEnabled") ~= enabled then character:SetAttribute("SprintEnabled", enabled) end
end

function Service.Start()
	if started then return end
	started = true
	game:GetService("StarterPlayer").EnableMouseLockOption = false
	local function added(player: Player)
		player.DevEnableMouseLock = false
		states[player] = {character = nil, humanoid = nil, baseSpeed = 16, appliedSpeed = nil, requested = false}
		update(player, states[player])
	end
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(player) states[player] = nil end)
	for _, player in Players:GetPlayers() do added(player) end
	Remotes.OnServerEvent("SetSprinting", function(player: Player, requested: boolean)
		local state = states[player]
		if not state then return end
		update(player, state)
		state.requested = requested
		update(player, state)
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < Config.ServerStep then return end
		elapsed = 0
		for player, state in states do update(player, state) end
	end)
end

return Service
