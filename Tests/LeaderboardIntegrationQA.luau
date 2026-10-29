--!nonstrict
-- Run manually through Studio's command bar/MCP during Play.
-- Exercises the live-server branch with an isolated fake OrderedDataStore.
-- Never calls Start(), writes real DataStores, or sends leaderboard events to clients.
return function()
	local services = game.ServerScriptService.Services
	local player = game.Players:GetPlayers()[1]
	assert(player, "A connected player is required")
	local profile = require(services.DataService).CreateDefaultProfile()
	local suffix = game:GetService("HttpService"):GenerateGUID(false):gsub("-", "")
	local provider = Instance.new("ModuleScript")
	provider.Name = "QAOrderedStore_" .. suffix
	provider.Source = [=[
local fake = { Budget = 100, FailReads = false, Writes = 0, Values = {} }
function fake:GetRequestBudgetForRequestType() return self.Budget end
function fake:GetOrderedDataStore(name)
 self.Values[name] = self.Values[name] or { ["900000001"] = 12000, ["900000002"] = 6000 }
 local owner, values = self, self.Values[name]
 return {
  GetSortedAsync = function(_, ascending, limit)
   assert(not ascending, "Rankings must sort descending")
   if owner.FailReads then error("Injected read outage") end
   local page = {}
   for key, value in pairs(values) do table.insert(page, { key = key, value = value }) end
   table.sort(page, function(a,b) return a.value > b.value end)
   while #page > limit do table.remove(page) end
   return { GetCurrentPage = function() return page end }
  end,
  SetAsync = function(_, key, value) values[key] = value owner.Writes += 1 end,
  UpdateAsync = function(_, key, transform) values[key] = transform(values[key]) owner.Writes += 1 end,
 }
end
return fake
]=]
	provider.Parent = services
	local sandbox = services.LeaderboardService:Clone()
	sandbox.Name = "QALeaderboard_" .. suffix
	local source = sandbox.Source
	source = source:gsub('local DataStoreService = game:GetService%("DataStoreService"%)', 'local DataStoreService = require(script.Parent["' .. provider.Name .. '"])', 1)
	source = source:gsub('local usingMemoryFallback = RunService:IsStudio%(%)', 'local usingMemoryFallback = false', 1)
	source = source:gsub('local PlayerState = require%(script.Parent:WaitForChild%("PlayerState"%)%)', 'local PlayerState = { Get = function() return require(script.Parent["' .. provider.Name .. '"]).Profile end }', 1)
	source = source:gsub('local Remotes = require%(Shared:WaitForChild%("Util"%):WaitForChild%("Remotes"%)%)', 'local Remotes = { GetEvent = function() return { FireAllClients = function() end } end }', 1)
	sandbox.Source = "local warn = function() end\n" .. source
	sandbox.Parent = services
	local ok, result = xpcall(function()
		local fake = require(provider)
		fake.Profile = profile
		local service = require(sandbox)
		assert(service.GetNextRefreshTime(0) == 900, "Refresh interval must be 15 minutes")
		assert(service.GetNextRefreshTime(899) == 900, "Refreshes must align across servers")
		assert(service.GetNextRefreshTime(900) == 1800, "A boundary must schedule the following quarter hour")
		assert(service.GetNextRefreshTime(3599) == 3600, "Hour rollover must stay aligned")
		service.ResolvePlayerName = function(id) return "Offline_" .. id end
		local first = service.RefreshLeaderboards()
		assert(first.CurrentCoins[1].UserId == 900000001, "An offline user from another server must be ranked")
		assert(first.CurrentCoins[1].Score == 12000 and first.CurrentCoins[2].Score == 6000, "Global descending order was lost")
		local updated = service.GetCachedLeaderboards().LastUpdated
		fake.FailReads = true
		local stale = service.RefreshLeaderboards()
		assert(stale.CurrentCoins[1].UserId == 900000001, "An outage must keep cached global data")
		assert(service.GetCachedLeaderboards().LastUpdated == updated, "An outage must not mark stale data fresh")
		fake.FailReads, fake.Budget = false, 0
		service.UpdatePlayerStats(player)
		task.wait(.1)
		assert(fake.Writes == 0, "Zero budget must queue writes")
		fake.Budget = 100
		fake.Values.Leaderboard_Play_Time[tostring(player.UserId)] = 999999
		service.UpdatePlayerStats(player)
		task.wait(.1)
		assert(fake.Writes == 5, "Queued stats must flush once budget recovers")
		assert(fake.Values.Leaderboard_Play_Time[tostring(player.UserId)] >= 999999, "Lifetime play time must never decrease")
		assert(not service.UpdateProfileStats(800001, "Ranker_1", profile), "Synthetic fixture users must be rejected")
		return { offlineGlobalUsers = true, sorted = true, cachedOnOutage = true, budgetRetry = true, monotonicPlayTime = true, rejectsFixtureUsers = true }
	end, debug.traceback)
	sandbox:Destroy()
	provider:Destroy()
	if not ok then error(result) end
	return result
end
