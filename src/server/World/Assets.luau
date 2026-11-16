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
	local root = model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
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
