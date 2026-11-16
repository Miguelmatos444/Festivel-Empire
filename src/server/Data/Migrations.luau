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

	-- v1 -> v2 (Fase 12): Settings.FastCrateAnim e Stats.CinematicsSeen.
	-- Garante os valores iniciais explicitamente (o Reconcile também os preencheria).
	[1] = function(data: RawData)
		local settings = data.Settings
		if type(settings) == "table" then
			local raw = (settings :: unknown) :: RawData
			if type(raw.FastCrateAnim) ~= "boolean" then
				raw.FastCrateAnim = false
			end
		end
		local stats = data.Stats
		if type(stats) == "table" then
			local raw = (stats :: unknown) :: RawData
			if type(raw.CinematicsSeen) ~= "number" then
				raw.CinematicsSeen = 0
			end
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
