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

Remotes.EnsureAll()
DataService.Start()
PlayerState.Start()
InventoryService.Start()
ShovelInventoryService.Start()
ShopService.Start()
BaseService.Start()
EggService.Start()
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
				"100k rolls [%s, Luck 1.0] matches PRD 5.1 within ±1%% (maxDiff=%.2f%% | Egg=%.2f%% vs %.1f%% | %s)",
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
			"100k rolls [Small, Luck 2.2] matches PRD targets (54.6/25.0/12.0/6.6/1.8) within ±1%% (maxDiff=%.2f%% | %s)",
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
			string.format("100k hatches [%s] matches PRD 7.1 table within ±1%% (maxDiff=%.2f%% | %s)", eggId, maxDiff, table.concat(parts, ", ")),
			string.format("maxDiff=%.2f%%", maxDiff)
		)
	end

	-- 2. 100,000 variant simulation (Normal 94%, Golden 5%, Shiny 1% — TANPA Luck per PRD)
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
end)
