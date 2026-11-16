--!strict
--[[
	Config/Dressing
	Adereços feitos no Blender (Models/FBX/Equipment, Pyro, Festival) colocados pelo
	servidor à volta dos palcos e na praça. Cada adereço é lido de
	ServerStorage/Assets/Props/<Nome> (nome = nome do ficheiro FBX) e escalado para o
	tamanho indicado aqui (o FBX pode vir com qualquer escala). Sem o modelo no Studio,
	o adereço simplesmente não aparece (sem erros).
]]

local Map = require(script.Parent.Map)

local Dressing = table.freeze({
	Stage = table.freeze({
		Enabled = true,
		-- Colunas de som no chão, de cada lado da frente do palco (modelo pela era)
		SpeakerByEra = table.freeze({
			Underground = "Speaker_T1",
			["Ascensão"] = "Speaker_T2",
			Estrelato = "Speaker_T3",
			Lenda = "Speaker_T4",
		} :: { [string]: string }),
		SpeakerHeightRatio = 0.45, -- altura = altura do palco × isto (com limites)
		SpeakerMinHeight = 5,
		SpeakerMaxHeight = 24,
		SpeakerGap = 1.5, -- distância à lateral do palco
		SpeakerDepth = 3, -- recuo a partir da frente do palco

		DJBooth = table.freeze({ Name = "DJBooth", Height = 3.6 }),

		-- Máquinas de pirotecnia desbloqueadas, nos Attachments Pyro_<Id>_<n> do palco
		PyroHeights = table.freeze({
			ColdSparks = 2.2,
			CO2Cannon = 3,
			Lasers = 1.8,
			Flamethrower = 3,
		} :: { [string]: number }),
		-- Máquinas penduradas (o topo encosta ao Attachment em vez da base)
		HangFromAbove = table.freeze({ Lasers = true } :: { [string]: boolean }),
	}),

	Plaza = table.freeze({
		Enabled = true,
		-- Com o modelo presente, substitui a roulotte/arco placeholder
		FoodTruck = table.freeze({ Name = "Festival_FoodTruck", Length = 12 }),
		EntranceArch = table.freeze({ Name = "Festival_EntranceArch", Width = Map.Plaza.PathWidth + 6 }),
		FerrisWheel = table.freeze({ Name = "Festival_FerrisWheel", Height = 46, Angle = 270, Radius = 88 }),
		VinylCrate = table.freeze({ Name = "VinylCrate", Height = 4 }), -- nos postos das crates
	}),
})

return Dressing
