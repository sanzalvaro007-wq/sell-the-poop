-- Ranking global (OrderedDataStore). Si el lugar no está publicado, enseña solo a los jugadores del servidor.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Leaderboard = {}

local UPDATE_SECONDS = 60
local TOP = 10
local STATS = { cash = "Cash", poop = "TotalPoop", clicks = "Clicks" }

local stores = {}
local storesOk = pcall(function()
	for key in STATS do
		stores[key] = DataStoreService:GetOrderedDataStore("SellThePoop_Top_" .. key)
	end
end)

local nameCache = {}
local function nameOf(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	name = ok and name or ("#" .. userId)
	nameCache[userId] = name
	return name
end

local function localTop(profiles, field)
	local list = {}
	for player, data in profiles do
		table.insert(list, { name = player.Name, value = data[field] or 0 })
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	while #list > TOP do
		table.remove(list)
	end
	return list
end

local function globalTop(key, field, profiles)
	local store = stores[key]
	for player, data in profiles do
		pcall(store.SetAsync, store, tostring(player.UserId), math.floor(math.min(data[field] or 0, 2 ^ 53)))
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
	if not ok then
		return nil
	end
	local list = {}
	for _, entry in pages:GetCurrentPage() do
		table.insert(list, { name = nameOf(tonumber(entry.key)), value = entry.value })
	end
	return list
end

-- profiles: [player] = data; onUpdate(lists) con lists.cash/poop/clicks = {{name, value}}
function Leaderboard.start(profiles, onUpdate)
	task.spawn(function()
		while true do
			local lists = {}
			for key, field in STATS do
				lists[key] = (storesOk and globalTop(key, field, profiles)) or localTop(profiles, field)
			end
			onUpdate(lists)
			task.wait(storesOk and UPDATE_SECONDS or 5)
		end
	end)
end

return Leaderboard
