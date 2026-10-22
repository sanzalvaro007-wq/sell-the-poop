-- Construye el mapa por código: césped, valla, spawn con arcos y cúpula-caca, tienda y leaderboard.
-- Si existe ReplicatedStorage.Assets.CacaGigante (el modelo de Blender importado), se usa en vez de la caca de bloques.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Map = {}

local folder

local GRASS = Color3.fromRGB(86, 160, 60)
local WHITE = Color3.fromRGB(245, 245, 245)
local STONE = Color3.fromRGB(230, 222, 205)
local POOP = { Color3.fromRGB(122, 74, 36), Color3.fromRGB(110, 65, 30), Color3.fromRGB(98, 57, 26) }
local YELLOW = Color3.fromRGB(240, 200, 60)
local RED = Color3.fromRGB(205, 40, 40)

local SPAWN_POS = Vector3.new(0, 0, 0)
local SHOP_POS = Vector3.new(0, 0, -62)
local BOARD_POS = Vector3.new(-34, 0, -38)
local FENCE_HALF = 120

-- Helpers ----------------------------------------------------------------------
local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props.Shape then
		p.Shape = props.Shape
	end
	for k, v in props do
		if k ~= "Shape" and k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent or folder
	return p
end

-- Disco horizontal (cilindro tumbado de pie)
local function disc(center, diameter, height, props)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	return part(props)
end

local function ball(position, diameter, props)
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.new(diameter, diameter, diameter)
	props.Position = position
	return part(props)
end

-- Barra entre dos puntos
local function beam(a, b, width, thick, props)
	props.Size = Vector3.new(width, thick, (b - a).Magnitude + thick * 0.6)
	props.CFrame = CFrame.lookAt((a + b) / 2, b)
	return part(props)
end

-- Caca con cara ------------------------------------------------------------------
-- base: CFrame en el centro de la base; la cara mira hacia -Z de base. R: radio del piso de abajo.
local TIERS = {
	{ r = 1.0, h = 0.5, y = 0.0 },
	{ r = 0.72, h = 0.42, y = 0.4 },
	{ r = 0.45, h = 0.34, y = 0.72 },
}

-- Perfil de cada piso: un "michelín" con la parte de abajo un poco metida y la de arriba redonda
local function poopRadiusAt(tier, R, dy)
	local h = tier.h * R
	local c = 0.35 * h
	local k
	if dy < c then
		k = (c - dy) / (c * 1.6)
	else
		k = (dy - c) / (h - c)
	end
	return tier.r * R * math.sqrt(math.max(0, 1 - k * k))
end

local function buildPoop(base, R, name)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = folder

	-- Modelo de Blender si está importado
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local mesh = assets and assets:FindFirstChild("CacaGigante")
	if mesh and mesh:IsA("Model") then
		local clone = mesh:Clone()
		clone.Parent = model
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		-- Tamaño
		local _, size = clone:GetBoundingBox()
		clone:ScaleTo(clone:GetScale() * (2 * R) / math.max(size.X, size.Z))
		-- Girar para que la cara (piezas "Ojo...") mire hacia -Z de base
		local center = clone:GetBoundingBox().Position
		local eyes, count = Vector3.zero, 0
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") and d.Name:lower():find("ojo") then
				eyes += d.Position
				count += 1
			end
		end
		if count > 0 then
			local face = eyes / count - center
			local want = base.LookVector
			local turn = math.atan2(want.X, want.Z) - math.atan2(face.X, face.Z)
			clone:PivotTo(CFrame.new(center) * CFrame.Angles(0, turn, 0) * CFrame.new(-center) * clone:GetPivot())
		end
		-- Apoyarla sobre la base
		local box, newSize = clone:GetBoundingBox()
		local target = base.Position + Vector3.new(0, newSize.Y / 2, 0)
		clone:PivotTo(clone:GetPivot() + (target - box.Position))
		return model
	end

	-- Pisos de la caca: discos que siguen un perfil redondeado
	local LAYERS = 8
	for t, tier in TIERS do
		local h = tier.h * R
		for j = 0, LAYERS - 1 do
			local y0 = h * j / LAYERS
			local y1 = h * (j + 1) / LAYERS
			local radius = poopRadiusAt(tier, R, (y0 + y1) / 2)
			local p = disc((base * CFrame.new(0, tier.y * R + (y0 + y1) / 2, 0)).Position, radius * 2, y1 - y0 + 0.05, {
				Color = POOP[t],
				Parent = model,
			})
			p.Name = "Poop"
		end
	end
	-- Punta con rizo
	ball((base * CFrame.new(0, 1.03 * R, 0)).Position, 0.26 * R, { Color = POOP[3], Parent = model })
	ball((base * CFrame.new(0.08 * R, 1.15 * R, 0.02 * R)).Position, 0.14 * R, { Color = POOP[3], Parent = model })

	-- Cara en el piso de abajo
	local tier = TIERS[1]
	local h = tier.h * R
	local function surface(x, dy, out)
		local r = poopRadiusAt(tier, R, dy)
		local z = math.sqrt(math.max(0, r * r - x * x))
		return (base * CFrame.new(x, dy, -(z + out))).Position
	end
	local eyeY = 0.5 * h
	for _, side in { -1, 1 } do
		local x = side * 0.26 * R
		ball(surface(x, eyeY, -0.03 * R), 0.24 * R, { Color = WHITE, Parent = model })
		ball(surface(x * 0.95, eyeY + 0.01 * R, 0.07 * R), 0.11 * R, {
			Color = Color3.new(0.05, 0.05, 0.05),
			Parent = model,
		})
	end
	-- Sonrisa
	for i = -4, 4 do
		local x = i * 0.045 * R
		local dy = 0.12 * h + 0.006 * R * (i * i) / 2
		ball(surface(x, dy, 0.0), 0.08 * R, { Color = Color3.fromRGB(60, 20, 20), Parent = model })
	end
	return model
end

-- Suelo y valla -------------------------------------------------------------------
local function buildGround()
	part({
		Name = "Grass",
		Size = Vector3.new(1000, 1, 1000),
		Position = Vector3.new(0, -0.4, 0),
		Color = GRASS,
		Material = Enum.Material.Grass,
	})
	-- Camino de piedra del spawn a la tienda y al cartel
	beam(Vector3.new(0, 0.15, -24), SHOP_POS + Vector3.new(0, 0.15, 8), 8, 0.3, {
		Color = Color3.fromRGB(190, 180, 160),
		Material = Enum.Material.Cobblestone,
	})
	beam(Vector3.new(-14, 0.15, -20), BOARD_POS + Vector3.new(4, 0.15, 6), 6, 0.3, {
		Color = Color3.fromRGB(190, 180, 160),
		Material = Enum.Material.Cobblestone,
	})
end

local function buildFence()
	local H = FENCE_HALF
	local corners = {
		Vector3.new(-H, 0, -H),
		Vector3.new(H, 0, -H),
		Vector3.new(H, 0, H),
		Vector3.new(-H, 0, H),
	}
	for i, a in corners do
		local b = corners[i % 4 + 1]
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		-- Postes con punta
		for d = 0, len - 1, 3 do
			local p = a + dir * d
			part({ Size = Vector3.new(0.6, 4.5, 0.6), Position = p + Vector3.new(0, 2.25, 0), Color = WHITE })
			part({
				Size = Vector3.new(0.6, 0.6, 0.6),
				CFrame = CFrame.new(p + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, math.rad(45), math.rad(45)),
				Color = WHITE,
			})
		end
		-- Travesaños
		for _, y in { 1.3, 3.4 } do
			beam(a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), 0.3, 0.5, { Color = WHITE })
		end
		-- Pared invisible para que nadie salte la valla
		beam(a + Vector3.new(0, 15, 0), b + Vector3.new(0, 15, 0), 1, 30, { Transparency = 1 })
	end
end

-- Spawn: plataforma redonda con 3 escalones, arcos y cúpula de caca -----------------
local function buildSpawn()
	local steps = { 52, 46, 40 }
	for i, d in steps do
		disc(SPAWN_POS + Vector3.new(0, i - 0.5, 0), d, 1, {
			Color = i % 2 == 0 and STONE or Color3.fromRGB(215, 205, 185),
			Material = Enum.Material.Marble,
		})
	end
	local floorY = #steps

	-- Quitar los SpawnLocation que traiga la plantilla
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.CFrame = CFrame.lookAt(SPAWN_POS + Vector3.new(0, floorY + 0.1, 0), SHOP_POS + Vector3.new(0, floorY + 0.1, 0))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	-- Columnas y arcos
	local N, R = 8, 16
	local colH = 8
	local archTop = floorY + colH
	local columns = {}
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * math.pi * 2
		local p = SPAWN_POS + Vector3.new(math.cos(a) * R, 0, math.sin(a) * R)
		columns[i + 1] = p
		part({ Size = Vector3.new(3, 0.8, 3), Position = p + Vector3.new(0, floorY + 0.4, 0), Color = WHITE, Material = Enum.Material.Marble })
		local col = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(colH, 2.2, 2.2),
			CFrame = CFrame.new(p + Vector3.new(0, floorY + colH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = STONE,
			Material = Enum.Material.Marble,
		})
		col.Name = "Column"
		part({ Size = Vector3.new(3, 0.8, 3), Position = p + Vector3.new(0, archTop - 0.4, 0), Color = WHITE, Material = Enum.Material.Marble })
	end

	local archRadius
	for i = 1, N do
		local a = columns[i] + Vector3.new(0, archTop, 0)
		local b = columns[i % N + 1] + Vector3.new(0, archTop, 0)
		local mid = (a + b) / 2
		local half = (b - a).Magnitude / 2
		archRadius = half
		local dir = (b - a).Unit
		local SEG = 10
		local prev = a
		for k = 1, SEG do
			local t = k / SEG * math.pi
			local p = mid - dir * (half * math.cos(t)) + Vector3.new(0, half * math.sin(t), 0)
			beam(prev, p, 1.8, 1.2, { Color = WHITE, Material = Enum.Material.Marble })
			prev = p
		end
	end

	-- Anillo sobre los arcos
	local ringY = archTop + archRadius + 0.6
	for i = 1, N do
		local a = columns[i] * 1.06 + Vector3.new(0, ringY, 0)
		local b = columns[i % N + 1] * 1.06 + Vector3.new(0, ringY, 0)
		beam(a, b, 2.4, 1.2, { Color = STONE, Material = Enum.Material.Marble })
	end

	-- La cúpula es una caca enorme con cara, mirando hacia la tienda
	buildPoop(CFrame.lookAt(SPAWN_POS + Vector3.new(0, ringY + 0.6, 0), SHOP_POS + Vector3.new(0, ringY + 0.6, 0)), 19, "CacaCupula")
end

-- Tienda de ventanilla con toldo de mercadillo ----------------------------------------
local function buildShop()
	-- base: la ventanilla mira hacia -Z local (hacia el spawn)
	local base = CFrame.lookAt(SHOP_POS, SPAWN_POS)
	local W, D, H = 18, 12, 12
	local winBottom, winTop = 4, 9.5
	local function kpart(x, y, z, size, props)
		props.Size = size
		props.CFrame = base * CFrame.new(x, y, z)
		return part(props)
	end
	local wall = { Color = YELLOW, Material = Enum.Material.WoodPlanks }
	local function wallProps()
		return table.clone(wall)
	end

	kpart(0, 0.3, 0, Vector3.new(W + 1, 0.6, D + 1), { Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Wood })
	kpart(0, H / 2, D / 2, Vector3.new(W, H, 1), wallProps()) -- trasera
	kpart(-W / 2, H / 2, 0, Vector3.new(1, H, D), wallProps())
	kpart(W / 2, H / 2, 0, Vector3.new(1, H, D), wallProps())
	-- Fachada con hueco de ventanilla
	local front = -D / 2
	kpart(0, winBottom / 2, front, Vector3.new(W, winBottom, 1), wallProps())
	kpart(0, (winTop + H) / 2, front, Vector3.new(W, H - winTop, 1), wallProps())
	kpart(-7.5, (winBottom + winTop) / 2, front, Vector3.new(3, winTop - winBottom, 1), wallProps())
	kpart(7.5, (winBottom + winTop) / 2, front, Vector3.new(3, winTop - winBottom, 1), wallProps())
	-- Marco blanco de la ventanilla
	kpart(0, winTop, front - 0.55, Vector3.new(12.4, 0.4, 0.3), { Color = WHITE })
	kpart(-6.1, (winBottom + winTop) / 2, front - 0.55, Vector3.new(0.4, winTop - winBottom, 0.3), { Color = WHITE })
	kpart(6.1, (winBottom + winTop) / 2, front - 0.55, Vector3.new(0.4, winTop - winBottom, 0.3), { Color = WHITE })
	-- Mostrador
	local counter = kpart(0, winBottom + 0.2, front - 1, Vector3.new(13, 0.4, 3), {
		Color = Color3.fromRGB(150, 100, 55),
		Material = Enum.Material.Wood,
	})
	counter.Name = "Mostrador"
	-- Tejado
	kpart(0, H + 0.4, 0, Vector3.new(W + 2, 0.8, D + 2), { Color = WHITE })

	-- Toldo a rayas rojas y blancas, inclinado hacia fuera
	local stripes = 9
	local stripeW = (W + 1) / stripes
	for i = 0, stripes - 1 do
		local x = -(W + 1) / 2 + stripeW * (i + 0.5)
		local color = i % 2 == 0 and RED or WHITE
		local a = (base * CFrame.new(x, winTop + 1.6, front - 0.6)).Position
		local b = (base * CFrame.new(x, winTop - 0.4, front - 5.5)).Position
		beam(a, b, stripeW, 0.2, { Color = color, Material = Enum.Material.Fabric })
		-- Faldón con picos
		kpart(x, winTop - 0.9, front - 5.55, Vector3.new(stripeW, 1, 0.15), { Color = color, Material = Enum.Material.Fabric })
	end
	-- Palos del toldo
	for _, x in { -(W + 1) / 2 + 0.2, (W + 1) / 2 - 0.2 } do
		local a = (base * CFrame.new(x, winTop - 0.4, front - 5.5)).Position
		local b = (base * CFrame.new(x, winTop + 1.6, front - 0.6)).Position
		beam(a, b, 0.25, 0.25, { Color = Color3.fromRGB(80, 80, 80), Material = Enum.Material.Metal })
	end

	-- Cartel en la fachada
	local sign = kpart(0, 2, front - 0.6, Vector3.new(12, 2.4, 0.2), { Color = RED })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "💩 SE COMPRA CACA 💵"
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = WHITE
	text.Parent = gui

	-- Caca con cara en el tejado
	buildPoop(base * CFrame.new(0, H + 0.8, -2.5), 5, "CacaTienda")

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Vender caca"
	prompt.ObjectText = "Ventanilla"
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	return prompt
end

-- Cartel con leaderboard ---------------------------------------------------------------
local columnsText = {}

local function buildBoard()
	local base = CFrame.lookAt(BOARD_POS, SPAWN_POS)
	local W, H = 26, 12
	for _, x in { -W / 2 + 1, W / 2 - 1 } do
		part({ Size = Vector3.new(1, 6, 1), CFrame = base * CFrame.new(x, 3, 0.2), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood })
	end
	local board = part({
		Name = "Leaderboard",
		Size = Vector3.new(W, H, 0.6),
		CFrame = base * CFrame.new(0, 6 + H / 2, 0),
		Color = Color3.fromRGB(45, 30, 20),
		Material = Enum.Material.Wood,
	})
	part({ Size = Vector3.new(W + 1, 0.6, 1.2), CFrame = base * CFrame.new(0, 6 + H + 0.3, 0), Color = YELLOW })

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.15, 0)
	title.BackgroundTransparency = 1
	title.Text = "🏆 LOS MÁS CAGONES 🏆"
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = YELLOW
	title.Parent = gui

	local heads = { "💵 Más dinero", "💩 Más caca", "👆 Más clicks" }
	for i, head in heads do
		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.Position = UDim2.new((i - 1) / 3, 8, 0.17, 0)
		col.Size = UDim2.new(1 / 3, -16, 0.8, 0)
		col.Parent = gui
		local h = Instance.new("TextLabel")
		h.Size = UDim2.new(1, 0, 0.14, 0)
		h.BackgroundTransparency = 1
		h.Text = head
		h.TextScaled = true
		h.Font = Enum.Font.FredokaOne
		h.TextColor3 = WHITE
		h.Parent = col
		local body = Instance.new("TextLabel")
		body.Position = UDim2.new(0, 0, 0.16, 0)
		body.Size = UDim2.new(1, 0, 0.84, 0)
		body.BackgroundTransparency = 1
		body.Text = "..."
		body.TextScaled = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.Font = Enum.Font.GothamBold
		body.TextColor3 = Color3.fromRGB(230, 230, 230)
		body.Parent = col
		columnsText[i] = body
	end
end

-- lists: { cash = {{name, value}}, poop = {...}, clicks = {...} }
function Map.setLeaderboard(lists, format)
	for i, key in { "cash", "poop", "clicks" } do
		local lines = {}
		for rank, entry in lists[key] or {} do
			table.insert(lines, rank .. ". " .. entry.name .. "  " .. format(entry.value))
		end
		if columnsText[i] then
			columnsText[i].Text = #lines > 0 and table.concat(lines, "\n") or "Nadie todavía"
		end
	end
end

function Map.build()
	folder = Instance.new("Folder")
	folder.Name = "Map"
	folder.Parent = workspace

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate.Transparency = 1
	end

	buildGround()
	buildFence()
	buildSpawn()
	local prompt = buildShop()
	buildBoard()
	return prompt
end

return Map
