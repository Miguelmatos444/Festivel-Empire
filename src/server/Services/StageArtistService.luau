--!strict
--[[
	StageArtistService
	Coloca os artistas equipados no palco do dono, nos Attachments Artist_1..7 do Root
	do palco, virados para o público. Reconstrói quando os equipados mudam ou o palco
	é trocado; limpa quando o dono sai. Cada artista leva o nome, a raridade e as
	estrelas por cima da cabeça (BillboardGui com LOD por distância).
	A dança é feita no cliente (ArtistDanceController), ao ritmo do relógio partilhado.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local Assets = require(script.Parent.Parent.World.Assets)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local StageService = require(script.Parent.StageService)
local ArtistService = require(script.Parent.ArtistService)

type ArtistData = Types.ArtistData
type RarityDef = Types.RarityDef

local FOLDER_NAME = "Artists"

local StageArtistService = {}

local trove = Trove.new()
local pending: { [Player]: boolean } = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(60, 255, 120)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(40, 200, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(140, 80, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 200)),
})

local function clearArtists(index: number)
	local model = MapService.GetPlotModel(index)
	local folder = if model then model:FindFirstChild(FOLDER_NAME) else nil
	if folder then
		folder:Destroy()
	end
end

local function addNameplate(rig: Model, data: ArtistData, rarity: RarityDef)
	local head = rig:FindFirstChild("Head")
	local adornee = if head and head:IsA("BasePart") then head else rig.PrimaryPart
	if not adornee then
		return
	end
	local def = ArtistCalc.GetArtist(data.Id)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromScale(8, 2)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = LodConfig.Vfx.HideDistance
	billboard.LightInfluence = 0
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 0.55)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = if def then def.Name else data.Id
	nameLabel.Parent = billboard

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Position = UDim2.fromScale(0, 0.55)
	rarityLabel.Size = UDim2.fromScale(1, 0.45)
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextScaled = true
	rarityLabel.TextColor3 = rarity.Color
	rarityLabel.TextStrokeTransparency = 0.3
	rarityLabel.Text = rarity.Name .. " " .. string.rep("★", data.Stars)
	rarityLabel.Parent = billboard

	if rarity.Effect == "Gradient" or rarity.Effect == "Rainbow" then
		rarityLabel.TextColor3 = Color3.new(1, 1, 1)
		local gradient = Instance.new("UIGradient")
		gradient.Color = if rarity.Effect == "Rainbow"
			then RAINBOW
			else ColorSequence.new(rarity.Color, Color3.new(1, 1, 1))
		gradient.Parent = rarityLabel
	end
end

local function decorate(rig: Model, data: ArtistData)
	local rarity = ArtistCalc.GetRarity(data.Rarity)
	if not rarity then
		return
	end
	if rig:GetAttribute("Placeholder") == true then
		for _, descendant in rig:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
				descendant.Color = rarity.Color
				descendant.Material = if rarity.Effect == "None" then Enum.Material.SmoothPlastic else Enum.Material.Neon
			end
		end
	end
	if rarity.Effect ~= "None" then
		local root = rig.PrimaryPart
		if root then
			local light = Instance.new("PointLight")
			light.Color = rarity.Color
			light.Range = 12
			light.Brightness = 2
			light.Parent = root
		end
	end
	addNameplate(rig, data, rarity)
end

-- Distância do pivot do rig à base dos pés (para assentar no estrado)
local function footOffset(rig: Model): number
	local boxCFrame, size = rig:GetBoundingBox()
	return rig:GetPivot().Position.Y - (boxCFrame.Position.Y - size.Y / 2)
end

function StageArtistService.Refresh(player: Player)
	local index = PlotService.GetPlotId(player)
	local data = DataService.GetProfile(player)
	if not index then
		return
	end
	clearArtists(index)
	local model = MapService.GetPlotModel(index)
	local stage = if model then model:FindFirstChild("Stage") else nil
	local root = if stage and stage:IsA("Model") then Assets.GetRoot(stage) else nil
	if not data or not model or not root then
		Diag.Log("StageArtists", player.Name .. ": sem palco/Root ainda — artistas colocados quando o palco existir")
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	local placed = 0
	for slot, uid in data.EquippedArtists do
		local artist = data.Artists[uid]
		local attachment = root:FindFirstChild("Artist_" .. slot)
		if artist and attachment and attachment:IsA("Attachment") then
			local rig = Assets.GetArtistTemplate(artist.Id):Clone()
			rig.Name = "Artist_" .. slot
			rig:SetAttribute("ArtistId", artist.Id)
			rig:SetAttribute("Rarity", artist.Rarity)
			rig:SetAttribute("Stars", artist.Stars)
			rig:SetAttribute("OwnerUserId", player.UserId)
			decorate(rig, artist)
			rig:PivotTo(attachment.WorldCFrame * CFrame.new(0, footOffset(rig), 0))
			-- Posição de referência para a dança no cliente (replica junto com o modelo)
			rig:SetAttribute("BaseCFrame", rig:GetPivot())
			rig.Parent = folder
			placed += 1
		end
	end
	folder.Parent = model
	Diag.Log(
		"StageArtists",
		string.format("%s: %d/%d artistas colocados no palco (Tier %s)", player.Name, placed, #data.EquippedArtists, tostring(stage and stage:GetAttribute("Tier")))
	)
end

-- Agrupa vários pedidos no mesmo frame (equipar + commit + troca de palco)
local function schedule(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if player.Parent then
			StageArtistService.Refresh(player)
		end
	end)
end

function StageArtistService.Init()
	trove:Add(ArtistService.EquippedChanged:Connect(schedule))
	trove:Add(StageService.StagePlaced:Connect(schedule))
	trove:Add(PlotService.PlotReleased:Connect(function(_player: Player, index: number)
		clearArtists(index)
	end))
end

function StageArtistService.Start() end

return StageArtistService
