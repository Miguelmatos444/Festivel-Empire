--!strict
--[[
	NetController
	Espera pelos RemoteEvents criados pelo servidor (a partir de RemoteDefs)
	e expõe Fire/On verificando a direção de cada remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)

type RemoteDef = Types.RemoteDef

local NetController = {}

local remotes: { [string]: RemoteEvent } = {}

local function getRemote(def: RemoteDef): RemoteEvent
	local remote = remotes[def.Name]
	assert(remote, "NetController não inicializado (" .. def.Name .. ")")
	return remote
end

function NetController.Init()
	local folder = ReplicatedStorage:WaitForChild(RemoteDefs.FolderName)
	for _, def in RemoteDefs.All do
		local remote = folder:WaitForChild(def.Name)
		if not remote:IsA("RemoteEvent") then
			error("NetController: '" .. def.Name .. "' não é um RemoteEvent")
		end
		remotes[def.Name] = remote :: RemoteEvent
	end
end

function NetController.Fire(def: RemoteDef, ...: unknown)
	assert(def.Direction == "ClientToServer", "NetController.Fire: '" .. def.Name .. "' não é ClientToServer")
	getRemote(def):FireServer(...)
end

function NetController.On(def: RemoteDef, handler: (...unknown) -> ()): RBXScriptConnection
	assert(def.Direction == "ServerToClient", "NetController.On: '" .. def.Name .. "' não é ServerToClient")
	return getRemote(def).OnClientEvent:Connect(handler)
end

return NetController
