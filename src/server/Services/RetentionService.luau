--!strict
--[[
	RetentionService
	  - Recompensa diária: 7 dias, reclamar após 20 h, sequência mantida até 48 h (os.time())
	  - Missões: 3 diárias + 2 semanais, sorteadas por jogador (determinístico) e reiniciadas
	    em UTC; o progresso vem SÓ dos sinais dos serviços (o cliente nunca envia progresso)
	  - Códigos promocionais: expiração, 1 uso por jogador e limite global entre servidores
	    (contador atómico em DataStore; em Studio sem API usa contador em memória)
	  - Sincronização com o cliente (RetentionSync), agregada a cada SYNC_INTERVAL
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RetentionConfig = require(ReplicatedStorage.Shared.Config.Retention)
local CodesConfig = require(ReplicatedStorage.Shared.Config.Codes)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local RetentionCalc = require(ReplicatedStorage.Shared.Calc.RetentionCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local BassDropService = require(script.Parent.BassDropService)
local EquipmentService = require(script.Parent.EquipmentService)
local GachaService = require(script.Parent.GachaService)
local ArtistService = require(script.Parent.ArtistService)
local StageService = require(script.Parent.StageService)
local PrestigeService = require(script.Parent.PrestigeService)
local MonetizationService = require(script.Parent.MonetizationService)
local RewardService = require(script.Parent.RewardService)
local ArrowGameService = require(script.Parent.ArrowGameService)
local ArrowGameConfig = require(ReplicatedStorage.Shared.Config.ArrowGame)

type ProfileData = Types.ProfileData
type MissionData = Types.MissionData
type MissionMetric = Types.MissionMetric
type RetentionSync = Types.RetentionSync

local SYNC_INTERVAL = 0.5

local RetentionService = {}

local dailyClaimed: Signal.Signal<Player, number> = Signal.new()

-- (jogador, dia 1..7) — conquistas
RetentionService.DailyClaimed = dailyClaimed

local trove = Trove.new()
local dirty: { [Player]: boolean } = {}
local redeeming: { [Player]: boolean } = {}
local memoryCodeUses: { [string]: number } = {}

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

-- Missões ----------------------------------------------------------------------

local function sanitizeList(list: { MissionData }): { MissionData }
	local clean: { MissionData } = {}
	for _, mission in list do
		if type(mission) == "table" and RetentionConfig.MissionById[mission.Id] then
			table.insert(clean, mission)
		end
	end
	return clean
end

-- Garante as missões do dia/semana atuais (sorteia de novo quando o período muda)
local function ensureMissions(player: Player, data: ProfileData)
	local now = os.time()
	local missions = data.Missions
	local day = RetentionCalc.GetDayIndex(now)
	local week = RetentionCalc.GetWeekIndex(now)
	if missions.DayIndex ~= day then
		missions.DayIndex = day
		missions.Daily = RetentionCalc.PickMissions(RetentionConfig.DailyMissions, RetentionConfig.DailyMissionCount, player.UserId, day)
		dirty[player] = true
	else
		missions.Daily = sanitizeList(missions.Daily)
	end
	if missions.WeekIndex ~= week then
		missions.WeekIndex = week
		missions.Weekly = RetentionCalc.PickMissions(RetentionConfig.WeeklyMissions, RetentionConfig.WeeklyMissionCount, player.UserId, week)
		dirty[player] = true
	else
		missions.Weekly = sanitizeList(missions.Weekly)
	end
end

-- Volta a verificar o período das missões (ex.: depois de /fe missions reroll)
function RetentionService.RefreshMissions(player: Player)
	local data = DataService.GetProfile(player)
	if data then
		ensureMissions(player, data)
		dirty[player] = true
	end
end

function RetentionService.AddProgress(player: Player, metric: MissionMetric, amount: number)
	local data = DataService.GetProfile(player)
	if not data or amount <= 0 then
		return
	end
	ensureMissions(player, data)
	for _, list in { data.Missions.Daily, data.Missions.Weekly } do
		for _, mission in list do
			local def = RetentionConfig.MissionById[mission.Id]
			if def and def.Metric == metric and not mission.Claimed and mission.Progress < def.Target then
				mission.Progress = math.min(def.Target, mission.Progress + amount)
				dirty[player] = true
				if mission.Progress >= def.Target then
					notify(player, "Missão completa: " .. def.Name .. " — reclama em MISSÕES!")
				end
			end
		end
	end
end

function RetentionService.ClaimMission(player: Player, slot: string): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	ensureMissions(player, data)
	local kind, indexText = string.match(slot, "^([DW])(%d)$")
	local list = if kind == "D" then data.Missions.Daily elseif kind == "W" then data.Missions.Weekly else nil
	local mission = if list and indexText then list[tonumber(indexText) or 0] else nil
	local def = if mission then RetentionConfig.MissionById[mission.Id] else nil
	if not mission or not def then
		return false, "Missão não encontrada."
	end
	if mission.Claimed then
		return false, "Já reclamaste esta missão."
	end
	if mission.Progress < def.Target then
		return false, string.format("Ainda falta: %d/%d.", mission.Progress, def.Target)
	end
	mission.Claimed = true
	dirty[player] = true
	local granted = RewardService.Grant(player, def.Reward)
	return true, def.Name .. " reclamada: " .. granted
end

-- Recompensa diária --------------------------------------------------------------------

function RetentionService.ClaimDaily(player: Player): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	local now = os.time()
	local status = RetentionCalc.GetDailyStatus(data.Daily, now)
	if not status.CanClaim then
		local hours = math.floor(status.SecondsUntilClaim / 3600)
		local minutes = math.floor(status.SecondsUntilClaim % 3600 / 60)
		return false, string.format("Próxima recompensa diária em %dh %02dm.", hours, minutes)
	end
	local reward = RetentionConfig.DailyRewards[status.NextDay]
	data.Daily.Streak = status.NextDay
	data.Daily.LastClaim = now
	dirty[player] = true
	local granted = RewardService.Grant(player, reward)
	dailyClaimed:Fire(player, status.NextDay)
	return true, string.format("Dia %d reclamado: %s", status.NextDay, granted)
end

-- Códigos -------------------------------------------------------------------------

-- Incrementa o contador global do código. Devolve false se o limite já foi atingido.
local function consumeGlobalUse(code: string, maxUses: number): (boolean, string?)
	if DataService.IsUsingMock() then
		local used = memoryCodeUses[code] or 0
		if used >= maxUses then
			return false, nil
		end
		memoryCodeUses[code] = used + 1
		return true, nil
	end
	local accepted = false
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(CodesConfig.StoreName):UpdateAsync(code, function(old: unknown): number?
			local used = if type(old) == "number" then old else 0
			if used >= maxUses then
				accepted = false
				return nil
			end
			accepted = true
			return used + 1
		end)
	end)
	if not ok then
		return false, tostring(err)
	end
	return accepted, nil
end

function RetentionService.RedeemCode(player: Player, raw: string): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	if redeeming[player] then
		return false, "Espera um momento…"
	end
	local code = string.upper(raw)
	local def = CodesConfig.ByCode[code]
	if not def then
		return false, "Código inválido."
	end
	if data.RedeemedCodes[code] then
		return false, "Já usaste este código."
	end
	local expiresAt = def.ExpiresAt
	if expiresAt and os.time() > expiresAt then
		return false, "Este código expirou."
	end
	local minTier = def.MinTier
	if minTier and data.StageTier < minTier then
		return false, string.format("Este código requer o Tier %d.", minTier)
	end

	local maxUses = def.MaxUses
	if maxUses then
		redeeming[player] = true
		local accepted, err = consumeGlobalUse(code, maxUses)
		redeeming[player] = nil
		if err then
			warn("[RetentionService] Falha no contador do código " .. code .. ": " .. err)
			return false, "Não foi possível validar o código. Tenta mais tarde."
		end
		if not accepted then
			return false, "Este código já atingiu o limite de usos."
		end
	end

	-- Depois do pedido ao DataStore: o perfil pode ter mudado
	local current = DataService.GetProfile(player)
	if not current or current.RedeemedCodes[code] then
		return false, "Já usaste este código."
	end
	current.RedeemedCodes[code] = true
	local granted = RewardService.Grant(player, def.Reward)
	Diag.Log("Retention", player.Name .. " resgatou " .. code)
	return true, "Código " .. code .. " resgatado: " .. granted
end

-- Sincronização ----------------------------------------------------------------------

function RetentionService.MarkDirty(player: Player)
	dirty[player] = true
end

local function buildSync(player: Player, data: ProfileData): RetentionSync
	return {
		Daily = table.clone(data.Daily),
		Missions = {
			DayIndex = data.Missions.DayIndex,
			WeekIndex = data.Missions.WeekIndex,
			Daily = table.clone(data.Missions.Daily),
			Weekly = table.clone(data.Missions.Weekly),
		},
		Gamepasses = MonetizationService.GetOwnedMap(player),
		AutoClick = data.AutoClick,
	}
end

local function syncLoop()
	while true do
		task.wait(SYNC_INTERVAL)
		for player in dirty do
			local data = DataService.GetProfile(player)
			if not data or player.Parent ~= Players then
				dirty[player] = nil
			elseif PlayerStateService.IsClientReady(player) then
				dirty[player] = nil
				ServerNet.FireClient(RemoteDefs.Defs.RetentionSync, player, buildSync(player, data))
			end
		end
	end
end

-- Minutos de jogo e mudança de dia/semana
local function minuteLoop()
	while true do
		task.wait(60)
		for _, player in DataService.GetLoadedPlayers() do
			local data = DataService.GetProfile(player)
			if data then
				ensureMissions(player, data)
				RetentionService.AddProgress(player, "PlayMinutes", 1)
			end
		end
	end
end

-- Ciclo de vida --------------------------------------------------------------

function RetentionService.Init()
	ServerNet.Connect(RemoteDefs.Defs.ClaimDaily, function(player: Player)
		local _, message = RetentionService.ClaimDaily(player)
		notify(player, message)
	end)
	ServerNet.Connect(RemoteDefs.Defs.ClaimMission, function(player: Player, slotArg: unknown)
		local _, message = RetentionService.ClaimMission(player, slotArg :: string)
		notify(player, message)
	end)
	ServerNet.Connect(RemoteDefs.Defs.RedeemCode, function(player: Player, codeArg: unknown)
		local _, message = RetentionService.RedeemCode(player, codeArg :: string)
		notify(player, message)
	end)

	-- Progresso das missões (só a partir de eventos do servidor)
	trove:Add(ArrowGameService.ArrowHit:Connect(function(player: Player, _grade: Types.ArrowGrade, combo: number, auto: boolean)
		RetentionService.AddProgress(player, "ArrowHits", 1)
		if not auto and combo == ArrowGameConfig.Combo.MissionTarget then
			RetentionService.AddProgress(player, "ArrowCombo", 1)
		end
	end))
	trove:Add(BassDropService.DropSucceeded:Connect(function(player: Player, grade: Types.DropGrade)
		RetentionService.AddProgress(player, "BassDrops", 1)
		if grade == "Perfect" then
			RetentionService.AddProgress(player, "PerfectDrops", 1)
		end
	end))
	trove:Add(EquipmentService.Purchased:Connect(function(player: Player, levels: number)
		RetentionService.AddProgress(player, "EquipmentLevels", levels)
	end))
	trove:Add(GachaService.CratesOpened:Connect(function(player: Player, count: number)
		RetentionService.AddProgress(player, "CratesOpened", count)
	end))
	trove:Add(ArtistService.Fused:Connect(function(player: Player, fusions: number)
		RetentionService.AddProgress(player, "Fusions", fusions)
	end))
	trove:Add(StageService.StageChanged:Connect(function(player: Player)
		RetentionService.AddProgress(player, "StagesBought", 1)
	end))
	trove:Add(PrestigeService.WorldTourCompleted:Connect(function(player: Player)
		RetentionService.AddProgress(player, "WorldTours", 1)
	end))

	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player, data: ProfileData)
		ensureMissions(player, data)
		dirty[player] = true
	end))
	trove:Add(PlayerStateService.ClientReady:Connect(function(player: Player)
		dirty[player] = true
	end))
	trove:Add(MonetizationService.Changed:Connect(function(player: Player)
		dirty[player] = true
	end))
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		dirty[player] = nil
		redeeming[player] = nil
	end)
end

function RetentionService.Start()
	trove:Add(task.spawn(syncLoop))
	trove:Add(task.spawn(minuteLoop))
end

return RetentionService
