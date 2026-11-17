--!strict
--[[
	Config/Variants
	Variantes Brilhantes (Fase 13A). Independentes da raridade: cada artista obtido numa
	crate tem uma chance à parte de sair numa variante (sorteio no servidor, da mais rara
	para a mais comum). O bónus multiplica o bónus de Hype do artista:
	  bónus = raridade × era da crate × estrelas × (1 + Bonus da variante)
	O visual é aplicado no cliente (VariantVisuals), com LOD de longe.
]]

local Types = require(script.Parent.Parent.Types)

type VariantDef = Types.VariantDef

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Da mais comum para a mais rara
-- stylua: ignore
local List: { VariantDef } = {
	{ Id = "Golden",      Name = "Dourado",     Chance = 250,    Bonus = 0.25, Color = rgb(255, 200, 60),  Announce = false },
	{ Id = "Neon",        Name = "Neon",        Chance = 500,    Bonus = 0.40, Color = rgb(60, 255, 230),  Announce = false },
	{ Id = "Holographic", Name = "Holográfico", Chance = 1000,   Bonus = 0.60, Color = rgb(200, 160, 255), Announce = true },
	{ Id = "Glitch",      Name = "Glitch",      Chance = 2500,   Bonus = 1.00, Color = rgb(255, 40, 160),  Announce = true },
	{ Id = "Galactic",    Name = "Galáctico",   Chance = 5000,   Bonus = 1.50, Color = rgb(120, 90, 255),  Announce = true },
	{ Id = "Infernal",    Name = "Infernal",    Chance = 10000,  Bonus = 2.50, Color = rgb(255, 70, 20),   Announce = true },
}

local ById: { [string]: VariantDef } = {}
local Ids: { string } = {}
for _, def in List do
	assert(ById[def.Id] == nil, "Config/Variants: variante duplicada " .. def.Id)
	assert(def.Chance >= 1, "Config/Variants: Chance tem de ser >= 1 em " .. def.Id)
	ById[def.Id] = table.freeze(def)
	table.insert(Ids, def.Id)
end

return table.freeze({
	List = table.freeze(List),
	ById = table.freeze(ById),
	Ids = table.freeze(Ids),
	AutoDeleteVariantsDefault = false, -- o Auto-Delete nunca apaga variantes, salvo se o jogador ligar
})
