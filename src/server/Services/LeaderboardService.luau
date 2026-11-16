--!strict
--[[
	LeaderboardService
	Dois rankings globais (OrderedDataStore) nos painéis da praça:
	  Slot 1 — Hype de sempre   (valor = floor(log10(TotalHypeEarned) × HypeScale))
	  Slot 2 — World Tours      (valor = WorldTours × 1e9 + Discos totais)
	Cada jogador envia o seu valor a cada SubmitInterval e ao sair; os painéis
	atualizam a cada RefreshInterval. Em Studio sem API (store em memória) os
	painéis mostram só os jogadores deste servidor.
	Painel: parte "Leaderboard_<slot>" da praça (placeholder ou modelo próprio); se não
	existir, é criada no Attachment "Leaderboard_<slot>" do Root da praça.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local LeaderboardConfig = require(ReplicatedStorage.Shared.Config.Leaderboards)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Placeholders = require(script.Parent.Parent.World.Placeholders)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)

type Entry = { UserId: number, Value: number }
type Board = {
	Key: string,
	Title: string,
	Store: string,
	Slot: number,
	Rows: { TextLabel },
}

local TOURS_FACTOR = 1e9

local LeaderboardService = {}

local trove = Trove.new()
local boards: { Board } = {}
local nameCache: { [number]: string } = {}

-- Valores ----------------------------------------------------------------------

local function scoreFromData(data: Types.ProfileData, key: string): number
	if key == "Hype" then
		local total = data.TotalHypeEarned
		if total.m <= 0 then
			return 0
		end
		return math.max(0, math.floor(BigNum.log10(total) * LeaderboardConfig.HypeScale))
	end
	return data.WorldTours * TOURS_FACTOR + math.min(data.TotalDiscsEarned, LeaderboardConfig.DiscsCap)
end

local function scoreFor(player: Player, key: string): number?
	local data = DataService.GetProfile(player)
	return if data then scoreFromData(data, key) else nil
end

local function formatScore(key: string, value: number): string
	if key == "Hype" then
		return NumberFormatter.format(BigNum.fromLog10(value / LeaderboardConfig.HypeScale))
	end
	local tours = math.floor(value / TOURS_FACTOR)
	local discs = value % TOURS_FACTOR
	return string.format("%d WT · %s ◉", tours, NumberFormatter.format(discs))
end

local function getName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.DisplayName else nil
	if not name then
		local ok, result = pcall(function(): string
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok then result else "Jogador " .. userId
	end
	nameCache[userId] = name :: string
	return name :: string
end

-- Painéis ----------------------------------------------------------------------

local function findOrCreateBoardPart(slot: number): BasePart?
	local map = MapService.GetMapFolder()
	local plaza = if map then map:FindFirstChild("Plaza") else nil
	if not plaza then
		return nil
	end
	local existing = plaza:FindFirstChild("Leaderboard_" .. slot, true)
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local root = plaza:FindFirstChild("Root")
	local attachment = if root then root:FindFirstChild("Leaderboard_" .. slot) else nil
	if not attachment or not attachment:IsA("Attachment") then
		return nil
	end
	local part = Placeholders.NewPart(
		"Leaderboard_" .. slot,
		Vector3.new(16, 12, 1),
		CFrame.lookAt(attachment.WorldPosition, Vector3.new(0, attachment.WorldPosition.Y, 0)),
		Color3.fromRGB(34, 20, 70),
		Enum.Material.SmoothPlastic,
		plaza
	)
	return part
end

local function buildBoard(part: BasePart, title: string): { TextLabel }
	local old = part:FindFirstChild("PlaceholderLabel")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(20, 11, 46)
	background.BorderSizePixel = 0
	background.Parent = gui

	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency = 1
	heading.Position = UDim2.fromScale(0.03, 0.02)
	heading.Size = UDim2.fromScale(0.94, 0.12)
	heading.Font = Enum.Font.FredokaOne
	heading.TextScaled = true
	heading.TextColor3 = Color3.fromRGB(255, 209, 102)
	heading.Text = title
	heading.Parent = background

	local rows: { TextLabel } = {}
	local rowHeight = 0.82 / LeaderboardConfig.TopCount
	for index = 1, LeaderboardConfig.TopCount do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = if index % 2 == 0 then 1 else 0.85
		row.BackgroundColor3 = Color3.fromRGB(120, 75, 255)
		row.BorderSizePixel = 0
		row.Position = UDim2.fromScale(0.03, 0.16 + (index - 1) * rowHeight)
		row.Size = UDim2.fromScale(0.94, rowHeight * 0.92)
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if index == 1
			then Color3.fromRGB(255, 209, 102)
			elseif index <= 3 then Color3.fromRGB(43, 210, 255)
			else Color3.new(1, 1, 1)
		row.Text = string.format("#%d  —", index)
		row.Parent = background
		table.insert(rows, row)
	end
	return rows
end

-- Envio / leitura ----------------------------------------------------------------

local function submitData(userId: number, data: Types.ProfileData)
	if DataService.IsUsingMock() then
		return -- em memória: os painéis leem os jogadores do servidor diretamente
	end
	for _, board in boards do
		local value = scoreFromData(data, board.Key)
		local ok, err = pcall(function()
			DataStoreService:GetOrderedDataStore(board.Store):SetAsync(tostring(userId), value)
		end)
		if not ok then
			warn("[LeaderboardService] SetAsync falhou: " .. tostring(err))
		end
	end
end

local function submit(player: Player)
	local data = DataService.GetProfile(player)
	if data then
		submitData(player.UserId, data)
	end
end

local function fetchTop(board: Board): { Entry }
	local entries: { Entry } = {}
	if DataService.IsUsingMock() then
		for _, player in DataService.GetLoadedPlayers() do
			local value = scoreFor(player, board.Key)
			if value then
				table.insert(entries, { UserId = player.UserId, Value = value })
			end
		end
		table.sort(entries, function(a: Entry, b: Entry): boolean
			return a.Value > b.Value
		end)
		return entries
	end
	local ok, result = pcall(function(): { { key: string, value: number } }
		local pages = DataStoreService:GetOrderedDataStore(board.Store):GetSortedAsync(false, LeaderboardConfig.TopCount)
		return pages:GetCurrentPage()
	end)
	if not ok then
		warn("[LeaderboardService] GetSortedAsync falhou: " .. tostring(result))
		return entries
	end
	for _, item in result do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { UserId = userId, Value = item.value })
		end
	end
	return entries
end

local function refresh()
	for _, board in boards do
		local entries = fetchTop(board)
		for index, row in board.Rows do
			local entry = entries[index]
			row.Text = if entry
				then string.format("#%d  %s  —  %s", index, getName(entry.UserId), formatScore(board.Key, entry.Value))
				else string.format("#%d  —", index)
		end
	end
end

local function submitLoop()
	while true do
		task.wait(LeaderboardConfig.SubmitInterval)
		for _, player in DataService.GetLoadedPlayers() do
			task.spawn(submit, player)
			task.wait(0.5) -- espalha os pedidos
		end
	end
end

local function refreshLoop()
	while true do
		refresh()
		task.wait(LeaderboardConfig.RefreshInterval)
	end
end

-- Ciclo de vida --------------------------------------------------------------

function LeaderboardService.Init()
	for _, config in LeaderboardConfig.Boards do
		local part = findOrCreateBoardPart(config.Slot)
		if part then
			table.insert(boards, {
				Key = config.Key,
				Title = config.Title,
				Store = config.Store,
				Slot = config.Slot,
				Rows = buildBoard(part, config.Title),
			})
		else
			warn("[LeaderboardService] Praça sem painel/Attachment Leaderboard_" .. config.Slot)
		end
	end
	-- Valor final ao sair (os dados ainda estão disponíveis antes do último save)
	trove:Add(DataService.ProfileReleasing:Connect(function(player: Player, data: Types.ProfileData)
		task.spawn(submitData, player.UserId, data)
	end))
end

function LeaderboardService.Start()
	trove:Add(task.spawn(submitLoop))
	trove:Add(task.spawn(refreshLoop))
end

return LeaderboardService
