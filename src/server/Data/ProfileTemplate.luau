--!strict
--[[
	ProfileTemplate
	Perfil por defeito de um jogador novo e reconciliação de perfis antigos/corrompidos.
	Sempre que mudares a estrutura: incrementa `Version` e adiciona o passo em Migrations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.Economy)

type RawData = { [string]: unknown }

local ProfileTemplate = {}

ProfileTemplate.Version = 2 -- v2: campo Social (Likes)

function ProfileTemplate.Create(): Types.ProfileData
	return {
		DataVersion = ProfileTemplate.Version,
		Hype = BigNum.serialize(BigNum.fromNumber(EconomyConfig.StartingHype)),
		TotalHypeEarned = BigNum.serialize(BigNum.ZERO),
		RunHypeEarned = BigNum.serialize(BigNum.ZERO),
		PlatinumDiscs = 0,
		TotalDiscsEarned = 0,
		WorldTours = 0,
		StageTier = 1,
		Equipment = {},
		Artists = {},
		EquippedArtists = {},
		NextArtistUid = 1,
		Pity = {
			Legendary = 0,
			Mythic = 0,
			Divine = 0,
			Cosmic = 0,
		},
		SkillTree = {},
		Stats = {
			Clicks = 0,
			PlayTime = 0,
			BassDrops = 0,
		},
		Settings = {
			MusicVolume = 0.8,
			SfxVolume = 1,
			LowVfx = false,
			AutoFuse = false,
			AutoDeleteUpTo = 0,
		},
		-- Faíscas Frias desbloqueadas desde o início; perfis antigos recebem-nas via Reconcile
		Pyro = {
			ColdSparks = true,
		},
		LastOnline = 0,
		Daily = {
			Streak = 0,
			LastClaim = 0,
		},
		Missions = {
			DayIndex = -1,
			WeekIndex = -1,
			Daily = {},
			Weekly = {},
		},
		RedeemedCodes = {},
		Badges = {},
		Receipts = {},
		AutoClick = false,
		Social = {
			LikesReceived = 0,
			LikesGivenDay = -1,
			LikedToday = {},
		},
	}
end

-- Preenche chaves em falta e substitui valores com tipo errado (recursivo).
local function reconcile(target: RawData, template: RawData)
	for key, default in template do
		local current = target[key]
		if current == nil or typeof(current) ~= typeof(default) then
			target[key] = default
		elseif type(current) == "table" and type(default) == "table" then
			reconcile(current :: RawData, default :: RawData)
		end
	end
end

function ProfileTemplate.Reconcile(data: RawData)
	local template = (ProfileTemplate.Create() :: unknown) :: RawData
	reconcile(data, template)
end

return ProfileTemplate
