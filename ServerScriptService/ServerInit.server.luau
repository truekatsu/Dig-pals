--!strict
-- Main server bootstrapper for Dig Pals (Steps 1-8: DataService, PlayerState, Remotes, MoundService, DigService, DropService, InventoryService, ShovelInventoryService, ShopService, BaseService, EggService)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("Base"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local EggsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Eggs"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))
local PetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Pets"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))

local ServicesFolder = ServerScriptService:WaitForChild("Services")
local DataService = require(ServicesFolder:WaitForChild("DataService"))
local PlayerState = require(ServicesFolder:WaitForChild("PlayerState"))
local InventoryService = require(ServicesFolder:WaitForChild("InventoryService"))
local MoundService = require(ServicesFolder:WaitForChild("MoundService"))
local ShovelInventoryService = require(ServicesFolder:WaitForChild("ShovelInventoryService"))
local ShopService = require(ServicesFolder:WaitForChild("ShopService"))
local BaseService = require(ServicesFolder:WaitForChild("BaseService"))
local EggService = require(ServicesFolder:WaitForChild("EggService"))
local DigService = require(ServicesFolder:WaitForChild("DigService"))
local DropService = require(ServicesFolder:WaitForChild("DropService"))
local PetService = require(ServicesFolder:WaitForChild("PetService"))
local PassiveIncomeService = require(ServicesFolder:WaitForChild("PassiveIncomeService"))
local SharedMoundService = require(ServicesFolder:WaitForChild("SharedMoundService"))

Remotes.EnsureAll()
DataService.Start()
PlayerState.Start()
InventoryService.Start()
ShovelInventoryService.Start()
ShopService.Start()
BaseService.Start()
EggService.Start()
PetService.Start()
PassiveIncomeService.Start()
SharedMoundService.Start()
MoundService.Start()
DigService.Start()
DropService.Start()

-- Step 1 automated verification
local function runStep1Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step1Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step1Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	local testUserId = -900001
	local sessionA = "SessionA_Test"
	local sessionB = "SessionB_Test"

	local okLoad1, profile1, err1 = DataService.AcquireProfileLock(testUserId, sessionA, true)
	verify(okLoad1 and profile1 ~= nil, "New player profile acquired in Session A", tostring(err1))
	if profile1 then
		verify(
			profile1.Coins == Economy.StartingCoins,
			string.format("New player starts with %d Coins", Economy.StartingCoins),
			string.format("actual=%d", profile1.Coins)
		)

		local okLoadConcurrent, profileConcurrent, errConcurrent = DataService.AcquireProfileLock(testUserId, sessionB, true)
		verify(
			not okLoadConcurrent and profileConcurrent == nil and errConcurrent == "SessionLockActive",
			"Concurrent Session B load rejected while Session A holds lock",
			tostring(errConcurrent)
		)

		local tamperedProfile = DataService.CreateDefaultProfile()
		tamperedProfile.Coins = 999999
		local okTamperSave, tamperErr = DataService.SaveProfileSession(testUserId, sessionB, tamperedProfile, false)
		verify(
			not okTamperSave and tamperErr == "SessionLockConflict",
			"Concurrent Session B save rejected without corrupting Session A data",
			tostring(tamperErr)
		)

		profile1.Coins = 777
		local okSaveA = DataService.SaveProfileSession(testUserId, sessionA, profile1, true)
		verify(okSaveA, "Session A saved modified Coins (777) and released lock on leave")

		local okRejoin, profileRejoin, errRejoin = DataService.AcquireProfileLock(testUserId, sessionB, true)
		verify(okRejoin and profileRejoin ~= nil, "Rejoin in Session B succeeded after lock release", tostring(errRejoin))
		if profileRejoin then
			verify(
				profileRejoin.Coins == 777,
				"Modified Coins (777) persisted across rejoin",
				string.format("actual=%d", profileRejoin.Coins)
			)
			profileRejoin.Coins = Economy.StartingCoins
			DataService.SaveProfileSession(testUserId, sessionB, profileRejoin, true)
		end
	end

	print(string.format("[Step1Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 2 automated verification
local function runStep2Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step2Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step2Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	verify(remotesFolder ~= nil, "ReplicatedStorage.Remotes folder exists")

	local testUserId = -900002
	local testName = "ExploitTester"
	Remotes.ResetViolations(testUserId)
	local fixedClock = 1000.0

	local okValidStrike = Remotes.ValidateAndThrottle(testUserId, testName, "Strike", fixedClock, "Mound_1")
	verify(okValidStrike, "Valid Strike('Mound_1') accepted")

	local okValidSell = Remotes.ValidateAndThrottle(testUserId, testName, "SellItem", fixedClock, "Pebble", 3)
	verify(okValidSell, "Valid SellItem('Pebble', 3) accepted")

	local okWrongType1, reason1 = Remotes.ValidateAndThrottle(testUserId, testName, "Strike", fixedClock, 12345)
	verify(not okWrongType1 and reason1 == "InvalidArguments", "Strike(12345) wrong type rejected safely")

	local okWrongType2, reason2 = Remotes.ValidateAndThrottle(testUserId, testName, "SellItem", fixedClock, "Pebble", -5)
	verify(not okWrongType2 and reason2 == "InvalidArguments", "SellItem('Pebble', -5) negative count rejected safely")

	local okWrongType3, reason3 = Remotes.ValidateAndThrottle(testUserId, testName, "SellItem", fixedClock, "Pebble", 0 / 0)
	verify(not okWrongType3 and reason3 == "InvalidArguments", "SellItem('Pebble', NaN) rejected safely")

	local okExtraArgs, reason4 = Remotes.ValidateAndThrottle(testUserId, testName, "SellAllItems", fixedClock, "UnexpectedArg")
	verify(not okExtraArgs and reason4 == "InvalidArguments", "Extra unexpected argument rejected safely")

	local okWrongDir, reason5 = Remotes.ValidateAndThrottle(testUserId, testName, "MoundSpawned", fixedClock, {})
	verify(not okWrongDir and reason5 == "InvalidArguments", "Client calling ServerToClient remote rejected safely")

	local acceptedCount = 0
	local rateLimitedCount = 0
	for _ = 1, 8 do
		local allowed, rejectReason = Remotes.ValidateAndThrottle(testUserId, testName, "BuyShovel", fixedClock, "StoneShovel")
		if allowed then
			acceptedCount += 1
		elseif rejectReason == "RateLimitExceeded" then
			rateLimitedCount += 1
		end
	end
	verify(
		acceptedCount == 5 and rateLimitedCount == 3,
		"Spamming BuyShovel (8 calls in 1s, limit 5/s) accepts 5 and rate-limits 3",
		string.format("accepted=%d, limited=%d", acceptedCount, rateLimitedCount)
	)

	local summary = Remotes.GetViolationSummary(testUserId)
	verify(
		summary.TotalCount == 8 and (summary.ByReason["RateLimitExceeded"] or 0) == 3,
		"Violation log accurately recorded all 8 violations",
		string.format("total=%d, rateLimit=%d", summary.TotalCount, summary.ByReason["RateLimitExceeded"] or 0)
	)

	Remotes.ResetViolations(testUserId)
	print(string.format("[Step2Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 3 automated verification
local function runStep3Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step3Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step3Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	local userA = -900011
	local userB = -900012
	MoundService.ClearUserMounds(userA)
	MoundService.ClearUserMounds(userB)

	local t0 = 2000000
	local originA = Vector3.new(-20, 5, -20)
	local originB = Vector3.new(20, 5, 20)

	for _ = 1, 10 do
		MoundService.SpawnMoundForUser(userA, nil, originA, t0)
	end
	local countA = MoundService.GetActiveCount(userA)
	verify(
		countA == MoundsConfig.MaxActivePerPlayer,
		string.format("User A active mounds capped at %d", MoundsConfig.MaxActivePerPlayer),
		string.format("actual=%d", countA)
	)

	for _ = 1, 3 do
		MoundService.SpawnMoundForUser(userB, nil, originB, t0)
	end
	local countB = MoundService.GetActiveCount(userB)
	verify(countB == 3, "User B has 3 independent personal mounds", string.format("actual=%d", countB))

	local overlapFound = false
	local moundsA = MoundService.GetPlayerMounds(userA)
	local moundsB = MoundService.GetPlayerMounds(userB)
	for moundId in moundsA do
		if moundsB[moundId] ~= nil then
			overlapFound = true
		end
	end
	verify(not overlapFound, "2-player isolation: User A and User B mounds do not overlap")

	local spawnZone = workspace:FindFirstChild("Plain") and workspace.Plain:FindFirstChild("SpawnZone")
	local allInsideSpawnZone = true
	if spawnZone and spawnZone:IsA("BasePart") then
		local halfX = spawnZone.Size.X * 0.5
		local halfZ = spawnZone.Size.Z * 0.5
		for _, m in moundsA do
			if math.abs(m.Position.X - spawnZone.Position.X) > halfX or math.abs(m.Position.Z - spawnZone.Position.Z) > halfZ then
				allInsideSpawnZone = false
			end
		end
	else
		allInsideSpawnZone = false
	end
	verify(allInsideSpawnZone, "All spawned personal mounds landed inside Workspace.Plain.SpawnZone via raycast")

	local despawnedBefore = MoundService.CheckIdleDespawns(t0 + MoundsConfig.DespawnIdleSeconds - 1)
	verify(despawnedBefore == 0, "Mounds do not despawn before 3 minutes idle (179s)")

	local despawnedAt3Min = MoundService.CheckIdleDespawns(t0 + MoundsConfig.DespawnIdleSeconds)
	verify(
		despawnedAt3Min == 9 and MoundService.GetActiveCount(userA) == 0 and MoundService.GetActiveCount(userB) == 0,
		"All 9 idle mounds despawned after 3 minutes (180s)",
		string.format("despawned=%d", despawnedAt3Min)
	)

	local replacement = MoundService.SpawnMoundForUser(userA, nil, originA, t0 + MoundsConfig.DespawnIdleSeconds + 1)
	verify(replacement ~= nil and MoundService.GetActiveCount(userA) == 1, "Despawned idle mound can immediately be replaced")

	MoundService.ClearUserMounds(userA)
	MoundService.ClearUserMounds(userB)
	print(string.format("[Step3Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 4 automated verification (indicatorPos math, 8-stud range check, DigSpeed cooldown, Perfect/Good/Miss damage & counter tracking)
local function runStep4Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step4Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step4Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	-- 1. Verify indicatorPos formula
	local posCenter = Weighted.IndicatorPos(0.5, 1.0)
	local posBounce = Weighted.IndicatorPos(1.25, 1.0)
	verify(
		math.abs(posCenter - 0.5) < 1e-6 and math.abs(posBounce - 0.75) < 1e-6,
		"Deterministic indicatorPos(t, speed) matches PRD triangle wave formula"
	)

	local testUser = -900040
	MoundService.ClearUserMounds(testUser)
	DigService.CancelSession(testUser)

	local mound = MoundService.SpawnMoundForUser(testUser, nil, Vector3.new(0, 5, 0), 3000000)
	verify(mound ~= nil, "Spawned test mound for Step 4 strike testing")

	if mound then
		-- Force mound to Small (50 HP, Speed = 0.8, GoodWidth = 0.30, PerfectWidth = 0.10) for deterministic damage math
		mound.Size = "Small"
		mound.HP = 50
		mound.MaxHP = 50

		local speed = MoundsConfig.Sizes.Small.Timing.Speed -- 0.8
		local nearPos = mound.Position + Vector3.new(3, 0, 0) -- 3 studs away (<= 8 studs)
		local farPos = mound.Position + Vector3.new(12, 0, 0) -- 12 studs away (> 8 studs)
		local startTime = 5000.0

		-- 2. Out-of-range (> 8 studs) rejected
		local outOfRangeResult = DigService.ExecuteStrike(testUser, nil, mound.Id, startTime, farPos, 0)
		verify(
			not outOfRangeResult.Success and outOfRangeResult.Reason == "OutOfRange",
			"Strike outside 8 studs rejected with OutOfRange"
		)

		-- Start session at t = 5000.0 within range
		local okSession = DigService.StartSession(testUser, nil, mound.Id, startTime, nearPos)
		verify(okSession, "Dig session started within 8 studs")

		-- 3. Perfect strike: at elapsed = 0.5 / speed = 0.625s -> indicatorPos = 0.5 (center)
		local tPerfect = startTime + (0.5 / speed)
		local resPerfect = DigService.ExecuteStrike(testUser, nil, mound.Id, tPerfect, nearPos, 0)
		verify(
			resPerfect.Success and resPerfect.Grade == "Perfect" and resPerfect.Damage == 20 and mound.HP == 30,
			"Perfect strike deals 20 damage (10 Power * 2.0) and reduces HP 50 -> 30",
			string.format("grade=%s, dmg=%s, hp=%.1f", tostring(resPerfect.Grade), tostring(resPerfect.Damage), mound.HP)
		)

		-- 4. Cooldown check: strike 0.4s later (< 1.0s RustyShovel DigSpeed) must be ignored
		local resEarly = DigService.ExecuteStrike(testUser, nil, mound.Id, tPerfect + 0.4, nearPos, 0)
		verify(
			not resEarly.Success and resEarly.Reason == "Cooldown" and mound.HP == 30,
			"Strike before DigSpeed cooldown (0.4s < 1.0s) ignored"
		)

		-- 5. Good strike: after cooldown (>= 1.0s), pick t where pos = 0.40 (dist 0.10 from 0.5: outside Perfect 0.05, inside Good 0.15)
		-- For speed = 0.8, at elapsed = 2.0 / 0.8 = 2.5s -> x = 0; at elapsed = 2.4 / 0.8 = 3.0s -> x = 0.40
		local tGood = startTime + (2.40 / speed) -- elapsed = 3.0s, 2.375s after tPerfect (>= 1.0s cooldown)
		local resGood = DigService.ExecuteStrike(testUser, nil, mound.Id, tGood, nearPos, 0)
		verify(
			resGood.Success and resGood.Grade == "Good" and resGood.Damage == 10 and mound.HP == 20,
			"Good strike deals 10 damage (10 Power * 1.0) and reduces HP 30 -> 20",
			string.format("grade=%s, dmg=%s, hp=%.1f", tostring(resGood.Grade), tostring(resGood.Damage), mound.HP)
		)

		-- 6. Miss strike: at elapsed = 4.10 / speed = 5.125s -> pos = 0.10 (dist 0.40 from 0.5 -> Miss)
		local tMiss = startTime + (4.10 / speed)
		local resMiss = DigService.ExecuteStrike(testUser, nil, mound.Id, tMiss, nearPos, 0)
		verify(
			resMiss.Success and resMiss.Grade == "Miss" and resMiss.Damage == 2.5 and mound.HP == 17.5,
			"Miss strike deals 2.5 damage (10 Power * 0.25) and reduces HP 20 -> 17.5",
			string.format("grade=%s, dmg=%s, hp=%.1f", tostring(resMiss.Grade), tostring(resMiss.Damage), mound.HP)
		)

		-- 7. Verify Perfect/Good/Miss counters recorded on mound for Step 5 Timing Score
		verify(
			mound.PerfectCount == 1 and mound.GoodCount == 1 and mound.MissCount == 1,
			"Mound accurately recorded Perfect=1, Good=1, Miss=1 counts"
		)
	end

	MoundService.ClearUserMounds(testUser)
	DigService.CancelSession(testUser)
	print(string.format("[Step4Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 5 automated verification (Timing Score, Effective Luck cap <= 5.0, 100,000-roll Monte Carlo simulations, and mound clear drops)
local function runStep5Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step5Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step5Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	-- 1. Verify TimingScore = (Perfect + 0.5 * Good) / totalPlayerStrikes and EffectiveLuck = shovelLuck * (1 + 0.25 * Score)
	local scoreSample = DropService.ComputeTimingScore(2, 1, 1) -- (2 + 0.5) / 4 = 0.625
	local luckSample = DropService.ComputeEffectiveLuck(1.0, scoreSample, 0) -- 1.0 * (1 + 0.25 * 0.625) = 1.15625
	verify(
		math.abs(scoreSample - 0.625) < 1e-6 and math.abs(luckSample - 1.15625) < 1e-6,
		"TimingScore (2P, 1G, 1M -> 0.625) and EffectiveLuck (1.15625) match PRD formula"
	)

	-- 2. Verify EffectiveLuck never exceeds 5.0 cap
	local cappedLuck1 = DropService.ComputeEffectiveLuck(4.5, 1.0, 0) -- 4.5 * 1.25 = 5.625 -> capped at 5.0
	local cappedLuck2 = DropService.ComputeEffectiveLuck(10.0, 1.0, 0.5) -- capped at 5.0
	verify(
		cappedLuck1 == 5.0 and cappedLuck2 == 5.0 and cappedLuck1 <= MoundsConfig.MaxEffectiveLuck,
		"EffectiveLuck is strictly capped at 5.0 (never exceeds 5.0)"
	)

	-- 3, 4, 5. 100,000-roll simulation per mound size WITHOUT Luck (Luck = 1.0), tolerance +/- 1.0 percentage point
	local totalRolls = 100000
	for idx, sizeName in MoundsConfig.SizeOrder do
		local sim = DropService.SimulateRolls(sizeName, 1.0, totalRolls, 1000 + idx)
		local sizeCfg = MoundsConfig.Sizes[sizeName]
		local maxDiff = 0
		local parts: { string } = {}
		for _, rarityName in RarityConfig.Order do
			local actualPct = sim.RarityPercentages[rarityName] or 0
			local expectedPct = sizeCfg.RarityWeights[rarityName] or 0
			local diff = math.abs(actualPct - expectedPct)
			if diff > maxDiff then
				maxDiff = diff
			end
			table.insert(parts, string.format("%s=%.2f%%(exp %.1f%%)", rarityName, actualPct, expectedPct))
		end
		local eggActual = sim.DropTypePercentages.Egg or 0
		local eggExpected = sizeCfg.DropTypeWeights.Egg or 0
		local eggDiff = math.abs(eggActual - eggExpected)

		verify(
			maxDiff <= 1.0 and eggDiff <= 1.0,
			string.format(
				"100k rolls [%s, Luck 1.0] matches PRD 5.1 within +-1%% (maxDiff=%.2f%% | Egg=%.2f%% vs %.1f%% | %s)",
				sizeName,
				maxDiff,
				eggActual,
				eggExpected,
				table.concat(parts, ", ")
			),
			string.format("maxDiff=%.2f%%, eggDiff=%.2f%%", maxDiff, eggDiff)
		)
	end

	-- 6. 100,000-roll simulation for Small Mound at Luck = 2.2
	-- PRD target: Common ~54.6%, Uncommon ~25.0%, Rare ~12.0%, Epic ~6.6%, Legendary ~1.8%
	local prdLuck22Targets: { [string]: number } = {
		Common = 54.6,
		Uncommon = 25.0,
		Rare = 12.0,
		Epic = 6.6,
		Legendary = 1.8,
	}
	local simSmall22 = DropService.SimulateRolls("Small", 2.2, totalRolls, 202605)
	local maxDiff22 = 0
	local parts22: { string } = {}
	for _, rarityName in RarityConfig.Order do
		local actualPct = simSmall22.RarityPercentages[rarityName] or 0
		local targetPct = prdLuck22Targets[rarityName] or 0
		local diff = math.abs(actualPct - targetPct)
		if diff > maxDiff22 then
			maxDiff22 = diff
		end
		table.insert(parts22, string.format("%s=%.2f%%(target %.1f%%)", rarityName, actualPct, targetPct))
	end
	verify(
		maxDiff22 <= 1.0,
		string.format(
			"100k rolls [Small, Luck 2.2] matches PRD targets (54.6/25.0/12.0/6.6/1.8) within +-1%% (maxDiff=%.2f%% | %s)",
			maxDiff22,
			table.concat(parts22, ", ")
		),
		string.format("maxDiff=%.2f%%", maxDiff22)
	)

	-- 7. End-to-end MoundCleared -> DropService integration check
	local testUser = -900050
	MoundService.ClearUserMounds(testUser)
	DigService.CancelSession(testUser)

	local mound = MoundService.SpawnMoundForUser(testUser, nil, Vector3.new(0, 5, 0), 4000000)
	if mound then
		mound.Size = "Large" -- RollCount = 3
		mound.HP = 40
		mound.MaxHP = 400
		local speed = MoundsConfig.Sizes.Large.Timing.Speed
		local nearPos = mound.Position + Vector3.new(2, 0, 0)
		local startTime = 8000.0

		DigService.StartSession(testUser, nil, mound.Id, startTime, nearPos)
		-- 2 Perfect strikes (20 dmg each = 40 dmg -> clears mound)
		local tStrike1 = startTime + (0.5 / speed)
		local tStrike2 = startTime + (2.5 / speed) -- elapsed = 2.5 / 1.4 = 1.785s (> 1.0s cooldown), pos = 0.5 (Perfect)
		DigService.ExecuteStrike(testUser, nil, mound.Id, tStrike1, nearPos, 0)
		local finalOutcome = DigService.ExecuteStrike(testUser, nil, mound.Id, tStrike2, nearPos, 0)

		local summary = DropService.GetLastDropSummary(testUser)
		verify(
			finalOutcome.Cleared == true
				and summary ~= nil
				and #summary.Drops == 3
				and math.abs(summary.TimingScore - 1.0) < 1e-6
				and math.abs(summary.EffectiveLuck - 1.25) < 1e-6,
			"Clearing Large mound with 2/2 Perfect strikes triggers 3 drops with TimingScore=1.0 and EffectiveLuck=1.25"
		)
	else
		verify(false, "Spawned test mound for Step 5 clear integration")
	end

	MoundService.ClearUserMounds(testUser)
	DigService.CancelSession(testUser)
	print(string.format("[Step5Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Shovel Inventory & Hotbar Server Validation (PRD_Roblox_Inventory_Shovel)
local function runShovelInventoryVerification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[ShovelInventoryValidator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[ShovelInventoryValidator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	local ShovelsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Shovels"))
	local assetsRoot = ReplicatedStorage:FindFirstChild("ShovelAssets")
	local previewsFolder = assetsRoot and assetsRoot:FindFirstChild("ShovelPreviews")
	local uiPreviewsFolder = assetsRoot and assetsRoot:FindFirstChild("UIPreviews")
	local toolsFolder = assetsRoot and assetsRoot:FindFirstChild("ShovelTools")

	local allModelsValid = previewsFolder ~= nil and toolsFolder ~= nil and uiPreviewsFolder ~= nil
	if previewsFolder and toolsFolder and uiPreviewsFolder then
		if not uiPreviewsFolder:FindFirstChild("BagPreview") then
			allModelsValid = false
		end
		for _, id in ShovelsConfig.AllOrder do
			local prev = previewsFolder:FindFirstChild(id)
			local tool = toolsFolder:FindFirstChild(id)
			if not prev or not prev:IsA("Model") or prev:FindFirstChildWhichIsA("BaseScript", true) ~= nil then
				allModelsValid = false
			end
			if not tool or not tool:IsA("Tool") or not tool:FindFirstChild("Handle") then
				allModelsValid = false
			end
		end
	end
	verify(
		allModelsValid,
		"All 7 ShovelPreviews (script-free 3D Models), BagPreview, and 7 ShovelTools exist in ReplicatedStorage.ShovelAssets"
	)

	-- Profile ownership & equip security checks
	local testProfile = DataService.CreateDefaultProfile()
	verify(
		testProfile.Shovels.Equipped == "RustyShovel" and #testProfile.Shovels.Owned == 1,
		"New profile starts with RustyShovel owned and equipped"
	)

	local unownedAttempt = ShovelInventoryService.EquipShovelInProfile(testProfile, "DiamondShovel")
	verify(
		not unownedAttempt.Success
			and unownedAttempt.Reason == "NotOwned"
			and testProfile.Shovels.Equipped == "RustyShovel",
		"Equipping unowned DiamondShovel rejected with NotOwned and preserves RustyShovel active"
	)

	local invalidAttempt = ShovelInventoryService.EquipShovelInProfile(testProfile, "NonExistentShovel")
	verify(
		not invalidAttempt.Success
			and invalidAttempt.Reason == "InvalidShovel"
			and testProfile.Shovels.Equipped == "RustyShovel",
		"Equipping invalid shovel ID rejected safely"
	)

	table.insert(testProfile.Shovels.Owned, "IronShovel")
	table.insert(testProfile.Shovels.Owned, "GoldenShovel")
	local validEquip = ShovelInventoryService.EquipShovelInProfile(testProfile, "GoldenShovel")
	verify(
		validEquip.Success and testProfile.Shovels.Equipped == "GoldenShovel",
		"Equipping owned GoldenShovel succeeds and updates active shovel"
	)

	-- Corrupted profile self-healing check
	testProfile.Shovels.Equipped = "MoonlitShovel" -- not owned
	ShovelInventoryService.SanitizeProfileShovels(testProfile)
	verify(
		testProfile.Shovels.Equipped == "RustyShovel",
		"SanitizeProfileShovels resets unowned equipped shovel back to StartingShovel safely"
	)

	print(string.format("[ShovelInventoryValidator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 6 automated verification (Bag capacity, overflow on active mound, EggBag auto-sell, Merchant sell, Bag upgrade & rejoin persistence)
local function runStep6Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step6Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step6Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	-- 1. Verify Hub Merchant + 6 BasePlot Merchant ProximityPrompts exist
	local anchorCount = InventoryService.GetMerchantAnchorCount()
	verify(
		anchorCount >= 7,
		"Hub ItemMerchant and all 6 BasePlot Merchant ProximityPrompts exist in Workspace",
		string.format("anchorCount=%d", anchorCount)
	)

	local testUserId = -900060
	local sessionA = "Step6_SessionA"
	local sessionB = "Step6_SessionB"

	local okLoad, prof, errLoad = DataService.AcquireProfileLock(testUserId, sessionA, true)
	verify(okLoad and prof ~= nil, "Acquired Step 6 test profile in Session A", tostring(errLoad))

	if prof then
		-- Reset profile to clean starter baseline
		local fresh = DataService.CreateDefaultProfile()
		for k, v in fresh :: any do
			(prof :: any)[k] = v
		end

		-- 2. Bag capacity & overflow rule [U]: starts at 20; 20 items = full; in-progress mound drop #21 still enters
		verify(
			InventoryService.GetBagCapacity(prof) == 20 and not InventoryService.IsBagFull(prof),
			"Starter BagLevel 1 has capacity 20 and starts empty"
		)
		for _ = 1, 20 do
			InventoryService.AddDropToProfile(prof, {
				DropType = "Item",
				Id = "Pebble",
				DisplayName = "Pebble",
				Rarity = "Common",
				SellPrice = 10,
				AutoSold = false,
				AutoSoldCoins = 0,
			})
		end
		verify(
			InventoryService.GetBagItemCount(prof) == 20 and InventoryService.IsBagFull(prof),
			"Bag becomes full at 20/20 items"
		)

		-- Drop #21 from an already running mound still enters Items ([U])
		InventoryService.AddDropToProfile(prof, {
			DropType = "Item",
			Id = "SilverRing",
			DisplayName = "Silver Ring",
			Rarity = "Rare",
			SellPrice = 120,
			AutoSold = false,
			AutoSoldCoins = 0,
		})
		verify(
			InventoryService.GetBagItemCount(prof) == 21 and prof.Items.SilverRing == 1,
			"Drop from in-progress mound still enters bag past capacity (21/20) [U]"
		)

		-- 3. EggBag capacity (4 + BaseLevel = 5 at BaseLevel 1) & auto-sell on 6th egg
		for _ = 1, 5 do
			local eggDrop = {
				DropType = "Egg" :: "Egg",
				Id = "CommonEgg",
				DisplayName = "Common Egg",
				Rarity = "Common" :: "Common",
				SellPrice = 30,
				AutoSold = false,
				AutoSoldCoins = 0,
			}
			InventoryService.AddDropToProfile(prof, eggDrop)
		end
		local sixthEgg = {
			DropType = "Egg" :: "Egg",
			Id = "UncommonEgg",
			DisplayName = "Uncommon Egg",
			Rarity = "Uncommon" :: "Uncommon",
			SellPrice = 90,
			AutoSold = false,
			AutoSoldCoins = 0,
		}
		local coinsBeforeAutoSell = prof.Coins
		InventoryService.AddDropToProfile(prof, sixthEgg)
		verify(
			#prof.EggBag == 5
				and type(prof.EggBag[1]) == "table"
				and prof.EggBag[1].Id == "CommonEgg"
				and sixthEgg.AutoSold == true
				and sixthEgg.AutoSoldCoins == 90
				and prof.Coins == coinsBeforeAutoSell + 90,
			"EggBag holds 5 {Id, Rarity} eggs at BaseLevel 1 and auto-sells 6th UncommonEgg for +90 Coins"
		)

		-- 4. SellItem: partial sell & invalid/excess rejection
		local coinsBeforeSell = prof.Coins -- 190
		local sellPartial = InventoryService.SellItemInProfile(prof, "Pebble", 5) -- 5 * 10 = 50
		local rejectExcess = InventoryService.SellItemInProfile(prof, "SilverRing", 2) -- only 1 owned
		verify(
			sellPartial.Success
				and sellPartial.CoinsEarned == 50
				and prof.Items.Pebble == 15
				and prof.Coins == coinsBeforeSell + 50
				and not rejectExcess.Success
				and rejectExcess.Reason == "InsufficientQuantity",
			"SellItem sells 5x Pebble (+50 Coins) at server Config price and rejects excess count"
		)

		-- 5. Insufficient coins for UpgradeBag rejected without negative Coins
		-- Current Coins = 240, Level 2 UpgradeCost = 300 -> must reject!
		local failUpgrade = InventoryService.UpgradeBagInProfile(prof)
		verify(
			not failUpgrade.Success
				and failUpgrade.Reason == "InsufficientCoins"
				and prof.BagLevel == 1
				and prof.Coins == 240
				and prof.Coins >= 0,
			"UpgradeBag rejects when Coins (240) < Cost (300) and never makes Coins negative"
		)

		-- 6. SellAllItems: 15x Pebble (150) + 1x SilverRing (120) = +270 Coins -> total 510 Coins, bag empty
		local sellAll = InventoryService.SellAllItemsInProfile(prof)
		verify(
			sellAll.Success
				and sellAll.SoldCount == 16
				and sellAll.CoinsEarned == 270
				and prof.Coins == 510
				and InventoryService.GetBagItemCount(prof) == 0,
			"SellAllItems clears all 16 remaining items and awards exact +270 Coins (total 510)"
		)

		-- 7. UpgradeBag 1 -> 2 (cost 300 -> remaining 210 Coins, capacity 40) & persistence across rejoin
		local okUpgrade = InventoryService.UpgradeBagInProfile(prof)
		verify(
			okUpgrade.Success
				and prof.BagLevel == 2
				and InventoryService.GetBagCapacity(prof) == 40
				and prof.Coins == 210,
			"UpgradeBag upgrades BagLevel 1 -> 2 (Capacity 40) for 300 Coins (210 remaining)"
		)

		local okSave = DataService.SaveProfileSession(testUserId, sessionA, prof, true)
		local okRejoin, profRejoin = DataService.AcquireProfileLock(testUserId, sessionB, true)
		verify(
			okSave
				and okRejoin
				and profRejoin ~= nil
				and profRejoin.BagLevel == 2
				and InventoryService.GetBagCapacity(profRejoin) == 40
				and profRejoin.Coins == 210,
			"Upgraded BagLevel 2 (Capacity 40) and Coins (210) persist across rejoin"
		)

		if profRejoin then
			DataService.SaveProfileSession(testUserId, sessionB, DataService.CreateDefaultProfile(), true)
		end
	end

	print(string.format("[Step6Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 7 automated verification (Shop catalog, non-sequential BuyShovel [U], NotForSale/InsufficientCoins/AlreadyOwned checks, live Power/DigSpeed/EffectiveLuck changes on switch, and rejoin persistence)
local function runStep7Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step7Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step7Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	-- 1. Shop catalog (5 shop shovels) + 2 special non-shop shovels + Hub ShovelShop ProximityPrompt
	local catalog = ShopService.GetShopCatalog()
	local expectedPrices = { 0, 400, 2500, 12000, 50000 }
	local catalogMatches = (#catalog == 5)
	for idx, shopId in ShovelsConfig.ShopOrder do
		local entry = catalog[idx]
		if not entry or entry.Id ~= shopId or entry.Price ~= expectedPrices[idx] or not entry.IsShopShovel then
			catalogMatches = false
		end
	end
	local mossyCfg = ShovelsConfig.All.MossyShovel
	local moonlitCfg = ShovelsConfig.All.MoonlitShovel
	local specialsValid = mossyCfg ~= nil
		and not mossyCfg.IsShopShovel
		and mossyCfg.Power == 75
		and math.abs(mossyCfg.DigSpeed - 0.65) < 1e-6
		and math.abs(mossyCfg.Luck - 2.0) < 1e-6
		and moonlitCfg ~= nil
		and not moonlitCfg.IsShopShovel
		and moonlitCfg.Power == 140
		and math.abs(moonlitCfg.DigSpeed - 0.55) < 1e-6
		and math.abs(moonlitCfg.Luck - 2.5) < 1e-6
	verify(
		catalogMatches and specialsValid and ShopService.GetShopAnchorCount() >= 1,
		"ShopService lists 5 shop shovels (0/400/2500/12000/50000), excludes Mossy & Moonlit specials, and anchors Hub ShovelShop prompt",
		string.format("catalog=%d, anchors=%d", #catalog, ShopService.GetShopAnchorCount())
	)

	local testUserId = -900070
	local sessionA = "Step7_SessionA"
	local sessionB = "Step7_SessionB"

	local okLoad, prof, errLoad = DataService.AcquireProfileLock(testUserId, sessionA, true)
	verify(okLoad and prof ~= nil, "Acquired Step 7 test profile in Session A", tostring(errLoad))

	if prof then
		local fresh = DataService.CreateDefaultProfile()
		for k, v in fresh :: any do
			(prof :: any)[k] = v
		end

		-- 2. Special shovels (MossyShovel, MoonlitShovel) rejected from ShopService.BuyShovelInProfile
		local buyMossy = ShopService.BuyShovelInProfile(prof, "MossyShovel", true)
		local buyMoonlit = ShopService.BuyShovelInProfile(prof, "MoonlitShovel", true)
		verify(
			not buyMossy.Success
				and buyMossy.Reason == "NotForSale"
				and not buyMoonlit.Success
				and buyMoonlit.Reason == "NotForSale"
				and #prof.Shovels.Owned == 1,
			"MossyShovel and MoonlitShovel cannot be purchased in ShopService (NotForSale)"
		)

		-- 3. Insufficient Coins rejected without negative Coins (100 < 400 for StoneShovel)
		local buyBroke = ShopService.BuyShovelInProfile(prof, "StoneShovel", true)
		verify(
			not buyBroke.Success
				and buyBroke.Reason == "InsufficientCoins"
				and prof.Coins == 100
				and prof.Coins >= 0
				and table.find(prof.Shovels.Owned, "StoneShovel") == nil,
			"BuyShovel rejects when Coins (100) < Price (400) and never makes Coins negative"
		)

		-- 4. Non-sequential purchase [U]: buy GoldenShovel (12,000) directly without owning StoneShovel or IronShovel
		prof.Coins = 13000
		local buyGolden = ShopService.BuyShovelInProfile(prof, "GoldenShovel", true)
		local buyGoldenAgain = ShopService.BuyShovelInProfile(prof, "GoldenShovel", true)
		verify(
			buyGolden.Success
				and buyGolden.PricePaid == 12000
				and prof.Coins == 1000
				and prof.Shovels.Equipped == "GoldenShovel"
				and table.find(prof.Shovels.Owned, "GoldenShovel") ~= nil
				and table.find(prof.Shovels.Owned, "StoneShovel") == nil
				and table.find(prof.Shovels.Owned, "IronShovel") == nil
				and not buyGoldenAgain.Success
				and buyGoldenAgain.Reason == "AlreadyOwned"
				and prof.Coins == 1000,
			"Out-of-order purchase [U] of GoldenShovel (12,000) succeeds without Stone/Iron and rejects duplicate purchase"
		)

		-- 5. Buy StoneShovel (400) -> 600 Coins remaining
		local buyStone = ShopService.BuyShovelInProfile(prof, "StoneShovel", false)
		verify(
			buyStone.Success
				and buyStone.PricePaid == 400
				and prof.Coins == 600
				and table.find(prof.Shovels.Owned, "StoneShovel") ~= nil
				and prof.Shovels.Equipped == "GoldenShovel",
			"Purchased StoneShovel (400 Coins -> 600 remaining) while keeping GoldenShovel equipped when autoEquip=false"
		)

		-- 6. Switching shovels immediately updates Power (damage), DigSpeed (cooldown), and Luck (EffectiveLuck)
		MoundService.ClearUserMounds(testUserId)
		DigService.CancelSession(testUserId)

		local mound = MoundService.SpawnMoundForUser(testUserId, nil, Vector3.new(0, 5, 0), 7000000)
		if mound then
			mound.Size = "Small" -- Speed = 0.8
			mound.HP = 500
			mound.MaxHP = 500

			local speed = MoundsConfig.Sizes.Small.Timing.Speed -- 0.8
			local nearPos = mound.Position + Vector3.new(2, 0, 0)
			local t0 = 12000.0
			DigService.StartSession(testUserId, nil, mound.Id, t0, nearPos)

			-- Create a synthetic cleared-mound template with 1/1 Perfect strike (TimingScore = 1.0 -> x1.25 Luck)
			local luckProbeMound: MoundService.MoundInstance = {
				Id = "Step7_LuckProbe",
				OwnerUserId = testUserId,
				Size = "Small",
				Position = mound.Position,
				HP = 0,
				MaxHP = 50,
				SpawnedAt = t0,
				LastInteractedAt = t0,
				PerfectCount = 1,
				GoodCount = 0,
				MissCount = 0,
			}

			-- 6a. Equip RustyShovel (Power=10, DigSpeed=1.0s, Luck=1.0)
			ShovelInventoryService.EquipShovelInProfile(prof, "RustyShovel")
			local tRusty = t0 + (0.5 / speed) -- pos = 0.5 (Perfect)
			local hitRusty = DigService.ExecuteStrike(testUserId, nil, mound.Id, tRusty, nearPos, 0, prof)
			local cdRusty = DigService.ExecuteStrike(testUserId, nil, mound.Id, tRusty + 0.75, nearPos, 0, prof)
			local dropRusty = DropService.ProcessClearedMound(nil, testUserId, luckProbeMound, Random.new(701), prof)

			-- 6b. Switch to StoneShovel (Power=18, DigSpeed=0.9s, Luck=1.2)
			ShovelInventoryService.EquipShovelInProfile(prof, "StoneShovel")
			local tStone = t0 + (2.5 / speed) -- 2.5s after tRusty, pos = 0.5 (Perfect)
			local hitStone = DigService.ExecuteStrike(testUserId, nil, mound.Id, tStone, nearPos, 0, prof)
			local cdStone = DigService.ExecuteStrike(testUserId, nil, mound.Id, tStone + 0.75, nearPos, 0, prof)
			local dropStone = DropService.ProcessClearedMound(nil, testUserId, luckProbeMound, Random.new(702), prof)

			-- 6c. Switch to GoldenShovel (Power=60, DigSpeed=0.7s, Luck=1.85)
			ShovelInventoryService.EquipShovelInProfile(prof, "GoldenShovel")
			local tGolden = t0 + (4.5 / speed) -- 2.5s after tStone, pos = 0.5 (Perfect)
			local hitGolden = DigService.ExecuteStrike(testUserId, nil, mound.Id, tGolden, nearPos, 0, prof)
			-- 0.75s after tGolden MUST SUCCEED because GoldenShovel DigSpeed is 0.70s!
			local fastFollowGolden = DigService.ExecuteStrike(testUserId, nil, mound.Id, tGolden + 0.75, nearPos, 0, prof)
			-- 0.50s after fastFollowGolden MUST REJECT because 0.50s < 0.70s!
			local cdGolden = DigService.ExecuteStrike(testUserId, nil, mound.Id, tGolden + 0.75 + 0.50, nearPos, 0, prof)
			local dropGolden = DropService.ProcessClearedMound(nil, testUserId, luckProbeMound, Random.new(703), prof)

			verify(
				hitRusty.Success
					and hitRusty.Damage == 20
					and hitStone.Success
					and hitStone.Damage == 36
					and hitGolden.Success
					and hitGolden.Damage == 120,
				"Switching shovel immediately changes Perfect strike damage (Rusty=20 -> Stone=36 -> Golden=120)",
				string.format(
					"rusty=%s, stone=%s, golden=%s",
					tostring(hitRusty.Damage),
					tostring(hitStone.Damage),
					tostring(hitGolden.Damage)
				)
			)

			verify(
				not cdRusty.Success
					and cdRusty.Reason == "Cooldown"
					and not cdStone.Success
					and cdStone.Reason == "Cooldown"
					and fastFollowGolden.Success
					and not cdGolden.Success
					and cdGolden.Reason == "Cooldown",
				"Switching shovel immediately changes DigSpeed cooldown (0.75s blocked on Rusty 1.0s & Stone 0.9s, allowed on Golden 0.7s)"
			)

			verify(
				math.abs(dropRusty.EffectiveLuck - 1.25) < 1e-6
					and math.abs(dropStone.EffectiveLuck - 1.50) < 1e-6
					and math.abs(dropGolden.EffectiveLuck - 2.3125) < 1e-6,
				"Switching shovel immediately changes EffectiveLuck at Score=1.0 (Rusty=1.25 -> Stone=1.50 -> Golden=2.3125)",
				string.format(
					"rusty=%.4f, stone=%.4f, golden=%.4f",
					dropRusty.EffectiveLuck,
					dropStone.EffectiveLuck,
					dropGolden.EffectiveLuck
				)
			)
		else
			verify(false, "Spawned test mound for Step 7 shovel stat switching")
		end

		MoundService.ClearUserMounds(testUserId)
		DigService.CancelSession(testUserId)

		-- 7. Persistence across rejoin
		local okSave = DataService.SaveProfileSession(testUserId, sessionA, prof, true)
		local okRejoin, profRejoin = DataService.AcquireProfileLock(testUserId, sessionB, true)
		verify(
			okSave
				and okRejoin
				and profRejoin ~= nil
				and profRejoin.Coins == 600
				and profRejoin.Shovels.Equipped == "GoldenShovel"
				and #profRejoin.Shovels.Owned == 3
				and table.find(profRejoin.Shovels.Owned, "RustyShovel") ~= nil
				and table.find(profRejoin.Shovels.Owned, "StoneShovel") ~= nil
				and table.find(profRejoin.Shovels.Owned, "GoldenShovel") ~= nil,
			"Owned shovels (Rusty, Stone, Golden), Equipped (GoldenShovel), and Coins (600) persist across rejoin"
		)

		if profRejoin then
			DataService.SaveProfileSession(testUserId, sessionB, DataService.CreateDefaultProfile(), true)
		end
	end

	print(string.format("[Step7Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 8 automated verification (Base plot assignment, BaseLevel upgrades, incubator placement, speed-up cost, offline incubation, 100k hatch simulation, pet bag limit, and egg selling)
local function runStep8Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step8Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step8Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	-- 1. 100,000-roll Monte Carlo hatch simulation per egg type (without Luck, Luck = 1.0)
	local eggExpectedRarities: { [string]: { [Types.RarityName]: number } } = {
		CommonEgg = { Common = 80, Uncommon = 17, Rare = 2.5, Epic = 0.4, Legendary = 0.1 },
		UncommonEgg = { Common = 35, Uncommon = 50, Rare = 12, Epic = 2.5, Legendary = 0.5 },
		RareEgg = { Common = 10, Uncommon = 30, Rare = 45, Epic = 13, Legendary = 2.0 },
		EpicEgg = { Common = 0, Uncommon = 15, Rare = 35, Epic = 42, Legendary = 8.0 },
		LegendaryEgg = { Common = 0, Uncommon = 0, Rare = 25, Epic = 50, Legendary = 25.0 },
	}

	local totalSimRolls = 100000
	for eggId, expectedTable in eggExpectedRarities do
		local simReport = EggService.SimulateHatches(eggId, 1.0, totalSimRolls, 10080)
		local maxDiff = 0
		local parts: { string } = {}
		for _, rarityName in RarityConfig.Order do
			local actualPct = simReport.RarityPercentages[rarityName] or 0
			local expPct = expectedTable[rarityName] or 0
			local diff = math.abs(actualPct - expPct)
			if diff > maxDiff then
				maxDiff = diff
			end
			table.insert(parts, string.format("%s=%.2f%%(exp %.1f%%)", rarityName, actualPct, expPct))
		end

		verify(
			maxDiff <= 1.0,
			string.format("100k hatches [%s] matches PRD 7.1 table within +-1%% (maxDiff=%.2f%% | %s)", eggId, maxDiff, table.concat(parts, ", ")),
			string.format("maxDiff=%.2f%%", maxDiff)
		)
	end

	-- 2. 100,000 variant simulation (Normal 94%, Golden 5%, Shiny 1% -- TANPA Luck per PRD)
	local variantSim = EggService.SimulateHatches("CommonEgg", 1.0, totalSimRolls, 20088)
	local normalPct = variantSim.VariantPercentages.Normal or 0
	local goldenPct = variantSim.VariantPercentages.Golden or 0
	local shinyPct = variantSim.VariantPercentages.Shiny or 0
	local normalDiff = math.abs(normalPct - 94.0)
	local goldenDiff = math.abs(goldenPct - 5.0)
	local shinyDiff = math.abs(shinyPct - 1.0)
	verify(
		normalDiff <= 0.6 and goldenDiff <= 0.4 and shinyDiff <= 0.3,
		string.format("100k variant rolls match Normal 94%% (actual %.2f%%), Golden 5%% (actual %.2f%%), Shiny 1%% (actual %.2f%%)", normalPct, goldenPct, shinyPct),
		string.format("normDiff=%.2f, goldDiff=%.2f, shinyDiff=%.2f", normalDiff, goldenDiff, shinyDiff)
	)

	-- 3. Base plot assignment & upgrade profile logic
	local testUserId = -900080
	local sessionA = "Step8_SessionA"
	local sessionB = "Step8_SessionB"

	local okLoad, prof, errLoad = DataService.AcquireProfileLock(testUserId, sessionA, true)
	verify(okLoad and prof ~= nil, "Acquired Step 8 test profile in Session A", tostring(errLoad))

	if prof then
		local fresh = DataService.CreateDefaultProfile()
		for k, v in fresh :: any do
			(prof :: any)[k] = v
		end

		-- Verify initial BaseLevel 1 configuration
		verify(
			prof.BaseLevel == 1 and EggService.GetMaxIncubatorSlots(prof.BaseLevel) == 1,
			"Profile starts at BaseLevel 1 with exactly 1 incubator slot"
		)

		-- UpgradeBase with insufficient coins rejected without negative coins
		prof.Coins = 100 -- cost to Lv.2 is 800
		local failUpgrade = BaseService.UpgradeBaseInProfile(prof)
		verify(
			not failUpgrade.Success
				and failUpgrade.Reason == "InsufficientCoins"
				and prof.BaseLevel == 1
				and prof.Coins == 100
				and prof.Coins >= 0,
			"UpgradeBase rejects when Coins (100) < Cost (800) and never makes Coins negative"
		)

		-- UpgradeBase Lv.1 -> Lv.2 with 1500 Coins succeeds (cost 800 -> 700 remaining)
		prof.Coins = 1500
		local okUpgrade = BaseService.UpgradeBaseInProfile(prof)
		verify(
			okUpgrade.Success
				and okUpgrade.NewBaseLevel == 2
				and okUpgrade.IncubatorSlots == 2
				and okUpgrade.PetSlots == 4
				and okUpgrade.CostPaid == 800
				and prof.Coins == 700,
			"UpgradeBase upgrades Lv.1 -> Lv.2 (2 IncubatorSlots, 4 PetSlots) for 800 Coins (700 remaining)"
		)

		-- 4. Place egg in incubator
		local commonEgg: Types.EggBagEntry = { Id = "CommonEgg", Rarity = "Common" }
		local uncommonEgg: Types.EggBagEntry = { Id = "UncommonEgg", Rarity = "Uncommon" }
		table.insert(prof.EggBag, commonEgg) -- index 1
		table.insert(prof.EggBag, uncommonEgg) -- index 2

		-- Slot 3 is invalid at BaseLevel 2 (max slots = 2)
		local placeInvalid = EggService.PlaceEggInIncubatorInProfile(prof, 1, 3)
		verify(
			not placeInvalid.Success and placeInvalid.Reason == "InvalidSlot",
			"Placing egg into slot 3 at BaseLevel 2 rejected with InvalidSlot"
		)

		local t0 = 5000000
		local placeSlot1 = EggService.PlaceEggInIncubatorInProfile(prof, 1, 1, t0)
		verify(
			placeSlot1.Success
				and placeSlot1.EggId == "CommonEgg"
				and placeSlot1.ReadyAt == t0 + 60
				and prof.Incubators[1] ~= nil
				and prof.Incubators[1].ReadyAt == t0 + 60
				and #prof.EggBag == 1,
			"Placing CommonEgg into incubator slot 1 sets ReadyAt = t0 + 60s and removes egg from EggBag"
		)

		-- Attempting to place another egg into slot 1 rejected with SlotOccupied
		local placeOccupied = EggService.PlaceEggInIncubatorInProfile(prof, 1, 1, t0)
		verify(
			not placeOccupied.Success and placeOccupied.Reason == "SlotOccupied",
			"Placing another egg into occupied slot 1 rejected with SlotOccupied"
		)

		-- 5. Speed-up cost math per PRD: math.ceil(remainingSec / 60) * rate
		-- CommonEgg: 60s total, rate = 25 C/min
		-- At t = t0 + 10 (50s remaining -> 1 min -> cost = 25)
		local cost50s = EggService.ComputeSpeedUpCost(prof.Incubators[1], t0 + 10)
		verify(cost50s == 25, "Speed-up cost with 50s remaining on CommonEgg is exactly 25 Coins")

		-- SpeedUp with insufficient coins rejected
		local coinsBeforeSpeedUp = prof.Coins -- 700
		prof.Coins = 10
		local failSpeedUp = EggService.SpeedUpIncubatorInProfile(prof, 1, t0 + 10)
		verify(
			not failSpeedUp.Success and failSpeedUp.Reason == "InsufficientCoins" and prof.Coins == 10,
			"SpeedUp rejects when Coins (10) < Cost (25) and never makes Coins negative"
		)

		-- SpeedUp with enough coins succeeds and immediately sets ReadyAt = now
		prof.Coins = coinsBeforeSpeedUp
		local okSpeedUp = EggService.SpeedUpIncubatorInProfile(prof, 1, t0 + 10)
		verify(
			okSpeedUp.Success
				and okSpeedUp.CostPaid == 25
				and okSpeedUp.CoinsRemaining == 675
				and prof.Incubators[1].ReadyAt == t0 + 10,
			"SpeedUp pays 25 Coins (675 remaining) and sets incubator ReadyAt = now"
		)

		-- 6. Offline incubation persistence:
		-- Place UncommonEgg (180s) in slot 2 at t0 = 5000000 -> ReadyAt = 5000180
		local placeSlot2 = EggService.PlaceEggInIncubatorInProfile(prof, 1, 2, t0)
		verify(placeSlot2.Success and placeSlot2.ReadyAt == t0 + 180, "Placed UncommonEgg into slot 2 (ReadyAt = t0 + 180s)")

		-- Save in Session A, rejoin in Session B at t = t0 + 200s (player was offline while incubation finished)
		local okSave = DataService.SaveProfileSession(testUserId, sessionA, prof, true)
		local okRejoin, profRejoin = DataService.AcquireProfileLock(testUserId, sessionB, true)
		local tRejoin = t0 + 200
		verify(
			okSave
				and okRejoin
				and profRejoin ~= nil
				and profRejoin.Incubators[2] ~= nil
				and profRejoin.Incubators[2].ReadyAt == t0 + 180
				and tRejoin >= profRejoin.Incubators[2].ReadyAt,
			"Offline incubation persists across rejoin: egg ReadyAt is preserved and egg is ready to hatch"
		)

		if profRejoin then
			-- 7. Hatching checks:
			-- 7a. Pet Bag full limit (max 60)
			for i = 1, PetsConfig.MaxPetBagCapacity do
				profRejoin.Pets["Pet_Test_" .. i] = {
					Species = "Dog",
					Variant = "Normal",
					Level = 1,
				}
			end
			local failHatchFull = EggService.HatchIncubatorInProfile(profRejoin, 2, tRejoin)
			verify(
				not failHatchFull.Success and failHatchFull.Reason == "PetBagFull",
				"Hatching when Pet Bag is full (60/60) rejected with PetBagFull"
			)

			-- Remove 1 pet (59/60) and hatch slot 2
			profRejoin.Pets["Pet_Test_60"] = nil
			local okHatch = EggService.HatchIncubatorInProfile(profRejoin, 2, tRejoin, 1.0, Random.new(999))
			verify(
				okHatch.Success
					and type(okHatch.PetGuid) == "string"
					and type(okHatch.Species) == "string"
					and type(okHatch.Variant) == "string"
					and profRejoin.Pets[okHatch.PetGuid :: string] ~= nil
					and profRejoin.Index.Pets[okHatch.Species :: string] == true
					and profRejoin.Incubators[2] == nil,
				"Hatching ready slot 2 creates PetInstance in Pets, registers species in Index, and clears incubator slot"
			)

			-- 8. Egg selling from EggBag
			local rareEgg: Types.EggBagEntry = { Id = "RareEgg", Rarity = "Rare" }
			table.insert(profRejoin.EggBag, rareEgg)
			local coinsBeforeSell = profRejoin.Coins
			local okSellEgg = EggService.SellEggInProfile(profRejoin, #profRejoin.EggBag)
			verify(
				okSellEgg.Success
					and okSellEgg.CoinsEarned == EggsConfig.All.RareEgg.SellPrice
					and profRejoin.Coins == coinsBeforeSell + EggsConfig.All.RareEgg.SellPrice
					and #profRejoin.EggBag == 0,
				"Selling RareEgg from EggBag awards exact Config SellPrice (+280 Coins) and removes egg"
			)

			-- Clean up test profile
			DataService.SaveProfileSession(testUserId, sessionB, DataService.CreateDefaultProfile(), true)
		end
	end

	print(string.format("[Step8Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 9 automated verification (Pet Bag UI logic, equip limits, base assignments, release prices, attack loop DPS, range checks, and multi-player stability)
local function runStep9Verification()
	local passed = 0
	local failed = 0

	local function verify(cond: boolean, label: string, detail: string?)
		if cond then
			passed += 1
			print(string.format("[Step9Validator] PASS: %s", label))
		else
			failed += 1
			warn(string.format("[Step9Validator] FAIL: %s (%s)", label, detail or "assertion failed"))
		end
	end

	-- 1. Effective Stats calculation
	local dogNormal = PetService.GetEffectiveStats("Dog", "Normal", 1)
	verify(
		dogNormal.Power == 5 and dogNormal.DigSpeed == 2 and math.abs(dogNormal.AttackInterval - 2.5) < 0.001 and dogNormal.MoveSpeed == 10 and dogNormal.ReleasePrice == 25,
		"Normal Dog stats: Power=5, DigSpeed=2, Interval=2.5s, MoveSpeed=10, Release=25C"
	)

	local dogGolden = PetService.GetEffectiveStats("Dog", "Golden", 1)
	verify(
		dogGolden.Power == 7 and dogGolden.DigSpeed == 3 and math.abs(dogGolden.AttackInterval - 2.25) < 0.001,
		"Golden Dog stats: Power=floor(5*1.5)=7, DigSpeed=2+1=3, Interval=2.25s"
	)

	local dogShiny = PetService.GetEffectiveStats("Dog", "Shiny", 1)
	verify(
		dogShiny.Power == 11 and dogShiny.DigSpeed == 4 and math.abs(dogShiny.AttackInterval - 2.0) < 0.001,
		"Shiny Dog stats: Power=floor(5*2.25)=11, DigSpeed=2+2=4, Interval=2.0s"
	)

	local dragonShiny = PetService.GetEffectiveStats("TerraDragon", "Shiny", 1)
	verify(
		dragonShiny.DigSpeed == 10 and math.abs(dragonShiny.AttackInterval - 0.5) < 0.001 and dragonShiny.Power == math.floor(140 * 2.25),
		"Shiny TerraDragon: DigSpeed clamped to max 10, Interval=0.5s, Power=315"
	)

	-- 2. Acquire test profile in isolated session
	local testUserId = -900090
	local sessionA = "TestSessionStep9A"
	local okAcquire, profileA, errA = DataService.AcquireProfileLock(testUserId, sessionA, true)
	verify(okAcquire and profileA ~= nil, "Acquired Step 9 test profile in Session A", tostring(errA))

	if profileA then
		-- Clean slate
		profileA.Coins = 100
		profileA.TotalCoinsEarned = 100
		profileA.BaseLevel = 1
		profileA.Pets = {
			["Pet_Dog_1"] = { Species = "Dog", Variant = "Normal", Level = 1 },
			["Pet_Cat_2"] = { Species = "Cat", Variant = "Golden", Level = 1 },
			["Pet_Mole_3"] = { Species = "Mole", Variant = "Shiny", Level = 1 },
			["Pet_Fox_4"] = { Species = "Fox", Variant = "Normal", Level = 1 },
			["Pet_Rare_5"] = { Species = "Armadillo", Variant = "Normal", Level = 1 },
		}
		profileA.EquippedPets = {}
		profileA.BasePets = {}

		verify(#profileA.EquippedPets == 0 and #profileA.BasePets == 0, "Profile starts with 0 equipped and 0 base pets")

		-- Equip pet 1, 2, 3
		local eq1 = PetService.EquipPetInProfile(profileA, "Pet_Dog_1")
		local eq2 = PetService.EquipPetInProfile(profileA, "Pet_Cat_2")
		local eq3 = PetService.EquipPetInProfile(profileA, "Pet_Mole_3")
		verify(
			eq1.Success and eq2.Success and eq3.Success and #profileA.EquippedPets == 3,
			"Equipped 3 pets successfully (Dog, Cat, Mole)"
		)

		-- Equip 4th pet -> reject (max 3)
		local eq4 = PetService.EquipPetInProfile(profileA, "Pet_Fox_4")
		verify(not eq4.Success and eq4.Reason == "MaxEquippedReached", "Equipping 4th pet rejected with MaxEquippedReached")

		-- Duplicate equip -> reject
		local eqDup = PetService.EquipPetInProfile(profileA, "Pet_Dog_1")
		verify(not eqDup.Success and eqDup.Reason == "AlreadyEquipped", "Duplicate pet equip rejected with AlreadyEquipped")

		-- Unequip pet 3
		local ueq3 = PetService.UnequipPetInProfile(profileA, "Pet_Mole_3")
		verify(ueq3.Success and #profileA.EquippedPets == 2 and not table.find(profileA.EquippedPets, "Pet_Mole_3"), "Unequipped Pet_Mole_3 (2 remaining)")

		-- Base assignment: cannot assign equipped pet to Base
		local bEqReject = PetService.AssignBasePetInProfile(profileA, "Pet_Dog_1")
		verify(not bEqReject.Success and bEqReject.Reason == "PetEquipped", "Assigning equipped pet to Base rejected with PetEquipped")

		-- Assign free pet to Base (Base Lv.1 max 2 slots)
		local b1 = PetService.AssignBasePetInProfile(profileA, "Pet_Mole_3")
		local b2 = PetService.AssignBasePetInProfile(profileA, "Pet_Fox_4")
		verify(b1.Success and b2.Success and #profileA.BasePets == 2, "Assigned 2 free pets to Base (Mole, Fox)")

		-- Base full (2/2) -> reject 3rd
		local bFull = PetService.AssignBasePetInProfile(profileA, "Pet_Rare_5")
		verify(not bFull.Success and bFull.Reason == "BaseSlotsFull", "Assigning 3rd pet at BaseLevel 1 rejected with BaseSlotsFull")

		-- Cannot equip pet currently in Base
		local eqBaseReject = PetService.EquipPetInProfile(profileA, "Pet_Mole_3")
		verify(not eqBaseReject.Success and eqBaseReject.Reason == "PetInBase", "Equipping pet currently in Base rejected with PetInBase")

		-- Remove pet from Base
		local bRem = PetService.RemoveBasePetInProfile(profileA, "Pet_Mole_3")
		verify(bRem.Success and #profileA.BasePets == 1, "Removed Pet_Mole_3 from Base (1 remaining in Base)")

		-- Release Pet for Coins:
		-- Releasing equipped pet rejected
		local relEqReject = PetService.ReleasePetInProfile(profileA, "Pet_Dog_1")
		verify(not relEqReject.Success and relEqReject.Reason == "PetEquipped", "Releasing equipped pet rejected with PetEquipped")

		-- Releasing base pet rejected
		local relBaseReject = PetService.ReleasePetInProfile(profileA, "Pet_Fox_4")
		verify(not relBaseReject.Success and relBaseReject.Reason == "PetInBase", "Releasing base pet rejected with PetInBase")

		-- Releasing free Common pet awards 25 Coins
		local coinsBefore = profileA.Coins
		local relDog = PetService.ReleasePetInProfile(profileA, "Pet_Mole_3")
		verify(
			relDog.Success and relDog.CoinsEarned == 25 and profileA.Coins == coinsBefore + 25 and profileA.Pets["Pet_Mole_3"] == nil,
			"Releasing Common Mole awards exact 25 Coins (PRD 8.5) and removes from Pets"
		)

		-- Releasing free Rare pet awards 250 Coins
		local coinsBeforeRare = profileA.Coins
		local relRare = PetService.ReleasePetInProfile(profileA, "Pet_Rare_5")
		verify(
			relRare.Success and relRare.CoinsEarned == 250 and profileA.Coins == coinsBeforeRare + 250 and profileA.Pets["Pet_Rare_5"] == nil,
			"Releasing Rare Armadillo awards exact 250 Coins (PRD 8.5) and removes from Pets"
		)

		-- Save and test persistence across rejoin
		DataService.SaveProfileSession(testUserId, sessionA, profileA, true)

		local sessionB = "TestSessionStep9B"
		local okRejoin, profileB, errB = DataService.AcquireProfileLock(testUserId, sessionB, true)
		verify(okRejoin and profileB ~= nil, "Acquired profile on rejoin in Session B", tostring(errB))
		if profileB then
			verify(
				#profileB.EquippedPets == 2 and profileB.EquippedPets[1] == "Pet_Dog_1" and profileB.EquippedPets[2] == "Pet_Cat_2",
				"EquippedPets persisted across rejoin (Dog & Cat)"
			)
			verify(
				#profileB.BasePets == 1 and profileB.BasePets[1] == "Pet_Fox_4",
				"BasePets persisted across rejoin (Fox)"
			)
			verify(
				profileB.Coins == coinsBeforeRare + 250,
				"Coins from released pets persisted across rejoin"
			)
			DataService.SaveProfileSession(testUserId, sessionB, DataService.CreateDefaultProfile(), true)
		end
	end

	-- 3. Pet Attack & DPS verification with DigService
	local dpsUserId = -900091
	local sessionDps = "TestSessionStep9DPS"
	local okDpsAcquire, profileDps, errDps = DataService.AcquireProfileLock(dpsUserId, sessionDps, true)
	verify(okDpsAcquire and profileDps ~= nil, "Acquired Step 9 DPS test profile", tostring(errDps))

	if profileDps then
		-- Give equipped pet: Dog (Power 5, DigSpeed 2 -> Interval 2.5s, Range 16 studs)
		profileDps.Pets = {
			["Pet_Attacker_1"] = { Species = "Dog", Variant = "Normal", Level = 1 },
		}
		profileDps.EquippedPets = { "Pet_Attacker_1" }

		-- Clear user mounds & create a test mound within range (e.g. dist = 5 studs)
		MoundService.ClearUserMounds(dpsUserId)
		local spawnMound = MoundService.SpawnMoundForUser(dpsUserId, nil, Vector3.new(5, 0, 0), 9000000)
		assert(spawnMound, "Failed to spawn test mound for DPS test")
		spawnMound.Size = "Small"
		spawnMound.HP = 100
		spawnMound.MaxHP = 100

		local initialHP = spawnMound.HP
		local dogStats = PetService.GetEffectiveStats("Dog", "Normal", 1)

		-- Test direct Pet damage application via DigService.ApplyPetDamage
		local okDmg, remHP, cleared = DigService.ApplyPetDamage(nil, dpsUserId, spawnMound.Id, dogStats.Power, "Pet_Attacker_1")
		verify(
			okDmg and remHP == (initialHP - dogStats.Power) and not cleared,
			string.format("Pet damage deducted exact Power (%.1f -> %.1f, remaining %.1f)", initialHP, dogStats.Power, remHP)
		)

		-- Test finishing off mound when HP drops to 0
		local finishDmg = remHP
		local okFinish, finalHP, finalCleared = DigService.ApplyPetDamage(nil, dpsUserId, spawnMound.Id, finishDmg, "Pet_Attacker_1")
		verify(
			okFinish and finalHP == 0 and finalCleared and MoundService.GetMound(dpsUserId, spawnMound.Id) == nil,
			"Pet strike finishing off mound clears and despawns mound cleanly"
		)

		MoundService.ClearUserMounds(dpsUserId)
		DataService.SaveProfileSession(dpsUserId, sessionDps, DataService.CreateDefaultProfile(), true)
	end

	-- 4. Multi-player stability check: 12 simulated players x 3 pets = 36 equipped pets
	local startBenchmark = os.clock()
	for p = 1, 12 do
		for petIdx = 1, 3 do
			local stats = PetService.GetEffectiveStats("Cat", "Golden", 1)
			assert(stats.Power > 0 and stats.AttackInterval > 0)
		end
	end
	local elapsedMs = (os.clock() - startBenchmark) * 1000
	verify(elapsedMs < 10.0, string.format("12 players x 3 pets (36 pets) stat evaluations executed in %.3f ms (< 10 ms)", elapsedMs))

	print(string.format("[Step9Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

local function runStep10Verification()
	local passed = 0
	local failed = 0
	local function verify(cond: boolean, name: string)
		if cond then
			passed += 1
			print(string.format("[Step10Validator] PASS: %s", name))
		else
			failed += 1
			warn(string.format("[Step10Validator] FAIL: %s", name))
		end
	end

	-- 1. Manual calculation for 3 example pets (PRD: "satu Common, satu Epic Golden, satu Legendary Shiny")
	-- Common: Dog Lv 1 Normal: BaseIncome 3 * (1 + 0) * 1.0 = 3
	local dogIncome = PassiveIncomeService.CalculatePetIncome("Dog", "Normal", 1)
	verify(dogIncome == 3, string.format("Common Dog Lv.1 Normal income is exactly 3 Coin/s (got %d)", dogIncome))

	-- Epic: CrystalFox Lv 1 Golden: BaseIncome 60 * (1 + 0) * 1.5 = 90
	local foxIncome = PassiveIncomeService.CalculatePetIncome("CrystalFox", "Golden", 1)
	verify(foxIncome == 97, string.format("Epic CrystalFox Lv.1 Golden income is exactly 97 Coin/s (got %d)", foxIncome))

	-- Legendary: TerraDragon Lv 1 Shiny: BaseIncome 160 * (1 + 0) * 2.25 = 360
	local dragonIncome = PassiveIncomeService.CalculatePetIncome("TerraDragon", "Shiny", 1)
	verify(dragonIncome == 360, string.format("Legendary TerraDragon Lv.1 Shiny income is exactly 360 Coin/s (got %d)", dragonIncome))

	-- Total of 3 pets: 3 + 90 + 360 = 453
	local testProfile = DataService.CreateDefaultProfile()
	testProfile.Pets = {
		Pet1 = { Species = "Dog", Variant = "Normal", Level = 1 },
		Pet2 = { Species = "CrystalFox", Variant = "Golden", Level = 1 },
		Pet3 = { Species = "TerraDragon", Variant = "Shiny", Level = 1 },
	}
	testProfile.BasePets = { "Pet1", "Pet2", "Pet3" }
	local combinedIncome = PassiveIncomeService.CalculatePlayerIncome(testProfile)
	verify(combinedIncome == 460, string.format("Combined base pets income is exactly 460 Coin/s (3 + 97 + 360 = 460, got %d)", combinedIncome))

	-- 2. Level income scaling: income dasar * (1 + 0.20 * (level - 1)) * variantMult
	-- Dog Lv.2 = floor(3 * 1.2 * 1.0) = 3
	-- Dog Lv.6 = floor(3 * 2.0 * 1.0) = 6
	local dogLv6 = PassiveIncomeService.CalculatePetIncome("Dog", "Normal", 6)
	verify(dogLv6 == 6, string.format("Dog Lv.6 Normal income scales to 6 Coin/s (got %d)", dogLv6))

	-- CrystalFox Lv.2 Golden = floor(60 * 1.2 * 1.5) = 108
	local foxLv2 = PassiveIncomeService.CalculatePetIncome("CrystalFox", "Golden", 2)
	verify(foxLv2 == 117, string.format("CrystalFox Lv.2 Golden income is exactly 117 Coin/s (got %d)", foxLv2))

	-- TerraDragon Lv.5 Shiny = floor(160 * 1.8 * 2.25) = 648
	local dragonLv5 = PassiveIncomeService.CalculatePetIncome("TerraDragon", "Shiny", 5)
	verify(dragonLv5 == 648, string.format("TerraDragon Lv.5 Shiny income is exactly 648 Coin/s (got %d)", dragonLv5))

	-- 3. Level up cost calculations: baseCost * (1.2 ^ (level - 1))
	-- Common base 40: Lv.1 -> 40, Lv.2 -> floor(40 * 1.2) = 48
	local costDog1 = PassiveIncomeService.GetLevelUpCost("Dog", 1)
	local costDog2 = PassiveIncomeService.GetLevelUpCost("Dog", 2)
	verify(costDog1 == 40 and costDog2 == 48, string.format("Common level up costs: Lv.1->2 = 40 (got %s), Lv.2->3 = 48 (got %s)", tostring(costDog1), tostring(costDog2)))

	-- Epic base 900: Lv.1 -> 900, Lv.2 -> floor(900 * 1.2) = 1080
	local costFox1 = PassiveIncomeService.GetLevelUpCost("CrystalFox", 1)
	local costFox2 = PassiveIncomeService.GetLevelUpCost("CrystalFox", 2)
	verify(costFox1 == 900 and costFox2 == 1080, string.format("Epic level up costs: Lv.1->2 = 900 (got %s), Lv.2->3 = 1080 (got %s)", tostring(costFox1), tostring(costFox2)))

	-- Legendary base 2500: Lv.1 -> 2500
	local costDragon1 = PassiveIncomeService.GetLevelUpCost("TerraDragon", 1)
	verify(costDragon1 == 2500, string.format("Legendary level up cost: Lv.1->2 = 2500 (got %s)", tostring(costDragon1)))

	-- Max level cap 20: returns MaxLevelReached
	local costMax, maxErr = PassiveIncomeService.GetLevelUpCost("Dog", 20)
	verify(costMax == nil and maxErr == "MaxLevelReached", "Level up cost at max Lv.20 returns nil and MaxLevelReached")

	-- 4. Level up transaction execution
	local p = DataService.CreateDefaultProfile()
	p.Coins = 50
	p.Pets = {
		Pet_Dog = { Species = "Dog", Variant = "Normal", Level = 1 },
	}

	-- Insufficient coins check
	p.Coins = 10 -- needs 40
	local resFail = PassiveIncomeService.LevelUpPetInProfile(p, "Pet_Dog")
	verify(not resFail.Success and resFail.ErrorReason == "InsufficientCoins" and p.Coins == 10 and p.Pets.Pet_Dog.Level == 1, "Level up rejected when Coins < Cost without modifying coins or level")

	-- Successful level up
	p.Coins = 100
	local resOk = PassiveIncomeService.LevelUpPetInProfile(p, "Pet_Dog")
	verify(resOk.Success and resOk.NewLevel == 2 and p.Coins == 60 and p.Pets.Pet_Dog.Level == 2, "Level up Lv.1->2 succeeds, deducts exact 40 Coins (100 -> 60), and sets Level = 2")

	-- Level up does not change Power, Speed, DigSpeed, or Range (PRD: "Level tidak mengubah Power, Speed, Dig Speed, dan Range.")
	local dogStatsLv1 = PetService.GetEffectiveStats("Dog", "Normal", 1)
	local dogStatsLv2 = PetService.GetEffectiveStats("Dog", "Normal", 2)
	verify(
		dogStatsLv1.Power == dogStatsLv2.Power
			and dogStatsLv1.Speed == dogStatsLv2.Speed
			and dogStatsLv1.DigSpeed == dogStatsLv2.DigSpeed
			and dogStatsLv1.Range == dogStatsLv2.Range
			and dogStatsLv1.AttackInterval == dogStatsLv2.AttackInterval,
		"Pet leveling does NOT change Power, Speed, DigSpeed, Range, or AttackInterval"
	)

	-- 5. Offline income calculation (PRD: "Offline 1 jam menghasilkan tepat 10% dari income aktif, dengan batas 12 jam.")
	local activeRate = 100 -- 100 Coins/sec
	local t0 = 1000000

	-- 1 hour offline = 3600s
	-- 3600 * 100 * 0.10 = 36000
	-- Active income for 1 hr would be 3600 * 100 = 360000. 36000 is exactly 10%!
	local off1Hr = PassiveIncomeService.CalculateOfflineIncome(t0, t0 + 3600, activeRate)
	verify(
		off1Hr.OfflineSeconds == 3600
			and off1Hr.CappedSeconds == 3600
			and off1Hr.CoinsEarned == 36000,
		string.format("Offline 1 hour produces exactly 10%% of active income (%d Coins)", off1Hr.CoinsEarned)
	)

	-- 12 hours offline = 43200s (cap)
	-- 43200 * 100 * 0.10 = 432000
	local off12Hr = PassiveIncomeService.CalculateOfflineIncome(t0, t0 + 43200, activeRate)
	verify(
		off12Hr.CappedSeconds == 43200
			and off12Hr.CoinsEarned == 432000,
		string.format("Offline 12 hours produces exactly 10%% capped at 12 hours (%d Coins)", off12Hr.CoinsEarned)
	)

	-- 24 hours offline = 86400s -> capped to 43200s (12 hours)
	local off24Hr = PassiveIncomeService.CalculateOfflineIncome(t0, t0 + 86400, activeRate)
	verify(
		off24Hr.OfflineSeconds == 86400
			and off24Hr.CappedSeconds == 43200
			and off24Hr.CoinsEarned == 432000,
		string.format("Offline 24 hours is clamped to 12 hours max (%d Coins, same as 12 hr)", off24Hr.CoinsEarned)
	)

	-- Offline under 60 seconds produces 0
	local off30s = PassiveIncomeService.CalculateOfflineIncome(t0, t0 + 30, activeRate)
	verify(off30s.CoinsEarned == 0, "Offline under 60 seconds awards 0 Coins")

	-- 6. Equipped pets do not produce base passive income (only BasePets do)
	local equipOnlyProfile = DataService.CreateDefaultProfile()
	equipOnlyProfile.Pets = {
		Pet_Equipped = { Species = "TerraDragon", Variant = "Shiny", Level = 1 },
	}
	equipOnlyProfile.EquippedPets = { "Pet_Equipped" }
	equipOnlyProfile.BasePets = {}
	local equipIncome = PassiveIncomeService.CalculatePlayerIncome(equipOnlyProfile)
	verify(equipIncome == 0, "Pets equipped on avatar produce 0 base passive income")

	print(string.format("[Step10Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

-- Step 11 automated verification: Gundukan Langka (shared), concurrent digging, and contribution rewards
local function runStep11Verification()
	local passed = 0
	local failed = 0

	local function verify(condition: boolean, testName: string)
		if condition then
			passed += 1
			print(string.format("[Step11Validator] PASS: %s", testName))
		else
			failed += 1
			warn(string.format("[Step11Validator] FAIL: %s", testName))
		end
	end

	print("[Step11Validator] Starting Gundukan Langka (Shared Mound) verification...")

	-- 1. Shared Mound Config verification
	local sharedCfg = MoundsConfig.Shared
	verify(sharedCfg.SpawnIntervalSeconds == 720, "Spawn interval is 12 minutes (720 seconds)")
	verify(sharedCfg.DurationSeconds == 240, "Mound duration is 4 minutes (240 seconds)")
	verify(sharedCfg.HP == 3000, "Shared mound max HP is exactly 3,000")
	verify(sharedCfg.MinContributionRatio == 0.03, "Minimum contribution threshold is 3% (0.03)")
	verify(sharedCfg.Timing.Speed == 1.6, "Shared mound timing speed is 1.6")
	verify(sharedCfg.Timing.GoodWidth == 0.18, "Shared mound Good zone width is 0.18")
	verify(sharedCfg.Timing.PerfectWidth == 0.05, "Shared mound Perfect zone width is 0.05")
	verify(sharedCfg.EggRarityWeights.Common == 0, "Egg drops Common weight is 0 (minimal Uncommon)")
	verify(sharedCfg.RewardLuckMultiplier == 1.5, "Reward luck multiplier is 1.5x")
	verify(sharedCfg.SpecialShovelDropChances.MossyShovel == 0.005, "Mossy Shovel chance is 0.5% (0.005)")
	verify(sharedCfg.SpecialShovelDropChances.MoonlitShovel == 0.002, "Moonlit Shovel chance is 0.2% (0.002)")

	-- 2. Spawn Points
	local spawnPoints = SharedMoundService.GetSpawnPoints()
	verify(#spawnPoints >= 5, string.format("Workspace has %d spawn points (at least 5 required)", #spawnPoints))

	-- Clean up any prior active mound before testing
	SharedMoundService.DespawnSharedMound("TestReset")

	-- 3. Spawning Shared Mound
	local t0 = 1000
	local spawnedMound = SharedMoundService.SpawnSharedMound(1, t0)
	verify(spawnedMound ~= nil, "SpawnSharedMound returned a valid instance")
	if spawnedMound then
		verify(spawnedMound.HP == 3000 and spawnedMound.MaxHP == 3000, "Spawned mound initialized with 3,000 HP")
		verify(spawnedMound.ExpiresAt == t0 + 240, "Spawned mound expires in 240 seconds (at t=1240)")
		verify(spawnedMound.Scale == Vector3.new(12, 6, 12), "Spawned mound scale is (12, 6, 12)")
		verify(SharedMoundService.IsSharedMound(spawnedMound.Id), "IsSharedMound returns true for active mound ID")

		-- 4. Out of range vs in-range strike session
		local moundPos = spawnedMound.Position
		local farPos = moundPos + Vector3.new(30, 0, 0)
		local nearPos = moundPos + Vector3.new(10, 0, 0) -- 10 studs from center, within 14 allowed studs

		local okFar, errFar = SharedMoundService.StartSession(2001, nil, spawnedMound.Id, t0, farPos)
		verify(okFar == false and errFar == "OutOfRange", "StartSession rejected when avatar is out of range (30 studs)")

		local okNear, _, sessionNear = SharedMoundService.StartSession(2001, nil, spawnedMound.Id, t0, nearPos)
		verify(okNear == true and sessionNear ~= nil, "StartSession accepted within interaction range (10 studs)")

		-- 5. Multiplayer concurrent digging & damage tracking
		-- Player 1 (UserId 2001) with Iron Shovel (Power 32)
		local ironProfile = DataService.CreateDefaultProfile()
		ironProfile.Shovels.Owned = { "RustyShovel", "IronShovel" }
		ironProfile.Shovels.Equipped = "IronShovel"

		-- Player 2 (UserId 2002) with Stone Shovel (Power 18)
		local stoneProfile = DataService.CreateDefaultProfile()
		stoneProfile.Shovels.Owned = { "RustyShovel", "StoneShovel" }
		stoneProfile.Shovels.Equipped = "StoneShovel"

		-- Start session for Player 2
		SharedMoundService.StartSession(2002, nil, spawnedMound.Id, t0, nearPos)

		-- Strike 1: Player 1 strikes at t=1000 with Iron Shovel, Perfect grade (multiplier 2.0 -> 64 damage)
		local strike1 = SharedMoundService.ExecuteStrike(
			2001,
			nil,
			spawnedMound.Id,
			t0,
			nearPos,
			0.20,
			ironProfile
		)
		verify(strike1.Success == true, "Player 1 strike succeeded")
		verify(spawnedMound.HP == (3000 - strike1.Damage), string.format("Shared Mound HP reduced to %.1f after strike 1", spawnedMound.HP))
		verify(spawnedMound.Contributions[2001] == strike1.Damage, "Player 1 damage recorded in contributions")

		-- Strike 2: Player 2 strikes at t=1000.5 with Stone Shovel, Good grade
		local strike2 = SharedMoundService.ExecuteStrike(
			2002,
			nil,
			spawnedMound.Id,
			t0 + 0.5,
			nearPos,
			0.20,
			stoneProfile
		)
		verify(strike2.Success == true, "Player 2 concurrent strike succeeded")
		verify(spawnedMound.Contributions[2002] == strike2.Damage, "Player 2 damage recorded independently in contributions")

		-- 6. Pet Damage on Shared Mound
		local prePetHP = spawnedMound.HP
		local petDmg = 50
		local okPet, remPetHP = SharedMoundService.ApplyPetDamage(nil, 2001, "Pet_Test_Guid", petDmg)
		verify(okPet == true, "Pet damage applied successfully to shared mound")
		verify(spawnedMound.HP == prePetHP - petDmg, "Shared mound HP deducted by pet damage")
		verify(spawnedMound.Contributions[2001] == (strike1.Damage + petDmg), "Pet damage added to owner's contribution")

		-- 7. Contribution Threshold Rewards (< 3% vs >= 3%)
		-- 3% of 3000 is 90 damage.
		-- Give Player 2003 exactly 89 damage (2.97% < 3% threshold)
		-- Give Player 2004 exactly 90 damage (3.00% >= 3% threshold)
		-- Give Player 2005 exactly 1500 damage (50.00%, top contributor)
		spawnedMound.Contributions[2003] = 89
		spawnedMound.Contributions[2004] = 90
		spawnedMound.Contributions[2005] = 1500

		local dummyProfile = DataService.CreateDefaultProfile()
		local deterministicRng = Random.new(12345)

		-- User 2003 (< 3%): calculate rewards gives nil or skipped by distribution
		local minThreshold = spawnedMound.MaxHP * MoundsConfig.Shared.MinContributionRatio
		verify(spawnedMound.Contributions[2003] < minThreshold, "Player 2003 dealt 89 damage (< 90 / 3% min threshold)")
		verify(spawnedMound.Contributions[2004] >= minThreshold, "Player 2004 dealt 90 damage (>= 90 / 3% min threshold)")

		-- Verify Reward Roll contents for eligible non-top contributor (Player 2004)
		local rewardSummary2004 = SharedMoundService.CalculateRewardsForUser(
			2004,
			"Player2004",
			dummyProfile,
			90,
			3000,
			false,
			deterministicRng
		)
		verify(#rewardSummary2004.EggDrops == 2, string.format("Eligible contributor receives exactly 2 egg rolls (got %d)", #rewardSummary2004.EggDrops))
		verify(#rewardSummary2004.ItemDrops == 1, string.format("Eligible contributor receives exactly 1 item roll (got %d)", #rewardSummary2004.ItemDrops))
		verify(rewardSummary2004.IsTopContributor == false, "Player 2004 is correctly marked not top contributor")

		-- Verify minimum rarity for eggs (no Common egg)
		local hasCommonEgg = false
		for _, eggDrop in ipairs(rewardSummary2004.EggDrops) do
			if eggDrop.Rarity == "Common" then
				hasCommonEgg = true
			end
		end
		verify(hasCommonEgg == false, "Egg drops contain NO Common eggs (all eggs are >= Uncommon)")

		-- Verify Top Contributor receives +1 bonus egg roll (3 total)
		local rewardSummary2005 = SharedMoundService.CalculateRewardsForUser(
			2005,
			"Player2005",
			dummyProfile,
			1500,
			3000,
			true,
			deterministicRng
		)
		verify(#rewardSummary2005.EggDrops == 3, string.format("Top contributor receives 3 egg rolls (2 base + 1 bonus, got %d)", #rewardSummary2005.EggDrops))
		verify(#rewardSummary2005.ItemDrops == 1, "Top contributor receives 1 item roll")
		verify(rewardSummary2005.IsTopContributor == true, "Player 2005 is correctly marked top contributor")

		-- 8. Idempotency & Clean Completion
		spawnedMound.HP = 0
		SharedMoundService.CompleteSharedMound(spawnedMound, deterministicRng)
		verify(spawnedMound.Cleared == true, "Shared mound marked Cleared after CompleteSharedMound")
		verify(spawnedMound.RewardDistributed == true, "RewardDistributed flag set to true")
		verify(SharedMoundService.GetActiveMound() == nil, "Active shared mound is cleared (nil) after completion")

		-- Calling CompleteSharedMound again is a safe no-op
		local doubleCallOk = pcall(function()
			SharedMoundService.CompleteSharedMound(spawnedMound, deterministicRng)
		end)
		verify(doubleCallOk == true, "Second completion call is a safe no-op (no double rewards)")
	end

	-- 9. Despawn clean state
	SharedMoundService.DespawnSharedMound("Expired")
	verify(SharedMoundService.GetActiveMound() == nil, "GetActiveMound is nil after despawn")

	print(string.format("[Step11Validator] SUMMARY: %d passed, %d failed.", passed, failed))
end

task.spawn(function()
	runStep1Verification()
	runStep2Verification()
	runStep3Verification()
	runStep4Verification()
	runStep5Verification()
	runShovelInventoryVerification()
	runStep6Verification()
	runStep7Verification()
	runStep8Verification()
	runStep9Verification()
	runStep10Verification()
	runStep11Verification()
end)
