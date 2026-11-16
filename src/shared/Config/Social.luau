--!strict
--[[
	Config/Social
	Bónus sociais (todos calculados no servidor) e evento global "Headliner".
	Multiplicador Social = (1 + amigos) × (1 + grupo) × (1 + Likes) × Headliner,
	aplicado ao Hype depois do Gamepass Hype ×2.
]]

local Types = require(script.Parent.Parent.Types)

local LIKER_REWARD: Types.RewardDef = { IncomeMinutes = 3 }

local Social = table.freeze({
	Friends = table.freeze({
		BonusPerFriend = 0.10, -- +10% por amigo no mesmo servidor
		MaxFriends = 5, -- até +50%
	}),

	Group = table.freeze({
		GroupId = 0, -- id do grupo Roblox do jogo (0 = bónus desligado)
		Bonus = 0.10, -- +10% para membros
	}),

	Likes = table.freeze({
		LikesPerStep = 10, -- cada 10 Likes recebidos (de sempre)...
		BonusPerStep = 0.01, -- ...dão +1% de Hype
		MaxBonus = 0.20, -- até +20%
		MaxGivenPerDay = 5, -- Likes que cada jogador pode dar por dia (UTC), 1 por festival
		LikerReward = table.freeze(LIKER_REWARD), -- recompensa de quem dá o Like
	}),

	-- Evento global: igual em todos os servidores (calculado a partir da hora UTC)
	Headliner = table.freeze({
		Interval = 2 * 3600, -- começa a cada 2 h (00:00, 02:00, … UTC)
		Offset = 0, -- desfasamento em segundos em relação à meia-noite UTC
		Duration = 10 * 60, -- dura 10 min
		WarningSeconds = 5 * 60, -- aviso no HUD 5 min antes
		HypeMultiplier = 2,
		EnergyMultiplier = 1.5,
	}),

	-- Atributos públicos do jogador (tier, World Tours, Likes) para a lista de festivais
	PublicRefreshInterval = 2,
})

return Social
