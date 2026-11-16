--!strict
--[[
	ServerNet
	Cria todos os RemoteEvents a partir de RemoteDefs e aplica, por esta ordem,
	RateLimiter -> Validate -> handler a cada pedido do cliente.
	É a única porta de entrada de rede no servidor.

	Arranque em dois passos (evita a race condition do ClientReady):
	  1) Init(): cria os remotes, mas a pasta ainda NÃO está em ReplicatedStorage
	  2) Open(): chamado pelo Main depois de todos os serviços registarem os
	     handlers; só então o cliente vê os remotes e pode enviar pedidos.
	Defesa extra: um pedido válido que chegue a um remote ainda sem handler fica
	em fila e é entregue quando o handler for registado (nunca é perdido).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local RateLimiter = require(script.Parent.RateLimiter)
local Validate = require(script.Parent.Validate)

type RemoteDef = Types.RemoteDef

export type Handler = (player: Player, ...unknown) -> ()

type PendingCall = {
	Player: Player,
	Args: { unknown },
	Count: number,
}

local REJECTION_LOG_EVERY = 25
local MAX_PENDING_PER_REMOTE = 64

local ServerNet = {}

local trove = Trove.new()
local folder: Folder? = nil
local remotes: { [string]: RemoteEvent } = {}
local handlers: { [string]: Handler } = {}
local pending: { [string]: { PendingCall } } = {}
local rejections: { [Player]: number } = {}
local initialized = false
local opened = false

local function reject(def: RemoteDef, player: Player, reason: string)
	local count = (rejections[player] or 0) + 1
	rejections[player] = count
	if count % REJECTION_LOG_EVERY == 1 then
		warn(string.format("[ServerNet] '%s' rejeitado para %s (#%d): %s", def.Name, player.Name, count, reason))
	end
end

local function queuePending(def: RemoteDef, call: PendingCall)
	local queue = pending[def.Name]
	if not queue then
		queue = {}
		pending[def.Name] = queue
	end
	if #queue >= MAX_PENDING_PER_REMOTE then
		warn(string.format("[ServerNet] fila de '%s' cheia; pedido de %s descartado", def.Name, call.Player.Name))
		return
	end
	table.insert(queue, call)
	Diag.Log("Net", string.format("'%s' de %s em fila: o serviço ainda não registou o handler", def.Name, call.Player.Name))
end

local function onServerEvent(def: RemoteDef, player: Player, ...: unknown)
	local limit = def.RateLimit
	if limit and not RateLimiter.Consume(player, def.Name, limit.PerSecond, limit.Burst) then
		Diag.LogSampled("Net", "rl:" .. def.Name, string.format("'%s' de %s descartado (rate limit)", def.Name, player.Name))
		return
	end

	local count = select("#", ...)
	local args: { unknown } = { ... }
	if not Validate.Args(def.Args, count, args) then
		reject(def, player, "argumentos inválidos")
		return
	end

	local handler = handlers[def.Name]
	if not handler then
		queuePending(def, { Player = player, Args = args, Count = count })
		return
	end
	Diag.LogSampled("Net", "in:" .. def.Name, string.format("← '%s' de %s", def.Name, player.Name))
	handler(player, table.unpack(args, 1, count))
end

-- Passo 1: cria os remotes e liga a validação (a pasta ainda não é visível ao cliente)
function ServerNet.Init()
	assert(not initialized, "ServerNet.Init chamado duas vezes")
	initialized = true

	local newFolder = trove:Add(Instance.new("Folder"))
	newFolder.Name = RemoteDefs.FolderName

	for _, def in RemoteDefs.All do
		local remote = Instance.new("RemoteEvent")
		remote.Name = def.Name
		remote.Parent = newFolder
		remotes[def.Name] = remote

		if def.Direction == "ClientToServer" then
			assert(def.RateLimit, "RemoteDefs: '" .. def.Name .. "' precisa de RateLimit")
			trove:Connect(remote.OnServerEvent, function(player: Player, ...: unknown)
				onServerEvent(def, player, ...)
			end)
		end
	end
	folder = newFolder

	trove:Connect(Players.PlayerRemoving, function(player: Player)
		RateLimiter.Clear(player)
		rejections[player] = nil
		for _, queue in pending do
			for index = #queue, 1, -1 do
				if queue[index].Player == player then
					table.remove(queue, index)
				end
			end
		end
	end)
end

-- Passo 2: expõe os remotes ao cliente. Chamar depois de TODOS os serviços fazerem Init.
function ServerNet.Open()
	assert(initialized, "ServerNet.Open antes de ServerNet.Init")
	if opened then
		return
	end
	opened = true

	for _, def in RemoteDefs.All do
		if def.Direction == "ClientToServer" and handlers[def.Name] == nil then
			warn(string.format("[ServerNet] '%s' aberto sem handler registado — pedidos ficam em fila", def.Name))
		end
	end

	local current = folder
	if current then
		current.Parent = ReplicatedStorage -- só agora o cliente vê os remotes
	end
	Diag.Log("Net", string.format("%d RemoteEvents abertos em ReplicatedStorage.%s", #RemoteDefs.All, RemoteDefs.FolderName))
end

function ServerNet.Connect(def: RemoteDef, handler: Handler)
	assert(def.Direction == "ClientToServer", "ServerNet.Connect: '" .. def.Name .. "' não é ClientToServer")
	assert(handlers[def.Name] == nil, "ServerNet.Connect: '" .. def.Name .. "' já tem handler")
	handlers[def.Name] = handler

	-- Entrega pedidos que chegaram antes de o handler existir
	local queue = pending[def.Name]
	if queue then
		pending[def.Name] = nil
		for _, call in queue do
			if call.Player.Parent == Players then
				Diag.Log("Net", string.format("'%s' de %s entregue a partir da fila", def.Name, call.Player.Name))
				task.spawn(handler, call.Player, table.unpack(call.Args, 1, call.Count))
			end
		end
	end
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
