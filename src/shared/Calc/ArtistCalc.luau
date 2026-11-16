--!strict
--[[
	ArtistCalc
	Cálculos puros dos artistas, partilhados por servidor e UI:
	bónus de Hype, habilidades (com raridade e estrelas), efeitos agregados dos
	artistas equipados (com limites), slots, sorteio de raridade e grupos de fusão.
	O sorteio recebe o Random do chamador: só o servidor o usa para resultados reais.
]]

local Types = require(script.Parent.Parent.Types)
local ArtistsConfig = require(script.Parent.Parent.Config.Artists)
local RaritiesConfig = require(script.Parent.Parent.Config.Rarities)
local PaidCratesConfig = require(script.Parent.Parent.Config.PaidCrates)
local PyroConfig = require(script.Parent.Parent.Config.Pyro)

type ArtistData = Types.ArtistData
type ArtistDef = Types.ArtistDef
type AbilityDef = Types.AbilityDef
type RarityDef = Types.RarityDef
type CrateDef = Types.CrateDef
type ArtistEffects = Types.ArtistEffects
type SaveDropEffect = Types.SaveDropEffect

local ArtistCalc = {}

local GRADE_ORDER: { [string]: number } = { Perfect = 4, Great = 3, Good = 2, Late = 1 }

-- Consultas ------------------------------------------------------------------

function ArtistCalc.GetRarity(id: string): RarityDef?
	return RaritiesConfig.ById[id]
end

function ArtistCalc.GetRarityIndex(id: string): number
	return RaritiesConfig.IndexById[id] or 0
end

function ArtistCalc.GetArtist(id: string): ArtistDef?
	return ArtistsConfig.ById[id]
end

function ArtistCalc.GetCrate(id: string): CrateDef?
	return ArtistsConfig.CratesById[id]
end

-- Valida dados vindos do DataStore
function ArtistCalc.IsValid(data: ArtistData): boolean
	return ArtistsConfig.ById[data.Id] ~= nil
		and RaritiesConfig.ById[data.Rarity] ~= nil
		and type(data.Stars) == "number"
		and data.Stars >= 1
		and data.Stars <= ArtistsConfig.MaxStars
		and data.Stars % 1 == 0
end

local function starIndex(stars: number): number
	return math.clamp(math.floor(stars), 1, ArtistsConfig.MaxStars)
end

-- Bónus de Hype próprio (sem Aura): raridade × era da crate × estrelas
function ArtistCalc.GetBonus(data: ArtistData): number
	local rarity = RaritiesConfig.ById[data.Rarity]
	local def = ArtistsConfig.ById[data.Id]
	local crate = if def then ArtistsConfig.CratesById[def.Crate] else nil
	if not rarity or not crate then
		return 0
	end
	return rarity.Bonus * crate.EraFactor * ArtistsConfig.StarBonus[starIndex(data.Stars)]
end

-- Habilidades ----------------------------------------------------------------

local function scaleAbility(ability: AbilityDef, scale: number): AbilityDef
	local cooldown = ability.Cooldown
	local value = ability.Value
	return {
		Kind = ability.Kind,
		Value = if value then value * scale else nil,
		Machine = ability.Machine,
		Grade = ability.Grade,
		Cooldown = if cooldown then cooldown / scale else nil,
	}
end

-- Lista de habilidades efetivas do artista (já escaladas por raridade e estrelas)
function ArtistCalc.GetAbilities(data: ArtistData): { AbilityDef }
	local result: { AbilityDef } = {}
	local def = ArtistsConfig.ById[data.Id]
	local rarity = RaritiesConfig.ById[data.Rarity]
	if not def or not rarity then
		return result
	end
	local starScale = ArtistsConfig.StarAbility[starIndex(data.Stars)]

	local own = def.Ability
	if own then
		table.insert(result, scaleAbility(own, rarity.AbilityScale * starScale))
	end
	if rarity.Duet then
		local partner = ArtistsConfig.ByCrateFamily[def.Crate .. "|Legendary"]
		local partnerAbility = if partner then partner.Ability else nil
		if partnerAbility then
			table.insert(result, scaleAbility(partnerAbility, starScale))
		end
	end
	if rarity.Aura > 0 then
		table.insert(result, { Kind = "Aura", Value = rarity.Aura * starScale })
	end
	if rarity.OmegaSave then
		table.insert(result, { Kind = "SaveDrop", Grade = "Perfect", Cooldown = ArtistsConfig.OmegaSaveCooldown / starScale })
	end
	return result
end

local function percent(value: number): string
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

function ArtistCalc.DescribeAbility(ability: AbilityDef): string
	local value = ability.Value or 0
	local kind = ability.Kind
	if kind == "ClickPower" then
		return "Batida Forte: +" .. percent(value) .. " Hype por acerto no palco"
	elseif kind == "Energy" then
		return "Carga: +" .. percent(value) .. " energia do Bass Drop"
	elseif kind == "WindowWiden" then
		return string.format("Ouvido Fino: janela +%.2f s", value)
	elseif kind == "BoostExtend" then
		return string.format("Eco: boost +%.1f s", value)
	elseif kind == "CooldownCut" then
		return "Montagem Rápida: cooldowns −" .. percent(value)
	elseif kind == "AutoPyro" then
		local machine = if ability.Machine then PyroConfig.ById[ability.Machine] else nil
		return "Auto: " .. (if machine then machine.Name else "máquina") .. " em todos os drops"
	elseif kind == "SaveDrop" then
		local labels: { [string]: string } = { Perfect = "PERFEITO", Great = "ÓTIMO", Good = "BOM", Late = "TARDE" }
		return string.format(
			"Salva-Drop: nota %s (recarga %d s)",
			labels[ability.Grade or "Good"] or "BOM",
			math.floor((ability.Cooldown or 0) + 0.5)
		)
	elseif kind == "FullShow" then
		return "Espetáculo Total: todas as máquinas em todos os drops"
	elseif kind == "Aura" then
		return "Aura: +" .. percent(value) .. " no bónus dos outros artistas"
	end
	return ""
end

-- Efeitos agregados ------------------------------------------------------------

function ArtistCalc.EmptyEffects(): ArtistEffects
	return {
		HypeMultiplier = 1,
		ClickBonus = 0,
		EnergyBonus = 0,
		WindowBonus = 0,
		BoostBonus = 0,
		CooldownCut = 0,
		AutoPyroMask = 0,
		FullShow = false,
		SaveDrops = {},
	}
end

function ArtistCalc.ComputeEffects(artists: { [string]: ArtistData }, equipped: { string }): ArtistEffects
	local effects = ArtistCalc.EmptyEffects()
	local caps = ArtistsConfig.Caps

	-- 1.ª passagem: bónus próprios, auras e habilidades
	local bonuses: { number } = {}
	local auras: { number } = {}
	local totalAura = 0
	for index, uid in equipped do
		local data = artists[uid]
		bonuses[index] = 0
		auras[index] = 0
		if data and ArtistCalc.IsValid(data) then
			bonuses[index] = ArtistCalc.GetBonus(data)
			for _, ability in ArtistCalc.GetAbilities(data) do
				local value = ability.Value or 0
				local kind = ability.Kind
				if kind == "Aura" then
					auras[index] += value
					totalAura += value
				elseif kind == "ClickPower" then
					effects.ClickBonus += value
				elseif kind == "Energy" then
					effects.EnergyBonus += value
				elseif kind == "WindowWiden" then
					effects.WindowBonus += value
				elseif kind == "BoostExtend" then
					effects.BoostBonus += value
				elseif kind == "CooldownCut" then
					effects.CooldownCut += value
				elseif kind == "AutoPyro" then
					local machine = if ability.Machine then PyroConfig.ById[ability.Machine] else nil
					if machine then
						effects.AutoPyroMask = bit32.bor(effects.AutoPyroMask, machine.Bit)
					end
				elseif kind == "FullShow" then
					effects.FullShow = true
					effects.AutoPyroMask = PyroConfig.FullMask
				elseif kind == "SaveDrop" then
					local def = ArtistsConfig.ById[data.Id]
					local save: SaveDropEffect = {
						Uid = uid,
						Name = if def then def.Name else uid,
						Grade = ability.Grade or "Good",
						Cooldown = ability.Cooldown or 60,
					}
					table.insert(effects.SaveDrops, save)
				end
			end
		end
	end

	-- 2.ª passagem: a Aura de cada artista soma-se ao bónus dos OUTROS
	local hypeBonus = 0
	for index, bonus in bonuses do
		hypeBonus += bonus * (1 + totalAura - auras[index])
	end
	effects.HypeMultiplier = 1 + hypeBonus

	effects.WindowBonus = math.min(effects.WindowBonus, caps.WindowBonus)
	effects.CooldownCut = math.min(effects.CooldownCut, caps.CooldownCut)
	effects.BoostBonus = math.min(effects.BoostBonus, caps.BoostBonus)
	effects.EnergyBonus = math.min(effects.EnergyBonus, caps.EnergyBonus)

	-- Melhor nota primeiro, depois recarga mais curta
	table.sort(effects.SaveDrops, function(a: SaveDropEffect, b: SaveDropEffect): boolean
		local gradeA, gradeB = GRADE_ORDER[a.Grade] or 0, GRADE_ORDER[b.Grade] or 0
		if gradeA ~= gradeB then
			return gradeA > gradeB
		end
		return a.Cooldown < b.Cooldown
	end)
	return effects
end

-- Slots ----------------------------------------------------------------------

function ArtistCalc.GetSlotCount(worldTours: number, hasVipGamepass: boolean): number
	local slots = ArtistsConfig.BaseSlots
	for _, required in ArtistsConfig.WorldTourSlots do
		if worldTours >= required then
			slots += 1
		end
	end
	if hasVipGamepass then
		slots += ArtistsConfig.GamepassSlots
	end
	return math.min(slots, ArtistsConfig.MaxSlots)
end

-- Sorteio --------------------------------------------------------------------

-- Sorteia uma raridade com índice >= minIndex, com os pesos exatos da Config
-- Sorte: multiplica o peso das raridades com índice >= FromIndex (as probabilidades são renormalizadas)
export type LuckSpec = {
	Multiplier: number,
	FromIndex: number,
}

local function rarityWeight(index: number, luck: LuckSpec?): number
	local weight = RaritiesConfig.List[index].Weight
	if luck and index >= luck.FromIndex then
		weight *= luck.Multiplier
	end
	return weight
end

-- Sorteia uma raridade a partir de minIndex (pity / garantia), com sorte opcional
function ArtistCalc.RollRarity(rng: Random, minIndex: number, luck: LuckSpec?): RarityDef
	local list = RaritiesConfig.List
	local first = math.clamp(minIndex, 1, #list)
	local total = 0
	for index = first, #list do
		total += rarityWeight(index, luck)
	end
	local roll = rng:NextNumber() * total
	for index = first, #list do
		roll -= rarityWeight(index, luck)
		if roll < 0 then
			return list[index]
		end
	end
	return list[#list]
end

export type RarityOdds = {
	Rarity: RarityDef,
	Chance: number, -- 0..1
}

-- Probabilidade exata de cada raridade (o mesmo cálculo do sorteio), sem contar com o pity
function ArtistCalc.GetOdds(minIndex: number, luck: LuckSpec?): { RarityOdds }
	local list = RaritiesConfig.List
	local first = math.clamp(minIndex, 1, #list)
	local total = 0
	for index = first, #list do
		total += rarityWeight(index, luck)
	end
	local odds: { RarityOdds } = {}
	for index = first, #list do
		table.insert(odds, { Rarity = list[index], Chance = rarityWeight(index, luck) / total })
	end
	return odds
end

-- Garantia mínima e sorte de uma caixa paga (Config/PaidCrates); nil se o tipo não existir
function ArtistCalc.GetPaidCrateRoll(kind: string): (number, LuckSpec?)
	local def = (PaidCratesConfig.Kinds :: { [string]: PaidCratesConfig.PaidCrateDef })[kind]
	if not def then
		return 1, nil
	end
	local minIndex = if def.MinRarity then RaritiesConfig.IndexById[def.MinRarity] or 1 else 1
	local luck: LuckSpec? = if def.Luck > 1
		then { Multiplier = def.Luck, FromIndex = RaritiesConfig.IndexById[def.LuckFrom] or 1 }
		else nil
	return minIndex, luck
end

-- Sorte da Poção nas crates normais enquanto `now` (os.time) < luckUntil
function ArtistCalc.GetPotionLuck(luckUntil: number, now: number): LuckSpec?
	if luckUntil <= now then
		return nil
	end
	local potion = PaidCratesConfig.LuckPotion
	return { Multiplier = potion.Multiplier, FromIndex = RaritiesConfig.IndexById[potion.LuckFrom] or 1 }
end

-- Soma das probabilidades por família (Common, Rare, Epic, Legendary, Mythic)
function ArtistCalc.GetFamilyOdds(odds: { RarityOdds }): { [string]: number }
	local families: { [string]: number } = {}
	for _, entry in odds do
		local family = entry.Rarity.Family
		families[family] = (families[family] or 0) + entry.Chance
	end
	return families
end

-- Fusão ----------------------------------------------------------------------

function ArtistCalc.GroupKey(data: ArtistData): string
	return string.format("%s|%s|%d", data.Id, data.Rarity, data.Stars)
end

-- Grupos fundíveis: mesmo artista + raridade + estrelas, < 3★, não protegidos
function ArtistCalc.GetFusableGroups(artists: { [string]: ArtistData }): { [string]: { string } }
	local groups: { [string]: { string } } = {}
	for uid, data in artists do
		if not data.Locked and data.Stars < ArtistsConfig.MaxStars and ArtistCalc.IsValid(data) then
			local key = ArtistCalc.GroupKey(data)
			local group = groups[key]
			if not group then
				group = {}
				groups[key] = group
			end
			table.insert(group, uid)
		end
	end
	for key, group in groups do
		if #group < ArtistsConfig.FuseCount then
			groups[key] = nil
		else
			table.sort(group, function(a: string, b: string): boolean
				return (tonumber(a) or 0) < (tonumber(b) or 0)
			end)
		end
	end
	return groups
end

return table.freeze(ArtistCalc)
