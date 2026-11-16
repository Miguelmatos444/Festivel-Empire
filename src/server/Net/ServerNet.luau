--!strict
--[[
	ServerNet
	Cria todos os RemoteEvents a partir de RemoteDefs e aplica, por esta ordem,
	RateLimiter -> Validate -> handler a cada pedido do cliente.
	É a única porta de entrada de rede no servidor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local RateLimiter = require(script.Parent.RateLimiter)
local Validate = require(script.Parent.Validate)

type RemoteDef = Types.RemoteDef

export type Handler = (player: Player, ...unknown) -> ()

local REJECTION_LOG_EVERY = 25

local ServerNet = {}

local trove = Trove.new()
local remotes: { [string]: RemoteEvent } = {}
local handlers: { [string]: Handler } = {}
local rejections: { [Player]: number } = {}
local initialized = false

local function reject(def: RemoteDef, player: Player, reason: string)
	local count = (rejections[player] or 0) + 1
	rejections[player] = count
	if count % REJECTION_LOG_EVERY == 1 then
		warn(string.format("[ServerNet] '%s' rejeitado para %s (#%d): %s", def.Name, player.Name, count, reason))
	end
end

local function onServerEvent(def: RemoteDef, player: Player, ...: unknown)
	local limit = def.RateLimit
	if limit and not RateLimiter.Consume(player, def.Name, limit.PerSecond, limit.Burst) then
		return -- excesso de pedidos: descartado em silêncio
	end

	local count = select("#", ...)
	local args: { unknown } = { ... }
	if not Validate.Args(def.Args, count, args) then
		reject(def, player, "argumentos inválidos")
		return
	end

	local handler = handlers[def.Name]
	if handler then
		handler(player, table.unpack(args, 1, count))
	end
end

function ServerNet.Init()
	assert(not initialized, "ServerNet.Init chamado duas vezes")
	initialized = true

	local folder = trove:Add(Instance.new("Folder"))
	folder.Name = RemoteDefs.FolderName

	for _, def in RemoteDefs.All do
		local remote = Instance.new("RemoteEvent")
		remote.Name = def.Name
		remote.Parent = folder
		remotes[def.Name] = remote

		if def.Direction == "ClientToServer" then
			assert(def.RateLimit, "RemoteDefs: '" .. def.Name .. "' precisa de RateLimit")
			trove:Connect(remote.OnServerEvent, function(player: Player, ...: unknown)
				onServerEvent(def, player, ...)
			end)
		end
	end

	-- Só fica visível ao cliente depois de todos os remotes existirem
	folder.Parent = ReplicatedStorage

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		RateLimiter.Clear(player)
		rejections[player] = nil
	end)
end

function ServerNet.Connect(def: RemoteDef, handler: Handler)
	assert(def.Direction == "ClientToServer", "ServerNet.Connect: '" .. def.Name .. "' não é ClientToServer")
	assert(handlers[def.Name] == nil, "ServerNet.Connect: '" .. def.Name .. "' já tem handler")
	handlers[def.Name] = handler
end

function ServerNet.FireClient(def: RemoteDef, player: Player, ...: unknown)
	assert(def.Direction == "ServerToClient", "ServerNet.FireClient: '" .. def.Name .. "' não é ServerToClient")
	local remote = remotes[def.Name]
	assert(remote, "ServerNet não inicializado")
	remote:FireClient(player, ...)
end

function ServerNet.FireAllClients(def: RemoteDef, ...: unknown)
	assert(def.Direction == "ServerToClient", "ServerNet.FireAllClients: '" .. def.Name .. "' não é ServerToClient")
	local remote = remotes[def.Name]
	assert(remote, "ServerNet não inicializado")
	remote:FireAllClients(...)
end

return ServerNet
