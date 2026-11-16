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

local Audio = table.freeze({
	MusicLoop = 0, -- música do festival em loop (~128 BPM); usada nas eras sem id próprio
	-- Música por era do palco do próprio jogador (0 = usa MusicLoop). Troca com crossfade.
	EraMusic = table.freeze({
		Underground = 0,
		["Ascensão"] = 0,
		Estrelato = 0,
		Lenda = 0,
	} :: { [string]: number }),
	CrossfadeSeconds = 2.5,
	BuildUpRiser = 0, -- tocado no início do build-up
	DropImpact = 0, -- tocado num drop bem-sucedido
	Pyro = table.freeze(PYRO_SOUNDS),

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
