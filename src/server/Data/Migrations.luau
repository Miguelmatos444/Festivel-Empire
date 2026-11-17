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
local MonetizationConfig = require(game:GetService("ReplicatedStorage").Shared.Config.Monetization)

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

	-- v2 -> v3 (Fase 10): Índice de Artistas e vitrine. Os artistas que o jogador já tem
	-- passam a contar como descobertos.
	[2] = function(data: RawData)
		local discovered: { [string]: boolean } = {}
		local artists = data.Artists
		if type(artists) == "table" then
			for _, value in (artists :: unknown) :: { [string]: unknown } do
				if type(value) == "table" then
					local artist = (value :: unknown) :: RawData
					local id, rarity = artist.Id, artist.Rarity
					if type(id) == "string" and type(rarity) == "string" then
						discovered[id .. "|" .. rarity] = true
					end
				end
			end
		end
		data.Index = { Discovered = discovered, Claimed = {} }
		if type(data.Showcase) ~= "table" then
			data.Showcase = { Mode = "Auto", Uid = "" }
		end
	end,

	-- v3 -> v4 (Fase 13A): variante Brilhante em cada artista ("" = normal) e
	-- descobertas de variantes no Índice. Nenhum artista existente fica com variante.
	[3] = function(data: RawData)
		local artists = data.Artists
		if type(artists) == "table" then
			for _, value in (artists :: unknown) :: { [string]: unknown } do
				if type(value) == "table" then
					local artist = (value :: unknown) :: RawData
					if type(artist.Variant) ~= "string" then
						artist.Variant = ""
					end
				end
			end
		end
		local index = data.Index
		if type(index) == "table" then
			local raw = (index :: unknown) :: RawData
			if type(raw.Variants) ~= "table" then
				raw.Variants = {}
			end
		end
	end,

	-- v4 -> v5 (Fase 13B): Cristais e campos do traço. Os artistas ficam SEM traço: só o
	-- ganham a rodar no Estúdio de Remix.
	[4] = function(data: RawData)
		if type(data.Crystals) ~= "number" then
			data.Crystals = 0
		end
		local artists = data.Artists
		if type(artists) == "table" then
			for _, value in (artists :: unknown) :: { [string]: unknown } do
				if type(value) == "table" then
					local artist = (value :: unknown) :: RawData
					if type(artist.Trait) ~= "string" or type(artist.TraitTier) ~= "string" then
						artist.Trait = ""
						artist.TraitTier = ""
					end
				end
			end
		end
	end,

	-- v5 -> v6 (Fase 13C): condições do Auto-Abrir com os valores por defeito
	[5] = function(data: RawData)
		local settings = data.Settings
		if type(settings) ~= "table" then
			return -- o Reconcile cria Settings completo a partir do template
		end
		local raw = (settings :: unknown) :: RawData
		if type(raw.AutoOpen) ~= "table" then
			raw.AutoOpen = {
				Count = 1,
				StopSlot = MonetizationConfig.AutoOpen.DefaultStopSlot,
				StopNew = true,
				StopShiny = true,
			}
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
