--!strict
--[[
	CrateAnimCalc
	Cálculos puros da apresentação das crates, partilhados servidor/cliente:
	  - IsMystery: que raridades aparecem como carta mistério (servidor marca, cliente mostra)
	  - BuildFiller: cartas de enchimento da roleta com as probabilidades reais da crate
	    (nunca inclui cartas mistério; o resultado vem sempre do servidor)
	  - ordem de revelação da grelha x10, melhor mistério
	  - fases e durações da cinemática, atraso até a cinemática começar (para o
	    servidor sincronizar a versão leve dos outros jogadores e a proteção)
]]

local Types = require(script.Parent.Parent.Types)
local CrateAnimConfig = require(script.Parent.Parent.Config.CrateAnimation)
local RaritiesConfig = require(script.Parent.Parent.Config.Rarities)
local ArtistCalc = require(script.Parent.ArtistCalc)

type CrateDef = Types.CrateDef
type CrateItem = Types.CrateItem
type CrateOdd = Types.CrateOdd
type CinematicPhase = Types.CinematicPhase
type RarityDef = Types.RarityDef

export type FillerCard = {
	ArtistId: string,
	Rarity: string,
}

local CrateAnimCalc = {}

local MYSTERY_MIN_INDEX = RaritiesConfig.IndexById[CrateAnimConfig.MysteryMinRarity] or math.huge

-- A raridade aparece como carta mistério nesta crate?
function CrateAnimCalc.IsMystery(crate: CrateDef, rarityId: string): boolean
	local index = RaritiesConfig.IndexById[rarityId]
	if not index or index < MYSTERY_MIN_INDEX then
		return false
	end
	for _, odd in ArtistCalc.GetCrateOdds(crate) do
		if odd.Rarity.Id == rarityId then
			return odd.Chance <= CrateAnimConfig.MysteryThreshold
		end
	end
	return false
end

-- Probabilidades da crate sem as raridades mistério (renormalizadas), para o enchimento
function CrateAnimCalc.GetFillerOdds(crate: CrateDef): { CrateOdd }
	local result: { CrateOdd } = {}
	local total = 0
	for _, odd in ArtistCalc.GetCrateOdds(crate) do
		if not CrateAnimCalc.IsMystery(crate, odd.Rarity.Id) then
			table.insert(result, { Rarity = odd.Rarity, Chance = odd.Chance, Slot = odd.Slot })
			total += odd.Chance
		end
	end
	if total > 0 then
		for _, odd in result do
			odd.Chance /= total
		end
	end
	return result
end

-- Cartas de enchimento da roleta (Random do cliente; só apresentação)
function CrateAnimCalc.BuildFiller(rng: Random, crate: CrateDef, count: number): { FillerCard }
	local odds = CrateAnimCalc.GetFillerOdds(crate)
	local artists = ArtistCalc.GetCrateArtists(crate)
	local cards: { FillerCard } = {}
	if #odds == 0 or #artists == 0 then
		return cards
	end
	for _ = 1, count do
		local roll = rng:NextNumber()
		local rarity = odds[#odds].Rarity
		for _, odd in odds do
			roll -= odd.Chance
			if roll < 0 then
				rarity = odd.Rarity
				break
			end
		end
		table.insert(cards, { ArtistId = artists[rng:NextInteger(1, #artists)].Id, Rarity = rarity.Id })
	end
	return cards
end

-- Probabilidade a mostrar na carta (0..1) — a da raridade na crate
function CrateAnimCalc.GetChance(crate: CrateDef, rarityId: string): number
	for _, odd in ArtistCalc.GetCrateOdds(crate) do
		if odd.Rarity.Id == rarityId then
			return odd.Chance
		end
	end
	return 0
end

-- Efeito ao parar/revelar, pela família da raridade
function CrateAnimCalc.GetStopEffect(rarity: RarityDef): Types.CrateStopEffect
	return CrateAnimConfig.StopEffects[rarity.Family] or "Simple"
end

-- Ordem de revelação da grelha x10: índices dos itens da menos rara para a mais rara
-- (mistérios sempre no fim; empate mantém a ordem original)
function CrateAnimCalc.GetRevealOrder(items: { CrateItem }): { number }
	local order: { number } = {}
	for index in items do
		table.insert(order, index)
	end
	local function key(index: number): number
		local item = items[index]
		local rarity = RaritiesConfig.IndexById[item.Rarity] or 0
		return (if item.Mystery then 1000 else 0) + rarity
	end
	table.sort(order, function(a: number, b: number): boolean
		local keyA, keyB = key(a), key(b)
		if keyA ~= keyB then
			return keyA < keyB
		end
		return a < b
	end)
	return order
end

-- Índice do melhor mistério do resultado (nil se não houver)
function CrateAnimCalc.GetBestMystery(items: { CrateItem }): number?
	local best: number? = nil
	local bestRarity = -1
	for index, item in items do
		local rarity = RaritiesConfig.IndexById[item.Rarity] or 0
		if item.Mystery and rarity > bestRarity then
			best = index
			bestRarity = rarity
		end
	end
	return best
end

-- Fases da cinemática (completa ou "Animação rápida")
function CrateAnimCalc.GetPhases(fast: boolean): { CinematicPhase }
	if not fast then
		return CrateAnimConfig.Timeline
	end
	local result: { CinematicPhase } = {}
	for _, phase in CrateAnimConfig.Timeline do
		if table.find(CrateAnimConfig.FastPhases, phase.Name) then
			table.insert(result, phase)
		end
	end
	return result
end

function CrateAnimCalc.GetDuration(phases: { CinematicPhase }): number
	local total = 0
	for _, phase in phases do
		total += phase.Duration
	end
	return total
end

-- Segundos desde o início de `name` em `phases` (nil se a fase não existir)
function CrateAnimCalc.GetPhaseStart(phases: { CinematicPhase }, name: string): number?
	local elapsed = 0
	for _, phase in phases do
		if phase.Name == name then
			return elapsed
		end
		elapsed += phase.Duration
	end
	return nil
end

-- Segundos desde a chegada do resultado até a cinemática começar no cliente do dono
function CrateAnimCalc.GetCinematicDelay(count: number, fast: boolean, cinematicOnly: boolean): number
	if cinematicOnly then
		return 0
	end
	if count <= 1 then
		local roulette = CrateAnimConfig.Roulette
		return (if fast then roulette.FastDuration else roulette.Duration) + CrateAnimConfig.MysteryPause
	end
	local grid = CrateAnimConfig.Grid
	local step = if fast then grid.FastRevealStep else grid.RevealStep
	return grid.StartDelay + count * step + grid.FlipTime + CrateAnimConfig.MysteryPause
end

return CrateAnimCalc
