--!strict
--[[
	GachaService
	Abertura de Vinyl Crates — tudo no servidor:
	  1) valida crate, tier do palco, quantidade (1 ou 10), espaço na coleção e Hype
	  2) por cada abertura: escada de pity -> raridade mínima; sorteio com os pesos exatos
	     de Config/Rarities (Random do servidor); artista = o da família dessa raridade na crate
	  3) Auto-Delete (raridades até ao limite escolhido) e Auto-Fuse
	  4) envia CrateResult ao jogador e anuncia a todos as raridades de Divino para cima
	Também cria os ProximityPrompts nas estações de Vinyl Crates da praça.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ArtistsConfig = require(ReplicatedStorage.Shared.Config.Artists)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local ArtistService = require(script.Parent.ArtistService)
local MapService = require(script.Parent.MapService)

type RarityDef = Types.RarityDef
type CrateItem = Types.CrateItem
type CrateResult = Types.CrateResult
type ProfileData = Types.ProfileData

local ANNOUNCE_FROM_RARITY = "Divine"
local PROMPT_NAME = "CrateStationPrompt"

local GachaService = {}

local cratesOpened: Signal.Signal<Player, number, { CrateItem }> = Signal.new()

-- (jogador, nº de aberturas, resultados) — missões e conquistas
GachaService.CratesOpened = cratesOpened

local rng = Random.new()

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

-- Uma abertura: atualiza a escada de pity e devolve a raridade sorteada
-- legendaryReduction: "Sorte de Estreia" adianta o primeiro patamar (Lendário+)
local function rollWithPity(data: ProfileData, legendaryReduction: number): RarityDef
	local counters = (data.Pity :: unknown) :: { [string]: number }
	local ladder = RaritiesConfig.PityLadder

	for _, level in ladder do
		counters[level.Key] = (counters[level.Key] or 0) + 1
	end

	local minIndex = 1
	for index, level in ladder do
		local threshold = if index == 1 then math.max(1, level.Threshold - legendaryReduction) else level.Threshold
		if counters[level.Key] >= threshold then
			minIndex = math.max(minIndex, RaritiesConfig.IndexById[level.MinRarity])
		end
	end

	local rarity = ArtistCalc.RollRarity(rng, minIndex)
	local rolledIndex = RaritiesConfig.IndexById[rarity.Id]
	for _, level in ladder do
		if rolledIndex >= RaritiesConfig.IndexById[level.MinRarity] then
			counters[level.Key] = 0
		end
	end
	return rarity
end

local function announce(player: Player, artistName: string, rarity: RarityDef)
	local text = string.format("%s tirou %s · %s!", player.DisplayName, artistName, rarity.Name)
	for _, other in Players:GetPlayers() do
		notify(other, text)
	end
end

function GachaService.Open(player: Player, crateId: string, count: number): (boolean, string?)
	local data = DataService.GetProfile(player)
	local crate = ArtistCalc.GetCrate(crateId)
	if not data or not crate then
		return false, "Crate indisponível."
	end
	if not table.find(ArtistsConfig.OpenCounts, count) then
		return false, "Quantidade inválida."
	end
	if data.StageTier < crate.RequiredTier then
		return false, string.format("%s requer o Tier %d (%s).", crate.Name, crate.RequiredTier, StageCalc.GetDef(crate.RequiredTier).Name)
	end
	local free = ArtistsConfig.InventoryCap - ArtistService.GetCount(player)
	if free < count then
		return false, string.format("Coleção cheia (%d/%d). Funde ou ativa o Auto-Delete.", ArtistsConfig.InventoryCap - free, ArtistsConfig.InventoryCap)
	end
	local skills = PrestigeCalc.GetSkillEffects(data.SkillTree)
	local cost = BigNum.fromNumber(crate.Cost * count * (1 - math.clamp(skills.CrateCostCut, 0, 0.9)))
	if not EconomyService.TrySpendHype(player, cost) then
		return false, "Hype insuficiente (" .. NumberFormatter.format(cost) .. ")."
	end

	GachaService.Pull(player, crate, count)
	return true, nil
end

-- Abre `count` crates já validadas/pagas: pity, sorteio, Auto-Delete/Fuse, resultado e sinais
function GachaService.Pull(player: Player, crate: Types.CrateDef, count: number)
	local data = DataService.GetProfile(player)
	if not data or count <= 0 then
		return
	end
	local skills = PrestigeCalc.GetSkillEffects(data.SkillTree)
	local items: { CrateItem } = {}
	local announceIndex = RaritiesConfig.IndexById[ANNOUNCE_FROM_RARITY]
	for _ = 1, count do
		local rarity = rollWithPity(data, skills.PityReduction)
		local artist = ArtistsConfig.ByCrateFamily[crate.Id .. "|" .. rarity.Family]
		local item: CrateItem
		if ArtistService.IsAutoDeleted(player, rarity.Id) then
			item = { ArtistId = artist.Id, Rarity = rarity.Id, Uid = nil, Outcome = "Deleted" }
		else
			local uid = ArtistService.AddArtist(player, artist.Id, rarity.Id)
			item = { ArtistId = artist.Id, Rarity = rarity.Id, Uid = uid, Outcome = "New" }
		end
		table.insert(items, item)
		if RaritiesConfig.IndexById[rarity.Id] >= announceIndex then
			announce(player, artist.Name, rarity)
		end
	end

	if data.Settings.AutoFuse then
		local consumed = ArtistService.AutoFuse(player)
		for _, item in items do
			local uid = item.Uid
			if uid and consumed[uid] then
				item.Outcome = "Fused"
			end
		end
	end

	ArtistService.Commit(player)
	local result: CrateResult = { CrateId = crate.Id, Items = items }
	ServerNet.FireClient(RemoteDefs.Defs.CrateResult, player, result)
	cratesOpened:Fire(player, count, items)
	Diag.Log("Gacha", string.format("%s abriu %dx %s", player.Name, count, crate.Id))
end

-- Melhor crate desbloqueada pelo tier atual
function GachaService.GetBestCrate(player: Player): Types.CrateDef?
	local data = DataService.GetProfile(player)
	if not data then
		return nil
	end
	local best: Types.CrateDef? = nil
	for _, crate in ArtistsConfig.Crates do
		if data.StageTier >= crate.RequiredTier then
			best = crate
		end
	end
	return best
end

-- Aberturas grátis (recompensas, produtos). Devolve quantas foram abertas
-- (limitadas pelo espaço livre na coleção).
function GachaService.OpenFree(player: Player, count: number): number
	local crate = GachaService.GetBestCrate(player)
	if not crate then
		return 0
	end
	local free = ArtistsConfig.InventoryCap - ArtistService.GetCount(player)
	local amount = math.clamp(count, 0, math.max(free, 0))
	if amount < count then
		notify(player, string.format("Coleção quase cheia: só %d de %d crates grátis foram abertas.", amount, count))
	end
	GachaService.Pull(player, crate, amount)
	return amount
end

-- Prompts nas estações da praça (abrem o painel no cliente)
local function createStationPrompts()
	local map = MapService.GetMapFolder()
	local plaza = if map then map:FindFirstChild("Plaza") else nil
	local root = if plaza then plaza:FindFirstChild("Root") else nil
	if not root then
		warn("[GachaService] Praça sem Root: estações de Vinyl Crates sem prompt")
		return
	end
	for _, child in root:GetChildren() do
		if child:IsA("Attachment") and string.match(child.Name, "^CrateStation_") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = PROMPT_NAME
			prompt.ActionText = "Abrir Vinyl Crates"
			prompt.ObjectText = "Vinyl Crates"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = child
		end
	end
end

function GachaService.Init()
	ServerNet.Connect(RemoteDefs.Defs.OpenCrate, function(player: Player, crateArg: unknown, countArg: unknown)
		local ok, message = GachaService.Open(player, crateArg :: string, countArg :: number)
		if not ok and message then
			notify(player, message)
		end
	end)
end

function GachaService.Start()
	createStationPrompts()
end

return GachaService
