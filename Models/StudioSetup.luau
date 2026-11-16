--!strict
--[[
	StudioSetup.luau — correr UMA vez no Command Bar do Roblox Studio (modo Edit),
	depois de importar os FBX de Models/FBX/Stages e Models/FBX/World para:
	  ServerStorage/Assets/Stages/Tier_01 … Tier_12
	  ServerStorage/Assets/Plaza
	  ServerStorage/Assets/PlotSign

	O que faz em cada modelo:
	  - Root invisível e sem colisões, definido como PrimaryPart
	  - todas as partes ancoradas; partes "Neon_*" com material Neon
	  - nos palcos, cria no Root os Attachments da secção 3 do PDF de medidas
	    (só cria os que faltam; nunca apaga nada)

	Antes de correr: confirma que a frente de cada palco está virada para -Z
	(o público). Se entrou rodado, roda o modelo 180° e só depois corre isto.
]]

local ServerStorage = game:GetService("ServerStorage")

-- L, P, A, E por tier (PDF "Medidas dos modelos 3D", secção 2)
local TIERS: { { number } } = {
	{ 20, 12, 8, 2 }, { 28, 16, 12, 2 }, { 36, 20, 16, 2.4 }, { 44, 24, 22, 3.3 },
	{ 52, 28, 28, 4.2 }, { 60, 32, 36, 5.4 }, { 68, 36, 46, 6.9 }, { 74, 40, 56, 8 },
	{ 80, 44, 66, 8 }, { 84, 46, 76, 8 }, { 88, 48, 88, 8 }, { 90, 48, 100, 8 },
}

local function prepare(model: Model): BasePart?
	local root = model:FindFirstChild("Root", true)
	if not (root and root:IsA("BasePart")) then
		warn("[StudioSetup] " .. model.Name .. ": sem peça 'Root'")
		return nil
	end
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	model.PrimaryPart = root
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if string.sub(d.Name, 1, 5) == "Neon_" then
				d.Material = Enum.Material.Neon
			end
		end
	end
	return root
end

local function addAttachment(root: BasePart, name: string, stagePoint: Vector3, rootCenter: Vector3)
	if root:FindFirstChild(name) then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = stagePoint - rootCenter
	a.Parent = root
end

local assets = ServerStorage:FindFirstChild("Assets")
assert(assets, "Falta ServerStorage/Assets")
local stages = assets:FindFirstChild("Stages")

if stages then
	for tier, dims in TIERS do
		local model = stages:FindFirstChild(string.format("Tier_%02d", tier))
		if model and model:IsA("Model") then
			local root = prepare(model)
			if root then
				local L, P, A, E = dims[1], dims[2], dims[3], dims[4]
				local c = Vector3.new(0, A / 2, P / 2) -- centro do Root no espaço do palco
				addAttachment(root, "StageOrigin", Vector3.zero, c)
				addAttachment(root, "DJBooth", Vector3.new(0, E, 0.6 * P), c)
				for i = 1, 7 do
					local x = -0.35 * L + (i - 1) * (0.7 * L / 6)
					addAttachment(root, "Artist_" .. i, Vector3.new(x, E, 0.3 * P), c)
				end
				for i, s in { -1, 1 } do
					addAttachment(root, "Pyro_ColdSparks_" .. i, Vector3.new(s * (L / 2 - 1), E, 1), c)
					addAttachment(root, "Pyro_CO2Cannon_" .. i, Vector3.new(s * 0.3 * L, E, 1.5), c)
					addAttachment(root, "Pyro_Lasers_" .. i, Vector3.new(s * 0.25 * L, A - 1, P - 2), c)
					addAttachment(root, "Pyro_Flamethrower_" .. i, Vector3.new(s * (L / 2 - 1), E, P / 2), c)
				end
				addAttachment(root, "Speaker_L", Vector3.new(-(L / 2 - 2), E, 2), c)
				addAttachment(root, "Speaker_R", Vector3.new(L / 2 - 2, E, 2), c)
				addAttachment(root, "CameraFocus", Vector3.new(0, E + 0.4 * (A - E), 0.4 * P), c)
				print(string.format("[StudioSetup] Tier_%02d pronto (Root %s)", tier, tostring(root.Size)))
			end
		end
	end
end

for _, name in { "Plaza", "PlotSign" } do
	local model = assets:FindFirstChild(name)
	if model and model:IsA("Model") then
		if prepare(model) then
			print("[StudioSetup] " .. name .. " pronto")
		end
	end
end
