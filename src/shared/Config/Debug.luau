--!strict
--[[
	Config/Debug
	Interruptores de diagnóstico. Desligar NetTrace antes de publicar o jogo.
]]

local Debug = table.freeze({
	-- Prints [Diag:S]/[Diag:C] em cada passo da cadeia cliente <-> servidor
	NetTrace = true,
	-- Repetições do mesmo evento: mostra as 3 primeiras e depois 1 em cada N
	SampleEvery = 25,
})

return Debug
