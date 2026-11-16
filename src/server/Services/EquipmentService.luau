--!strict
--[[
	EquipmentService
	Compra autoritativa de equipamento:
	  rate limit + validação (ServerNet) -> perfil carregado -> desbloqueio/tier
	  -> cotação por soma geométrica (EquipmentCalc) -> cobrança -> subida de nível
	  -> invalidação da cache de taxas -> PurchaseResult para o cliente.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local EquipmentCalc = require(ReplicatedStorage.Shared.Calc.EquipmentCalc)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

type BuyMode = Types.BuyMode
type PurchaseResult = Types.PurchaseResult
type PurchaseFailReason = Types.PurchaseFailReason

local EquipmentService = {}

local purchased: Signal.Signal<Player, number> = Signal.new()

-- (jogador, níveis comprados) — missões
EquipmentService.Purchased = purchased

local function fail(id: string, reason: PurchaseFailReason, level: number): PurchaseResult
	return {
		EquipmentId = id,
		Success = false,
		Reason = reason,
		Levels = 0,
		NewLevel = level,
	}
end

function EquipmentService.Purchase(player: Player, id: string, mode: BuyMode): PurchaseResult
	local data = DataService.GetProfile(player)
	if not data then
		return fail(id, "NotLoaded", 0)
	end

	local def = EquipmentCalc.GetDef(id)
	if not def then
		return fail(id, "Unknown", 0)
	end

	local level = EquipmentCalc.GetLevel(data.Equipment, id)

	local unlock = EquipmentCalc.GetUnlockState(def, data.Equipment, data.StageTier)
	if unlock == "Locked" then
		return fail(id, "Locked", level)
	elseif unlock == "TierTooLow" then
		return fail(id, "TierTooLow", level)
	end

	local count, cost, affordable = EquipmentCalc.Quote(def, level, mode, data.Hype)
	if not affordable or count <= 0 or not EconomyService.TrySpendHype(player, cost) then
		return fail(id, "NotEnoughHype", level)
	end

	local newLevel = level + count
	data.Equipment[id] = newLevel
	EconomyService.InvalidateRates(player)
	purchased:Fire(player, count)

	return {
		EquipmentId = id,
		Success = true,
		Reason = nil,
		Levels = count,
		NewLevel = newLevel,
	}
end

-- Debug: define o nível diretamente, sem custo
function EquipmentService.SetLevel(player: Player, id: string, level: number): boolean
	local data = DataService.GetProfile(player)
	if not data or not EquipmentCalc.GetDef(id) or level < 0 or level % 1 ~= 0 then
		return false
	end
	data.Equipment[id] = level
	EconomyService.InvalidateRates(player)
	return true
end

function EquipmentService.Init()
	ServerNet.Connect(RemoteDefs.Defs.BuyEquipment, function(player: Player, idArg: unknown, modeArg: unknown)
		-- Tipos e valores já validados por Validate (enums de RemoteDefs)
		local result = EquipmentService.Purchase(player, idArg :: string, modeArg :: BuyMode)
		ServerNet.FireClient(RemoteDefs.Defs.PurchaseResult, player, result)
	end)
end

function EquipmentService.Start() end

return EquipmentService
