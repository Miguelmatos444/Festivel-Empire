--!strict
--[[
	PlotService
	Atribuição de terrenos (1 por jogador, máx. 6), spawn/respawn no terreno
	próprio, placa dinâmica do dono, validação de posse e teleporte "Voltar ao
	meu festival".

	A atribuição é síncrona (sem yields entre procurar e marcar o terreno),
	por isso dois jogadores nunca recebem o mesmo terreno.
	Replicação: Plot:GetAttribute("OwnerUserId") e Player:GetAttribute("PlotId").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)

local KICK_FULL = "Este festival está cheio (6/6 terrenos ocupados). Tenta outro servidor."
local SPAWN_HEIGHT = 4
local SPAWN_FALLBACK_DISTANCE = 25

local PlotService = {}

local plotAssigned: Signal.Signal<Player, number> = Signal.new()
local plotReleased: Signal.Signal<Player, number> = Signal.new()

PlotService.PlotAssigned = plotAssigned
PlotService.PlotReleased = plotReleased

local trove = Trove.new()
local owners: { [number]: Player } = {}
local playerPlots: { [Player]: number } = {}
local playerTroves: { [Player]: Trove.Trove } = {}
local lastTeleport: { [Player]: number } = {}

-- Consultas ------------------------------------------------------------------

function PlotService.GetPlotId(player: Player): number?
	return playerPlots[player]
end

function PlotService.GetOwner(index: number): Player?
	return owners[index]
end

function PlotService.IsOwner(player: Player, index: number): boolean
	return owners[index] == player
end

-- true se a posição (mundo) está dentro dos limites do terreno do jogador
function PlotService.IsInsidePlot(player: Player, position: Vector3): boolean
	local index = playerPlots[player]
	if not index then
		return false
	end
	local plots = MapConfig.Plots
	local localPosition = MapCalc.GetPlotCFrame(index):PointToObjectSpace(position)
	return math.abs(localPosition.X) <= plots.Width / 2 and math.abs(localPosition.Z) <= plots.Depth / 2
end

local function getBaseAttachment(index: number, name: string): Attachment?
	local model = MapService.GetPlotModel(index)
	local base = if model then model.PrimaryPart else nil
	local attachment = if base then base:FindFirstChild(name) else nil
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end
	return nil
end

function PlotService.GetSpawnCFrame(index: number): CFrame?
	local attachment = getBaseAttachment(index, "Spawn")
	if not attachment then
		return nil
	end
	return attachment.WorldCFrame * CFrame.new(0, SPAWN_HEIGHT, 0)
end

-- Placa ----------------------------------------------------------------------

local function ensureSignLabels(board: BasePart): (TextLabel, TextLabel)
	local gui = board:FindFirstChild("OwnerGui")
	if not gui or not gui:IsA("SurfaceGui") then
		local surface = Instance.new("SurfaceGui")
		surface.Name = "OwnerGui"
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 40
		surface.LightInfluence = 0
		surface.Parent = board

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromScale(0.05, 0.08)
		title.Size = UDim2.fromScale(0.9, 0.5)
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 209, 102)
		title.Parent = surface

		local subtitle = Instance.new("TextLabel")
		subtitle.Name = "Subtitle"
		subtitle.BackgroundTransparency = 1
		subtitle.Position = UDim2.fromScale(0.05, 0.6)
		subtitle.Size = UDim2.fromScale(0.9, 0.3)
		subtitle.Font = Enum.Font.GothamBold
		subtitle.TextScaled = true
		subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		subtitle.Parent = surface

		gui = surface
	end
	local surface = gui :: SurfaceGui
	return surface:FindFirstChild("Title") :: TextLabel, surface:FindFirstChild("Subtitle") :: TextLabel
end

function PlotService.RefreshSign(index: number)
	local model = MapService.GetPlotModel(index)
	local sign = if model then model:FindFirstChild("Sign") else nil
	local board = if sign then sign:FindFirstChild("Board", true) else nil
	if not board or not board:IsA("BasePart") then
		return
	end
	local title, subtitle = ensureSignLabels(board)

	local owner = owners[index]
	if not owner then
		title.Text = "TERRENO LIVRE"
		subtitle.Text = "À espera de um novo festival"
		return
	end

	title.Text = "Festival de " .. owner.DisplayName
	local data = DataService.GetProfile(owner)
	if data then
		local def = MapCalc.GetStageDef(data.StageTier)
		local tours = if data.WorldTours > 0
			then string.rep("★", math.min(data.WorldTours, 5)) .. " World Tour " .. data.WorldTours .. " · "
			else ""
		subtitle.Text = string.format("%sTier %d · %s · Era %s", tours, def.Tier, def.Name, def.Era)
	else
		subtitle.Text = "A preparar o palco…"
	end
end

-- Atribuição -----------------------------------------------------------------

local function moveToSpawn(player: Player, character: Model, index: number)
	task.defer(function()
		local spawnCFrame = PlotService.GetSpawnCFrame(index)
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if not spawnCFrame or not root or not root:IsA("BasePart") or character.Parent == nil then
			return
		end
		-- Fallback: só move se a SpawnLocation não tiver colocado a personagem no terreno
		if playerPlots[player] == index and (root.Position - spawnCFrame.Position).Magnitude > SPAWN_FALLBACK_DISTANCE then
			character:PivotTo(spawnCFrame)
		end
	end)
end

local function assign(player: Player): number?
	local existing = playerPlots[player]
	if existing then
		return existing
	end
	for index = 1, MapConfig.Plots.Count do
		if owners[index] == nil then
			owners[index] = player
			playerPlots[player] = index

			local model = MapService.GetPlotModel(index)
			if model then
				model:SetAttribute("OwnerUserId", player.UserId)
				local spawn = model:FindFirstChild("Spawn")
				if spawn and spawn:IsA("SpawnLocation") then
					player.RespawnLocation = spawn
				end
			end
			player:SetAttribute("PlotId", index)
			PlotService.RefreshSign(index)
			plotAssigned:Fire(player, index)
			return index
		end
	end
	return nil
end

local function release(player: Player)
	local playerTrove = playerTroves[player]
	if playerTrove then
		playerTroves[player] = nil
		playerTrove:Destroy()
	end
	lastTeleport[player] = nil

	local index = playerPlots[player]
	if not index then
		return
	end
	playerPlots[player] = nil
	if owners[index] == player then
		owners[index] = nil
	end
	local model = MapService.GetPlotModel(index)
	if model then
		model:SetAttribute("OwnerUserId", 0)
	end
	PlotService.RefreshSign(index)
	plotReleased:Fire(player, index)
end

local function onPlayerAdded(player: Player)
	local index = assign(player)
	if not index then
		player:Kick(KICK_FULL)
		return
	end

	local playerTrove = Trove.new()
	playerTroves[player] = playerTrove
	playerTrove:Connect(player.CharacterAdded, function(character: Model)
		moveToSpawn(player, character, index)
	end)
	local character = player.Character
	if character then
		moveToSpawn(player, character, index)
	end
end

-- Teleporte ------------------------------------------------------------------

function PlotService.TeleportHome(player: Player): boolean
	local index = playerPlots[player]
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not index or not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	if now - (lastTeleport[player] or -math.huge) < MapConfig.ReturnCooldown then
		return false
	end
	local spawnCFrame = PlotService.GetSpawnCFrame(index)
	if not spawnCFrame then
		return false
	end
	lastTeleport[player] = now
	humanoid.Sit = false
	character:PivotTo(spawnCFrame)
	return true
end

-- Ciclo de vida --------------------------------------------------------------

function PlotService.Init()
	ServerNet.Connect(RemoteDefs.Defs.ReturnToPlot, function(player: Player)
		PlotService.TeleportHome(player)
	end)

	-- Atualiza a placa quando o perfil (tier) fica disponível
	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player)
		local index = playerPlots[player]
		if index then
			PlotService.RefreshSign(index)
		end
	end))

	for index = 1, MapService.GetPlotCount() do
		PlotService.RefreshSign(index)
	end
end

function PlotService.Start()
	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	trove:Connect(Players.PlayerRemoving, release)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlotService
