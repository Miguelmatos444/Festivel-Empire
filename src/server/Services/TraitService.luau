--!strict
--[[
	TraitService
	Estúdio de Remix (Fase 13B), tudo validado no servidor:
	  - remote RemixTrait(uid): o artista tem de existir e ser do jogador; paga os
	    Cristais (custo pela família da raridade do artista, Config/Crystals) e sorteia um
	    novo traço com as probabilidades de Config/Traits (pode repetir)
	  - um traço Lendário faz explodir o disco do Estúdio para todos (RemixBurst) e é
	    anunciado no servidor
	Cria o ProximityPrompt do Estúdio no Attachment "RemixStudio" da praça.
	Os Cristais ganham-se nas fusões (ArtistService) e ficam no World Tour.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local TraitsConfig = require(ReplicatedStorage.Shared.Config.Traits)
local CrystalsConfig = require(ReplicatedStorage.Shared.Config.Crystals)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local TraitCalc = require(ReplicatedStorage.Shared.Calc.TraitCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local ArtistService = require(script.Parent.ArtistService)
local MapService = require(script.Parent.MapService)

type RemixResult = Types.RemixResult

local PROMPT_NAME = CrystalsConfig.Studio.PromptName

local TraitService = {}

local rng = Random.new()

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

-- Faz o Remix; devolve (ok, mensagem)
function TraitService.Remix(player: Player, uid: string): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	local artist = data.Artists[uid]
	if not artist then
		return false, "Artista não encontrado."
	end
	local rarity = ArtistCalc.GetRarity(artist.Rarity)
	local cost = TraitCalc.GetRemixCost(if rarity then rarity.Family else "Common")
	if data.Crystals < cost then
		return false, string.format("Cristais insuficientes (%d/%d).", data.Crystals, cost)
	end
	data.Crystals -= cost

	local oldTrait, oldTier = artist.Trait, artist.TraitTier
	artist.Trait, artist.TraitTier = TraitCalc.Roll(rng)
	ArtistService.Commit(player) -- os traços mudam os efeitos (e as taxas em cache)
	PlayerStateService.MarkDirty(player)

	local result: RemixResult = { Uid = uid, OldTrait = oldTrait, OldTier = oldTier, Trait = artist.Trait, Tier = artist.TraitTier }
	ServerNet.FireClient(RemoteDefs.Defs.RemixResult, player, result)

	if artist.TraitTier == TraitsConfig.AnnounceTier then
		ServerNet.FireAllClients(RemoteDefs.Defs.RemixBurst, player.UserId)
		local def = ArtistCalc.GetArtist(artist.Id)
		local trait = TraitCalc.Get(artist.Trait)
		local text = string.format(
			"%s fez Remix e tirou um traço LENDÁRIO: %s em %s!",
			player.DisplayName,
			if trait then trait.Name else artist.Trait,
			if def then def.Name else artist.Id
		)
		for _, other in Players:GetPlayers() do
			notify(other, text)
		end
	end
	Diag.Log("Remix", string.format("%s: %s %s -> %s %s (-%d Cristais)", player.Name, uid, oldTrait, artist.Trait, artist.TraitTier, cost))
	return true, "Novo traço: " .. TraitCalc.Describe(artist.Trait, artist.TraitTier)
end

local function createStudioPrompt()
	local map = MapService.GetMapFolder()
	local plaza = if map then map:FindFirstChild("Plaza") else nil
	local root = if plaza then plaza:FindFirstChild("Root") else nil
	local attachment = if root then root:FindFirstChild("RemixStudio") else nil
	if not attachment or not attachment:IsA("Attachment") then
		warn("[TraitService] Praça sem o Attachment 'RemixStudio': Estúdio de Remix sem prompt")
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Remixar traços"
	prompt.ObjectText = "Estúdio de Remix"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CrystalsConfig.Studio.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = attachment
end

function TraitService.Init()
	ServerNet.Connect(RemoteDefs.Defs.RemixTrait, function(player: Player, uidArg: unknown)
		local ok, message = TraitService.Remix(player, uidArg :: string)
		if not ok then
			notify(player, message)
		end
	end)
end

function TraitService.Start()
	createStudioPrompt()
end

TraitService.PromptName = PROMPT_NAME

return TraitService
