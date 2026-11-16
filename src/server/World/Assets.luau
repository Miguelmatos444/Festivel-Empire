--!strict
--[[
	Assets
	Devolve o modelo a usar para cada elemento do mapa:
	  1) o teu modelo em ServerStorage/Assets (não gerido pelo Rojo), se for válido
	  2) caso contrário, o placeholder gerado com as medidas de Config

	Caminhos:
	  ServerStorage/Assets/Stages/Tier_01 … Tier_12
	  ServerStorage/Assets/Plaza
	  ServerStorage/Assets/PlotSign   (tem de conter uma BasePart chamada "Board")

	Avisos no Output (uma vez por modelo) se o Root faltar, se o modelo exceder
	o envelope do tier ou se faltarem Attachments.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local StagesConfig = require(ReplicatedStorage.Shared.Config.Stages)
local DressingConfig = require(ReplicatedStorage.Shared.Config.Dressing)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local Placeholders = require(script.Parent.Placeholders)

type StageDef = Types.StageDef

local SIZE_TOLERANCE = 0.05
local EXTENTS_TOLERANCE = 0.5

local Assets = {}

local cache: { [string]: Model } = {}
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[Assets] " .. message)
end

local function findAsset(path: { string }): Model?
	local current: Instance? = ServerStorage:FindFirstChild("Assets")
	for _, name in path do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	if current and current:IsA("Model") then
		return current
	end
	return nil
end

function Assets.GetRoot(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary then
		return primary
	end
	-- Os FBX importados podem trazer o Root dentro de um sub-modelo: procura em profundidade
	local root = model:FindFirstChild("Root") or model:FindFirstChild("Root", true)
	if root and root:IsA("BasePart") then
		model.PrimaryPart = root
		return root
	end
	return nil
end

-- Coloca o modelo de forma a que o Root fique exatamente em rootCFrame
function Assets.PivotRoot(model: Model, rootCFrame: CFrame)
	local root = Assets.GetRoot(model)
	if not root then
		return
	end
	model.PrimaryPart = root
	model:PivotTo(rootCFrame * root.PivotOffset)
end

-- Caixa alinhada com o mundo das peças visíveis do modelo (ignora Root, HeadAnchor, KitOrigin…)
function Assets.GetWorldBounds(model: Instance): (Vector3, Vector3)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 and descendant.Name ~= "HumanoidRootPart" then
			found = true
			local cf, half = descendant.CFrame, descendant.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local corner = cf * Vector3.new(half.X * x, half.Y * y, half.Z * z)
						minV = minV:Min(corner)
						maxV = maxV:Max(corner)
					end
				end
			end
		end
	end
	if not found and model:IsA("Model") then
		local cf, size = model:GetBoundingBox()
		return cf.Position - size / 2, cf.Position + size / 2
	end
	return minV, maxV
end

--[[
	Coloca o modelo de pé com a base (ou o topo, se hang) no ponto `position` e a frente
	(-Z do modelo tal como está guardado) rodada por `facing` (só se usa a rotação).
	Não depende da orientação do PrimaryPart/Root do FBX: mantém o modelo direito como
	está em ServerStorage e só lhe aplica a rotação do terreno.
]]
function Assets.PlaceUpright(model: Model, position: Vector3, facing: CFrame, hang: boolean?)
	local minV, maxV = Assets.GetWorldBounds(model)
	local anchor = Vector3.new((minV.X + maxV.X) / 2, if hang then maxV.Y else minV.Y, (minV.Z + maxV.Z) / 2)
	local offset = CFrame.new(anchor):ToObjectSpace(model:GetPivot())
	model:PivotTo(CFrame.new(position) * facing.Rotation * offset)
end

-- Rotação "virada para o público" de um terreno (Attachment StageOrigin do PlotBase)
function Assets.GetPlotFacing(plot: Instance?): CFrame?
	local base = if plot and plot:IsA("Model") then plot.PrimaryPart else nil
	local origin = if base then base:FindFirstChild("StageOrigin") else nil
	if origin and origin:IsA("Attachment") then
		return origin.WorldCFrame
	end
	return nil
end

--[[
	Altura da superfície do palco por baixo de `position` (estrado real do modelo).
	Lança um raio para baixo a partir de meio palco, só contra as peças visíveis do palco
	(o Root e os adereços têm CanQuery = false). Sem acerto devolve `fallbackY`.
]]
function Assets.FindStageSurfaceY(stage: Model, position: Vector3, groundY: number, stageHeight: number, fallbackY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { stage }
	local startHeight = math.max(stageHeight * 0.55, 3)
	local origin = Vector3.new(position.X, groundY + startHeight, position.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -(startHeight + 1), 0), params)
	return if result then result.Position.Y else fallbackY
end

-- Garante que todas as partes ficam ancoradas (modelos importados nem sempre vêm assim)
local function anchorAll(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function validateStage(model: Model, def: StageDef): boolean
	local key = model.Name
	local root = Assets.GetRoot(model)
	if not root then
		warnOnce(key .. ":root", key .. ": sem 'Root' (BasePart) — a usar o placeholder.")
		return false
	end
	model.PrimaryPart = root

	local size = root.Size
	if
		size.X > def.Width + SIZE_TOLERANCE
		or size.Y > def.Height + SIZE_TOLERANCE
		or size.Z > def.Depth + SIZE_TOLERANCE
	then
		warnOnce(
			key .. ":size",
			string.format(
				"%s: Root %.1f x %.1f x %.1f excede o envelope %d x %d x %d (L x A x P).",
				key,
				size.X,
				size.Y,
				size.Z,
				def.Width,
				def.Height,
				def.Depth
			)
		)
	end

	local _, extents = model:GetBoundingBox()
	if
		extents.X > def.Width + EXTENTS_TOLERANCE
		or extents.Y > def.Height + EXTENTS_TOLERANCE
		or extents.Z > def.Depth + EXTENTS_TOLERANCE
	then
		warnOnce(
			key .. ":extents",
			string.format("%s: a geometria (%.1f x %.1f x %.1f) sai do envelope do tier.", key, extents.X, extents.Y, extents.Z)
		)
	end

	local missing: { string } = {}
	for _, name in StagesConfig.AttachmentNames do
		local attachment = root:FindFirstChild(name)
		if not attachment or not attachment:IsA("Attachment") then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		warnOnce(key .. ":attachments", key .. ": Attachments em falta no Root: " .. table.concat(missing, ", "))
	end

	anchorAll(model)
	return true
end

function Assets.GetStageTemplate(tier: number): Model
	local def = MapCalc.GetStageDef(tier)
	local name = string.format("Tier_%02d", def.Tier)
	local custom = findAsset({ "Stages", name })
	if custom and validateStage(custom, def) then
		return custom
	end
	local cached = cache[name]
	if not cached then
		cached = Placeholders.BuildStage(def)
		cache[name] = cached
	end
	return cached
end

function Assets.GetPlazaTemplate(): Model
	local custom = findAsset({ "Plaza" })
	if custom then
		if Assets.GetRoot(custom) then
			anchorAll(custom)
			return custom
		end
		warnOnce("Plaza:root", "Plaza: sem 'Root' (BasePart) — a usar o placeholder.")
	end
	local cached = cache.Plaza
	if not cached then
		cached = Placeholders.BuildPlaza()
		cache.Plaza = cached
	end
	return cached
end

-- Decoração da praça: ServerStorage/Assets/PlazaDecor (Model com Root; partes com o
-- atributo RhythmLight = true mudam de cor ao ritmo no cliente)
function Assets.GetPlazaDecorTemplate(): Model
	local custom = findAsset({ "PlazaDecor" })
	if custom then
		if Assets.GetRoot(custom) then
			anchorAll(custom)
			return custom
		end
		warnOnce("PlazaDecor:root", "PlazaDecor: sem 'Root' (BasePart) — a usar o placeholder.")
	end
	local cached = cache.PlazaDecor
	if not cached then
		-- Com os modelos do Blender presentes (Props), não constrói as versões placeholder
		local plaza = DressingConfig.Plaza
		cached = Placeholders.BuildPlazaDecor({
			SkipFoodTrucks = plaza.Enabled and Assets.HasProp(plaza.FoodTruck.Name),
			SkipArches = plaza.Enabled and Assets.HasProp(plaza.EntranceArch.Name),
		})
		cache.PlazaDecor = cached
	end
	return cached
end

-- Decoração do terreno por era: ServerStorage/Assets/Decor/<Era> (Underground, Ascensão, Estrelato, Lenda)
function Assets.GetDecorTemplate(era: Types.EraName): Model
	local custom = findAsset({ "Decor", era })
	if custom then
		if Assets.GetRoot(custom) then
			anchorAll(custom)
			return custom
		end
		warnOnce("Decor:" .. era, "Decor/" .. era .. ": sem 'Root' (BasePart) — a usar o placeholder.")
	end
	local key = "Decor_" .. era
	local cached = cache[key]
	if not cached then
		cached = Placeholders.BuildDecor(era)
		cache[key] = cached
	end
	return cached
end

-- Artista: ServerStorage/Assets/Artists/<ArtistId> (Model com PrimaryPart/HumanoidRootPart).
-- Sem modelo próprio, usa o boneco placeholder (pintado com a cor da raridade).
function Assets.GetArtistTemplate(artistId: string): Model
	local custom = findAsset({ "Artists", artistId })
	if custom then
		local root = custom.PrimaryPart or custom:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			custom.PrimaryPart = root
			anchorAll(custom)
			return custom
		end
		warnOnce("Artist:" .. artistId, "Artists/" .. artistId .. ": sem PrimaryPart/HumanoidRootPart — a usar o placeholder.")
	end
	local cached = cache.ArtistRig
	if not cached then
		cached = Placeholders.BuildArtistRig()
		cache.ArtistRig = cached
	end
	return cached
end

-- Arco de Prestige: ServerStorage/Assets/Prestige/Arch (Model com Root; parte "Beam" opcional para o texto)
function Assets.GetPrestigeArchTemplate(): Model
	local custom = findAsset({ "Prestige", "Arch" })
	if custom then
		if Assets.GetRoot(custom) then
			anchorAll(custom)
			return custom
		end
		warnOnce("Prestige:Arch", "Prestige/Arch: sem 'Root' (BasePart) — a usar o placeholder.")
	end
	local cached = cache.PrestigeArch
	if not cached then
		cached = Placeholders.BuildPrestigeArch()
		cache.PrestigeArch = cached
	end
	return cached
end

-- Materiais pelo nome da peça (convenção dos FBX): Neon_* → Neon; Holo* → Neon translúcido
local function applyMaterials(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			local name = descendant.Name
			if string.sub(name, 1, 5) == "Neon_" or string.find(name, "Pulse_", 1, true) then
				descendant.Material = Enum.Material.Neon
			elseif string.sub(name, 1, 4) == "Holo" then
				descendant.Material = Enum.Material.Neon
				descendant.Transparency = math.max(descendant.Transparency, 0.35)
			end
			if name == "Root" or name == "KitOrigin" or string.find(name, "FXPoint_", 1, true) or string.sub(name, 1, 10) == "HeadAnchor" then
				descendant.Transparency = 1
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end
	end
end

export type FitAxis = "X" | "Y" | "Z"

--[[
	Adereço do Blender: ServerStorage/Assets/Props/<name> (nome = ficheiro FBX).
	Devolve um modelo-modelo escalado para que a dimensão `axis` meça `size` studs
	(em cache por nome/eixo/tamanho; clona antes de usar). Sem modelo → nil, sem erro.
]]
function Assets.GetProp(name: string, axis: FitAxis, size: number): Model?
	local key = string.format("Prop:%s:%s:%.2f", name, axis, size)
	local cached = cache[key]
	if cached then
		return cached
	end
	local source = findAsset({ "Props", name })
	if not source then
		return nil
	end
	local model = source:Clone()
	applyMaterials(model)
	local _, extents = model:GetBoundingBox()
	local current = if axis == "X" then extents.X elseif axis == "Y" then extents.Y else extents.Z
	if current > 0.01 and size > 0 then
		local ok, err = pcall(function()
			model:ScaleTo(model:GetScale() * size / current)
		end)
		if not ok then
			warnOnce("Prop:scale:" .. name, "Props/" .. name .. ": não foi possível escalar (" .. tostring(err) .. ")")
		end
	end
	cache[key] = model
	return model
end

function Assets.HasProp(name: string): boolean
	return findAsset({ "Props", name }) ~= nil
end

-- Kit de raridade: ServerStorage/Assets/RarityKits/<RarityId> (PrimaryPart = KitOrigin, centro da cabeça)
function Assets.GetRarityKitTemplate(kitName: string): Model?
	local key = "Kit:" .. kitName
	local cached = cache[key]
	if cached then
		return cached
	end
	local source = findAsset({ "RarityKits", kitName })
	if not source then
		return nil
	end
	local model = source:Clone()
	local origin = model:FindFirstChild("KitOrigin", true)
	if origin and origin:IsA("BasePart") then
		model.PrimaryPart = origin
	else
		warnOnce("Kit:" .. kitName, "RarityKits/" .. kitName .. ": sem peça 'KitOrigin' — o kit fica centrado na caixa do modelo.")
	end
	applyMaterials(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
	cache[key] = model
	return model
end

function Assets.GetSignTemplate(): Model
	local custom = findAsset({ "PlotSign" })
	if custom then
		local board = custom:FindFirstChild("Board", true)
		if Assets.GetRoot(custom) and board and board:IsA("BasePart") then
			anchorAll(custom)
			return custom
		end
		warnOnce("PlotSign:invalid", "PlotSign: precisa de 'Root' e de uma BasePart 'Board' — a usar o placeholder.")
	end
	local cached = cache.PlotSign
	if not cached then
		cached = Placeholders.BuildSign()
		cache.PlotSign = cached
	end
	return cached
end

return table.freeze(Assets)
