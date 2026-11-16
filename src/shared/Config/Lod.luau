--!strict
--[[
	Config/Lod
	Nível de detalhe por distância para o que acontece nos OUTROS terrenos.
	O terreno do próprio jogador usa sempre a versão completa.
	Distâncias em studs, medidas da câmara ao ponto do efeito.
]]

local Lod = table.freeze({
	-- Pirotecnia dos outros jogadores: leve até LightDistance, mínima até HideDistance, nada além
	Vfx = table.freeze({
		LightDistance = 120,
		HideDistance = 250,
		Scale = table.freeze({ Full = 1, Light = 0.4, Minimal = 0.15 }),
	}),

	-- Sons dos outros terrenos: posicionais (3D) até MaxDistance, silêncio além
	Audio = table.freeze({
		MaxDistance = 120,
		VolumeScale = 0.6,
	}),

	-- Público dos OUTROS terrenos (o próprio é sempre completo):
	-- animado (só saltos) até AnimatedDistance, parado até StaticDistance, escondido além
	Crowd = table.freeze({
		AnimatedDistance = 120,
		StaticDistance = 250,
		OtherUpdateRate = 15, -- atualizações por segundo dos públicos dos outros terrenos
		CheckInterval = 0.5, -- segundos entre verificações de distância
	}),

	-- Animação de troca de palco dos outros terrenos:
	-- completa até FullDistance, sem efeitos/som até MaxDistance, salto direto ao fim além
	StageAnimation = table.freeze({
		FullDistance = 120,
		MaxDistance = 250,
	}),
})

return Lod
