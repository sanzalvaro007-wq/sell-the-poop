-- Servidor de Sell the Poop: datos, guardado, economía, tratos y el mundo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Map = require(script.Parent.Map)
local Crouch = require(script.Parent.Crouch)
local Leaderboard = require(script.Parent.Leaderboard)

-- En un lugar sin publicar GetDataStore da error: seguimos sin guardado en vez de romper el juego.
local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
end)
if not storeOk then
	warn("[SellThePoop] DataStore no disponible (publica el lugar para guardar):", store)
	store = nil
end

-- Remotes ------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local PoopRemote = makeRemote("Poop")
local BuyRemote = makeRemote("BuyUpgrade")
local BuyOneTimeRemote = makeRemote("BuyOneTime")
local RebirthRemote = makeRemote("Rebirth")
local AcceptDealRemote = makeRemote("AcceptDeal")
local StateRemote = makeRemote("State") -- servidor -> cliente
local NotifyRemote = makeRemote("Notify") -- servidor -> cliente
local DealOfferRemote = makeRemote("DealOffer") -- servidor -> cliente

-- Estado en memoria ---------------------------------------------------------
local profiles = {} -- [player] = data
local session = {} -- [player] = { clicks, clickWindow, deal, dealMult, dealEnds, nextDeal }

local function sync(player)
	local data = profiles[player]
	local s = session[player]
	if not data or not s then
		return
	end
	StateRemote:FireClient(player, data, {
		dealMult = s.dealMult,
		dealEndsIn = s.dealEnds - os.clock(),
	})
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Cash.Value = data.Cash
		ls.Poop.Value = data.Poop
		ls.Rebirths.Value = data.Rebirths
	end
end

local function notify(player, text)
	NotifyRemote:FireClient(player, text)
end

local function makeLeaderstats(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, name in { "Cash", "Poop", "Rebirths" } do
		local v = Instance.new("NumberValue")
		v.Name = name
		v.Parent = ls
	end
	ls.Parent = player
end

-- Guardado ------------------------------------------------------------------
local function load(player)
	if not store then
		return Config.newData()
	end
	local ok, saved = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	local data = Config.newData()
	if ok and type(saved) == "table" then
		for k, v in saved do
			data[k] = v
		end
		for k, v in Config.newData().Levels do
			if data.Levels[k] == nil then
				data.Levels[k] = v
			end
		end
	elseif not ok then
		warn("[SellThePoop] No se pudieron cargar los datos de", player.Name, saved)
	end
	return data
end

local function save(player)
	local data = profiles[player]
	if not data or not store then
		return
	end
	data.LastOnline = os.time()
	local ok, err = pcall(function()
		store:SetAsync("u_" .. player.UserId, data)
	end)
	if not ok then
		warn("[SellThePoop] Error guardando", player.Name, err)
	end
end

-- Economía --------------------------------------------------------------------
local function sellAll(player)
	local data = profiles[player]
	local s = session[player]
	if data.Poop <= 0 then
		return 0
	end
	local mult = (s.dealEnds > os.clock()) and s.dealMult or 1
	local earned = data.Poop * Config.poopValue(data) * mult
	data.Cash += earned
	data.Poop = 0
	return earned
end

PoopRemote.OnServerEvent:Connect(function(player)
	local data = profiles[player]
	local s = session[player]
	if not data then
		return
	end
	-- Anti autoclicker: máximo N clicks por segundo
	local now = os.clock()
	if now - s.clickWindow >= 1 then
		s.clickWindow = now
		s.clicks = 0
	end
	s.clicks += 1
	if s.clicks > Config.MAX_CLICKS_PER_SECOND then
		return
	end
	local amount = Config.poopPerClick(data)
	data.Poop += amount
	data.TotalPoop += amount
	data.Clicks += 1
	Crouch.play(player)
	sync(player)
end)

BuyRemote.OnServerEvent:Connect(function(player, id)
	local data = profiles[player]
	if not data or type(id) ~= "string" or not Config.getUpgrade(id) then
		return
	end
	local cost = Config.upgradeCost(id, data.Levels[id])
	if data.Cash < cost then
		notify(player, "❌ Te falta dinero")
		return
	end
	data.Cash -= cost
	data.Levels[id] += 1
	sync(player)
end)

BuyOneTimeRemote.OnServerEvent:Connect(function(player, id)
	local data = profiles[player]
	if not data or type(id) ~= "string" then
		return
	end
	local item = Config.getOneTime(id)
	if not item or data.Owned[id] then
		return
	end
	if data.Cash < item.cost then
		notify(player, "❌ Te falta dinero")
		return
	end
	data.Cash -= item.cost
	data.Owned[id] = true
	notify(player, "✅ Comprado: " .. item.name)
	sync(player)
end)

RebirthRemote.OnServerEvent:Connect(function(player)
	local data = profiles[player]
	if not data then
		return
	end
	local cost = Config.rebirthCost(data)
	if data.Cash < cost then
		notify(player, "❌ Necesitas $" .. Config.format(cost) .. " para el Laxante Cósmico")
		return
	end
	data.Rebirths += 1
	data.Cash = 0
	data.Poop = 0
	data.Levels = Config.newData().Levels
	data.Owned = {}
	notify(player, "🌌 ¡Laxante Cósmico! Ahora tienes x" .. Config.rebirthMult(data) .. " a todo")
	sync(player)
end)

AcceptDealRemote.OnServerEvent:Connect(function(player)
	local s = session[player]
	if not s or not s.deal or s.deal.expires < os.clock() then
		return
	end
	s.dealMult = s.deal.mult
	s.dealEnds = os.clock() + Config.DEAL_DURATION
	s.deal = nil
	notify(player, "🤝 ¡Trato hecho! Tu caca vale x" .. s.dealMult .. " durante " .. Config.DEAL_DURATION .. "s")
	sync(player)
end)

-- Entrar / salir -------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	makeLeaderstats(player)
	local data = load(player)
	profiles[player] = data
	session[player] = {
		clicks = 0,
		clickWindow = 0,
		deal = nil,
		dealMult = 1,
		dealEnds = 0,
		nextDeal = os.clock() + math.random(Config.DEAL_MIN_INTERVAL, Config.DEAL_MAX_INTERVAL),
	}

	-- Ganancias offline: el 100% de lo que producen tus váteres automáticos
	if data.LastOnline > 0 then
		local seconds = math.clamp(os.time() - data.LastOnline, 0, Config.OFFLINE_MAX_SECONDS)
		local earned = Config.poopPerSecond(data) * Config.poopValue(data) * seconds
		if earned > 0 then
			data.Cash += earned
			task.delay(3, notify, player, "😴 Mientras no estabas ganaste $" .. Config.format(earned))
		end
	end

	sync(player)
end)

Players.PlayerRemoving:Connect(function(player)
	save(player)
	profiles[player] = nil
	session[player] = nil
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(save, player)
	end
	task.wait(3)
end)

-- Bucle principal: producción automática, camión, tratos ---------------------
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for player, data in profiles do
			local s = session[player]
			local auto = Config.poopPerSecond(data)
			data.Poop += auto
			data.TotalPoop += auto
			if now >= s.nextDeal then
				s.nextDeal = now + math.random(Config.DEAL_MIN_INTERVAL, Config.DEAL_MAX_INTERVAL)
				s.deal = {
					mult = math.random(Config.DEAL_MIN_MULT, Config.DEAL_MAX_MULT),
					expires = now + Config.DEAL_ACCEPT_WINDOW,
				}
				DealOfferRemote:FireClient(player, s.deal.mult, Config.DEAL_ACCEPT_WINDOW)
			end
			sync(player)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_SECONDS)
		for player in profiles do
			task.spawn(save, player)
		end
	end
end)

-- Mundo: solo se vende en la ventanilla de la tienda --------------------------
local sellPrompt = Map.build()
sellPrompt.Triggered:Connect(function(player)
	if not profiles[player] then
		return
	end
	local earned = sellAll(player)
	if earned > 0 then
		notify(player, "💵 Vendiste caca por $" .. Config.format(earned))
	else
		notify(player, "💩 No tienes caca que vender")
	end
	sync(player)
end)

Leaderboard.start(profiles, function(lists)
	Map.setLeaderboard(lists, Config.format)
end)
