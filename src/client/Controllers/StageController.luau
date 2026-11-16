--!strict
--[[
	StageController
	Pedidos de compra de palco (o servidor valida tudo) e consultas locais
	sobre o próprio terreno (transição em curso).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local NetController = require(script.Parent.NetController)
local PlotController = require(script.Parent.PlotController)

local REQUEST_COOLDOWN = 0.6

local StageController = {}

local lastRequest = -math.huge

-- true enquanto o palco do próprio terreno está a ser trocado
function StageController.IsMyStageTransitioning(): boolean
	local plot = PlotController.GetMyPlot()
	return plot ~= nil and plot:GetAttribute("TransitionStart") ~= nil
end

-- Pede a compra do tier indicado (tem de ser o atual + 1). Devolve true se o pedido saiu.
function StageController.RequestPurchase(targetTier: number): boolean
	local now = os.clock()
	if now - lastRequest < REQUEST_COOLDOWN or StageController.IsMyStageTransitioning() then
		return false
	end
	lastRequest = now
	NetController.Fire(RemoteDefs.Defs.BuyStage, targetTier)
	return true
end

return StageController
