-- Animación de agacharse al cagar, hecha moviendo las articulaciones (Motor6D.C0) desde el servidor
-- para que todos los jugadores la vean. Funciona con R15 y R6 sin subir animaciones.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Crouch = {}

-- nombre de la articulación -> { bajar (studs), girar en X (grados) }
local POSE = {
	Root = { drop = 0.8 }, -- R15
	LeftHip = { angle = 75 },
	RightHip = { angle = 75 },
	LeftKnee = { angle = -100 },
	RightKnee = { angle = -100 },
	RootJoint = { drop = 1.4 }, -- R6
	["Left Hip"] = { angle = 85 },
	["Right Hip"] = { angle = 85 },
}

local HOLD_SECONDS = 0.6
local DOWN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local UP = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local state = {} -- [character] = { joints = {{motor, original}}, crouched, until }

local function getState(character)
	local s = state[character]
	if s then
		return s
	end
	s = { joints = {}, crouched = false, untilTime = 0, lastDrop = 0 }
	for _, motor in character:GetDescendants() do
		if motor:IsA("Motor6D") and POSE[motor.Name] then
			table.insert(s.joints, { motor = motor, original = motor.C0 })
		end
	end
	state[character] = s
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			state[character] = nil
		end
	end)
	return s
end

local function crouchedC0(name, original)
	local pose = POSE[name]
	if pose.drop then
		return CFrame.new(0, -pose.drop, 0) * original
	end
	-- Girar en el espacio de la pieza padre, alrededor de la propia articulación
	return CFrame.new(original.Position) * CFrame.Angles(math.rad(pose.angle), 0, 0) * original.Rotation
end

local function tweenAll(s, down)
	for _, j in s.joints do
		if j.motor.Parent then
			local goal = down and crouchedC0(j.motor.Name, j.original) or j.original
			TweenService:Create(j.motor, down and DOWN or UP, { C0 = goal }):Play()
		end
	end
end

-- Suelta una cacotita detrás del jugador (como mucho cada 0.4 s)
local function dropPoop(character, s)
	local now = os.clock()
	if now - s.lastDrop < 0.4 then
		return
	end
	s.lastDrop = now
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.9, 0.9, 0.9)
	p.Color = Color3.fromRGB(110, 65, 30)
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = true
	p.CFrame = root.CFrame * CFrame.new(0, -1.5, 0.8)
	p.Parent = workspace
	p:SetNetworkOwner(nil)
	Debris:AddItem(p, 4)
end

function Crouch.play(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local s = getState(character)
	s.untilTime = os.clock() + HOLD_SECONDS
	dropPoop(character, s)
	if s.crouched then
		return
	end
	s.crouched = true
	tweenAll(s, true)
	task.spawn(function()
		while os.clock() < s.untilTime do
			task.wait(0.1)
		end
		s.crouched = false
		tweenAll(s, false)
	end)
end

return Crouch
