--!strict
--[[
	Config/Stages
	Os 12 palcos (4 eras). Width/Depth/Height são o envelope máximo de cada tier:
	o modelo do palco (placeholder ou .fbx) tem de caber nestas medidas.
	Todos os palcos começam na mesma linha da frente e crescem para trás e para cima.
]]

local Types = require(script.Parent.Parent.Types)
local MapConfig = require(script.Parent.Map)

type StageDef = Types.StageDef

local List: { StageDef } = {
	{ Tier = 1, Name = "Palco de paletes", Era = "Underground", Width = 20, Depth = 12, Height = 8, RequiredWorldTours = 0 },
	{ Tier = 2, Name = "Palco de bairro", Era = "Underground", Width = 28, Depth = 16, Height = 12, RequiredWorldTours = 0 },
	{ Tier = 3, Name = "Palco de praia", Era = "Underground", Width = 36, Depth = 20, Height = 16, RequiredWorldTours = 0 },
	{ Tier = 4, Name = "Palco clube", Era = "Ascensão", Width = 44, Depth = 24, Height = 22, RequiredWorldTours = 0 },
	{ Tier = 5, Name = "Palco médio LED", Era = "Ascensão", Width = 52, Depth = 28, Height = 28, RequiredWorldTours = 0 },
	{ Tier = 6, Name = "Palco coberto arena", Era = "Ascensão", Width = 60, Depth = 32, Height = 36, RequiredWorldTours = 0 },
	{ Tier = 7, Name = "Palco principal", Era = "Estrelato", Width = 68, Depth = 36, Height = 46, RequiredWorldTours = 1 },
	{ Tier = 8, Name = "Palco pirotécnico", Era = "Estrelato", Width = 74, Depth = 40, Height = 56, RequiredWorldTours = 1 },
	{ Tier = 9, Name = "Mega palco", Era = "Estrelato", Width = 80, Depth = 44, Height = 66, RequiredWorldTours = 2 },
	{ Tier = 10, Name = "Palco holográfico", Era = "Lenda", Width = 84, Depth = 46, Height = 76, RequiredWorldTours = 3 },
	{ Tier = 11, Name = "Palco estratosférico", Era = "Lenda", Width = 88, Depth = 48, Height = 88, RequiredWorldTours = 4 },
	{ Tier = 12, Name = "Palco orbital", Era = "Lenda", Width = 90, Depth = 48, Height = 100, RequiredWorldTours = 5 },
}

-- Attachments que cada palco expõe no seu Root (usados por VFX, artistas e câmara)
local ATTACHMENT_NAMES: { string } = {
	"StageOrigin",
	"DJBooth",
	"Artist_1",
	"Artist_2",
	"Artist_3",
	"Artist_4",
	"Artist_5",
	"Artist_6",
	"Artist_7",
	"Pyro_ColdSparks_1",
	"Pyro_ColdSparks_2",
	"Pyro_CO2Cannon_1",
	"Pyro_CO2Cannon_2",
	"Pyro_Lasers_1",
	"Pyro_Lasers_2",
	"Pyro_Flamethrower_1",
	"Pyro_Flamethrower_2",
	"Speaker_L",
	"Speaker_R",
	"CameraFocus",
}

-- Validação: todos os palcos cabem na zona do palco do terreno
do
	local zone = MapConfig.Plots.StageZone
	for index, def in List do
		assert(def.Tier == index, "Config/Stages: tiers têm de estar por ordem")
		assert(
			def.Width <= zone.Width and def.Depth <= zone.Depth and def.Height <= zone.Height,
			string.format("Config/Stages: Tier %d excede a zona do palco", def.Tier)
		)
		table.freeze(def)
	end
end

return table.freeze({
	List = table.freeze(List),
	MaxTier = #List,
	AttachmentNames = table.freeze(ATTACHMENT_NAMES),
})
