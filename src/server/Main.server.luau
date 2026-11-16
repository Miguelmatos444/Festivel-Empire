--!strict
--[[
	Bootstrap único do servidor.
	Fase Init: cada módulo regista remotes/sinais (sem lógica de jogo).
	Fase Start: arranque de loops e carregamento de jogadores.
	O DataService arranca por último para que todos os listeners já existam.
]]

local Server = script.Parent

local ServerNet = require(Server.Net.ServerNet)
local DataService = require(Server.Services.DataService)
local EconomyService = require(Server.Services.EconomyService)
local EquipmentService = require(Server.Services.EquipmentService)
local PlayerStateService = require(Server.Services.PlayerStateService)
local PyroService = require(Server.Services.PyroService)
local BassDropService = require(Server.Services.BassDropService)
local DebugService = require(Server.Services.DebugService)

local startedAt = os.clock()

ServerNet.Init()
DataService.Init()
EconomyService.Init()
EquipmentService.Init()
PlayerStateService.Init()
PyroService.Init()
BassDropService.Init()
DebugService.Init()

EconomyService.Start()
EquipmentService.Start()
PlayerStateService.Start()
PyroService.Start()
BassDropService.Start()
DebugService.Start()
DataService.Start()

print(string.format("[Server] Festival Empire Tycoon pronto (%.1f ms)", (os.clock() - startedAt) * 1000))
