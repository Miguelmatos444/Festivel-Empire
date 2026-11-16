--!strict
--[[
	AchievementService
	Conquistas (Config/Badges) atribuídas pelo servidor a partir dos sinais do jogo.
	Cada conquista fica em ProfileData.Badges (nunca se pede duas vezes); se tiver
	BadgeId > 0, chama BadgeService:AwardBadge (protegido com pcall, fora do fluxo).
]]

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local BadgesConfig = require(ReplicatedStorage.Shared.Config.Badges)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local DataService = require(script.Parent.DataService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local BassDropService = require(script.Parent.BassDropService)
local GachaService = require(script.Parent.GachaService)
local ArtistService = require(script.Parent.ArtistService)
local StageService = require(script.Parent.StageService)
local PrestigeService = require(script.Parent.PrestigeService)
local RetentionService = require(script.Parent.RetentionService)
local ArrowGameService = require(script.Parent.ArrowGameService)

type ProfileData = Types.ProfileData

local AchievementService = {}

local trove = Trove.new()

function AchievementService.Award(player: Player, key: string)
	local data = DataService.GetProfile(player)
	local def = BadgesConfig.ByKey[key]
	if not data or not def or data.Badges[key] then
		return
	end
	data.Badges[key] = true
	local notice: Types.Notice = { Kind = "Info", Text = "🏆 Conquista: " .. def.Name }
	PlayerStateService.Notify(player, notice)
	Diag.Log("Achievements", player.Name .. " → " .. key)
	if def.BadgeId > 0 then
		task.spawn(function()
			local ok, err = pcall(function()
				BadgeService:AwardBadge(player.UserId, def.BadgeId)
			end)
			if not ok then
				warn("[AchievementService] AwardBadge falhou (" .. key .. "): " .. tostring(err))
			end
		end)
	end
end

local function checkTier(player: Player)
	local data = DataService.GetProfile(player)
	if not data then
		return
	end
	for tier, key in BadgesConfig.TierBadges do
		if data.StageTier >= tier then
			AchievementService.Award(player, key)
		end
	end
end

local function checkPlatinum(player: Player)
	local data = DataService.GetProfile(player)
	if not data then
		return
	end
	for _, artist in data.Artists do
		if artist.Stars >= 3 then
			AchievementService.Award(player, "FirstPlatinum")
			return
		end
	end
end

function AchievementService.Init()
	trove:Add(ArrowGameService.ArrowHit:Connect(function(player: Player)
		AchievementService.Award(player, "FirstBeat") -- "Primeira Batida" = primeiro acerto no palco
	end))
	trove:Add(BassDropService.DropSucceeded:Connect(function(player: Player, grade: Types.DropGrade)
		if grade == "Perfect" then
			AchievementService.Award(player, "FirstPerfect")
		end
	end))
	trove:Add(StageService.StagePlaced:Connect(checkTier))
	trove:Add(PrestigeService.WorldTourCompleted:Connect(function(player: Player)
		AchievementService.Award(player, "FirstWorldTour")
	end))
	trove:Add(GachaService.CratesOpened:Connect(function(player: Player, _count: number, items: { Types.CrateItem })
		local mythicIndex = RaritiesConfig.IndexById.Mythic
		for _, item in items do
			if (RaritiesConfig.IndexById[item.Rarity] or 0) >= mythicIndex then
				AchievementService.Award(player, "FirstMythic")
				break
			end
		end
		checkPlatinum(player) -- o Auto-Fuse pode criar um 3★
	end))
	trove:Add(ArtistService.Fused:Connect(checkPlatinum))
	trove:Add(RetentionService.DailyClaimed:Connect(function(player: Player, day: number)
		if day >= 7 then
			AchievementService.Award(player, "Streak7")
		end
	end))
	-- Perfis antigos: atribui o que já foi conquistado antes de existirem conquistas
	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player, data: ProfileData)
		task.defer(function()
			checkTier(player)
			checkPlatinum(player)
			if data.WorldTours > 0 then
				AchievementService.Award(player, "FirstWorldTour")
			end
		end)
	end))
end

function AchievementService.Start() end

return AchievementService
