--!strict
--[[
	Config/Codes
	Códigos promocionais. Code em maiúsculas (letras e números). ExpiresAt em os.time()
	UTC (nil = não expira). MaxUses = limite GLOBAL entre servidores (nil = ilimitado).
	Cada jogador só pode usar cada código uma vez.
]]

local Types = require(script.Parent.Parent.Types)

type CodeDef = Types.CodeDef

local List: { CodeDef } = {
	{
		Code = "FESTIVAL2026",
		Reward = { IncomeMinutes = 60 },
		ExpiresAt = 1798761599, -- 31/12/2026 23:59:59 UTC
	},
	{
		Code = "PRIMEIROPALCO",
		Reward = { Crates = 1 },
		MaxUses = 1000,
	},
}

local ByCode: { [string]: CodeDef } = {}
for _, def in List do
	assert(string.match(def.Code, "^[%u%d]+$"), "Config/Codes: código inválido " .. def.Code)
	assert(ByCode[def.Code] == nil, "Config/Codes: código duplicado " .. def.Code)
	table.freeze(def.Reward)
	ByCode[def.Code] = table.freeze(def)
end

return table.freeze({
	List = table.freeze(List),
	ByCode = table.freeze(ByCode),
	StoreName = "FestivalEmpire_CodeUses",
})
