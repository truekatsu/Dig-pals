--!strict
-- Centralized Audio Controller for Dig Pals (Step 15)
-- Loads all sounds through Shared.AssetIds, manages sound instances, pitch variation, and remote event triggers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared:WaitForChild("AssetIds"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))

local LocalPlayer = Players.LocalPlayer

local AudioController = {}

local soundTemplates: { [string]: Sound } = {}
local lastCoinsValue: number? = nil
local lastCoinSoundTime: number = 0
local started = false

local function ensureSoundGroup(): SoundGroup
	local group = SoundService:FindFirstChild("DigPalsSoundGroup")
	if not group then
		local newGroup = Instance.new("SoundGroup")
		newGroup.Name = "DigPalsSoundGroup"
		newGroup.Volume = 0.8
		newGroup.Parent = SoundService
		return newGroup
	end
	return group :: SoundGroup
end

local function initSoundTemplates()
	local soundGroup = ensureSoundGroup()
	for soundName, assetId in pairs(AssetIds.Sounds) do
		local sound = Instance.new("Sound")
		sound.Name = soundName
		sound.SoundId = assetId
		sound.Volume = 0.7
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.SoundGroup = soundGroup
		sound.Parent = soundGroup
		soundTemplates[soundName] = sound
	end
end

function AudioController.PlaySound(soundName: string, volumeScale: number?, pitchScale: number?): Sound?
	local template = soundTemplates[soundName]
	if not template then
		return nil
	end

	local clone = template:Clone()
	local baseVol = template.Volume
	local vol = if type(volumeScale) == "number" then baseVol * volumeScale else baseVol
	local pitch = if type(pitchScale) == "number" then pitchScale else (1.0 + (math.random(-4, 4) * 0.02))

	clone.Volume = math.clamp(vol, 0, 1.5)
	clone.PlaybackSpeed = math.clamp(pitch, 0.5, 2.0)
	clone.Parent = SoundService

	clone.Ended:Connect(function()
		clone:Destroy()
	end)

	task.delay(4, function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)

	clone:Play()
	return clone
end

function AudioController.PlayStrike(grade: string)
	if grade == "Perfect" then
		AudioController.PlaySound("StrikePerfect", 1.0, 1.05)
	elseif grade == "Good" then
		AudioController.PlaySound("StrikeGood", 0.9, 1.0)
	else
		AudioController.PlaySound("StrikeMiss", 0.7, 0.9)
	end
end

function AudioController.PlayMoundBreak()
	AudioController.PlaySound("MoundBreak", 1.1, 1.0)
end

function AudioController.PlayRareDrop(_rarity: string?)
	AudioController.PlaySound("RareDrop", 1.1, 1.0)
end

function AudioController.PlayEggHatch(_rarity: string?)
	AudioController.PlaySound("EggHatch", 1.15, 1.05)
end

function AudioController.PlayLevelUp()
	AudioController.PlaySound("LevelUp", 1.2, 1.0)
end

function AudioController.PlayBaseUpgrade()
	AudioController.PlaySound("BaseUpgrade", 1.2, 1.0)
end

function AudioController.PlayCoinGain()
	local now = os.clock()
	if now - lastCoinSoundTime < 0.15 then
		return
	end
	lastCoinSoundTime = now
	AudioController.PlaySound("CoinGain", 0.65, 1.0 + math.random(0, 3) * 0.05)
end

function AudioController.PlayClick()
	AudioController.PlaySound("StrikeGood", 0.45, 1.4)
end

function AudioController.Start()
	if started then
		return
	end
	started = true

	initSoundTemplates()

	-- Track coin gains
	local initialCoins = LocalPlayer:GetAttribute("Coins")
	if type(initialCoins) == "number" then
		lastCoinsValue = initialCoins
	end

	LocalPlayer:GetAttributeChangedSignal("Coins"):Connect(function()
		local currentCoins = LocalPlayer:GetAttribute("Coins")
		if type(currentCoins) == "number" then
			if lastCoinsValue ~= nil and currentCoins > lastCoinsValue then
				AudioController.PlayCoinGain()
			end
			lastCoinsValue = currentCoins
		end
	end)

	-- Listen to StrikeResult
	Remotes.GetEvent("StrikeResult").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.Event == "StrikeHit" then
			local grade = tostring(payload.Grade or "Miss")
			AudioController.PlayStrike(grade)
			if payload.Cleared == true then
				task.delay(0.12, function()
					AudioController.PlayMoundBreak()
				end)
			end
		end
	end)

	-- Listen to DropNotification
	Remotes.GetEvent("DropNotification").OnClientEvent:Connect(function(summary: any)
		if type(summary) == "table" and type(summary.Drops) == "table" then
			local hasRare = false
			for _, drop in ipairs(summary.Drops) do
				local rarity = tostring(drop.Rarity or "")
				if rarity == "Rare" or rarity == "Epic" or rarity == "Legendary" or drop.DropType == "Egg" then
					hasRare = true
					break
				end
			end
			if hasRare then
				task.delay(0.2, function()
					AudioController.PlayRareDrop()
				end)
			end
		end
	end)
end

return AudioController
