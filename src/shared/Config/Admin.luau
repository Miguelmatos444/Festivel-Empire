--!strict
--[[
	Config/Admin
	Quem pode usar os comandos do DebugService.
]]

local Admin = table.freeze({
	-- UserIds com acesso total aos comandos de debug
	UserIds = table.freeze({} :: { number }),

	-- Dono do jogo (utilizador) ou rank 255 do grupo dono
	AllowGameOwner = true,

	-- Em Studio, todos os jogadores de teste são admin
	AllowStudio = true,

	-- Aliases do comando de chat (ex.: "/fe hype add 1e12")
	CommandAliases = table.freeze({ "/fe", "/admin" }),
})

return Admin
