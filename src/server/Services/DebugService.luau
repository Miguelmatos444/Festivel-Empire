--!strict
--[[
	DebugService
	Comandos de admin por chat:  /fe <comando> [args]   (alias: /admin)
	Acesso: Config/Admin (UserIds, dono do jogo, todos em Studio).
	Comandos de não-admins são ignorados em silêncio.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Types = require(ReplicatedStorage.Shared.Types)
local AdminConfig = require(ReplicatedStorage.Shared.Config.Admin)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.Economy)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local EquipmentConfig = require(ReplicatedStorage.Shared.Config.Equipment)
local EquipmentCalc = require(ReplicatedStorage.Shared.Calc.EquipmentCalc)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EquipmentService = require(script.Parent.EquipmentService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PyroService = require(script.Parent.PyroService)
local BassDropService = require(script.Parent.BassDropService)
local PlotService = require(script.Parent.PlotService)
local StageService = require(script.Parent.StageService)
local ArtistService = require(script.Parent.ArtistService)
local PrestigeService = require(script.Parent.PrestigeService)
local ArtistsConfig = require(ReplicatedStorage.Shared.Config.Artists)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)

type Command = {
	Usage: string,
	Description: string,
	Run: (player: Player, args: { string }) -> string,
}

local DebugService = {}

local trove = Trove.new()
local adminCache: { [Player]: boolean } = {}
local commands: { [string]: Command } = {}
local COMMAND_ORDER = {
	"help",
	"hype",
	"pps",
	"offline",
	"cost",
	"equip",
	"energy",
	"drop",
	"pyro",
	"cd",
	"stage",
	"wt",
	"artist",
	"pity",
	"tour",
	"discs",
	"skills",
	"plots",
	"home",
	"state",
	"save",
	"wipe",
}

-- Permissões -----------------------------------------------------------------

local function computeIsAdmin(player: Player): boolean
	if AdminConfig.AllowStudio and RunService:IsStudio() then
		return true
	end
	if table.find(AdminConfig.UserIds, player.UserId) then
		return true
	end
	if AdminConfig.AllowGameOwner then
		if game.CreatorType == Enum.CreatorType.User then
			return game.CreatorId == player.UserId
		elseif game.CreatorType == Enum.CreatorType.Group then
			local ok, rank = pcall(function(): number
				return player:GetRankInGroup(game.CreatorId)
			end)
			return ok and rank == 255
		end
	end
	return false
end

function DebugService.IsAdmin(player: Player): boolean
	return adminCache[player] == true
end

-- Feedback -------------------------------------------------------------------

local function reply(player: Player, text: string)
	print(string.format("[Debug] %s: %s", player.Name, text))
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

local function currentHypeText(player: Player): string
	local data = DataService.GetProfile(player)
	return if data then NumberFormatter.format(data.Hype) else "?"
end

-- Comandos -------------------------------------------------------------------

commands.help = {
	Usage = "help",
	Description = "Lista os comandos",
	Run = function(_player: Player, _args: { string }): string
		local lines = { "Comandos (/fe <comando>):" }
		for _, name in COMMAND_ORDER do
			local command = commands[name]
			table.insert(lines, string.format("%s — %s", command.Usage, command.Description))
		end
		return table.concat(lines, "\n")
	end,
}

commands.hype = {
	Usage = "hype add|set <valor>",
	Description = "Adiciona/define Hype (1500, 2.5M, 1e40)",
	Run = function(player: Player, args: { string }): string
		local mode = args[1]
		local valueText = args[2]
		local value = if valueText then NumberFormatter.parse(valueText) else nil
		if (mode ~= "add" and mode ~= "set") or not value then
			return "Uso: /fe hype add|set <valor>"
		end
		if mode == "add" then
			EconomyService.AddHype(player, value)
		else
			EconomyService.SetHype(player, value)
		end
		return "Hype: " .. currentHypeText(player)
	end,
}

commands.pps = {
	Usage = "pps <valor>|off",
	Description = "Força Hype passivo/s nesta sessão",
	Run = function(player: Player, args: { string }): string
		local valueText = args[1]
		if valueText == "off" then
			EconomyService.SetDebugPassive(player, nil)
			return "Passivo de debug desligado."
		end
		local value = if valueText then NumberFormatter.parse(valueText) else nil
		if not value or value.m < 0 then
			return "Uso: /fe pps <valor>|off"
		end
		EconomyService.SetDebugPassive(player, value)
		return "Passivo de debug: " .. NumberFormatter.format(value) .. "/s"
	end,
}

commands.offline = {
	Usage = "offline <segundos>",
	Description = "Simula rendimento offline",
	Run = function(player: Player, args: { string }): string
		local seconds = tonumber(args[1] or "")
		if not seconds or seconds <= 0 then
			return "Uso: /fe offline <segundos>"
		end
		local earned = EconomyService.GrantOfflineEarnings(player, seconds)
		if earned.m <= 0 then
			return "Sem rendimento offline (passivo = 0). Usa primeiro /fe pps <valor>."
		end
		return string.format(
			"Offline %s (teto %s, eficiência %d%%): +%s",
			NumberFormatter.formatTime(seconds),
			NumberFormatter.formatTime(EconomyConfig.Offline.MaxSeconds),
			math.round(EconomyConfig.Offline.Efficiency * 100),
			NumberFormatter.format(earned)
		)
	end,
}

commands.cost = {
	Usage = "cost <base> <taxa> <nível> <qtd|max>",
	Description = "Testa custos em massa (soma geométrica)",
	Run = function(player: Player, args: { string }): string
		local usage = "Uso: /fe cost <base> <taxa> <nível> <qtd|max>"
		local baseCost = tonumber(args[1] or "")
		local rate = tonumber(args[2] or "")
		local level = tonumber(args[3] or "")
		if not baseCost or not rate or not level or baseCost <= 0 or level < 0 or level % 1 ~= 0 then
			return usage
		end
		local bounds = EconomyConfig.GrowthRate
		if rate < bounds.Min or rate > bounds.Max then
			return string.format("Taxa tem de estar entre %.2f e %.2f", bounds.Min, bounds.Max)
		end

		if args[4] == "max" then
			local count = EconomyService.GetMaxAffordable(player, baseCost, rate, level)
			local cost = EconomyService.GetBulkCost(baseCost, rate, level, count)
			return string.format(
				"Com %s Hype: máx. %s níveis (custo %s)",
				currentHypeText(player),
				NumberFormatter.format(count),
				NumberFormatter.format(cost)
			)
		end

		local count = tonumber(args[4] or "1")
		if not count or count < 1 or count % 1 ~= 0 then
			return usage
		end
		local cost = EconomyService.GetBulkCost(baseCost, rate, level, count)
		return string.format(
			"%s níveis a partir do nível %d: %s",
			NumberFormatter.format(count),
			level,
			NumberFormatter.format(cost)
		)
	end,
}

commands.equip = {
	Usage = "equip list | equip <id> <nível>",
	Description = "Lista ou define níveis de equipamento",
	Run = function(player: Player, args: { string }): string
		local data = DataService.GetProfile(player)
		if not data then
			return "Perfil não carregado."
		end

		local first = args[1]
		if first == nil or string.lower(first) == "list" then
			local lines = { "Equipamento:" }
			for _, def in EquipmentConfig.List do
				local level = EquipmentCalc.GetLevel(data.Equipment, def.Id)
				local unit = if def.Kind == "Click" then "/batida" else "/s"
				table.insert(
					lines,
					string.format(
						"%s — Nv. %d (+%s%s)",
						def.Id,
						level,
						NumberFormatter.format(EquipmentCalc.GetOutput(def, level)),
						unit
					)
				)
			end
			return table.concat(lines, "\n")
		end

		local id: string? = nil
		for _, candidate in EquipmentConfig.Ids do
			if string.lower(candidate) == string.lower(first) then
				id = candidate
				break
			end
		end
		local level = tonumber(args[2] or "")
		if not id or not level then
			return "Uso: /fe equip <id> <nível>  (ids em /fe equip list)"
		end
		if not EquipmentService.SetLevel(player, id, level) then
			return "Nível inválido (inteiro >= 0)."
		end
		return string.format(
			"%s -> Nv. %d | Hype/s %s | Hype/batida %s",
			id,
			level,
			NumberFormatter.format(EconomyService.GetHypePerSecond(player)),
			NumberFormatter.format(EconomyService.GetHypePerClick(player))
		)
	end,
}

commands.energy = {
	Usage = "energy <0-100>",
	Description = "Define a energia do Bass Drop",
	Run = function(player: Player, args: { string }): string
		local value = tonumber(args[1] or "")
		if not value then
			return "Uso: /fe energy <0-100>"
		end
		if not BassDropService.SetEnergy(player, value) then
			return "Só é possível na fase de carga (fase atual: " .. tostring(BassDropService.GetPhase(player)) .. ")."
		end
		return "Energia definida para " .. math.clamp(value, 0, 100) .. "."
	end,
}

commands.drop = {
	Usage = "drop",
	Description = "Inicia já o build-up do Bass Drop",
	Run = function(player: Player, _args: { string }): string
		if not BassDropService.ForceDrop(player) then
			return "Só é possível na fase de carga (fase atual: " .. tostring(BassDropService.GetPhase(player)) .. ")."
		end
		return "Build-up iniciado: carrega DROP! no momento certo."
	end,
}

commands.pyro = {
	Usage = "pyro all",
	Description = "Desbloqueia todas as máquinas",
	Run = function(player: Player, args: { string }): string
		if args[1] ~= "all" then
			return "Uso: /fe pyro all"
		end
		return if PyroService.UnlockAll(player) then "Todas as máquinas desbloqueadas." else "Perfil não carregado."
	end,
}

commands.cd = {
	Usage = "cd reset",
	Description = "Limpa os cooldowns das máquinas",
	Run = function(player: Player, args: { string }): string
		if args[1] ~= "reset" then
			return "Uso: /fe cd reset"
		end
		PyroService.ResetCooldowns(player)
		return "Cooldowns limpos."
	end,
}

commands.stage = {
	Usage = "stage <1-12> [anim]",
	Description = "Troca o palco (sem custo); 'anim' mostra a animação",
	Run = function(player: Player, args: { string }): string
		local tier = tonumber(args[1] or "")
		if not tier or not StageService.SetTier(player, tier, args[2] == "anim") then
			return "Uso: /fe stage <1-12> [anim]  (requer terreno e perfil carregados)"
		end
		local def = MapCalc.GetStageDef(tier)
		return string.format(
			"Tier %d · %s (%s) — envelope %d x %d x %d",
			def.Tier,
			def.Name,
			def.Era,
			def.Width,
			def.Depth,
			def.Height
		)
	end,
}

commands.wt = {
	Usage = "wt <0-99>",
	Description = "Define o nº de World Tours (testar requisitos)",
	Run = function(player: Player, args: { string }): string
		local data = DataService.GetProfile(player)
		local value = tonumber(args[1] or "")
		if not data or not value or value < 0 or value % 1 ~= 0 then
			return "Uso: /fe wt <0-99>"
		end
		data.WorldTours = value
		PlayerStateService.MarkDirty(player)
		return "World Tours: " .. value
	end,
}

local function findIdCaseless(list: { string }, text: string?): string?
	if not text then
		return nil
	end
	for _, id in list do
		if string.lower(id) == string.lower(text) then
			return id
		end
	end
	return nil
end

commands.artist = {
	Usage = "artist give <artistId> <raridade> [estrelas] [qtd] | artist clear",
	Description = "Dá artistas (ids em Config/Artists) ou limpa a coleção",
	Run = function(player: Player, args: { string }): string
		local data = DataService.GetProfile(player)
		if not data then
			return "Perfil não carregado."
		end
		if args[1] == "clear" then
			table.clear(data.Artists)
			table.clear(data.EquippedArtists)
			ArtistService.Commit(player)
			return "Coleção limpa."
		end
		local artistIds: { string } = {}
		for _, def in ArtistsConfig.List do
			table.insert(artistIds, def.Id)
		end
		local rarityIds: { string } = {}
		for _, rarity in RaritiesConfig.List do
			table.insert(rarityIds, rarity.Id)
		end
		local artistId = findIdCaseless(artistIds, args[2])
		local rarityId = findIdCaseless(rarityIds, args[3])
		local stars = tonumber(args[4] or "1") or 1
		local amount = math.clamp(tonumber(args[5] or "1") or 1, 1, 50)
		if args[1] ~= "give" or not artistId or not rarityId then
			return "Uso: /fe artist give <artistId> <raridade> [estrelas] [qtd]  (ex.: LinaLoop Brilliant 1 3)"
		end
		for _ = 1, amount do
			ArtistService.AddArtist(player, artistId, rarityId, stars)
		end
		ArtistService.Commit(player)
		return string.format("+%d %s · %s %d★", amount, artistId, rarityId, stars)
	end,
}

commands.pity = {
	Usage = "pity",
	Description = "Mostra os contadores de pity",
	Run = function(player: Player, _args: { string }): string
		local data = DataService.GetProfile(player)
		if not data then
			return "Perfil não carregado."
		end
		local counters = (data.Pity :: unknown) :: { [string]: number }
		local parts: { string } = {}
		for _, level in RaritiesConfig.PityLadder do
			table.insert(parts, string.format("%s %d/%d", level.Label, counters[level.Key] or 0, level.Threshold))
		end
		return "Pity: " .. table.concat(parts, " · ")
	end,
}

commands.tour = {
	Usage = "tour [force]",
	Description = "Faz World Tour ('force' ignora requisitos)",
	Run = function(player: Player, args: { string }): string
		local discs, can, reason = PrestigeService.GetPreview(player)
		if args[1] ~= "force" and not can then
			return string.format("Não pode (%s). Preview: %d Discos. Usa /fe tour force", tostring(reason), discs)
		end
		local ok, message = PrestigeService.DoWorldTour(player, args[1] == "force")
		return if ok then "World Tour feito." else message
	end,
}

commands.discs = {
	Usage = "discs <n>",
	Description = "Define os Discos de Platina por gastar",
	Run = function(player: Player, args: { string }): string
		local data = DataService.GetProfile(player)
		local value = tonumber(args[1] or "")
		if not data or not value or value < 0 then
			return "Uso: /fe discs <n>"
		end
		data.PlatinumDiscs = math.floor(value)
		PlayerStateService.MarkDirty(player)
		return "Discos de Platina: " .. data.PlatinumDiscs
	end,
}

commands.skills = {
	Usage = "skills reset",
	Description = "Limpa a árvore e devolve os Discos gastos",
	Run = function(player: Player, args: { string }): string
		if args[1] ~= "reset" then
			return "Uso: /fe skills reset"
		end
		return "Árvore limpa: +" .. PrestigeService.ResetTree(player) .. " Discos devolvidos."
	end,
}

commands.plots = {
	Usage = "plots",
	Description = "Lista os donos dos terrenos",
	Run = function(_player: Player, _args: { string }): string
		local lines = { "Terrenos:" }
		for index = 1, MapConfig.Plots.Count do
			local owner = PlotService.GetOwner(index)
			table.insert(lines, string.format("Plot_%d — %s", index, if owner then owner.Name else "livre"))
		end
		return table.concat(lines, "\n")
	end,
}

commands.home = {
	Usage = "home",
	Description = "Teleporta para o teu terreno",
	Run = function(player: Player, _args: { string }): string
		return if PlotService.TeleportHome(player)
			then "De volta ao teu festival."
			else "Não foi possível (sem personagem, sem terreno ou em cooldown)."
	end,
}

commands.state = {
	Usage = "state",
	Description = "Mostra o resumo do perfil",
	Run = function(player: Player, _args: { string }): string
		local data = DataService.GetProfile(player)
		if not data then
			return "Perfil não carregado."
		end
		return string.format(
			"v%d | Hype %s | Total %s | +%s/s | Cliques %s | Tier %d | WT %d | Jogo %s%s",
			data.DataVersion,
			NumberFormatter.format(data.Hype),
			NumberFormatter.format(data.TotalHypeEarned),
			NumberFormatter.format(EconomyService.GetHypePerSecond(player)),
			NumberFormatter.formatInteger(data.Stats.Clicks),
			data.StageTier,
			data.WorldTours,
			NumberFormatter.formatTime(data.Stats.PlayTime),
			if DataService.IsUsingMock() then " | STORE EM MEMÓRIA" else ""
		)
	end,
}

commands.save = {
	Usage = "save",
	Description = "Grava o perfil agora",
	Run = function(player: Player, _args: { string }): string
		return if DataService.SaveNow(player) then "Perfil gravado." else "Falha ao gravar (ver Output)."
	end,
}

commands.wipe = {
	Usage = "wipe confirm",
	Description = "Reinicia o perfil para o template",
	Run = function(player: Player, args: { string }): string
		if args[1] ~= "confirm" then
			return "Isto apaga o progresso. Usa: /fe wipe confirm"
		end
		if not DataService.ResetProfile(player) then
			return "Perfil não carregado."
		end
		EconomyService.SetDebugPassive(player, nil)
		return "Perfil reiniciado."
	end,
}

-- Execução -------------------------------------------------------------------

local function execute(player: Player, text: string)
	if not DebugService.IsAdmin(player) then
		return
	end

	local parts: { string } = {}
	for _, word in string.split(text, " ") do
		if word ~= "" then
			table.insert(parts, word)
		end
	end
	table.remove(parts, 1) -- alias (/fe)

	local name = string.lower(table.remove(parts, 1) or "help")
	local command = commands[name]
	if not command then
		reply(player, "Comando desconhecido: " .. name .. ". Usa /fe help")
		return
	end

	local ok, result = pcall(command.Run, player, parts)
	reply(player, if ok then result else "Erro: " .. tostring(result))
end

local function isAlias(text: string): boolean
	local first = string.lower(string.split(text, " ")[1] or "")
	return table.find(AdminConfig.CommandAliases, first) ~= nil
end

local function setupTextChatCommand()
	local command = trove:Add(Instance.new("TextChatCommand"))
	command.Name = "FestivalEmpireAdmin"
	command.PrimaryAlias = AdminConfig.CommandAliases[1]
	command.SecondaryAlias = AdminConfig.CommandAliases[2] or ""
	trove:Connect(command.Triggered, function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			execute(player, text)
		end
	end)
	command.Parent = TextChatService
end

local function onPlayerAdded(player: Player)
	adminCache[player] = computeIsAdmin(player)
	if TextChatService.ChatVersion == Enum.ChatVersion.LegacyChatService then
		trove:Connect(player.Chatted, function(message: string)
			if isAlias(message) then
				execute(player, message)
			end
		end)
	end
end

-- Ciclo de vida --------------------------------------------------------------

function DebugService.Init()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.LegacyChatService then
		setupTextChatCommand()
	end
end

function DebugService.Start()
	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		adminCache[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DebugService
