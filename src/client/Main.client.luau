--!strict
--[[
	Bootstrap único do cliente.
	Ordem: rede -> controllers -> UI -> avisar o servidor (ClientReady) -> áudio/VFX.

	Cada passo corre isolado (xpcall): um erro numa View ou controller é mostrado no
	Output e NÃO impede o ClientReady — sem ele o servidor nunca envia o Hype nem a
	barra de energia.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Client = script.Parent

local NetController = require(Client.Controllers.NetController)
local StateController = require(Client.Controllers.StateController)
local ClickController = require(Client.Controllers.ClickController)
local EquipmentController = require(Client.Controllers.EquipmentController)
local BassDropController = require(Client.Controllers.BassDropController)
local AudioController = require(Client.Controllers.AudioController)
local PyroVfxController = require(Client.Controllers.PyroVfxController)
local PlotController = require(Client.Controllers.PlotController)
local HudView = require(Client.UI.Views.HudView)
local ShopView = require(Client.UI.Views.ShopView)
local DropBarView = require(Client.UI.Views.DropBarView)
local ReturnView = require(Client.UI.Views.ReturnView)

local failures: { string } = {}

local function run(label: string, callback: () -> ())
	local ok, err = xpcall(callback, debug.traceback)
	if not ok then
		table.insert(failures, label)
		warn(string.format("[Client] %s FALHOU:\n%s", label, tostring(err)))
	end
end

-- A rede é obrigatória: sem os remotes nada mais funciona
NetController.Init()

run("StateController.Init", StateController.Init)
run("ClickController.Init", ClickController.Init)
run("EquipmentController.Init", EquipmentController.Init)
run("BassDropController.Init", BassDropController.Init)
run("AudioController.Init", AudioController.Init)
run("PyroVfxController.Init", PyroVfxController.Init)
run("PlotController.Init", PlotController.Init)

run("HudView.Mount", HudView.Mount)
run("ShopView.Mount", ShopView.Mount)
run("DropBarView.Mount", DropBarView.Mount)
run("ReturnView.Mount", ReturnView.Mount)

run("StateController.Start", StateController.Start) -- envia ClientReady
run("AudioController.Start", AudioController.Start)
run("PyroVfxController.Start", PyroVfxController.Start)

if #failures > 0 then
	warn(string.format("[Client] Arrancou com %d falha(s): %s", #failures, table.concat(failures, ", ")))
end
