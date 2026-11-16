--!strict
--[[
	NetController
	Espera pelos RemoteEvents criados pelo servidor em
	ReplicatedStorage.<RemoteDefs.FolderName> (por defeito "Remotes") e expõe
	Fire/On verificando a direção de cada remote.
	Com Config/Debug.NetTrace, regista cada envio/receção ([Diag:C][Net]).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)

type RemoteDef = Types.RemoteDef

local WAIT_WARNING_SECONDS = 10

local NetController = {}

local remotes: { [string]: RemoteEvent } = {}

local function getRemote(def: RemoteDef): RemoteEvent
	local remote = remotes[def.Name]
	assert(remote, "NetController não inicializado (" .. def.Name .. ")")
	return remote
end

-- Espera por um filho; avisa (uma vez) se demorar, em vez de ficar parado em silêncio
local function waitForChildWithWarning(parent: Instance, name: string): Instance
	local child = parent:WaitForChild(name, WAIT_WARNING_SECONDS)
	if child then
		return child
	end
	warn(
		string.format(
			"[NetController] Ainda à espera de %s.%s ao fim de %ds — o servidor arrancou (ServerNet.Init)?",
			parent:GetFullName(),
			name,
			WAIT_WARNING_SECONDS
		)
	)
	return parent:WaitForChild(name)
end

function NetController.Init()
	local folder = waitForChildWithWarning(ReplicatedStorage, RemoteDefs.FolderName)
	for _, def in RemoteDefs.All do
		local remote = waitForChildWithWarning(folder, def.Name)
		if not remote:IsA("RemoteEvent") then
			error("NetController: '" .. remote:GetFullName() .. "' não é um RemoteEvent")
		end
		remotes[def.Name] = remote :: RemoteEvent
	end
	Diag.Log("Net", string.format("%d RemoteEvents encontrados em %s", #RemoteDefs.All, folder:GetFullName()))
end

function NetController.Fire(def: RemoteDef, ...: unknown)
	assert(def.Direction == "ClientToServer", "NetController.Fire: '" .. def.Name .. "' não é ClientToServer")
	getRemote(def):FireServer(...)
	Diag.LogSampled("Net", "out:" .. def.Name, "→ " .. def.Name)
end

function NetController.On(def: RemoteDef, handler: (...unknown) -> ()): RBXScriptConnection
	assert(def.Direction == "ServerToClient", "NetController.On: '" .. def.Name .. "' não é ServerToClient")
	return getRemote(def).OnClientEvent:Connect(function(...: unknown)
		Diag.LogSampled("Net", "in:" .. def.Name, "← " .. def.Name)
		handler(...)
	end)
end

return NetController
