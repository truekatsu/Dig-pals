--!strict
-- Run deliberately in Studio via execute_luau; leaves player profiles and shared mound state alone.
local Shared = game:GetService("ReplicatedStorage").Shared
local Services = game:GetService("ServerScriptService").Services
local Timing = require(Shared.Util.DigTiming)
local Weighted = require(Shared.Util.Weighted)
local Dig = require(Services.DigService)
local Mounds = require(Services.MoundService)
local uid = -990091001
local checks: { [string]: boolean } = {}
local function check(name: string, value: boolean)
	checks[name] = value
	assert(value, name)
end
local ok, err = pcall(function()
	local ids = { "RustyShovel", "StoneShovel", "IronShovel", "GoldenShovel", "MossyShovel", "DiamondShovel", "MoonlitShovel" }
	local speed, misses = math.huge, 0
	for _, id in ids do
		local attempt = Timing.New(id, "Small", 1000)
		check(id .. "Difficulty", attempt.Speed < speed and attempt.MaxMisses > misses)
		speed, misses = attempt.Speed, attempt.MaxMisses
	end
	check("MovedPerfectGrade", Weighted.GradeAtPosition(0.75, 0.3, 0.1, 0.75) == "Perfect")
	check("OldCenterMisses", Weighted.GradeAtPosition(0.5, 0.3, 0.1, 0.75) == "Miss")
	local center = 0.5
	for _ = 1, 100 do
		local nextCenter = Timing.NextZone(center, 0.3)
		assert(nextCenter >= 0.19 and nextCenter <= 0.81 and math.abs(nextCenter - center) >= 0.1599)
		center = nextCenter
	end
	check("RandomZoneBoundsAndMovement", true)
	local mound = Mounds.SpawnMoundForUser(uid, nil, Vector3.new(-80, 3, 0), 1000)
	assert(mound, "No valid grass spawn for fixture")
	mound.HP, mound.MaxHP = 1000, 1000
	local started, _, session = Dig.StartSession(uid, nil, mound.Id, 1000, mound.Position)
	assert(started and session)
	local function nextTime(position: number): number
		local phase = position / session.Attempt.Speed
		local period = 2 / session.Attempt.Speed
		local earliest = math.max(session.StartTime, session.LastStrikeTime + 1.01)
		local cycles = math.max(0, math.ceil((earliest - session.StartTime - phase) / period))
		return session.StartTime + phase + cycles * period
	end
	session.Attempt.ZoneCenter = 0.75
	local perfectTime = nextTime(0.75)
	local first = Dig.ExecuteStrike(uid, nil, mound.Id, perfectTime, mound.Position, 0)
	check("PerfectProgress", first.Grade == "Perfect" and mound.HP < mound.MaxHP)
	local previous = session.Attempt.ZoneCenter
	local blocked = Dig.ExecuteStrike(uid, nil, mound.Id, perfectTime + 0.01, mound.Position, 0)
	check("CooldownNoSideEffects", not blocked.Success and blocked.Reason == "Cooldown"
		and session.Attempt.ZoneCenter == previous and session.Attempt.Misses == 0)
	for i = 1, 3 do
		local hp = mound.HP
		local outcome = Dig.ExecuteStrike(uid, nil, mound.Id, nextTime(0), mound.Position, 0)
		check("Miss" .. i .. "NoDamage", outcome.Grade == "Miss" and outcome.Damage == 0)
		if i < 3 then
			check("Miss" .. i .. "PreservesProgress", mound.HP == hp)
		else
			check("FailureResetsProgress", outcome.Failed == true and mound.HP == mound.MaxHP
				and mound.MissCount == 0 and mound.PerfectCount == 0 and mound.GoodCount == 0)
		end
	end
	check("QueuedStrikesBlocked", Dig.ExecuteStrike(uid, nil, mound.Id, session.LastStrikeTime + 4, mound.Position, 0).Reason == "DigFailed")
	check("PetsCannotBypassFailure", not Dig.ApplyPetDamage(nil, uid, mound.Id, 10, "QA_Pet"))
	local _, _, retry = Dig.StartSession(uid, nil, mound.Id, session.LastStrikeTime + 4, mound.Position)
	assert(retry)
	session = retry
	check("RetryFromZero", session.Attempt.Misses == 0 and not session.Attempt.Failed
		and not mound.DigFailed and mound.HP == mound.MaxHP)
	Dig.ExecuteStrike(uid, nil, mound.Id, nextTime(0), mound.Position, 0)
	Dig.CancelSession(uid)
	local _, _, resumed = Dig.StartSession(uid, nil, mound.Id, session.LastStrikeTime + 4, mound.Position)
	check("CancelPreservesMisses", resumed ~= nil and resumed.Attempt.Misses == 1)
end)
Dig.CancelSession(uid)
Mounds.ClearUserMounds(uid)
return { Pass = ok, Error = if ok then "" else tostring(err), Checks = checks }
