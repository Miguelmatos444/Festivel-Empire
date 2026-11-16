--!strict
--[[
	Config/Badges
	Conquistas atribuídas pelo servidor. BadgeId = 0 até criares a Badge no site
	(a conquista fica registada no perfil e o aviso aparece na mesma).
]]

local Types = require(script.Parent.Parent.Types)

type BadgeDef = Types.BadgeDef

local List: { BadgeDef } = {
	{ Key = "FirstBeat", Name = "Primeira Batida", BadgeId = 0 },
	{ Key = "FirstPerfect", Name = "Primeiro PERFEITO", BadgeId = 0 },
	{ Key = "EraAscensao", Name = "Era Ascensão", BadgeId = 0 },
	{ Key = "EraEstrelato", Name = "Era Estrelato", BadgeId = 0 },
	{ Key = "EraLenda", Name = "Era Lenda", BadgeId = 0 },
	{ Key = "OrbitalStage", Name = "Palco Orbital", BadgeId = 0 },
	{ Key = "FirstWorldTour", Name = "Primeiro World Tour", BadgeId = 0 },
	{ Key = "FirstMythic", Name = "Primeiro Mítico ou melhor", BadgeId = 0 },
	{ Key = "FirstPlatinum", Name = "Primeiro Platinum (3★)", BadgeId = 0 },
	{ Key = "Streak7", Name = "Sequência de 7 dias", BadgeId = 0 },
}

local ByKey: { [string]: BadgeDef } = {}
for _, def in List do
	ByKey[def.Key] = table.freeze(def)
end

return table.freeze({
	List = table.freeze(List),
	ByKey = table.freeze(ByKey),
	-- Tier de palco -> conquista
	TierBadges = table.freeze({ [4] = "EraAscensao", [7] = "EraEstrelato", [10] = "EraLenda", [12] = "OrbitalStage" }),
})
