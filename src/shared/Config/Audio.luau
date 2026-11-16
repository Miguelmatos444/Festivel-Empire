--!strict
--[[
	Config/Audio
	Cola aqui os ids numéricos dos sons (Creator Store com licença ou uploads próprios).
	0 = desativado: o som não é criado (sem erros de asset) e os efeitos visuais
	pulsam pelo relógio de BPM (Config/BassDrop.BPM) em vez do PlaybackLoudness.
]]

local PYRO_SOUNDS: { [string]: number } = {
	ColdSparks = 0,
	CO2Cannon = 0,
	Lasers = 0,
	Flamethrower = 0,
}

-- Abertura das crates e cinemática (Fase 12). 0 = usa o som de fallback abaixo.
local CRATE_SOUNDS: { [string]: number } = {
	CrateTick = 0, -- cada carta que passa o marcador da roleta
	CrateStop = 0, -- a roleta para (Comum)
	CrateRare = 0, -- paragem Raro/Épico
	CrateLegendary = 0, -- paragem Lendário/Mítico (flash + confetti)
	MysteryPulse = 0, -- "???" a pulsar
	Thunder = 0,
	RiftOpen = 0, -- o céu começa a rachar
	SkyShatter = 0, -- o céu estilhaça
	Impact = 0, -- aterragem do artista
	RevealSting = 0, -- revelação final
}

-- Sons de fallback (ficheiros que vêm com o cliente Roblox) e velocidade de cada um.
-- Placeholders até haver ids próprios em CRATE_SOUNDS.
type FallbackSound = { Path: string, Speed: number, Volume: number }
-- stylua: ignore
local CRATE_FALLBACKS: { [string]: FallbackSound } = {
	CrateTick      = { Path = "rbxasset://sounds/clickfast.wav",            Speed = 1.6,  Volume = 0.35 },
	CrateStop      = { Path = "rbxasset://sounds/electronicpingshort.wav",  Speed = 1,    Volume = 0.6 },
	CrateRare      = { Path = "rbxasset://sounds/electronicpingshort.wav",  Speed = 1.25, Volume = 0.8 },
	CrateLegendary = { Path = "rbxasset://sounds/electronicpingshort.wav",  Speed = 0.7,  Volume = 1 },
	MysteryPulse   = { Path = "rbxasset://sounds/electronicpingshort.wav",  Speed = 0.45, Volume = 0.7 },
	Thunder        = { Path = "rbxasset://sounds/collide.wav",              Speed = 0.25, Volume = 1 },
	RiftOpen       = { Path = "rbxasset://sounds/electronicpingshort.wav",  Speed = 0.3,  Volume = 0.8 },
	SkyShatter     = { Path = "rbxasset://sounds/collide.wav",              Speed = 0.6,  Volume = 1 },
	Impact         = { Path = "rbxasset://sounds/collide.wav",              Speed = 0.35, Volume = 1 },
	RevealSting    = { Path = "rbxasset://sounds/electronicpingshort.wav",  Speed = 0.85, Volume = 1 },
}

local Audio = table.freeze({
	MusicLoop = 0, -- música do festival em loop (~128 BPM)
	BuildUpRiser = 0, -- tocado no início do build-up
	DropImpact = 0, -- tocado num drop bem-sucedido
	Pyro = table.freeze(PYRO_SOUNDS),
	Crate = table.freeze(CRATE_SOUNDS),
	CrateFallbacks = table.freeze(CRATE_FALLBACKS),
	CrateVolume = 0.8,
	MusicFadeTime = 0.5, -- s para cortar/repor a música na cinemática

	Volumes = table.freeze({
		Music = 0.5,
		Riser = 0.7,
		Impact = 0.9,
		Pyro = 0.6,
	}),

	-- PlaybackLoudness que corresponde a intensidade 1.0 (ajustar à música escolhida)
	LoudnessReference = 350,
	-- Suavização da intensidade vinda da música (maior = reage mais depressa)
	IntensitySmoothing = 14,
})

return Audio
