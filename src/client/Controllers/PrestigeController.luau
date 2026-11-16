--!strict
--[[
	PrestigeController
	Pedidos de World Tour e de compra de nós da árvore. O servidor valida tudo
	(requisitos, Discos, transições); aqui só há limitadores contra spam.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local NetController = require(script.Parent.NetController)

local TOUR_COOLDOWN = 5

local PrestigeController = {}

local nodeBucket = TokenBucket.new(3, 6)
local lastTour = -math.huge

function PrestigeController.BuyNode(nodeId: string): boolean
	if not nodeBucket:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.BuySkillNode, nodeId)
	return true
end

function PrestigeController.DoWorldTour(): boolean
	local now = os.clock()
	if now - lastTour < TOUR_COOLDOWN then
		return false
	end
	lastTour = now
	NetController.Fire(RemoteDefs.Defs.DoWorldTour)
	return true
end

return PrestigeController
