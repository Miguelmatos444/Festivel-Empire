--!strict
--[[
	Config/Data
	Parâmetros de persistência e session locking.
]]

local Data = table.freeze({
	StoreName = "FestivalEmpire_Profiles",
	KeyPrefix = "Player_",

	-- Auto-save (também renova o session lock)
	AutoSaveInterval = 60,

	-- Um lock sem renovação há mais de X segundos é considerado abandonado (servidor caiu)
	SessionLockTimeout = 300,

	-- Quando o perfil está bloqueado noutro servidor ativo
	LockRetryAttempts = 8,
	LockRetryDelay = 4,

	-- Falhas de pedidos ao DataStore (backoff exponencial)
	RequestRetryAttempts = 4,
	RequestRetryBaseDelay = 1,

	-- Tempo máximo à espera dos saves em BindToClose
	ShutdownTimeout = 25,

	-- Em Studio sem acesso à API, usar store em memória (nada é persistido)
	UseMockInStudioWithoutApi = true,
})

return Data
