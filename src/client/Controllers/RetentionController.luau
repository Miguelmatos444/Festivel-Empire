--!strict
--[[
	RetentionController
	Cópia local (só de leitura) do diário, missões, Gamepasses e Auto-Play,
	mais os pedidos ao servidor (reclamar, códigos, Auto-Play) e as compras Robux
	(o servidor entrega via ProcessReceipt / PromptGamePassPurchaseFinished).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local NetController = require(script.Parent.NetController)

type RetentionSync = Types.RetentionSync

local RetentionController = {}

local changed: Signal.Signal<RetentionSync> = Signal.new()

RetentionController.Changed = changed

local trove = Trove.new()
local state: RetentionSync? = nil
local bucket = TokenBucket.new(2, 4)
local priceCache: { [string]: string } = {}

function RetentionController.Get(): RetentionSync?
	return state
end

function RetentionController.Owns(key: string): boolean
	local current = state
	return current ~= nil and current.Gamepasses[key] == true
end

local function fire(def: Types.RemoteDef, ...: unknown): boolean
	if not bucket:TryConsume() then
		return false
	end
	NetController.Fire(def, ...)
	return true
end

function RetentionController.ClaimDaily(): boolean
	return fire(RemoteDefs.Defs.ClaimDaily)
end

function RetentionController.ClaimMission(slot: string): boolean
	return fire(RemoteDefs.Defs.ClaimMission, slot)
end

function RetentionController.RedeemCode(code: string): boolean
	local clean = string.upper((string.gsub(code, "[^%w]", "")))
	if clean == "" or #clean > 24 then
		return false
	end
	return fire(RemoteDefs.Defs.RedeemCode, clean)
end

function RetentionController.SetAutoClick(enabled: boolean): boolean
	return fire(RemoteDefs.Defs.SetAutoClick, enabled)
end

-- Compras Robux ----------------------------------------------------------------------

function RetentionController.PromptGamepass(id: number)
	if id > 0 then
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
	end
end

function RetentionController.PromptProduct(id: number)
	if id > 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
	end
end

-- Preço em Robux lido do Roblox (em cache). "Em breve" quando o id ainda é 0.
function RetentionController.GetPriceText(id: number, isGamepass: boolean): string
	if id <= 0 then
		return "Em breve"
	end
	local key = (if isGamepass then "G" else "P") .. id
	local cached = priceCache[key]
	if cached then
		return cached
	end
	local ok, info = pcall(function(): { [string]: any }
		-- `any`: GetProductInfo devolve um dicionário não tipado
		return MarketplaceService:GetProductInfo(id, if isGamepass then Enum.InfoType.GamePass else Enum.InfoType.Product)
	end)
	local price = if ok and info and type(info.PriceInRobux) == "number" then "R$ " .. info.PriceInRobux else "R$ ?"
	priceCache[key] = price
	return price
end

function RetentionController.Init()
	trove:Add(NetController.On(RemoteDefs.Defs.RetentionSync, function(payload: unknown)
		local sync = payload :: RetentionSync
		state = sync
		changed:Fire(sync)
	end))
end

return RetentionController
