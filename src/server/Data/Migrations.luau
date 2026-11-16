--!strict
--[[
	Migrations
	Cadeia de migrações aplicada no load: steps[n] converte dados vN -> v(N+1).
	Para uma nova versão:
	  1) incrementar ProfileTemplate.Version
	  2) adicionar steps[versãoAnterior] aqui
	Campos novos simples não precisam de passo: o Reconcile preenche-os.
]]

local ProfileTemplate = require(script.Parent.ProfileTemplate)

type RawData = { [string]: unknown }
type Migration = (data: RawData) -> ()

local Migrations = {}

local steps: { [number]: Migration } = {
	-- v0 -> v1: dados sem DataVersion (anteriores ao sistema de versões). Nada a converter.
	[0] = function(_data: RawData) end,
	-- v1 -> v2: dados sociais (Likes). Ninguém perde progresso: só acrescenta o campo.
	[1] = function(data: RawData)
		if type(data.Social) ~= "table" then
			data.Social = {
				LikesReceived = 0,
				LikesGivenDay = -1,
				LikedToday = {},
			}
		end
	end,
	-- v2 -> v3: estatísticas do minijogo de setas (Fase 9). Só acrescenta campos a 0.
	[2] = function(data: RawData)
		local stats = data.Stats
		if type(stats) ~= "table" then
			return -- o Reconcile cria Stats completo
		end
		local raw = stats :: RawData
		for _, key in { "ArrowHits", "ArrowPerfects", "BestCombo" } do
			if type(raw[key]) ~= "number" then
				raw[key] = 0
			end
		end
	end,
	-- v3 -> v4: Poção da Sorte (loja VIP). Começa inativa.
	[3] = function(data: RawData)
		if type(data.LuckUntil) ~= "number" then
			data.LuckUntil = 0
		end
	end,
}

-- Devolve (true) em sucesso, ou (false, motivo) se os dados não puderem ser usados.
function Migrations.Run(data: RawData): (boolean, string?)
	local stored = data.DataVersion
	local version = if type(stored) == "number" then stored else 0
	local target = ProfileTemplate.Version

	if version > target then
		-- Dados gravados por um servidor mais recente: nunca sobrescrever.
		return false, string.format("versão dos dados (%d) superior à do servidor (%d)", version, target)
	end

	while version < target do
		local step = steps[version]
		if not step then
			return false, string.format("migração em falta para v%d", version)
		end
		step(data)
		version += 1
		data.DataVersion = version
	end

	return true, nil
end

return table.freeze(Migrations)
