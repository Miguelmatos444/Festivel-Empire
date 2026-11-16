--!strict
--[[
	Config/Prestige
	World Tour: requisitos, fórmula dos Discos de Platina, Fama e apresentação.

	Discos = floor( DiscBase × √(HypeDaRun ÷ HypeReference)
	              × (1 + TierBonus × (TierFinal − MinTier))
	              × (1 + bónus "Contrato Discográfico") )
]]

local Types = require(script.Parent.Parent.Types)

local TRANSITION: Types.TransitionTiming = { Dismantle = 3, Pause = 1, Build = 2 }

local Prestige = table.freeze({
	MinTier = 6,
	DiscBase = 10,
	HypeReference = 1e12,
	TierBonus = 0.25,

	-- Fama do Tour: Hype global × FamePerWorldTour ^ WorldTours
	FamePerWorldTour = 1.5,

	-- Geradores que o nó "Material Guardado" mantém num nível inicial
	StartingGeneratorIds = table.freeze({ "GarageSpeaker", "BassSpeaker", "Mixer4", "LineArray" }),
	MaxStartTier = 4,

	-- Confirmação no cliente (manter premido)
	ConfirmHoldSeconds = 2,

	-- Animação do reset (replicada, como as trocas de palco)
	Transition = table.freeze(TRANSITION),

	-- Decoração de Prestige: cor do arco por nº de World Tours (o maior limiar atingido)
	ArchLevels = table.freeze({
		table.freeze({ MinTours = 1, Name = "Bronze", Color = Color3.fromRGB(205, 127, 50) }),
		table.freeze({ MinTours = 2, Name = "Prata", Color = Color3.fromRGB(200, 205, 215) }),
		table.freeze({ MinTours = 3, Name = "Ouro", Color = Color3.fromRGB(255, 200, 60) }),
		table.freeze({ MinTours = 5, Name = "Platina", Color = Color3.fromRGB(180, 235, 255) }),
		table.freeze({ MinTours = 10, Name = "Diamante", Color = Color3.fromRGB(120, 220, 255) }),
	}),
	MaxBanners = 10,
})

return Prestige
