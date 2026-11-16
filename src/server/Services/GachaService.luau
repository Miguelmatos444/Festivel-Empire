--!strict
--[[
	GachaService
	Abertura de Vinyl Crates — tudo no servidor:
	  1) valida crate, tier do palco, quantidade (1 ou 10), espaço na coleção e Hype
	  2) por cada abertura: escada de pity (só os patamares que a crate pode dar) ->
	     raridade mínima; sorteio na janela de 6 raridades da crate com
	     Config/Artists.SlotOdds (Random do servidor); artista = um dos 5 da crate ao acaso
	  3) Auto-Delete (raridades até ao limite escolhido) e Auto-Fuse
	  4) entrega (perfil + coleção) e só depois envia CrateResult ao jogador; anuncia a
	     todos as 2 raridades mais raras da crate quando a roleta para
	  5) Fase 12: marca as cartas mistério (CrateAnimCalc.IsMystery), conta as cinemáticas
	     vistas (CanSkip), protege a personagem, envia CrateSummon aos outros jogadores e
	     anuncia "<Jogador> invocou um <Raridade>!" na revelação
	Também cria os ProximityPrompts nas estações da praça, copia os modelos dos artistas
	para ReplicatedStorage e trata a opção "Animação rápida".
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local ArtistsConfig = require(ReplicatedStorage.Shared.Config.Artists)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local CrateAnimConfig = require(ReplicatedStorage.Shared.Config.CrateAnimation)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local CrateAnimCalc = require(ReplicatedStorage.Shared.Calc.CrateAnimCalc)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local ArtistService = require(script.Parent.ArtistService)
local MapService = require(script.Parent.MapService)
local Assets = require(script.Parent.Parent.World.Assets)

type RarityDef = Types.RarityDef
type CrateItem = Types.CrateItem
type CrateResult = Types.CrateResult
type CrateSummon = Types.CrateSummon
type ProfileData = Types.ProfileData

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
-- Só contam (e só forçam) os patamares que esta crate pode dar; obter uma raridade
-- reinicia todos os patamares que ela cumpre, venha de que crate vier.
-- legendaryReduction: "Sorte de Estreia" adianta o primeiro patamar (Lendário+)
local function rollWithPity(data: ProfileData, crate: Types.CrateDef, legendaryReduction: number): RarityDef
	local counters = (data.Pity :: unknown) :: { [string]: number }
	local levels = ArtistCalc.GetCratePityLevels(crate)

	for _, level in levels do
		counters[level.Key] = (counters[level.Key] or 0) + 1
	end

	local minIndex = 1
	for _, level in levels do
		if counters[level.Key] >= ArtistCalc.GetPityThreshold(level, legendaryReduction) then
			minIndex = math.max(minIndex, RaritiesConfig.IndexById[level.MinRarity])
		end
	end

	local rarity = ArtistCalc.RollCrateRarity(rng, crate, minIndex)
	local rolledIndex = RaritiesConfig.IndexById[rarity.Id]
	for _, level in RaritiesConfig.PityLadder do
		if rolledIndex >= RaritiesConfig.IndexById[level.MinRarity] then
			counters[level.Key] = 0
		end
	end
	return rarity
end

-- Anúncio a todo o servidor, atrasado `delay` s para não estragar a surpresa da roleta
local function announce(text: string, delay: number)
	task.delay(delay, function()
		for _, other in Players:GetPlayers() do
			notify(other, text)
		end
	end)
end

-- ForceField invisível durante a cinemática (a personagem fica parada no cliente)
local function protect(player: Player, duration: number)
	local character = player.Character
	if not character then
		return
	end
	local field = Instance.new("ForceField")
	field.Name = "CinematicProtection"
	field.Visible = false
	field.Parent = character
	Debris:AddItem(field, duration)
end

--[[
	Marca as cartas mistério do resultado. Se houver alguma:
	  - conta mais uma cinemática vista (o "Saltar" fica disponível a partir da 2.ª)
	  - protege a personagem durante a roleta + cinemática
	  - envia CrateSummon aos outros jogadores (versão leve, sincronizada pelo relógio)
	  - anuncia "<Jogador> invocou um <Raridade>!" na altura da revelação
	Devolve (CanSkip, segundos até à revelação ou nil se não houver mistério).
]]
local function handleMystery(
	player: Player,
	data: ProfileData?,
	crate: Types.CrateDef,
	items: { CrateItem },
	cinematicOnly: boolean,
	preview: boolean
): (boolean, number?)
	for _, item in items do
		item.Mystery = CrateAnimCalc.IsMystery(crate, item.Rarity)
	end
	local best = CrateAnimCalc.GetBestMystery(items)
	if not best then
		return false, nil
	end

	local seen = if data then data.Stats.CinematicsSeen else 0
	local canSkip = seen + 1 >= CrateAnimConfig.SkipFromView
	if data then
		data.Stats.CinematicsSeen = seen + 1
	end

	local fast = data ~= nil and data.Settings.FastCrateAnim
	local phases = CrateAnimCalc.GetPhases(fast)
	local delay = CrateAnimCalc.GetCinematicDelay(#items, fast, cinematicOnly)
	local revealAt = delay + (CrateAnimCalc.GetPhaseStart(phases, "Reveal") or 0)
	local item = items[best]
	local summon: CrateSummon = {
		UserId = player.UserId,
		ArtistId = item.ArtistId,
		Rarity = item.Rarity,
		StartTime = Workspace:GetServerTimeNow() + delay,
	}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			ServerNet.FireClient(RemoteDefs.Defs.CrateSummon, other, summon)
		end
	end
	protect(player, delay + CrateAnimCalc.GetDuration(phases) + CrateAnimConfig.ProtectionMargin)

	if not preview then
		local rarity = RaritiesConfig.ById[item.Rarity]
		if rarity then
			announce(string.format("%s invocou um %s!", player.DisplayName, rarity.Name), revealAt)
		end
	end
	return canSkip, revealAt
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
	for _ = 1, count do
		local rarity = rollWithPity(data, crate, skills.PityReduction)
		local artist = ArtistCalc.RollCrateArtist(rng, crate)
		local item: CrateItem
		if ArtistService.IsAutoDeleted(player, rarity.Id) then
			item = { ArtistId = artist.Id, Rarity = rarity.Id, Uid = nil, Outcome = "Deleted" }
		else
			local uid = ArtistService.AddArtist(player, artist.Id, rarity.Id)
			item = { ArtistId = artist.Id, Rarity = rarity.Id, Uid = uid, Outcome = "New" }
		end
		table.insert(items, item)
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

	-- Entrega já feita (perfil + coleção) ANTES de o cliente animar: fechar a UI ou sair
	-- a meio nunca faz perder o artista.
	ArtistService.Commit(player)
	local canSkip = handleMystery(player, data, crate, items, false, false)

	-- Anúncio normal (2 raridades mais raras da crate), depois da roleta/grelha parar
	local announceDelay = CrateAnimCalc.GetCinematicDelay(count, data.Settings.FastCrateAnim, false) - CrateAnimConfig.MysteryPause
	for _, item in items do
		local slot = ArtistCalc.GetCrateSlot(crate, item.Rarity)
		local rarity = RaritiesConfig.ById[item.Rarity]
		local def = ArtistCalc.GetArtist(item.ArtistId)
		if not item.Mystery and slot and slot >= ArtistsConfig.AnnounceFromSlot and rarity and def then
			announce(string.format("%s tirou %s · %s!", player.DisplayName, def.Name, rarity.Name), announceDelay)
		end
	end

	local result: CrateResult = { CrateId = crate.Id, Items = items, CanSkip = canSkip }
	ServerNet.FireClient(RemoteDefs.Defs.CrateResult, player, result)
	cratesOpened:Fire(player, count, items)
	Diag.Log("Gacha", string.format("%s abriu %dx %s", player.Name, count, crate.Id))
end

-- Crate que melhor mostra uma raridade: a que a tem como mistério, senão a primeira que a dá
local function crateForRarity(rarityId: string): Types.CrateDef?
	local fallback: Types.CrateDef? = nil
	for _, crate in ArtistsConfig.Crates do
		if ArtistCalc.GetCrateSlot(crate, rarityId) then
			if CrateAnimCalc.IsMystery(crate, rarityId) then
				return crate
			end
			fallback = fallback or crate
		end
	end
	return fallback
end

--[[
	Pré-visualização de debug (/fe crate anim, /fe cinematic): envia um CrateResult
	"Preview" sem gastar nem dar nada. A última carta tem a raridade pedida; as outras
	(x10) são enchimento. Conta como cinemática vista e faz o broadcast, para testar o
	"Saltar" e a versão leve noutro cliente.
]]
function GachaService.Preview(player: Player, rarityId: string, count: number, cinematicOnly: boolean): string
	local crate = crateForRarity(rarityId)
	if not crate then
		return "Nenhuma crate dá a raridade " .. rarityId .. "."
	end
	local artists = ArtistCalc.GetCrateArtists(crate)
	local items: { CrateItem } = {}
	for _, card in CrateAnimCalc.BuildFiller(rng, crate, count - 1) do
		table.insert(items, { ArtistId = card.ArtistId, Rarity = card.Rarity, Uid = nil, Outcome = "Preview" })
	end
	table.insert(items, {
		ArtistId = artists[rng:NextInteger(1, #artists)].Id,
		Rarity = rarityId,
		Uid = nil,
		Outcome = "Preview",
	})
	local data = DataService.GetProfile(player)
	local canSkip = handleMystery(player, data, crate, items, cinematicOnly, true)
	local result: CrateResult = {
		CrateId = crate.Id,
		Items = items,
		CanSkip = canSkip,
		Preview = true,
		CinematicOnly = cinematicOnly,
	}
	ServerNet.FireClient(RemoteDefs.Defs.CrateResult, player, result)
	local mystery = CrateAnimCalc.GetBestMystery(items) ~= nil
	return string.format(
		"Pré-visualização: %s · %s x%d%s",
		crate.Name,
		rarityId,
		count,
		if mystery then " (carta mistério + cinemática)" else ""
	)
end

-- Copia os modelos dos artistas para ReplicatedStorage (o cliente não vê o ServerStorage):
-- usados na carta ganha da roleta e na silhueta da cinemática.
local function publishArtistRigs()
	local folder = Instance.new("Folder")
	folder.Name = CrateAnimConfig.ArtistRigsFolder
	for _, def in ArtistsConfig.List do
		local ok, rig = pcall(function(): Model
			return Assets.GetArtistTemplate(def.Id):Clone()
		end)
		if ok then
			rig.Name = def.Id
			rig.Parent = folder
		else
			warn("[GachaService] Sem modelo para " .. def.Id .. ": " .. tostring(rig))
		end
	end
	folder.Parent = ReplicatedStorage
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
	ServerNet.Connect(RemoteDefs.Defs.SetFastCrateAnim, function(player: Player, enabledArg: unknown)
		local data = DataService.GetProfile(player)
		if data then
			data.Settings.FastCrateAnim = enabledArg :: boolean
			PlayerStateService.MarkDirty(player)
		end
	end)
end

function GachaService.Start()
	publishArtistRigs()
	createStationPrompts()
end

return GachaService
