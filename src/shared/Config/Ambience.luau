--!strict
--[[
	Config/Ambience
	Ambiente do festival (tudo no cliente; nada replica):
	  - Público por terreno: tamanho pelo Hype ganho na run (+ World Tours), avatares dos
	    amigos do dono à frente, reação à música e ao Bass Drop
	  - Luzes da praça ao ritmo
	  - Danças dos artistas (procedimentais por família, ou AnimationId próprio)
	As distâncias de LOD estão em Config/Lod.Crowd.
]]

local Types = require(script.Parent.Parent.Types)

type DanceStyle = Types.DanceStyle

export type CrowdLevel = {
	MinHype: number, -- Hype ganho na run a partir do qual vale este nível
	Own: number, -- pessoas no terreno do próprio jogador
	Other: number, -- pessoas nos terrenos dos outros jogadores (visto por quem visita)
}

-- Nível replicado pelo servidor no atributo FE_CrowdLevel do dono (índice desta tabela)
-- stylua: ignore
local CROWD_BY_HYPE: { CrowdLevel } = {
	{ MinHype = 0,      Own = 6,  Other = 3 },
	{ MinHype = 1e3,    Own = 10, Other = 4 },
	{ MinHype = 1e5,    Own = 16, Other = 6 },
	{ MinHype = 1e7,    Own = 22, Other = 8 },
	{ MinHype = 1e9,    Own = 28, Other = 10 },
	{ MinHype = 1e11,   Own = 36, Other = 12 },
	{ MinHype = 1e13,   Own = 44, Other = 14 },
	{ MinHype = 1e15,   Own = 52, Other = 16 },
	{ MinHype = 1e17,   Own = 60, Other = 18 },
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
		ByHype = table.freeze(CROWD_BY_HYPE),
		PerWorldTourOwn = 2, -- pessoas extra permanentes por World Tour (terreno próprio)
		PerWorldTourOther = 1,
		MaxOwn = 80,
		MaxOther = 24,
		-- Avatares dos amigos do dono (cliente: GetFriendsAsync + CreateHumanoidModelFromDescription)
		Friends = table.freeze({
			Enabled = true,
			MaxOwn = 12, -- avatares completos no próprio terreno
			MaxOther = 4, -- nos terrenos dos outros
			FetchLimit = 60, -- amigos lidos da lista (os que estão no servidor vêm primeiro)
			NameDistance = 70, -- distância máxima a que se vê o nome
			-- Emotes R15 do Roblox (dança, vivas, aceno, dança 2, dança 3)
			Animations = table.freeze({ 507771019, 507770677, 507770239, 507771955, 507772104 }),
		}),
		-- Bonecos-padrão do Roblox (R15) com cores aleatórias: enchem os lugares de avatar que os
		-- amigos não ocupam. Max* = total de avatares (amigos + padrão) por terreno; o resto do
		-- público são os bonecos simples.
		DefaultAvatars = table.freeze({
			Enabled = true,
			MaxOwn = 24,
			MaxOther = 6,
		}),
		-- Bonecos simples
		HeightRange = table.freeze({ 0.9, 1.12 }),
		FaceTexture = "rbxasset://textures/face.png",
		HairColors = table.freeze({
			Color3.fromRGB(30, 22, 18),
			Color3.fromRGB(92, 58, 32),
			Color3.fromRGB(214, 170, 90),
			Color3.fromRGB(180, 60, 40),
			Color3.fromRGB(255, 90, 180),
			Color3.fromRGB(60, 200, 255),
		}),
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
