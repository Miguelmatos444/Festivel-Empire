--!strict
--[[
	IndexController
	Cópia local (só de leitura) do Índice de Artistas e da vitrine (IndexSync) e pedidos
	ao servidor: reclamar prémios e mudar a vitrine. O servidor valida tudo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local NetController = require(script.Parent.NetController)

type IndexSync = Types.IndexSync

local IndexController = {}

local changed: Signal.Signal<IndexSync> = Signal.new()

IndexController.Changed = changed

local trove = Trove.new()
local state: IndexSync? = nil
local bucket = TokenBucket.new(2, 4)

function IndexController.Get(): IndexSync?
	return state
end

-- key: RarityId ou Config/ArtistIndex.FinalKey
function IndexController.Claim(key: string): boolean
	if not bucket:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.ClaimIndexReward, key)
	return true
end

-- mode "Auto" (uid ignorado) ou "Manual" com o uid do artista
function IndexController.SetShowcase(mode: Types.ShowcaseMode, uid: string?): boolean
	if not bucket:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.SetShowcase, mode, if mode == "Manual" then uid or "" else "")
	return true
end

function IndexController.Init()
	trove:Add(NetController.On(RemoteDefs.Defs.IndexSync, function(payload: unknown)
		local sync = payload :: IndexSync
		state = sync
		changed:Fire(sync)
	end))
end

return IndexController
