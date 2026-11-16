--!strict
--[[
	SocialService (tudo decidido no servidor)
	  - Amigos no servidor: +10% de Hype por amigo (máx. 5). IsFriendsWith em cache por par.
	  - Grupo Roblox: +10% para membros (Config/Social.Group.GroupId; 0 = desligado).
	  - Likes: 1 por festival por dia (UTC), máx. 5 por dia; só dentro do terreno do dono.
	    Quem dá recebe minutos de rendimento; o dono acumula LikesReceived (+1% por 10, máx. +20%).
	  - Visitar festivais: teleporte para o spawn de outro terreno (cooldown partilhado).
	  - Evento global Headliner: horário fixo em UTC (igual em todos os servidores),
	    Hype ×2 e energia ×1.5. Overrides de debug em atributos de ReplicatedStorage.
	O multiplicador total entra no EconomyService como fonte "Social".
	Atributos públicos do jogador (lista de festivais): FE_StageTier, FE_WorldTours, FE_Likes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local SocialConfig = require(ReplicatedStorage.Shared.Config.Social)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local SocialCalc = require(ReplicatedStorage.Shared.Calc.SocialCalc)
local RetentionCalc = require(ReplicatedStorage.Shared.Calc.RetentionCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local BassDropService = require(script.Parent.BassDropService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PlotService = require(script.Parent.PlotService)
local RewardService = require(script.Parent.RewardService)

type ProfileData = Types.ProfileData
type SocialSync = Types.SocialSync
type HeadlinerState = Types.HeadlinerState

local SYNC_INTERVAL = 0.5
local HEADLINER_CHECK_INTERVAL = 1

local SocialService = {}

local likeGiven: Signal.Signal<Player, Player> = Signal.new()
local headlinerChanged: Signal.Signal<boolean> = Signal.new()

-- (quem deu, dono do festival)
SocialService.LikeGiven = likeGiven
-- (ativo) — início/fim do evento Headliner neste servidor
SocialService.HeadlinerChanged = headlinerChanged

local trove = Trove.new()
local friendCache: { [string]: boolean } = {} -- "menorId:maiorId" -> são amigos
local pendingPairs: { [string]: boolean } = {}
local friendCounts: { [Player]: number } = {}
local debugFriends: { [Player]: number } = {}
local groupMembers: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local headlinerActive = false

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

function SocialService.GetHeadliner(): HeadlinerState
	return SocialCalc.ReadHeadliner(serverNow(), ReplicatedStorage)
end

function SocialService.IsHeadlinerActive(): boolean
	return headlinerActive
end

-- Multiplicador -------------------------------------------------------------------

local function getFriendCount(player: Player): number
	return debugFriends[player] or friendCounts[player] or 0
end

local function applyMultiplier(player: Player)
	local data = DataService.GetProfile(player)
	if not data then
		return
	end
	local multiplier = SocialCalc.GetMultiplier(
		getFriendCount(player),
		groupMembers[player] == true,
		data.Social.LikesReceived,
		headlinerActive
	)
	EconomyService.SetMultiplier(player, "Social", multiplier)
	BassDropService.SetEnergyMultiplier(
		player,
		"Headliner",
		if headlinerActive then SocialConfig.Headliner.EnergyMultiplier else 1
	)
	dirty[player] = true
end

-- Amigos ------------------------------------------------------------------------

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

-- Conta amigos entre os jogadores do servidor (exceto `leaving`, que está a sair)
local function recountFriends(leaving: Player?)
	local present: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player ~= leaving then
			table.insert(present, player)
		end
	end
	for _, player in present do
		local count = 0
		for _, other in present do
			if other ~= player and friendCache[pairKey(player.UserId, other.UserId)] then
				count += 1
			end
		end
		if friendCounts[player] ~= count then
			friendCounts[player] = count
			applyMultiplier(player)
		end
	end
end

local function checkPair(a: Player, b: Player)
	local key = pairKey(a.UserId, b.UserId)
	if friendCache[key] ~= nil or pendingPairs[key] then
		return
	end
	pendingPairs[key] = true
	task.spawn(function()
		local ok, result = pcall(function(): boolean
			return a:IsFriendsWith(b.UserId)
		end)
		pendingPairs[key] = nil
		friendCache[key] = ok and result == true
		if not ok then
			Diag.Log("Social", "IsFriendsWith falhou para " .. key .. ": " .. tostring(result))
			friendCache[key] = nil -- tenta outra vez na próxima entrada
		end
		recountFriends()
	end)
end

local function checkGroup(player: Player)
	local groupId = SocialConfig.Group.GroupId
	if groupId <= 0 then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function(): boolean
			return player:IsInGroup(groupId)
		end)
		if player.Parent ~= Players then
			return
		end
		groupMembers[player] = ok and result == true
		applyMultiplier(player)
	end)
end

-- Likes --------------------------------------------------------------------------

local function ensureLikeDay(data: ProfileData)
	local today = RetentionCalc.GetDayIndex(os.time())
	if data.Social.LikesGivenDay ~= today then
		data.Social.LikesGivenDay = today
		data.Social.LikedToday = {}
	end
end

local function countGivenToday(data: ProfileData): number
	local count = 0
	for _ in data.Social.LikedToday do
		count += 1
	end
	return count
end

local function refreshPublic(player: Player)
	local data = DataService.GetProfile(player)
	if not data then
		return
	end
	player:SetAttribute("FE_StageTier", data.StageTier)
	player:SetAttribute("FE_WorldTours", data.WorldTours)
	player:SetAttribute("FE_Likes", data.Social.LikesReceived)
end

function SocialService.GiveLike(player: Player, index: number): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	local owner = PlotService.GetOwner(index)
	if not owner then
		return false, "Este terreno está livre."
	end
	if owner == player then
		return false, "Não podes dar Like ao teu próprio festival."
	end
	local ownerData = DataService.GetProfile(owner)
	if not ownerData then
		return false, "Esse festival ainda está a carregar."
	end
	if PlotService.GetPlotIndexOfCharacter(player) ~= index then
		return false, "Entra no festival para lhe dares Like."
	end
	ensureLikeDay(data)
	local key = tostring(owner.UserId)
	if data.Social.LikedToday[key] then
		return false, "Já deste Like a este festival hoje."
	end
	local maxPerDay = SocialConfig.Likes.MaxGivenPerDay
	if countGivenToday(data) >= maxPerDay then
		return false, string.format("Já deste os %d Likes de hoje. Volta amanhã!", maxPerDay)
	end

	data.Social.LikedToday[key] = true
	ownerData.Social.LikesReceived += 1
	dirty[player] = true
	applyMultiplier(owner)
	refreshPublic(owner)
	PlotService.RefreshSign(index)

	local granted = RewardService.Grant(player, SocialConfig.Likes.LikerReward)
	notify(
		owner,
		string.format("%s deu ❤ Like ao teu festival! (total: %d)", player.DisplayName, ownerData.Social.LikesReceived)
	)
	likeGiven:Fire(player, owner)
	return true, string.format("❤ Like dado ao festival de %s! %s", owner.DisplayName, granted)
end

-- Visitas -------------------------------------------------------------------------

function SocialService.Visit(player: Player, index: number): (boolean, string)
	local owner = PlotService.GetOwner(index)
	if not owner then
		return false, "Este terreno está livre."
	end
	if not PlotService.TeleportToPlot(player, index) then
		return false, "Aguarda um momento antes de viajar outra vez."
	end
	if owner == player then
		return true, "De volta ao teu festival."
	end
	return true, string.format("Bem-vindo ao festival de %s! Dá-lhe um ❤ Like.", owner.DisplayName)
end

-- Headliner ------------------------------------------------------------------------

local function updateHeadliner()
	local active = SocialService.GetHeadliner().Active
	if active == headlinerActive then
		return
	end
	headlinerActive = active
	for _, player in DataService.GetLoadedPlayers() do
		applyMultiplier(player)
		notify(
			player,
			if active
				then string.format(
					"🎤 HEADLINER AO VIVO! Hype ×%g e energia ×%g durante %d min!",
					SocialConfig.Headliner.HypeMultiplier,
					SocialConfig.Headliner.EnergyMultiplier,
					SocialConfig.Headliner.Duration // 60
				)
				else string.format(
					"O Headliner terminou. O próximo é daqui a %g h!",
					SocialConfig.Headliner.Interval / 3600
				)
		)
	end
	headlinerChanged:Fire(active)
end

-- Sincronização -----------------------------------------------------------------------

local function buildSync(player: Player, data: ProfileData): SocialSync
	ensureLikeDay(data)
	return {
		Friends = getFriendCount(player),
		InGroup = groupMembers[player] == true,
		LikesReceived = data.Social.LikesReceived,
		LikedToday = table.clone(data.Social.LikedToday),
		GivenToday = countGivenToday(data),
		Multiplier = EconomyService.GetMultiplier(player, "Social"),
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
				ServerNet.FireClient(RemoteDefs.Defs.SocialSync, player, buildSync(player, data))
			end
		end
	end
end

local function headlinerLoop()
	while true do
		updateHeadliner()
		task.wait(HEADLINER_CHECK_INTERVAL)
	end
end

local function publicLoop()
	while true do
		task.wait(SocialConfig.PublicRefreshInterval)
		for _, player in DataService.GetLoadedPlayers() do
			refreshPublic(player)
		end
	end
end

-- Debug -----------------------------------------------------------------------------

-- n = nil remove a simulação e volta à contagem real
function SocialService.DebugSetFriends(player: Player, count: number?)
	debugFriends[player] = count
	applyMultiplier(player)
end

function SocialService.DebugSetLikes(player: Player, likes: number): boolean
	local data = DataService.GetProfile(player)
	if not data then
		return false
	end
	data.Social.LikesReceived = math.max(0, math.floor(likes))
	applyMultiplier(player)
	refreshPublic(player)
	local index = PlotService.GetPlotId(player)
	if index then
		PlotService.RefreshSign(index)
	end
	return true
end

function SocialService.DebugResetGiven(player: Player): boolean
	local data = DataService.GetProfile(player)
	if not data then
		return false
	end
	data.Social.LikedToday = {}
	dirty[player] = true
	return true
end

function SocialService.DebugHeadliner(start: boolean)
	local now = serverNow()
	if start then
		ReplicatedStorage:SetAttribute(SocialCalc.SuppressAttribute, nil)
		ReplicatedStorage:SetAttribute(SocialCalc.OverrideAttribute, now + SocialConfig.Headliner.Duration)
	else
		local state = SocialService.GetHeadliner()
		ReplicatedStorage:SetAttribute(SocialCalc.OverrideAttribute, nil)
		ReplicatedStorage:SetAttribute(SocialCalc.SuppressAttribute, if state.Active then state.EndsAt else now)
	end
	updateHeadliner()
end

function SocialService.Describe(player: Player): string
	local data = DataService.GetProfile(player)
	if not data then
		return "Perfil não carregado."
	end
	local state = SocialService.GetHeadliner()
	local now = serverNow()
	return string.format(
		"Amigos %d (+%d%%) | Grupo %s | Likes %d (+%d%%) | Headliner %s | Social ×%.2f",
		getFriendCount(player),
		math.floor(SocialCalc.GetFriendsBonus(getFriendCount(player)) * 100 + 0.5),
		if groupMembers[player] then "sim" else "não",
		data.Social.LikesReceived,
		math.floor(SocialCalc.GetLikesBonus(data.Social.LikesReceived) * 100 + 0.5),
		if state.Active
			then string.format("ATIVO (%ds)", math.floor(state.EndsAt - now))
			else string.format("em %ds", math.floor(state.StartsAt - now)),
		EconomyService.GetMultiplier(player, "Social")
	)
end

-- Ciclo de vida --------------------------------------------------------------

function SocialService.Init()
	ServerNet.Connect(RemoteDefs.Defs.GiveLike, function(player: Player, indexArg: unknown)
		local _, message = SocialService.GiveLike(player, indexArg :: number)
		notify(player, message)
	end)
	ServerNet.Connect(RemoteDefs.Defs.VisitPlot, function(player: Player, indexArg: unknown)
		local _, message = SocialService.Visit(player, indexArg :: number)
		notify(player, message)
	end)

	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player, data: ProfileData)
		ensureLikeDay(data)
		applyMultiplier(player)
		refreshPublic(player)
	end))
	trove:Add(PlayerStateService.ClientReady:Connect(function(player: Player)
		dirty[player] = true
	end))
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		dirty[player] = nil
		friendCounts[player] = nil
		debugFriends[player] = nil
		groupMembers[player] = nil
		recountFriends(player)
	end)
end

local function onPlayerAdded(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			checkPair(player, other)
		end
	end
	checkGroup(player)
end

function SocialService.Start()
	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	trove:Add(task.spawn(syncLoop))
	trove:Add(task.spawn(headlinerLoop))
	trove:Add(task.spawn(publicLoop))
end

return SocialService
