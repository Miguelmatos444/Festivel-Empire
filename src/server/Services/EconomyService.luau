--!strict
--[[
	EconomyService
	Toda a economia de Hype é calculada aqui (servidor autoritativo):
	  - cliques (via ServerNet, já com rate limit)
	  - rendimento passivo num único loop a 1 Hz para todos os jogadores
	  - rendimento offline no load do perfil
	  - custos em massa por soma geométrica
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.Economy)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local EquipmentCalc = require(ReplicatedStorage.Shared.Calc.EquipmentCalc)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)

type BigNum = BigNum.BigNum
type ProfileData = Types.ProfileData

type RateCache = {
	PerClick: BigNum,
	PerSecond: BigNum,
}

type Boost = {
	Multiplier: number,
	EndsAt: number, -- os.clock()
}

local MAX_TICK_CATCHUP = 5 -- após lag, nunca creditar mais de 5 ticks de uma vez

local EconomyService = {}

local hypeChanged: Signal.Signal<Player> = Signal.new()
local offlineEarned: Signal.Signal<Player, BigNum, number> = Signal.new()
local clicked: Signal.Signal<Player> = Signal.new()

-- Disparado por cada batida aceite pelo servidor (usado pelo BassDropService para energia).
EconomyService.Clicked = clicked

-- Disparado sempre que o Hype de um jogador muda.
EconomyService.HypeChanged = hypeChanged
-- (jogador, valor ganho, segundos contabilizados)
EconomyService.OfflineEarned = offlineEarned

local trove = Trove.new()
local debugPassiveOverride: { [Player]: BigNum } = {}
local rateCache: { [Player]: RateCache } = {}
local boosts: { [Player]: Boost } = {}
local artistModifiers: { [Player]: { Hype: number, Click: number } } = {}

local function assertGrowthRate(rate: number)
	local bounds = EconomyConfig.GrowthRate
	assert(
		rate >= bounds.Min and rate <= bounds.Max,
		string.format("GrowthRate %.3f fora de [%.2f, %.2f]", rate, bounds.Min, bounds.Max)
	)
end

-- Taxas ----------------------------------------------------------------------

-- Taxas em cache por jogador; recalculadas só após InvalidateRates (compras, reset).
-- Multiplicadores futuros (artistas, skills, Bass Drop) entram neste cálculo.
local function getRates(player: Player): RateCache?
	local cached = rateCache[player]
	if cached then
		return cached
	end
	local data = DataService.GetProfile(player)
	if not data then
		return nil
	end
	local modifiers = artistModifiers[player]
	local skills = PrestigeCalc.GetSkillEffects(data.SkillTree)
	-- Bónus dos artistas, ampliado pela "Aura do Público" da árvore
	local artistMultiplier = 1 + ((if modifiers then modifiers.Hype else 1) - 1) * (1 + skills.ArtistBonus)
	local globalMultiplier = StageCalc.GetMultiplier(data.StageTier)
		* PrestigeCalc.GetFameMultiplier(data.WorldTours)
		* skills.HypeMultiplier
		* artistMultiplier
	local clickMultiplier = (1 + (if modifiers then modifiers.Click else 0)) * skills.ClickMultiplier
	local rates: RateCache = {
		PerClick = BigNum.mulNumber(EquipmentCalc.GetHypePerClick(data.Equipment), globalMultiplier * clickMultiplier),
		PerSecond = BigNum.mulNumber(EquipmentCalc.GetPassivePerSecond(data.Equipment), globalMultiplier),
	}
	rateCache[player] = rates
	return rates
end

-- Definido pelo ArtistService: multiplicador global de Hype e bónus extra por batida
function EconomyService.SetArtistModifiers(player: Player, hypeMultiplier: number, clickBonus: number)
	artistModifiers[player] = { Hype = hypeMultiplier, Click = clickBonus }
	EconomyService.InvalidateRates(player)
end

function EconomyService.InvalidateRates(player: Player)
	rateCache[player] = nil
	hypeChanged:Fire(player)
end

function EconomyService.GetHypePerClick(player: Player): BigNum
	local rates = getRates(player)
	return if rates then rates.PerClick else BigNum.fromNumber(EconomyConfig.BaseHypePerClick)
end

function EconomyService.GetHypePerSecond(player: Player): BigNum
	local override = debugPassiveOverride[player]
	if override then
		return override
	end
	local rates = getRates(player)
	return if rates then rates.PerSecond else BigNum.ZERO
end

-- Boost do Bass Drop -------------------------------------------------------------

-- Aplica-se a batidas e ao passivo (não ao offline). multiplier <= 1 remove o boost.
function EconomyService.SetBoost(player: Player, multiplier: number, endsAt: number)
	if multiplier <= 1 then
		boosts[player] = nil
	else
		boosts[player] = { Multiplier = multiplier, EndsAt = endsAt }
	end
end

function EconomyService.GetBoostMultiplier(player: Player): number
	local boost = boosts[player]
	if not boost then
		return 1
	end
	if os.clock() >= boost.EndsAt then
		boosts[player] = nil
		return 1
	end
	return boost.Multiplier
end

-- Saldo ----------------------------------------------------------------------

function EconomyService.AddHype(player: Player, amount: BigNum): boolean
	local data = DataService.GetProfile(player)
	if not data or amount.m <= 0 then
		return false
	end
	data.Hype = BigNum.add(data.Hype, amount)
	data.TotalHypeEarned = BigNum.add(data.TotalHypeEarned, amount)
	data.RunHypeEarned = BigNum.add(data.RunHypeEarned, amount)
	hypeChanged:Fire(player)
	return true
end

function EconomyService.TrySpendHype(player: Player, cost: BigNum): boolean
	local data = DataService.GetProfile(player)
	if not data or cost.m < 0 or BigNum.lt(data.Hype, cost) then
		return false
	end
	local remaining = BigNum.sub(data.Hype, cost)
	data.Hype = if remaining.m < 0 then BigNum.ZERO else remaining
	hypeChanged:Fire(player)
	return true
end

-- Debug: define o saldo diretamente (não conta para TotalHypeEarned)
function EconomyService.SetHype(player: Player, value: BigNum): boolean
	local data = DataService.GetProfile(player)
	if not data then
		return false
	end
	data.Hype = if value.m < 0 then BigNum.ZERO else value
	hypeChanged:Fire(player)
	return true
end

-- Debug: força um rendimento passivo para a sessão (nil remove). Não é gravado.
function EconomyService.SetDebugPassive(player: Player, value: BigNum?)
	debugPassiveOverride[player] = value
	hypeChanged:Fire(player)
end

-- Custos ---------------------------------------------------------------------

function EconomyService.GetBulkCost(baseCost: number, rate: number, level: number, count: number): BigNum
	assertGrowthRate(rate)
	return BigNum.geometricCost(baseCost, rate, level, count)
end

function EconomyService.GetMaxAffordable(player: Player, baseCost: number, rate: number, level: number): number
	assertGrowthRate(rate)
	local data = DataService.GetProfile(player)
	if not data then
		return 0
	end
	return BigNum.maxAffordable(baseCost, rate, level, data.Hype)
end

-- Offline --------------------------------------------------------------------

function EconomyService.GrantOfflineEarnings(player: Player, seconds: number): BigNum
	local offline = EconomyConfig.Offline
	local counted = math.clamp(seconds, 0, offline.MaxSeconds)
	local data = DataService.GetProfile(player)
	local skillBonus = if data then PrestigeCalc.GetSkillEffects(data.SkillTree).OfflineEfficiency else 0
	local efficiency = math.min(offline.Efficiency + skillBonus, 1) -- "Eco Infinito"
	local earned = BigNum.mulNumber(EconomyService.GetHypePerSecond(player), counted * efficiency)
	if earned.m > 0 and EconomyService.AddHype(player, earned) then
		offlineEarned:Fire(player, earned, counted)
		return earned
	end
	return BigNum.ZERO
end

local function onProfileLoaded(player: Player, data: ProfileData)
	rateCache[player] = nil -- perfil novo ou reiniciado
	local lastOnline = data.LastOnline
	data.LastOnline = os.time()
	if lastOnline <= 0 then
		return -- jogador novo (ou perfil reiniciado)
	end
	local away = os.time() - lastOnline
	if away >= EconomyConfig.Offline.MinSecondsToReport then
		-- Adiado: os outros serviços (ex.: bónus dos artistas) aplicam-se primeiro
		task.defer(EconomyService.GrantOfflineEarnings, player, away)
	end
end

-- Cliques e tick -------------------------------------------------------------

local function onClick(player: Player)
	local data = DataService.GetProfile(player)
	if not data then
		Diag.LogSampled(
			"Economy",
			"noprofile:" .. player.UserId,
			string.format("batida de %s ignorada: perfil ainda não carregado", player.Name)
		)
		return
	end
	data.Stats.Clicks += 1
	local gain = BigNum.mulNumber(EconomyService.GetHypePerClick(player), EconomyService.GetBoostMultiplier(player))
	EconomyService.AddHype(player, gain)
	clicked:Fire(player)
end

local function tick(deltaTime: number)
	for _, player in DataService.GetLoadedPlayers() do
		local perSecond = EconomyService.GetHypePerSecond(player)
		if perSecond.m > 0 then
			local boosted = deltaTime * EconomyService.GetBoostMultiplier(player)
			EconomyService.AddHype(player, BigNum.mulNumber(perSecond, boosted))
		end
	end
end

local function tickLoop()
	local interval = EconomyConfig.TickInterval
	local last = os.clock()
	while true do
		task.wait(interval)
		local now = os.clock()
		tick(math.min(now - last, interval * MAX_TICK_CATCHUP))
		last = now
	end
end

-- Ciclo de vida --------------------------------------------------------------

function EconomyService.Init()
	ServerNet.Connect(RemoteDefs.Defs.Click, onClick)
	trove:Add(DataService.ProfileLoaded:Connect(onProfileLoaded))
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		debugPassiveOverride[player] = nil
		rateCache[player] = nil
		boosts[player] = nil
		artistModifiers[player] = nil
	end)
end

function EconomyService.Start()
	trove:Add(task.spawn(tickLoop))
end

return EconomyService
