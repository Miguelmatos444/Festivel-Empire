--!strict
--[[
	Diag
	Prints de diagnóstico da cadeia cliente <-> servidor, ligados por
	Config/Debug.NetTrace. Prefixo [Diag:S] no servidor e [Diag:C] no cliente.
]]

local RunService = game:GetService("RunService")

local DebugConfig = require(script.Parent.Parent.Config.Debug)

local SIDE = if RunService:IsServer() then "S" else "C"

local Diag = {}

local counters: { [string]: number } = {}

function Diag.Enabled(): boolean
	return DebugConfig.NetTrace
end

function Diag.Log(tag: string, message: string)
	if DebugConfig.NetTrace then
		print(string.format("[Diag:%s][%s] %s", SIDE, tag, message))
	end
end

-- Para eventos repetidos (cliques, deltas): as 3 primeiras ocorrências e depois 1 em cada SampleEvery
function Diag.LogSampled(tag: string, key: string, message: string)
	if not DebugConfig.NetTrace then
		return
	end
	local count = (counters[key] or 0) + 1
	counters[key] = count
	if count <= 3 or count % DebugConfig.SampleEvery == 0 then
		Diag.Log(tag, string.format("%s (#%d)", message, count))
	end
end

return table.freeze(Diag)
