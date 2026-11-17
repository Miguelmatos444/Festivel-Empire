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
local StageAnimController = require(Client.Controllers.StageAnimController)
local ArtistController = require(Client.Controllers.ArtistController)
local ArtistDanceController = require(Client.Controllers.ArtistDanceController)
local CrateZoneController = require(Client.Controllers.CrateZoneController)
local CrateSfx = require(Client.Controllers.CrateSfx)
local CrateAnimController = require(Client.Controllers.CrateAnimController)
local CrateRevealView = require(Client.UI.Views.CrateRevealView)
local IndexController = require(Client.Controllers.IndexController)
local ShowcaseController = require(Client.Controllers.ShowcaseController)
local VariantVisuals = require(Client.Controllers.VariantVisuals)
local RemixFxController = require(Client.Controllers.RemixFxController)
local RemixView = require(Client.UI.Views.RemixView)
local IndexView = require(Client.UI.Views.IndexView)
local HudView = require(Client.UI.Views.HudView)
local ShopView = require(Client.UI.Views.ShopView)
local StagesView = require(Client.UI.Views.StagesView)
local ArtistsView = require(Client.UI.Views.ArtistsView)
local PrestigeView = require(Client.UI.Views.PrestigeView)
local RetentionController = require(Client.Controllers.RetentionController)
local MissionsView = require(Client.UI.Views.MissionsView)
local WelcomeBackView = require(Client.UI.Views.WelcomeBackView)
local VipButtonView = require(Client.UI.Views.VipButtonView)
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
run("StageAnimController.Init", StageAnimController.Init)
run("ArtistController.Init", ArtistController.Init)
run("ArtistDanceController.Init", ArtistDanceController.Init)
run("RetentionController.Init", RetentionController.Init)
run("CrateSfx.Init", CrateSfx.Init)
run("CrateAnimController.Init", CrateAnimController.Init)
run("IndexController.Init", IndexController.Init)
run("ShowcaseController.Init", ShowcaseController.Init)
run("VariantVisuals.Init", VariantVisuals.Init)
run("RemixFxController.Init", RemixFxController.Init)

run("HudView.Mount", HudView.Mount)
run("ShopView.Mount", ShopView.Mount)
run("StagesView.Mount", StagesView.Mount)
run("ArtistsView.Mount", ArtistsView.Mount)
run("CrateRevealView.Mount", CrateRevealView.Mount)
run("IndexView.Mount", IndexView.Mount)
run("RemixView.Mount", RemixView.Mount)
run("PrestigeView.Mount", PrestigeView.Mount)
run("MissionsView.Mount", MissionsView.Mount)
run("WelcomeBackView.Mount", WelcomeBackView.Mount)
run("VipButtonView.Mount", VipButtonView.Mount)
run("DropBarView.Mount", DropBarView.Mount)
run("ReturnView.Mount", ReturnView.Mount)

run("StateController.Start", StateController.Start) -- envia ClientReady
run("AudioController.Start", AudioController.Start)
run("PyroVfxController.Start", PyroVfxController.Start)
run("StageAnimController.Start", StageAnimController.Start)
run("ArtistDanceController.Start", ArtistDanceController.Start)
run("CrateZoneController.Init", CrateZoneController.Init) -- depois das Views (ArtistsView ouve Entered/Exited)

if #failures > 0 then
	warn(string.format("[Client] Arrancou com %d falha(s): %s", #failures, table.concat(failures, ", ")))
end
