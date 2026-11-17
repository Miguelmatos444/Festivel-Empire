--!strict
--[[
	IndexCalc
	Cálculos puros do Índice de Artistas (Fase 10), partilhados servidor/cliente:
	  - combinações válidas artista × raridade (as raridades que a crate de cada
	    artista pode dar, segundo ArtistCalc.GetCrateWindow)
	  - progresso por raridade e total, prémios por reclamar, Índice completo
	  - escolha automática do artista da vitrine
	A UI mostra e o servidor valida sempre com estas funções.
]]

local Types = require(script.Parent.Parent.Types)
local ArtistsConfig = require(script.Parent.Parent.Config.Artists)
local RaritiesConfig = require(script.Parent.Parent.Config.Rarities)
local ArtistIndexConfig = require(script.Parent.Parent.Config.ArtistIndex)
local VariantsConfig = require(script.Parent.Parent.Config.Variants)
local ArtistCalc = require(script.Parent.ArtistCalc)

type ArtistData = Types.ArtistData
type ArtistDef = Types.ArtistDef
type IndexReward = Types.IndexReward

export type Combo = {
	ArtistId: string,
	Rarity: string,
	CrateId: string,
	Key: string,
}

local IndexCalc = {}

function IndexCalc.Key(artistId: string, rarityId: string): string
	return artistId .. "|" .. rarityId
end

-- Combinações agrupadas por raridade (ordem: crates, depois artistas), calculadas uma vez
local combosByRarity: { [string]: { Combo } } = {}
local validKeys: { [string]: boolean } = {}
local totalCombos = 0
do
	for _, rarity in RaritiesConfig.List do
		combosByRarity[rarity.Id] = {}
	end
	for _, crate in ArtistsConfig.Crates do
		local first, last = ArtistCalc.GetCrateWindow(crate)
		for index = first, last do
			local rarity = RaritiesConfig.List[index]
			for _, artist in ArtistCalc.GetCrateArtists(crate) do
				local key = IndexCalc.Key(artist.Id, rarity.Id)
				table.insert(combosByRarity[rarity.Id], { ArtistId = artist.Id, Rarity = rarity.Id, CrateId = crate.Id, Key = key })
				validKeys[key] = true
				totalCombos += 1
			end
		end
	end
	for _, list in combosByRarity do
		table.freeze(list)
	end
end

function IndexCalc.GetCombos(rarityId: string): { Combo }
	return combosByRarity[rarityId] or {}
end

function IndexCalc.IsValidKey(key: string): boolean
	return validKeys[key] == true
end

function IndexCalc.GetTotalCombos(): number
	return totalCombos
end

-- (descobertas, total) de uma raridade
function IndexCalc.GetProgress(discovered: { [string]: boolean }, rarityId: string): (number, number)
	local combos = IndexCalc.GetCombos(rarityId)
	local have = 0
	for _, combo in combos do
		if discovered[combo.Key] then
			have += 1
		end
	end
	return have, #combos
end

function IndexCalc.GetTotalProgress(discovered: { [string]: boolean }): (number, number)
	local have = 0
	for key, value in discovered do
		if value and validKeys[key] then
			have += 1
		end
	end
	return have, totalCombos
end

function IndexCalc.IsRarityComplete(discovered: { [string]: boolean }, rarityId: string): boolean
	local have, total = IndexCalc.GetProgress(discovered, rarityId)
	return total > 0 and have >= total
end

function IndexCalc.IsIndexComplete(discovered: { [string]: boolean }): boolean
	local have, total = IndexCalc.GetTotalProgress(discovered)
	return have >= total
end

function IndexCalc.GetReward(rarityId: string): IndexReward?
	return ArtistIndexConfig.Rewards[rarityId]
end

-- A raridade (ou o prémio final, com Config/ArtistIndex.FinalKey) pode ser reclamada agora?
function IndexCalc.CanClaim(discovered: { [string]: boolean }, claimed: { [string]: boolean }, key: string): boolean
	if claimed[key] then
		return false
	end
	if key == ArtistIndexConfig.FinalKey then
		return IndexCalc.IsIndexComplete(discovered)
	end
	return ArtistIndexConfig.Rewards[key] ~= nil and IndexCalc.IsRarityComplete(discovered, key)
end

-- Nº de prémios prontos a reclamar (indicador no botão do Índice)
function IndexCalc.GetClaimableCount(discovered: { [string]: boolean }, claimed: { [string]: boolean }): number
	local count = 0
	for _, rarity in RaritiesConfig.List do
		if IndexCalc.CanClaim(discovered, claimed, rarity.Id) then
			count += 1
		end
	end
	if IndexCalc.CanClaim(discovered, claimed, ArtistIndexConfig.FinalKey) then
		count += 1
	end
	return count
end

-- Slots extra permanentes vindos do Índice
function IndexCalc.GetBonusSlots(claimed: { [string]: boolean }): number
	return if claimed[ArtistIndexConfig.FinalKey] then ArtistIndexConfig.Final.SlotBonus else 0
end

-- Variantes Brilhantes (separador do Índice): artista × variante ---------------------------

function IndexCalc.VariantKey(artistId: string, variantId: string): string
	return artistId .. "|" .. variantId
end

-- Os 25 artistas, por ordem de crate (mesma lista para todas as variantes)
local allArtists: { ArtistDef } = {}
for _, crate in ArtistsConfig.Crates do
	for _, artist in ArtistCalc.GetCrateArtists(crate) do
		table.insert(allArtists, artist)
	end
end
table.freeze(allArtists)

function IndexCalc.GetVariantArtists(): { ArtistDef }
	return allArtists
end

function IndexCalc.GetVariantProgress(variants: { [string]: boolean }, variantId: string): (number, number)
	local have = 0
	for _, artist in allArtists do
		if variants[IndexCalc.VariantKey(artist.Id, variantId)] then
			have += 1
		end
	end
	return have, #allArtists
end

function IndexCalc.GetVariantTotalProgress(variants: { [string]: boolean }): (number, number)
	local have, total = 0, 0
	for _, variant in VariantsConfig.List do
		local vHave, vTotal = IndexCalc.GetVariantProgress(variants, variant.Id)
		have += vHave
		total += vTotal
	end
	return have, total
end

-- Melhor artista para a vitrine automática: raridade, depois estrelas, depois bónus
function IndexCalc.PickShowcase(artists: { [string]: ArtistData }): string?
	local bestUid: string? = nil
	local bestRarity, bestStars, bestBonus = -1, -1, -1
	for uid, artist in artists do
		local rarity = ArtistCalc.GetRarityIndex(artist.Rarity)
		local bonus = ArtistCalc.GetBonus(artist)
		local better = rarity > bestRarity
			or (rarity == bestRarity and artist.Stars > bestStars)
			or (rarity == bestRarity and artist.Stars == bestStars and bonus > bestBonus)
			or (rarity == bestRarity and artist.Stars == bestStars and bonus == bestBonus and bestUid ~= nil and uid < bestUid)
		if better then
			bestUid, bestRarity, bestStars, bestBonus = uid, rarity, artist.Stars, bonus
		end
	end
	return bestUid
end

-- Artista que está na vitrine: o manual se ainda existir, senão o automático
function IndexCalc.ResolveShowcase(artists: { [string]: ArtistData }, mode: string, manualUid: string): string?
	if mode == "Manual" and manualUid ~= "" and artists[manualUid] then
		return manualUid
	end
	return IndexCalc.PickShowcase(artists)
end

return IndexCalc
