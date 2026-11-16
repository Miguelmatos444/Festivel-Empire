--!strict
--[[
	StageService
	Palcos de cada terreno:
	  - compra validada no servidor (tier seguinte, World Tours, Hype; nunca durante uma montagem)
	  - troca do palco no mesmo sítio com transição replicada (maior nas trocas de era)
	  - evolução do terreno: decoração e cores por era

	Transição (sem loops por frame no servidor):
	  1) o palco antigo passa a "StageOld" e o novo "Stage" é colocado na posição final
	  2) o Plot recebe atributos Transition* (início em hora do servidor, tiers, era, duração)
	     -> cada cliente anima localmente (StageAnimController), com LOD por distância
	  3) no fim, um task.delay apaga o "StageOld" e limpa os atributos
	Casos limite: o dono sai (PlotReleased) ou o perfil é reiniciado a meio -> o token da
	transição é invalidado e os dois modelos são removidos de imediato. Morrer não afeta nada:
	a transição pertence ao terreno, não à personagem.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local StagesConfig = require(ReplicatedStorage.Shared.Config.Stages)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local Assets = require(script.Parent.Parent.World.Assets)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local PlayerStateService = require(script.Parent.PlayerStateService)

type EraName = Types.EraName

-- Cores do chão e dos limites do terreno por era
local ERA_GROUND: { [string]: Color3 } = {
	Underground = Color3.fromRGB(70, 68, 80),
	["Ascensão"] = Color3.fromRGB(52, 40, 82),
	Estrelato = Color3.fromRGB(44, 44, 54),
	Lenda = Color3.fromRGB(24, 34, 56),
}

local StageService = {}

local stageChanged: Signal.Signal<Player, number, number> = Signal.new()
local stagePlaced: Signal.Signal<Player> = Signal.new()

-- (jogador, tier anterior, tier novo) — disparado após uma compra
StageService.StageChanged = stageChanged
-- Disparado sempre que um palco novo é colocado (os artistas reposicionam-se)
StageService.StagePlaced = stagePlaced

local trove = Trove.new()
local tokens: { [number]: number } = {} -- por terreno; invalida transições agendadas
local transitioning: { [number]: boolean } = {}
local transitionIds: { [number]: number } = {}

local function nextToken(index: number): number
	local token = (tokens[index] or 0) + 1
	tokens[index] = token
	return token
end

local function clearTransitionAttributes(model: Model)
	model:SetAttribute("TransitionStart", nil)
	model:SetAttribute("TransitionFrom", nil)
	model:SetAttribute("TransitionTo", nil)
	model:SetAttribute("TransitionEra", nil)
	model:SetAttribute("TransitionKind", nil)
	model:SetAttribute("TransitionWorldTour", nil)
end

-- Remove palcos e cancela qualquer transição do terreno
local function clearStage(index: number)
	nextToken(index)
	transitioning[index] = nil
	local model = MapService.GetPlotModel(index)
	if not model then
		return
	end
	for _, name in { "Stage", "StageOld" } do
		local stage = model:FindFirstChild(name)
		if stage then
			stage:Destroy()
		end
	end
	clearTransitionAttributes(model)
end

-- Evolução do terreno ------------------------------------------------------------

local function applyEra(index: number, era: EraName)
	local model = MapService.GetPlotModel(index)
	local base = if model then model.PrimaryPart else nil
	if not model or not base or model:GetAttribute("Era") == era then
		return
	end
	model:SetAttribute("Era", era)
	base.Color = ERA_GROUND[era] or base.Color

	local previous = model:FindFirstChild("Decor")
	if previous then
		previous:Destroy()
	end
	local decor = Assets.GetDecorTemplate(era):Clone()
	decor.Name = "Decor"
	local root = Assets.GetRoot(decor)
	if root then
		local groundCenter = base.CFrame * CFrame.new(0, base.Size.Y / 2, 0)
		Assets.PivotRoot(decor, groundCenter * CFrame.new(0, root.Size.Y / 2, 0))
	end
	decor.Parent = model
end

local function resetEra(index: number)
	local model = MapService.GetPlotModel(index)
	local base = if model then model.PrimaryPart else nil
	if not model or not base then
		return
	end
	model:SetAttribute("Era", nil)
	base.Color = ERA_GROUND.Underground
	local decor = model:FindFirstChild("Decor")
	if decor then
		decor:Destroy()
	end
end

-- Colocação ------------------------------------------------------------------

local function buildStage(player: Player, tier: number, origin: Attachment): Model?
	local def = StageCalc.GetDef(tier)
	local stage = Assets.GetStageTemplate(def.Tier):Clone()
	local root = Assets.GetRoot(stage)
	if not root then
		stage:Destroy()
		return nil
	end
	stage.Name = "Stage"
	stage:SetAttribute("Tier", def.Tier)
	stage:SetAttribute("OwnerUserId", player.UserId)
	-- Root com a face da frente na linha StageOrigin, assente no chão, a crescer para trás
	Assets.PivotRoot(stage, origin.WorldCFrame * CFrame.new(0, root.Size.Y / 2, root.Size.Z / 2))
	return stage
end

--[[
	Coloca o palco do tier atual do jogador.
	animateFromTier: se indicado, anima a troca a partir desse tier (o palco atual vira "StageOld").
	kind: "Prestige" para o reset do World Tour (animação própria, mais longa).
]]
function StageService.PlaceStage(player: Player, animateFromTier: number?, kind: string?): boolean
	local index = PlotService.GetPlotId(player)
	local data = DataService.GetProfile(player)
	if not index or not data then
		return false
	end
	local model = MapService.GetPlotModel(index)
	local base = if model then model.PrimaryPart else nil
	local origin = if base then base:FindFirstChild("StageOrigin") else nil
	if not model or not origin or not origin:IsA("Attachment") then
		return false
	end

	local current = model:FindFirstChild("Stage")
	local animate = animateFromTier ~= nil and current ~= nil

	-- Cancela uma transição anterior ainda a decorrer (o "StageOld" antigo desaparece já)
	local token = nextToken(index)
	local staleOld = model:FindFirstChild("StageOld")
	if staleOld then
		staleOld:Destroy()
	end
	if current then
		if animate then
			current.Name = "StageOld"
		else
			current:Destroy()
		end
	end

	local stage = buildStage(player, data.StageTier, origin)
	if not stage then
		return false
	end
	stage.Parent = model
	applyEra(index, StageCalc.GetDef(data.StageTier).Era)

	if animate and animateFromTier then
		local timing = StageCalc.GetTimingForKind(kind, animateFromTier, data.StageTier)
		local duration = StageCalc.GetTransitionDuration(timing)
		local transitionId = (transitionIds[index] or 0) + 1
		transitionIds[index] = transitionId
		transitioning[index] = true

		model:SetAttribute("TransitionStart", Workspace:GetServerTimeNow())
		model:SetAttribute("TransitionFrom", animateFromTier)
		model:SetAttribute("TransitionTo", data.StageTier)
		model:SetAttribute("TransitionEra", StageCalc.IsEraChange(animateFromTier, data.StageTier))
		model:SetAttribute("TransitionKind", kind or "Stage")
		model:SetAttribute("TransitionWorldTour", data.WorldTours)
		model:SetAttribute("TransitionId", transitionId) -- último: o cliente reage a este

		task.delay(duration + 0.25, function()
			if tokens[index] ~= token then
				return -- cancelada (dono saiu, wipe ou nova troca)
			end
			transitioning[index] = nil
			local old = model:FindFirstChild("StageOld")
			if old then
				old:Destroy()
			end
			clearTransitionAttributes(model)
		end)
	else
		transitioning[index] = nil
		clearTransitionAttributes(model)
	end

	PlotService.RefreshSign(index)
	stagePlaced:Fire(player)
	return true
end

-- Compra ---------------------------------------------------------------------

function StageService.IsTransitioning(player: Player): boolean
	local index = PlotService.GetPlotId(player)
	return index ~= nil and transitioning[index] == true
end

function StageService.PurchaseTier(player: Player, targetTier: number): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data or not PlotService.GetPlotId(player) then
		return false, "O teu festival ainda está a carregar."
	end
	if StageService.IsTransitioning(player) then
		return false, "O palco ainda está a ser montado — espera uns segundos."
	end

	local currentTier = data.StageTier
	if targetTier > StagesConfig.MaxTier then
		return false, "Já tens o palco máximo."
	end
	local status = StageCalc.GetStatus(targetTier, currentTier, data.WorldTours)
	local def = StageCalc.GetDef(targetTier)
	if status == "Current" or status == "Owned" then
		return false, def.Name .. " já está construído."
	elseif status == "NeedPrevious" then
		return false, "Compra primeiro o Tier " .. (currentTier + 1) .. "."
	elseif status == "NeedWorldTours" then
		return false, string.format("%s requer %d World Tour(s).", def.Name, def.RequiredWorldTours)
	end

	-- "Negociação" (árvore de Prestige) reduz o custo
	local costCut = PrestigeCalc.GetSkillEffects(data.SkillTree).StageCostCut
	local cost = BigNum.fromNumber(def.Cost * (1 - math.clamp(costCut, 0, 0.9)))
	if not EconomyService.TrySpendHype(player, cost) then
		return false, "Hype insuficiente para " .. def.Name .. " (" .. NumberFormatter.format(cost) .. ")."
	end

	data.StageTier = targetTier
	EconomyService.InvalidateRates(player) -- novo multiplicador global
	PlayerStateService.MarkDirty(player)
	StageService.PlaceStage(player, currentTier)
	stageChanged:Fire(player, currentTier, targetTier)

	Diag.Log("Stage", string.format("%s comprou o Tier %d (%s)", player.Name, targetTier, def.Name))
	return true,
		string.format(
			"%s construído! Hype ×%s",
			def.Name,
			NumberFormatter.format(StageCalc.GetMultiplier(targetTier))
		)
end

-- Debug: muda o tier sem custo nem requisitos (com animação opcional)
function StageService.SetTier(player: Player, tier: number, animate: boolean?): boolean
	local data = DataService.GetProfile(player)
	if not data or tier < 1 or tier > StagesConfig.MaxTier or tier % 1 ~= 0 then
		return false
	end
	local previous = data.StageTier
	data.StageTier = tier
	EconomyService.InvalidateRates(player)
	PlayerStateService.MarkDirty(player)
	return StageService.PlaceStage(player, if animate and previous ~= tier then previous else nil)
end

-- Ciclo de vida --------------------------------------------------------------

function StageService.Init()
	ServerNet.Connect(RemoteDefs.Defs.BuyStage, function(player: Player, tierArg: unknown)
		local _, message = StageService.PurchaseTier(player, tierArg :: number)
		local notice: Types.Notice = { Kind = "Info", Text = message }
		PlayerStateService.Notify(player, notice)
	end)

	-- Perfil carregado (ou reiniciado): coloca o palco sem animação, cancelando qualquer transição
	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player)
		StageService.PlaceStage(player)
	end))
	trove:Add(PlotService.PlotAssigned:Connect(function(player: Player)
		StageService.PlaceStage(player)
	end))
	-- Dono saiu (mesmo a meio de uma montagem): limpa tudo de imediato
	trove:Add(PlotService.PlotReleased:Connect(function(_player: Player, index: number)
		clearStage(index)
		resetEra(index)
	end))

	for index = 1, MapConfig.Plots.Count do
		tokens[index] = 0
	end
end

function StageService.Start() end

return StageService
