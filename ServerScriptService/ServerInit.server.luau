--!strict
-- Main server bootstrapper for Dig Pals (Steps 1-5: DataService, PlayerState, Remotes, MoundService, DigService, DropService)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local MoundsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mounds"))
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("Rarity"))
local Remotes = require(Shared:WaitForChild("Util"):WaitForChild("Remotes"))
local Weighted = require(Shared:WaitForChild("Util"):WaitForChild("Weighted"))

local ServicesFolder = ServerScriptService:WaitForChild("Services")
local DataService = require(ServicesFolder:WaitForChild("DataService"))
local PlayerState = require(ServicesFolder:WaitForChild("PlayerState"))
local InventoryService = require(ServicesFolder:WaitForChild("InventoryService"))
local MoundService = require(ServicesFolder:WaitForChild("MoundService"))
local ShovelInventoryService = require(ServicesFolder:WaitForChild("ShovelInventoryService"))
local DigService = require(ServicesFolder:WaitForChild("DigService"))
local DropService = require(ServicesFolder:WaitForChild("DropService"))

Remotes.EnsureAll()
DataService.Start()
PlayerState.Start()
InventoryService.Start()
ShovelInventoryService.Start()
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

task.spawn(function()
	runStep1Verification()
	runStep2Verification()
	runStep3Verification()
	runStep4Verification()
	runStep5Verification()
	runShovelInventoryVerification()
	runStep6Verification()
end)
