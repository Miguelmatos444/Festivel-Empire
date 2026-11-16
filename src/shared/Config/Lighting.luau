--!strict
--[[
	Config/Lighting
	Iluminação de festival aplicada pelo LightingService ao arrancar o servidor
	(replica para todos). Fim de tarde roxo, néon a brilhar e cores mais vivas.
	Para manter a iluminação feita à mão no place: atributo KeepLighting = true no Lighting.
]]

local Lighting = table.freeze({
	Enabled = true,

	Properties = table.freeze({
		ClockTime = 18.3,
		Brightness = 2.2,
		Ambient = Color3.fromRGB(70, 50, 110),
		OutdoorAmbient = Color3.fromRGB(120, 90, 160),
		ColorShift_Top = Color3.fromRGB(255, 170, 120),
		ColorShift_Bottom = Color3.fromRGB(90, 60, 160),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.7,
		GlobalShadows = true,
		ShadowSoftness = 0.25,
		ExposureCompensation = 0.1,
	}),

	Atmosphere = table.freeze({
		Density = 0.32,
		Offset = 0.2,
		Color = Color3.fromRGB(205, 170, 255),
		Decay = Color3.fromRGB(110, 70, 170),
		Glare = 0.4,
		Haze = 1.4,
	}),

	-- Brilho (Bloom) normal: suave. O StageLightController (cliente) sobe-o no Bass Drop do jogador.
	Bloom = table.freeze({
		Intensity = 0.15,
		Size = 16,
		Threshold = 1.3,
	}),
	DropBloom = table.freeze({
		Intensity = 0.9,
		Size = 30,
		Threshold = 0.95,
	}),

	-- Luzes dos palcos (peças Neon_*/Led*/LEDScreen, tag FE_StageLight), no cliente.
	-- Dim = quanto a cor escurece (0 = brilho total, 1 = apagada). Quanto mais escura, menos o néon brilha.
	StageLights = table.freeze({
		IdleDim = 0.55, -- fora do drop
		BuildUpDim = 0.3, -- build-up/janela (pisca a cada batida)
		BoostDim = 0, -- boost do drop: brilho total
		BeatFlash = 0.25, -- quanto acende a cada batida durante o boost/build-up
		OtherBoostSeconds = 12, -- duração assumida do boost dos outros jogadores
		TweenSeconds = 0.4, -- transição do Bloom
	}),

	ColorCorrection = table.freeze({
		Brightness = 0.02,
		Contrast = 0.12,
		Saturation = 0.28,
		TintColor = Color3.fromRGB(255, 242, 255),
	}),

	SunRays = table.freeze({
		Intensity = 0.06,
		Spread = 0.8,
	}),
})

return Lighting
