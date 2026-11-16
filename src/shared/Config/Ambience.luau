--!strict
--[[
	Config/Ambience
	Ambiente do festival (tudo no cliente; nada replica):
	  - Público por terreno: tamanho por tier, reação à música e ao Bass Drop
	  - Luzes da praça ao ritmo
	  - Danças dos artistas (procedimentais por família, ou AnimationId próprio)
	As distâncias de LOD estão em Config/Lod.Crowd.
]]

local Types = require(script.Parent.Parent.Types)

type DanceStyle = Types.DanceStyle

export type CrowdTier = {
	MinTier: number,
	Own: number, -- pessoas no terreno do próprio jogador
	Other: number, -- pessoas nos terrenos dos outros jogadores
}

-- stylua: ignore
local CROWD_BY_TIER: { CrowdTier } = {
	{ MinTier = 1,  Own = 12, Other = 4 },
	{ MinTier = 2,  Own = 20, Other = 6 },
	{ MinTier = 4,  Own = 32, Other = 10 },
	{ MinTier = 7,  Own = 44, Other = 14 },
	{ MinTier = 10, Own = 60, Other = 18 },
}

local DANCE_BY_FAMILY: { [string]: DanceStyle } = {
	Common = "Sway",
	Rare = "Jump",
	Epic = "Headbang",
	Legendary = "Spin",
	Mythic = "Spin",
}

-- [ArtistId] = AnimationId (rbxassetid numérico). Sem entrada (ou 0) = dança procedimental.
-- A animação só toca se o modelo do artista tiver Humanoid (o placeholder R15 tem).
local ARTIST_ANIMATIONS: { [string]: number } = {}

local Ambience = table.freeze({
	Crowd = table.freeze({
		ByTier = table.freeze(CROWD_BY_TIER),
		-- Zona do público (coordenadas do terreno): X em ±AreaHalfWidth, profundidade de Map.Plots.CrowdStart a CrowdEnd
		AreaHalfWidth = 40,
		DepthMargin = 3,
		MinSpacing = 3.2, -- distância mínima entre pessoas
		BounceHeight = 0.8, -- salto em cada batida (×intensidade)
		BuildUpBounce = 1.5, -- salto no build-up (mais agitado)
		DropJumpHeight = 4, -- salto da explosão do Bass Drop (×força da nota)
		DropJumpDuration = 1.4,
		-- Força da explosão por nota (multiplica salto e confetes)
		GradeStrength = table.freeze({ Perfect = 1.4, Great = 1.15, Good = 0.9, Late = 0.6 }),
		ConfettiBase = 120, -- partículas de confetes no próprio terreno (força 1)
		ShirtColors = table.freeze({
			Color3.fromRGB(255, 60, 172),
			Color3.fromRGB(43, 210, 255),
			Color3.fromRGB(255, 209, 102),
			Color3.fromRGB(57, 217, 138),
			Color3.fromRGB(160, 120, 255),
			Color3.fromRGB(255, 120, 60),
			Color3.fromRGB(240, 240, 240),
			Color3.fromRGB(40, 40, 48),
		}),
		SkinColors = table.freeze({
			Color3.fromRGB(255, 220, 185),
			Color3.fromRGB(234, 184, 146),
			Color3.fromRGB(198, 134, 94),
			Color3.fromRGB(141, 85, 54),
			Color3.fromRGB(92, 56, 36),
		}),
		GlowstickColors = table.freeze({
			Color3.fromRGB(57, 255, 120),
			Color3.fromRGB(255, 60, 200),
			Color3.fromRGB(60, 200, 255),
			Color3.fromRGB(255, 240, 60),
		}),
	}),

	PlazaLights = table.freeze({
		HueStepPerBeat = 0.07, -- quanto a cor das luzes avança a cada batida
		Saturation = 0.85,
		HeadlinerColor = Color3.fromRGB(255, 200, 60),
		BeamColor = Color3.fromRGB(255, 220, 120),
	}),

	Dance = table.freeze({
		ByFamily = table.freeze(DANCE_BY_FAMILY),
		DropJumpHeight = 2.5, -- salto extra dos artistas no Bass Drop do dono
		DropJumpDuration = 1.2,
	}),

	ArtistAnimations = table.freeze(ARTIST_ANIMATIONS),
})

return Ambience
