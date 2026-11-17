--!strict
--[[
	IndexService
	Índice de Artistas (Fase 10), tudo validado no servidor:
	  - as descobertas são registadas pelo ArtistService.MarkDiscovered (todas as entradas
	    de artistas, incluindo os apagados pelo Auto-Delete)
	  - reclamar o prémio de uma raridade completa (uma vez) ou o prémio final
	    (Discos + slot de artista permanente + título na placa do terreno)
	  - sincroniza Índice + vitrine com o próprio cliente (IndexSync), agrupado a cada
	    Config/ArtistIndex.SyncInterval
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ArtistIndexConfig = require(ReplicatedStorage.Shared.Config.ArtistIndex)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local IndexCalc = require(ReplicatedStorage.Shared.Calc.IndexCalc)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local ArtistService = require(script.Parent.ArtistService)
local RewardService = require(script.Parent.RewardService)
local PlotService = require(script.Parent.PlotService)

type ProfileData = Types.ProfileData
type IndexSync = Types.IndexSync

local IndexService = {}

local trove = Trove.new()
local dirty: { [Player]: boolean } = {}

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

function IndexService.MarkDirty(player: Player)
	dirty[player] = true
end

local function buildSync(data: ProfileData): IndexSync
	return {
		Discovered = table.clone(data.Index.Discovered),
		Claimed = table.clone(data.Index.Claimed),
		Variants = table.clone(data.Index.Variants),
		Showcase = table.clone(data.Showcase),
		ShowcaseUid = IndexCalc.ResolveShowcase(data.Artists, data.Showcase.Mode, data.Showcase.Uid) or "",
	}
end

-- Reclama o prémio de `key` (RarityId ou Config/ArtistIndex.FinalKey)
function IndexService.Claim(player: Player, key: string): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	local index = data.Index
	if index.Claimed[key] then
		return false, "Esse prémio já foi reclamado."
	end
	if not IndexCalc.CanClaim(index.Discovered, index.Claimed, key) then
		return false, "Ainda não completaste isto no Índice."
	end
	index.Claimed[key] = true

	local given: string
	if key == ArtistIndexConfig.FinalKey then
		local final = ArtistIndexConfig.Final
		given = RewardService.Grant(player, { Discs = final.Discs })
		ArtistService.Commit(player) -- slot extra
		local plot = PlotService.GetPlotId(player)
		if plot then
			PlotService.RefreshSign(plot)
		end
		given = string.format("%s · +%d slot de artista · título \"%s\"", given, final.SlotBonus, final.Title)
	else
		local reward = IndexCalc.GetReward(key)
		given = if reward then RewardService.Grant(player, { Crates = reward.Crates, Discs = reward.Discs }) else ""
	end
	dirty[player] = true
	PlayerStateService.MarkDirty(player)
	local rarity = ArtistCalc.GetRarity(key)
	local label = if rarity then rarity.Name elseif key == ArtistIndexConfig.FinalKey then "Índice completo" else key
	Diag.Log("Index", string.format("%s reclamou %s", player.Name, key))
	return true, string.format("Prémio do Índice (%s): %s", label, given)
end

local function syncLoop()
	while true do
		task.wait(ArtistIndexConfig.SyncInterval)
		for player in dirty do
			local data = DataService.GetProfile(player)
			if not data or player.Parent ~= Players then
				dirty[player] = nil
			elseif PlayerStateService.IsClientReady(player) then
				dirty[player] = nil
				ServerNet.FireClient(RemoteDefs.Defs.IndexSync, player, buildSync(data))
			end
		end
	end
end

function IndexService.Init()
	ServerNet.Connect(RemoteDefs.Defs.ClaimIndexReward, function(player: Player, keyArg: unknown)
		local _, message = IndexService.Claim(player, keyArg :: string)
		notify(player, message)
	end)

	trove:Add(ArtistService.Discovered:Connect(function(player: Player, _key: string)
		dirty[player] = true
	end))
	trove:Add(ArtistService.VariantDiscovered:Connect(function(player: Player, _key: string)
		dirty[player] = true
	end))
	-- A vitrine automática pode mudar sempre que a coleção muda
	trove:Add(ArtistService.EquippedChanged:Connect(function(player: Player)
		dirty[player] = true
	end))
	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player, _data: ProfileData)
		dirty[player] = true
	end))
	trove:Add(PlayerStateService.ClientReady:Connect(function(player: Player)
		dirty[player] = true
	end))
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		dirty[player] = nil
	end)
end

function IndexService.Start()
	trove:Add(task.spawn(syncLoop))
end

return IndexService
