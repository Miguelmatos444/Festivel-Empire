--!strict
--[[
	EquipmentController
	Guarda o modo de compra escolhido (x1/x10/x100/Max), envia pedidos de
	compra ao servidor e expõe o resultado de cada compra à UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local NetController = require(script.Parent.NetController)

type BuyMode = Types.BuyMode
type PurchaseResult = Types.PurchaseResult

local SAFETY_FACTOR = 0.9

local EquipmentController = {}

local modeChanged: Signal.Signal<BuyMode> = Signal.new()
local purchaseCompleted: Signal.Signal<PurchaseResult> = Signal.new()

EquipmentController.ModeChanged = modeChanged
EquipmentController.PurchaseCompleted = purchaseCompleted

local trove = Trove.new()
local buyDef = RemoteDefs.Defs.BuyEquipment
local bucket: TokenBucket.TokenBucket? = nil
local mode: BuyMode = "x1"

function EquipmentController.GetMode(): BuyMode
	return mode
end

function EquipmentController.SetMode(newMode: BuyMode)
	if newMode == mode then
		return
	end
	mode = newMode
	modeChanged:Fire(newMode)
end

-- Devolve true se o pedido foi enviado
function EquipmentController.RequestPurchase(equipmentId: string): boolean
	local current = bucket
	if not current or not current:TryConsume() then
		return false
	end
	NetController.Fire(buyDef, equipmentId, mode)
	return true
end

function EquipmentController.Init()
	local limit = buyDef.RateLimit
	assert(limit, "RemoteDefs.BuyEquipment precisa de RateLimit")
	bucket = TokenBucket.new(limit.PerSecond * SAFETY_FACTOR, math.max(1, math.floor(limit.Burst * SAFETY_FACTOR)))

	trove:Add(NetController.On(RemoteDefs.Defs.PurchaseResult, function(payload: unknown)
		purchaseCompleted:Fire(payload :: PurchaseResult)
	end))
end

return EquipmentController
