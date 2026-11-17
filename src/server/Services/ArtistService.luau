--!strict
--[[
	ArtistService
	Coleção de artistas do jogador (persistida em ProfileData.Artists/EquippedArtists):
	  - equipar/desequipar nos slots do palco (3 a 7: base + World Tours + Gamepass)
	  - cadeado (protege de fusão e Auto-Delete)
	  - fusão: 3x mesmo artista + raridade + estrelas -> +1★ (até 3★); Auto-Fuse opcional
	  - efeitos agregados dos equipados -> EconomyService (Hype/batidas); BassDropService lê-os
	  - sincronização da coleção com o cliente (agregada a cada SyncInterval)
	Tudo é validado aqui; o cliente só envia pedidos.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ArtistsConfig = require(ReplicatedStorage.Shared.Config.Artists)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local IndexCalc = require(ReplicatedStorage.Shared.Calc.IndexCalc)
local VariantCalc = require(ReplicatedStorage.Shared.Calc.VariantCalc)
local TraitCalc = require(ReplicatedStorage.Shared.Calc.TraitCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)

type ArtistData = Types.ArtistData
type ArtistEffects = Types.ArtistEffects
type ArtistsSync = Types.ArtistsSync
type ProfileData = Types.ProfileData

local SYNC_INTERVAL = 0.25

local MAX_FUSE_PASSES = 10

local ArtistService = {}

local equippedChanged: Signal.Signal<Player> = Signal.new()

-- Disparado quando os artistas equipados (ou as suas estrelas) mudam
ArtistService.EquippedChanged = equippedChanged

local fused: Signal.Signal<Player, number> = Signal.new()

-- (jogador, nº de fusões) — missões e conquistas
ArtistService.Fused = fused

local discovered: Signal.Signal<Player, string> = Signal.new()
local variantDiscovered: Signal.Signal<Player, string> = Signal.new()

-- (jogador, chave "ArtistId|VariantId") — primeira vez que obtém esta variante
ArtistService.VariantDiscovered = variantDiscovered

-- (jogador, chave "ArtistId|RarityId") — primeira vez que obtém esta combinação (Índice)
ArtistService.Discovered = discovered

local trove = Trove.new()
local effectsCache: { [Player]: ArtistEffects } = {}
local vipOwners: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

local function artistLabel(data: ArtistData): string
	local def = ArtistCalc.GetArtist(data.Id)
	local rarity = ArtistCalc.GetRarity(data.Rarity)
	return string.format(
		"%s · %s %s",
		if def then def.Name else data.Id,
		if rarity then rarity.Name else data.Rarity,
		string.rep("★", data.Stars)
	)
end

-- Dados -------------------------------------------------------------------------

-- Remove entradas inválidas (DataStore) e repara equipados e contador de uids
local function sanitize(data: ProfileData)
	for uid, artist in data.Artists do
		if type(artist) == "table" and type(artist.Variant) ~= "string" then
			artist.Variant = "" -- perfis antigos: sem variante
		end
		if type(artist) == "table" and (type(artist.Trait) ~= "string" or type(artist.TraitTier) ~= "string") then
			artist.Trait, artist.TraitTier = "", "" -- sem traço: só se ganha a rodar no Estúdio de Remix
		end
		if type(artist) ~= "table" or not ArtistCalc.IsValid(artist) then
			data.Artists[uid] = nil
		elseif type(artist.Locked) ~= "boolean" then
			artist.Locked = false
		end
	end

	local seen: { [string]: boolean } = {}
	local equipped: { string } = {}
	for _, uid in data.EquippedArtists do
		if type(uid) == "string" and data.Artists[uid] and not seen[uid] then
			seen[uid] = true
			table.insert(equipped, uid)
		end
	end
	data.EquippedArtists = equipped

	local maxUid = 0
	for uid in data.Artists do
		local number = tonumber(uid)
		if number and number > maxUid then
			maxUid = number
		end
	end
	if data.NextArtistUid <= maxUid then
		data.NextArtistUid = maxUid + 1
	end
end

function ArtistService.GetSlotCount(player: Player): number
	local data = DataService.GetProfile(player)
	local bonus = if data then IndexCalc.GetBonusSlots(data.Index.Claimed) else 0
	return ArtistCalc.GetSlotCount(if data then data.WorldTours else 0, vipOwners[player] == true, bonus)
end

-- Regista no Índice que o jogador obteve esta combinação (mesmo que seja logo fundida
-- ou apagada pelo Auto-Delete). Devolve true se foi a primeira vez.
function ArtistService.MarkDiscovered(player: Player, artistId: string, rarityId: string): boolean
	local data = DataService.GetProfile(player)
	if not data then
		return false
	end
	local key = IndexCalc.Key(artistId, rarityId)
	if data.Index.Discovered[key] then
		return false
	end
	data.Index.Discovered[key] = true
	discovered:Fire(player, key)
	return true
end

local function trimEquipped(player: Player, data: ProfileData)
	local slots = ArtistService.GetSlotCount(player)
	while #data.EquippedArtists > slots do
		table.remove(data.EquippedArtists)
	end
end

-- Recalcula efeitos, aplica-os à economia e agenda a sincronização
function ArtistService.Commit(player: Player)
	local data = DataService.GetProfile(player)
	if not data then
		return
	end
	trimEquipped(player, data)
	local effects = ArtistCalc.ComputeEffects(data.Artists, data.EquippedArtists)
	effectsCache[player] = effects
	EconomyService.SetArtistModifiers(player, effects.HypeMultiplier, effects.ClickBonus, effects.PassiveBonus)
	dirty[player] = true
	equippedChanged:Fire(player)
end

function ArtistService.GetEffects(player: Player): ArtistEffects
	return effectsCache[player] or ArtistCalc.EmptyEffects()
end

function ArtistService.GetCount(player: Player): number
	local data = DataService.GetProfile(player)
	local count = 0
	if data then
		for _ in data.Artists do
			count += 1
		end
	end
	return count
end

-- Regista no Índice uma variante Brilhante obtida. Devolve true se foi a primeira vez.
function ArtistService.MarkVariantDiscovered(player: Player, artistId: string, variantId: string): boolean
	local data = DataService.GetProfile(player)
	if not data or variantId == "" or not VariantCalc.Get(variantId) then
		return false
	end
	local key = IndexCalc.VariantKey(artistId, variantId)
	if data.Index.Variants[key] then
		return false
	end
	data.Index.Variants[key] = true
	variantDiscovered:Fire(player, key)
	return true
end

-- Adiciona um artista (sem Commit — o chamador agrupa as alterações). Devolve o uid.
-- Os artistas nascem SEM traço (só se ganha a rodar no Estúdio de Remix); trait/traitTier só no debug
function ArtistService.AddArtist(player: Player, artistId: string, rarityId: string, stars: number?, variant: string?, trait: string?, traitTier: string?): string?
	local data = DataService.GetProfile(player)
	if not data or not ArtistCalc.GetArtist(artistId) or not ArtistCalc.GetRarity(rarityId) then
		return nil
	end
	local uid = tostring(data.NextArtistUid)
	data.NextArtistUid += 1
	data.Artists[uid] = {
		Id = artistId,
		Rarity = rarityId,
		Stars = math.clamp(stars or 1, 1, ArtistsConfig.MaxStars),
		Locked = false,
		Variant = if variant and VariantCalc.IsValid(variant) then variant else "",
		Trait = "",
		TraitTier = "",
	}
	local entry = data.Artists[uid]
	if trait and traitTier and trait ~= "" and TraitCalc.IsValid(trait, traitTier) then
		entry.Trait, entry.TraitTier = trait, traitTier
	end
	ArtistService.MarkDiscovered(player, artistId, rarityId)
	if variant and variant ~= "" then
		ArtistService.MarkVariantDiscovered(player, artistId, variant)
	end
	return uid
end

-- variant: as variantes Brilhantes só são apagadas se o jogador ligou essa opção
function ArtistService.IsAutoDeleted(player: Player, rarityId: string, variant: string?): boolean
	local data = DataService.GetProfile(player)
	if not data then
		return false
	end
	if variant and variant ~= "" and not data.Settings.AutoDeleteVariants then
		return false
	end
	local upTo = math.min(data.Settings.AutoDeleteUpTo, ArtistsConfig.AutoDeleteMaxIndex)
	return upTo > 0 and ArtistCalc.GetRarityIndex(rarityId) <= upTo
end

-- Equipar ----------------------------------------------------------------------

function ArtistService.Equip(player: Player, uid: string): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data or not data.Artists[uid] then
		return false, "Artista não encontrado."
	end
	if table.find(data.EquippedArtists, uid) then
		return false, "Esse artista já está no palco."
	end
	local slots = ArtistService.GetSlotCount(player)
	if #data.EquippedArtists >= slots then
		return false, string.format("Slots cheios (%d/%d). Desequipa alguém primeiro.", #data.EquippedArtists, slots)
	end
	table.insert(data.EquippedArtists, uid)
	ArtistService.Commit(player)
	return true, artistLabel(data.Artists[uid]) .. " subiu ao palco!"
end

--[[
	Equipa a combinação com maior multiplicador de Hype (bónus próprio + Auras).
	Escolha gananciosa slot a slot: em cada passo entra o artista que mais aumenta o
	multiplicador; empates resolvem-se pela raridade e depois pelas estrelas.
]]
function ArtistService.EquipBest(player: Player): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	local slots = ArtistService.GetSlotCount(player)
	local chosen: { string } = {}
	for _ = 1, slots do
		local bestUid: string? = nil
		local bestScore = -math.huge
		for uid, artist in data.Artists do
			if not table.find(chosen, uid) and ArtistCalc.IsValid(artist) then
				table.insert(chosen, uid)
				local multiplier = ArtistCalc.ComputeEffects(data.Artists, chosen).HypeMultiplier
				table.remove(chosen)
				local score = multiplier + ArtistCalc.GetRarityIndex(artist.Rarity) * 1e-6 + artist.Stars * 1e-8
				if score > bestScore then
					bestScore = score
					bestUid = uid
				end
			end
		end
		if not bestUid then
			break
		end
		table.insert(chosen, bestUid)
	end

	if #chosen == 0 then
		return false, "Ainda não tens artistas. Abre uma Vinyl Crate!"
	end
	data.EquippedArtists = chosen
	ArtistService.Commit(player)
	return true,
		string.format(
			"%d melhor(es) artista(s) no palco · Hype ×%.1f",
			#chosen,
			ArtistService.GetEffects(player).HypeMultiplier
		)
end

function ArtistService.Unequip(player: Player, uid: string): (boolean, string)
	local data = DataService.GetProfile(player)
	local index = if data then table.find(data.EquippedArtists, uid) else nil
	if not data or not index then
		return false, "Esse artista não está no palco."
	end
	table.remove(data.EquippedArtists, index)
	ArtistService.Commit(player)
	return true, ""
end

function ArtistService.SetLock(player: Player, uid: string, locked: boolean): boolean
	local data = DataService.GetProfile(player)
	local artist = if data then data.Artists[uid] else nil
	if not artist then
		return false
	end
	artist.Locked = locked
	dirty[player] = true
	return true
end

-- Fusão ------------------------------------------------------------------------

-- Funde um grupo (uids com a mesma chave). Equipados ficam como "keeper"; consumidos saem do fim.
-- O resultado fica com o MELHOR traço dos 3 e o jogador ganha Cristais. Devolve (fusões, Cristais).
local function fuseGroup(data: ProfileData, uids: { string }, consumed: { [string]: boolean }): (number, number)
	local ordered: { string } = {}
	for _, uid in uids do
		if table.find(data.EquippedArtists, uid) then
			table.insert(ordered, uid)
		end
	end
	for _, uid in uids do
		if not table.find(data.EquippedArtists, uid) then
			table.insert(ordered, uid)
		end
	end

	local fusions = 0
	local crystals = 0
	while #ordered >= ArtistsConfig.FuseCount do
		local keeper = table.remove(ordered, 1) :: string
		local kept = data.Artists[keeper]
		for _ = 1, ArtistsConfig.FuseCount - 1 do
			local victim = table.remove(ordered) :: string
			local lost = data.Artists[victim]
			if lost and TraitCalc.IsBetter(lost.Trait, lost.TraitTier, kept.Trait, kept.TraitTier) then
				kept.Trait, kept.TraitTier = lost.Trait, lost.TraitTier
			end
			data.Artists[victim] = nil
			consumed[victim] = true
			local equippedIndex = table.find(data.EquippedArtists, victim)
			if equippedIndex then
				table.remove(data.EquippedArtists, equippedIndex)
			end
		end
		kept.Stars = math.min(kept.Stars + 1, ArtistsConfig.MaxStars)
		local rarity = ArtistCalc.GetRarity(kept.Rarity)
		local gained = TraitCalc.GetFusionCrystals(if rarity then rarity.Family else "Common", kept.Stars)
		data.Crystals += gained
		crystals += gained
		fusions += 1
	end
	return fusions, crystals
end

-- Funde todos os grupos possíveis (várias passagens: 1★->2★->3★). Sem Commit.
local function fuseAllRaw(data: ProfileData, consumed: { [string]: boolean }): (number, number)
	local total, crystals = 0, 0
	for _ = 1, MAX_FUSE_PASSES do
		local fusionsThisPass = 0
		for _, group in ArtistCalc.GetFusableGroups(data.Artists) do
			local fusions, gained = fuseGroup(data, group, consumed)
			fusionsThisPass += fusions
			crystals += gained
		end
		total += fusionsThisPass
		if fusionsThisPass == 0 then
			break
		end
	end
	return total, crystals
end

-- Usado pelo GachaService (Auto-Fuse) — devolve os uids consumidos
function ArtistService.AutoFuse(player: Player): { [string]: boolean }
	local consumed: { [string]: boolean } = {}
	local data = DataService.GetProfile(player)
	if data then
		local fusions = fuseAllRaw(data, consumed)
		if fusions > 0 then
			fused:Fire(player, fusions)
			PlayerStateService.MarkDirty(player) -- Cristais
		end
	end
	return consumed
end

function ArtistService.Fuse(player: Player, target: string): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	local consumed: { [string]: boolean } = {}
	local fusions, crystals = 0, 0
	if target == "all" then
		fusions, crystals = fuseAllRaw(data, consumed)
	else
		local artist = data.Artists[target]
		if not artist then
			return false, "Artista não encontrado."
		end
		local group = ArtistCalc.GetFusableGroups(data.Artists)[ArtistCalc.GroupKey(artist)]
		if not group then
			return false, "Precisas de 3 cópias iguais (sem cadeado) para fundir."
		end
		fusions, crystals = fuseGroup(data, group, consumed)
	end
	if fusions == 0 then
		return false, "Nada para fundir."
	end
	ArtistService.Commit(player)
	fused:Fire(player, fusions)
	PlayerStateService.MarkDirty(player) -- Cristais
	return true, string.format("%d fusão(ões) concluída(s)! +%d Cristais", fusions, crystals)
end

-- Sincronização ----------------------------------------------------------------------

local function buildSync(player: Player, data: ProfileData): ArtistsSync
	local artists: { [string]: ArtistData } = {}
	for uid, artist in data.Artists do
		artists[uid] = {
			Id = artist.Id,
			Rarity = artist.Rarity,
			Stars = artist.Stars,
			Locked = artist.Locked,
			Variant = artist.Variant,
			Trait = artist.Trait,
			TraitTier = artist.TraitTier,
		}
	end
	return {
		Artists = artists,
		Equipped = table.clone(data.EquippedArtists),
		Slots = ArtistService.GetSlotCount(player),
		Pity = table.clone(data.Pity),
		AutoFuse = data.Settings.AutoFuse,
		AutoDeleteUpTo = data.Settings.AutoDeleteUpTo,
		AutoDeleteVariants = data.Settings.AutoDeleteVariants,
		Effects = ArtistService.GetEffects(player),
	}
end

function ArtistService.MarkDirty(player: Player)
	dirty[player] = true
end

local function syncLoop()
	while true do
		task.wait(SYNC_INTERVAL)
		for player in dirty do
			local data = DataService.GetProfile(player)
			if not data or player.Parent ~= Players then
				dirty[player] = nil
			elseif PlayerStateService.IsClientReady(player) then
				dirty[player] = nil
				ServerNet.FireClient(RemoteDefs.Defs.ArtistsSync, player, buildSync(player, data))
			end
		end
	end
end

-- Gamepass ---------------------------------------------------------------------

local function refreshVip(player: Player)
	local gamepassId = ArtistsConfig.VipGamepassId
	if gamepassId <= 0 then
		return
	end
	local ok, owns = pcall(function(): boolean
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
	end)
	if ok and owns and player.Parent == Players then
		vipOwners[player] = true
		ArtistService.Commit(player)
	end
end

-- Ciclo de vida --------------------------------------------------------------

function ArtistService.Init()
	ServerNet.Connect(RemoteDefs.Defs.EquipArtist, function(player: Player, uidArg: unknown)
		local ok, message = ArtistService.Equip(player, uidArg :: string)
		if not ok or message ~= "" then
			notify(player, message)
		end
	end)
	ServerNet.Connect(RemoteDefs.Defs.EquipBestArtists, function(player: Player)
		local _, message = ArtistService.EquipBest(player)
		notify(player, message)
	end)
	ServerNet.Connect(RemoteDefs.Defs.UnequipArtist, function(player: Player, uidArg: unknown)
		local ok, message = ArtistService.Unequip(player, uidArg :: string)
		if not ok then
			notify(player, message)
		end
	end)
	ServerNet.Connect(RemoteDefs.Defs.SetArtistLock, function(player: Player, uidArg: unknown, lockedArg: unknown)
		ArtistService.SetLock(player, uidArg :: string, lockedArg :: boolean)
	end)
	ServerNet.Connect(RemoteDefs.Defs.FuseArtists, function(player: Player, targetArg: unknown)
		local target = targetArg :: string
		if target ~= "all" and not string.match(target, "^%d+$") then
			return
		end
		local _, message = ArtistService.Fuse(player, target)
		notify(player, message)
	end)
	ServerNet.Connect(RemoteDefs.Defs.SetAutoFuse, function(player: Player, enabledArg: unknown)
		local data = DataService.GetProfile(player)
		if data then
			data.Settings.AutoFuse = enabledArg :: boolean
			dirty[player] = true
		end
	end)
	ServerNet.Connect(RemoteDefs.Defs.SetAutoDelete, function(player: Player, upToArg: unknown)
		local data = DataService.GetProfile(player)
		if data then
			data.Settings.AutoDeleteUpTo = math.clamp(upToArg :: number, 0, ArtistsConfig.AutoDeleteMaxIndex)
			dirty[player] = true
		end
	end)

	ServerNet.Connect(RemoteDefs.Defs.SetAutoDeleteVariants, function(player: Player, enabledArg: unknown)
		local data = DataService.GetProfile(player)
		if data then
			data.Settings.AutoDeleteVariants = enabledArg :: boolean
			dirty[player] = true
		end
	end)

	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player, data: ProfileData)
		sanitize(data)
		ArtistService.Commit(player)
		Diag.Log("Artists", string.format("%s: %d artistas, %d equipados", player.Name, ArtistService.GetCount(player), #data.EquippedArtists))
	end))
	trove:Add(PlayerStateService.ClientReady:Connect(function(player: Player)
		dirty[player] = true
	end))

	trove:Connect(Players.PlayerAdded, function(player: Player)
		task.spawn(refreshVip, player)
	end)
	trove:Connect(MarketplaceService.PromptGamePassPurchaseFinished, function(player: Player, gamepassId: number, purchased: boolean)
		if purchased and gamepassId == ArtistsConfig.VipGamepassId and gamepassId > 0 then
			vipOwners[player] = true
			ArtistService.Commit(player)
			notify(player, "Palco VIP ativo: +" .. ArtistsConfig.GamepassSlots .. " slots de artistas!")
		end
	end)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		effectsCache[player] = nil
		vipOwners[player] = nil
		dirty[player] = nil
	end)
end

function ArtistService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(refreshVip, player)
	end
	trove:Add(task.spawn(syncLoop))
end

-- Exposto para o DebugService / GachaService
ArtistService.RarityCount = RaritiesConfig.Count

return ArtistService
