--!strict
--[[
	Bootstrap único do servidor.
	Fase Init: cada módulo regista remotes/sinais (o MapService constrói o mapa).
	Fase Start: arranque de loops e de jogadores.

	Cada passo corre isolado (xpcall): um erro num módulo é mostrado no Output com
	traceback e NÃO impede os restantes de arrancar. O núcleo da economia
	(rede, dados, cliques, estado, Bass Drop) inicializa antes do mundo, para que um
	erro no mapa nunca desligue os cliques nem a replicação.
	O PlotService arranca antes do DataService para atribuir terrenos logo à entrada;
	o DataService arranca por último para que todos os listeners já existam.
]]

local Server = script.Parent

local ServerNet = require(Server.Net.ServerNet)
local DataService = require(Server.Services.DataService)
local EconomyService = require(Server.Services.EconomyService)
local EquipmentService = require(Server.Services.EquipmentService)
local PlayerStateService = require(Server.Services.PlayerStateService)
local PyroService = require(Server.Services.PyroService)
local BassDropService = require(Server.Services.BassDropService)
local MapService = require(Server.Services.MapService)
local PlotService = require(Server.Services.PlotService)
local StageService = require(Server.Services.StageService)
local ArtistService = require(Server.Services.ArtistService)
local GachaService = require(Server.Services.GachaService)
local StageArtistService = require(Server.Services.StageArtistService)
local PrestigeService = require(Server.Services.PrestigeService)
local MonetizationService = require(Server.Services.MonetizationService)
local RetentionService = require(Server.Services.RetentionService)
local AchievementService = require(Server.Services.AchievementService)
local LeaderboardService = require(Server.Services.LeaderboardService)
local DebugService = require(Server.Services.DebugService)

local startedAt = os.clock()
local failures: { string } = {}

local function run(label: string, callback: () -> ())
	local ok, err = xpcall(callback, debug.traceback)
	if not ok then
		table.insert(failures, label)
		warn(string.format("[Server] %s FALHOU:\n%s", label, tostring(err)))
	end
end

-- Init: núcleo primeiro, mundo depois
run("ServerNet.Init", ServerNet.Init)
run("DataService.Init", DataService.Init)
run("EconomyService.Init", EconomyService.Init)
run("EquipmentService.Init", EquipmentService.Init)
run("PlayerStateService.Init", PlayerStateService.Init)
run("PyroService.Init", PyroService.Init)
run("ArtistService.Init", ArtistService.Init)
run("BassDropService.Init", BassDropService.Init)
run("GachaService.Init", GachaService.Init)
run("DebugService.Init", DebugService.Init)
run("MapService.Init", MapService.Init)
run("PlotService.Init", PlotService.Init)
run("StageService.Init", StageService.Init)
run("StageArtistService.Init", StageArtistService.Init)
run("PrestigeService.Init", PrestigeService.Init)
run("MonetizationService.Init", MonetizationService.Init)
run("RetentionService.Init", RetentionService.Init)
run("AchievementService.Init", AchievementService.Init)
run("LeaderboardService.Init", LeaderboardService.Init)

-- Só agora (todos os handlers registados) os remotes ficam visíveis ao cliente
run("ServerNet.Open", ServerNet.Open)

-- Start
run("MapService.Start", MapService.Start)
run("EconomyService.Start", EconomyService.Start)
run("EquipmentService.Start", EquipmentService.Start)
run("PlayerStateService.Start", PlayerStateService.Start)
run("PyroService.Start", PyroService.Start)
run("ArtistService.Start", ArtistService.Start)
run("BassDropService.Start", BassDropService.Start)
run("GachaService.Start", GachaService.Start)
run("StageService.Start", StageService.Start)
run("StageArtistService.Start", StageArtistService.Start)
run("PrestigeService.Start", PrestigeService.Start)
run("MonetizationService.Start", MonetizationService.Start)
run("RetentionService.Start", RetentionService.Start)
run("AchievementService.Start", AchievementService.Start)
run("LeaderboardService.Start", LeaderboardService.Start)
run("DebugService.Start", DebugService.Start)
run("PlotService.Start", PlotService.Start)
run("DataService.Start", DataService.Start)

if #failures == 0 then
	print(string.format("[Server] Festival Empire Tycoon pronto (%.1f ms)", (os.clock() - startedAt) * 1000))
else
	warn(string.format("[Server] Arrancou com %d falha(s): %s", #failures, table.concat(failures, ", ")))
end
