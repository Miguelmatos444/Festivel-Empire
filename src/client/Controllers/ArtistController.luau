--!strict
--[[
	ArtistController
	Cópia local (só de leitura) da coleção de artistas, resultados das crates e
	pedidos ao servidor (abrir crate, equipar, cadeado, fundir, Auto-Fuse/Delete).
	O servidor valida tudo; aqui só há limitadores locais contra spam.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local NetController = require(script.Parent.NetController)

type ArtistsSync = Types.ArtistsSync
type CrateResult = Types.CrateResult

local ArtistController = {}

local changed: Signal.Signal<ArtistsSync> = Signal.new()
local crateOpened: Signal.Signal<CrateResult> = Signal.new()

ArtistController.Changed = changed
ArtistController.CrateOpened = crateOpened

local trove = Trove.new()
local state: ArtistsSync? = nil
local actionBucket = TokenBucket.new(5, 8)
local crateBucket = TokenBucket.new(1.5, 3)

function ArtistController.Get(): ArtistsSync?
	return state
end

function ArtistController.OpenCrate(crateId: string, count: number): boolean
	if not crateBucket:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.OpenCrate, crateId, count)
	return true
end

local function fireAction(def: Types.RemoteDef, ...: unknown): boolean
	if not actionBucket:TryConsume() then
		return false
	end
	NetController.Fire(def, ...)
	return true
end

function ArtistController.Equip(uid: string): boolean
	return fireAction(RemoteDefs.Defs.EquipArtist, uid)
end

-- Pede ao servidor para equipar a combinação com maior multiplicador de Hype
function ArtistController.EquipBest(): boolean
	return fireAction(RemoteDefs.Defs.EquipBestArtists)
end

function ArtistController.Unequip(uid: string): boolean
	return fireAction(RemoteDefs.Defs.UnequipArtist, uid)
end

function ArtistController.SetLock(uid: string, locked: boolean): boolean
	return fireAction(RemoteDefs.Defs.SetArtistLock, uid, locked)
end

-- target = uid do artista (funde o seu grupo) ou "all"
function ArtistController.Fuse(target: string): boolean
	return fireAction(RemoteDefs.Defs.FuseArtists, target)
end

function ArtistController.SetAutoFuse(enabled: boolean): boolean
	return fireAction(RemoteDefs.Defs.SetAutoFuse, enabled)
end

function ArtistController.SetAutoDelete(upToIndex: number): boolean
	return fireAction(RemoteDefs.Defs.SetAutoDelete, upToIndex)
end

function ArtistController.Init()
	trove:Add(NetController.On(RemoteDefs.Defs.ArtistsSync, function(payload: unknown)
		local sync = payload :: ArtistsSync
		state = sync
		changed:Fire(sync)
	end))
	trove:Add(NetController.On(RemoteDefs.Defs.CrateResult, function(payload: unknown)
		crateOpened:Fire(payload :: CrateResult)
	end))
end

return ArtistController
