--!strict
--[[
	Bootstrap único do cliente.
	Ordem: rede -> controllers -> UI -> avisar o servidor (ClientReady) -> áudio/VFX.
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
local HudView = require(Client.UI.Views.HudView)
local ShopView = require(Client.UI.Views.ShopView)
local DropBarView = require(Client.UI.Views.DropBarView)

NetController.Init()
StateController.Init()
ClickController.Init()
EquipmentController.Init()
BassDropController.Init()
AudioController.Init()
PyroVfxController.Init()

HudView.Mount()
ShopView.Mount()
DropBarView.Mount()

StateController.Start()
AudioController.Start()
PyroVfxController.Start()
