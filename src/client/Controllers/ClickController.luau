--!strict
--[[
	ClickController
	Envia batidas ao servidor com um limitador local ligeiramente mais
	restritivo do que o do servidor (Config/Economy.Click), para que o feedback
	visual nunca mostre batidas que o servidor iria descartar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local NetController = require(script.Parent.NetController)

local SAFETY_FACTOR = 0.9

local ClickController = {}

local clickDef = RemoteDefs.Defs.Click
local bucket: TokenBucket.TokenBucket? = nil

function ClickController.Init()
	local limit = clickDef.RateLimit
	assert(limit, "RemoteDefs.Click precisa de RateLimit")
	bucket = TokenBucket.new(limit.PerSecond * SAFETY_FACTOR, math.max(1, math.floor(limit.Burst * SAFETY_FACTOR)))
end

-- Devolve true se a batida foi enviada (para a UI mostrar feedback)
function ClickController.RequestClick(): boolean
	local current = bucket
	if not current or not current:TryConsume() then
		return false
	end
	NetController.Fire(clickDef)
	return true
end

return ClickController
