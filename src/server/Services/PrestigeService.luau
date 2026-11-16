--!strict
--[[
	PrestigeService
	World Tour e árvore de habilidades permanente (Discos de Platina).

	World Tour (validado no servidor, reset aplicado de uma só vez antes da animação):
	  ganha Discos (PrestigeCalc) · +1 World Tour (Fama ×1.5) ·
	  reinicia Hype, Hype da run, equipamento, palco (tier inicial da árvore, sempre dentro
	  dos bloqueios de World Tour), Bass Drop, boost e cooldowns ·
	  mantém artistas, árvore, Discos por gastar, pirotecnia desbloqueada e estatísticas.
	O palco desmonta-se com a transição "Prestige" (replicada a todos), a placa mostra as
	estrelas de Tour e a entrada do terreno ganha o arco + estandartes de Prestige.
	Sair a meio da animação é seguro: os dados já foram reiniciados por inteiro.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.Economy)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local PrestigeConfig = require(ReplicatedStorage.Shared.Config.Prestige)
local SkillTreeConfig = require(ReplicatedStorage.Shared.Config.SkillTree)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local Placeholders = require(script.Parent.Parent.World.Placeholders)
local Assets = require(script.Parent.Parent.World.Assets)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PyroService = require(script.Parent.PyroService)
local BassDropService = require(script.Parent.BassDropService)
local ArtistService = require(script.Parent.ArtistService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local StageService = require(script.Parent.StageService)
local MonetizationService = require(script.Parent.MonetizationService)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DECOR_NAME = "PrestigeDecor"

local PrestigeService = {}

local worldTourCompleted: Signal.Signal<Player, number> = Signal.new()

-- (jogador, nº do World Tour) — missões e conquistas
PrestigeService.WorldTourCompleted = worldTourCompleted

local trove = Trove.new()

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

-- Decoração de Prestige ------------------------------------------------------------

local function archColor(worldTours: number): (Color3, string)
	local chosen = PrestigeConfig.ArchLevels[1]
	for _, level in PrestigeConfig.ArchLevels do
		if worldTours >= level.MinTours then
			chosen = level
		end
	end
	return chosen.Color, chosen.Name
end

local function applyDecor(index: number, worldTours: number)
	local model = MapService.GetPlotModel(index)
	local base = if model then model.PrimaryPart else nil
	if not model or not base then
		return
	end
	local previous = model:FindFirstChild(DECOR_NAME)
	if previous then
		previous:Destroy()
	end
	if worldTours <= 0 then
		return
	end

	local color, levelName = archColor(worldTours)
	local plots = MapConfig.Plots
	local frontCenter = base.CFrame * CFrame.new(0, base.Size.Y / 2, -plots.Depth / 2 + 1)

	local decor = Instance.new("Model")
	decor.Name = DECOR_NAME
	decor:SetAttribute("WorldTours", worldTours)

	-- Arco sobre a entrada
	local arch = Assets.GetPrestigeArchTemplate():Clone()
	arch.Name = "Arch"
	local root = Assets.GetRoot(arch)
	if root then
		Assets.PivotRoot(arch, frontCenter * CFrame.new(0, root.Size.Y / 2, 0))
	end
	if arch:GetAttribute("Placeholder") == true then
		for _, descendant in arch:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= root then
				descendant.Color = color
				descendant.Material = if worldTours >= 5 then Enum.Material.Neon else Enum.Material.Metal
			end
		end
	end
	local beam = arch:FindFirstChild("Beam", true)
	if beam and beam:IsA("BasePart") then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = beam
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Text = string.format("WORLD TOUR ×%d · %s", worldTours, string.upper(levelName))
		label.Parent = gui
	end
	arch.Parent = decor

	-- Um estandarte por World Tour (até MaxBanners), ao longo da frente do terreno
	local banners = math.min(worldTours, PrestigeConfig.MaxBanners)
	for bannerIndex = 1, banners do
		local side = if bannerIndex % 2 == 1 then -1 else 1
		local slot = math.ceil(bannerIndex / 2)
		local x = side * (plots.EntranceWidth / 2 + 4 + (slot - 1) * 8)
		local pole = Placeholders.NewPart(
			"BannerPole",
			Vector3.new(0.4, 9, 0.4),
			frontCenter * CFrame.new(x, 4.5, 1),
			Color3.fromRGB(60, 60, 64),
			Enum.Material.Metal,
			decor
		)
		pole.CanCollide = false
		local flag = Placeholders.NewPart(
			"Banner",
			Vector3.new(2.4, 3.2, 0.2),
			frontCenter * CFrame.new(x + side * 1.3, 7, 1),
			color,
			Enum.Material.Neon,
			decor
		)
		flag.CanCollide = false
	end

	decor.Parent = model
end

local function refreshDecorFor(player: Player)
	local index = PlotService.GetPlotId(player)
	local data = DataService.GetProfile(player)
	if index and data then
		applyDecor(index, data.WorldTours)
		PlotService.RefreshSign(index)
	end
end

-- Árvore -----------------------------------------------------------------------

function PrestigeService.BuyNode(player: Player, nodeId: string): (boolean, string)
	local data = DataService.GetProfile(player)
	local def = SkillTreeConfig.ById[nodeId]
	if not data or not def then
		return false, "Nó indisponível."
	end
	local status = PrestigeCalc.GetNodeStatus(data.SkillTree, nodeId, data.PlatinumDiscs)
	local level = PrestigeCalc.GetLevel(data.SkillTree, nodeId)
	if status == "Maxed" then
		return false, def.Name .. " já está no nível máximo."
	elseif status == "Locked" then
		local requirement = def.Requires
		local requiredDef = if requirement then SkillTreeConfig.ById[requirement] else nil
		return false,
			string.format("%s requer %s nível %d.", def.Name, if requiredDef then requiredDef.Name else "?", def.RequiresLevel or 1)
	elseif status == "TooExpensive" then
		return false, string.format("Precisas de %d Discos de Platina.", PrestigeCalc.GetNextCost(def, level))
	end

	data.PlatinumDiscs -= PrestigeCalc.GetNextCost(def, level)
	data.SkillTree[nodeId] = level + 1
	EconomyService.InvalidateRates(player)
	PlayerStateService.MarkDirty(player)
	return true, string.format("%s → nível %d: %s", def.Name, level + 1, PrestigeCalc.DescribeEffect(def, level + 1))
end

-- Debug: devolve todos os Discos gastos e limpa a árvore
function PrestigeService.ResetTree(player: Player): number
	local data = DataService.GetProfile(player)
	if not data then
		return 0
	end
	local refund = 0
	for _, def in SkillTreeConfig.List do
		for level = 0, PrestigeCalc.GetLevel(data.SkillTree, def.Id) - 1 do
			refund += PrestigeCalc.GetNextCost(def, level)
		end
	end
	table.clear(data.SkillTree)
	data.PlatinumDiscs += refund
	EconomyService.InvalidateRates(player)
	PlayerStateService.MarkDirty(player)
	return refund
end

-- World Tour -------------------------------------------------------------------

function PrestigeService.GetPreview(player: Player): (number, boolean, string?)
	local data = DataService.GetProfile(player)
	if not data then
		return 0, false, "Perfil não carregado."
	end
	local discs = PrestigeCalc.GetDiscsPreview(data.RunHypeEarned, data.StageTier, data.SkillTree, MonetizationService.GetDiscBonus(player))
	local can, reason = PrestigeCalc.CanWorldTour(data.StageTier, discs)
	return discs, can, reason
end

-- force (debug): ignora os requisitos e garante pelo menos 1 Disco
function PrestigeService.DoWorldTour(player: Player, force: boolean?): (boolean, string)
	local data = DataService.GetProfile(player)
	local index = PlotService.GetPlotId(player)
	if not data or not index then
		return false, "O teu festival ainda está a carregar."
	end
	if StageService.IsTransitioning(player) then
		return false, "Espera que o palco acabe de ser montado."
	end
	local discs, can, reason = PrestigeService.GetPreview(player)
	if not can and not force then
		return false, reason or "Ainda não podes fazer World Tour."
	end
	discs = math.max(discs, if force then 1 else 0)

	-- Reset atómico (sem yields) ------------------------------------------------
	local fromTier = data.StageTier
	data.PlatinumDiscs += discs
	data.TotalDiscsEarned += discs
	data.WorldTours += 1

	local skills = PrestigeCalc.GetSkillEffects(data.SkillTree)
	data.Hype = BigNum.fromNumber(EconomyConfig.StartingHype + skills.StartingHype)
	data.RunHypeEarned = BigNum.ZERO
	local equipment: { [string]: number } = {}
	if skills.StartingGenerators > 0 then
		for _, id in PrestigeConfig.StartingGeneratorIds do
			equipment[id] = skills.StartingGenerators
		end
	end
	data.Equipment = equipment
	data.StageTier = PrestigeCalc.GetStartTier(data.SkillTree, data.WorldTours)

	EconomyService.SetDebugPassive(player, nil)
	EconomyService.SetBoost(player, 1, 0)
	EconomyService.InvalidateRates(player)
	PyroService.ResetCooldowns(player)
	BassDropService.ResetSession(player)
	ArtistService.Commit(player) -- novos slots por World Tour
	PlayerStateService.MarkDirty(player)

	-- Apresentação (replicada) -------------------------------------------------
	StageService.PlaceStage(player, fromTier, "Prestige")
	applyDecor(index, data.WorldTours)
	PlotService.RefreshSign(index)

	local announcement = string.format(
		"%s partiu em World Tour #%d e ganhou %s Discos de Platina!",
		player.DisplayName,
		data.WorldTours,
		NumberFormatter.formatInteger(discs)
	)
	for _, other in Players:GetPlayers() do
		notify(other, announcement)
	end
	Diag.Log("Prestige", string.format("%s: World Tour #%d, +%d Discos (Tier %d → %d)", player.Name, data.WorldTours, discs, fromTier, data.StageTier))

	task.spawn(DataService.SaveNow, player) -- grava já uma alteração tão importante
	worldTourCompleted:Fire(player, data.WorldTours)
	return true, ""
end

-- Ciclo de vida --------------------------------------------------------------

function PrestigeService.Init()
	ServerNet.Connect(RemoteDefs.Defs.BuySkillNode, function(player: Player, nodeArg: unknown)
		local _, message = PrestigeService.BuyNode(player, nodeArg :: string)
		notify(player, message)
	end)
	ServerNet.Connect(RemoteDefs.Defs.DoWorldTour, function(player: Player)
		local ok, message = PrestigeService.DoWorldTour(player, false)
		if not ok then
			notify(player, message)
		end
	end)

	trove:Add(DataService.ProfileLoaded:Connect(refreshDecorFor))
	trove:Add(PlotService.PlotAssigned:Connect(refreshDecorFor))
	trove:Add(PlotService.PlotReleased:Connect(function(_player: Player, index: number)
		applyDecor(index, 0)
	end))
end

function PrestigeService.Start() end

return PrestigeService
