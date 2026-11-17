--!strict
--[[
	ShowcaseService
	Vitrine (Fase 10): pedestal à frente de cada terreno ocupado com um artista do dono.
	  - Automático: o melhor por raridade -> estrelas -> bónus (IndexCalc.PickShowcase),
	    atualiza sozinho sempre que a coleção muda
	  - Manual: o artista escolhido pelo jogador (remote SetShowcase); se deixar de existir,
	    volta a Automático
	O servidor coloca o pedestal e o modelo e grava a posição base no atributo
	"BaseCFrame"; o cliente (ShowcaseController) só anima, com LOD por distância.
	Modelos: Assets.GetShowcasePedestalTemplate e Assets.GetArtistTemplate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ShowcaseConfig = require(ReplicatedStorage.Shared.Config.Showcase)
local MapConfig = require(ReplicatedStorage.Shared.Config.Map)
local LodConfig = require(ReplicatedStorage.Shared.Config.Lod)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local IndexCalc = require(ReplicatedStorage.Shared.Calc.IndexCalc)
local MapCalc = require(ReplicatedStorage.Shared.Calc.MapCalc)
local Assets = require(script.Parent.Parent.World.Assets)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local PlotService = require(script.Parent.PlotService)
local MapService = require(script.Parent.MapService)
local ArtistService = require(script.Parent.ArtistService)
local IndexService = require(script.Parent.IndexService)

type ArtistData = Types.ArtistData
type RarityDef = Types.RarityDef

local FOLDER_NAME = "Showcase"

local ShowcaseService = {}

local STAT_INTERVAL = 2 -- s entre atualizações da linha do Hype

local trove = Trove.new()
local pending: { [Player]: boolean } = {}
local shown: { [number]: string } = {} -- terreno -> "uid|id|raridade|estrelas" em exibição
local shownUid: { [number]: string } = {} -- terreno -> uid do artista na vitrine
local statLabels: { [number]: TextLabel } = {} -- terreno -> linha do Hype no letreiro
local updateStat: (player: Player, index: number) -> ()

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 255, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(40, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 200)),
})

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

local function getFolder(index: number, create: boolean): Folder?
	local model = MapService.GetPlotModel(index)
	if not model then
		return nil
	end
	local existing = model:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if not create then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = model
	return folder
end

local function clear(index: number)
	local folder = getFolder(index, false)
	if folder then
		folder:Destroy()
	end
	shown[index] = nil
	shownUid[index] = nil
	statLabels[index] = nil
end

-- Pedestal no chão do terreno, entre a placa e o spawn, virado para a praça
local function ensurePedestal(index: number, folder: Folder): CFrame
	local ground = MapCalc.PlotPoint(index, ShowcaseConfig.OffsetX, MapConfig.Plots.BaseThickness, ShowcaseConfig.Depth)
	local pedestal = folder:FindFirstChild("Pedestal")
	if not pedestal or not pedestal:IsA("Model") then
		local model = Assets.GetShowcasePedestalTemplate():Clone()
		model.Name = "Pedestal"
		local root = Assets.GetRoot(model)
		local rootHeight = if root then root.Size.Y / 2 else 0
		Assets.PivotRoot(model, ground * CFrame.new(0, rootHeight, 0))
		model.Parent = folder
		pedestal = model
	end
	local root = if pedestal and pedestal:IsA("Model") then Assets.GetRoot(pedestal) else nil
	local spot = if root then root:FindFirstChild("ArtistSpot") else nil
	if spot and spot:IsA("Attachment") then
		return spot.WorldCFrame
	end
	return ground * CFrame.new(0, ShowcaseConfig.PedestalHeight, 0)
end

-- Devolve o TextLabel do Hype (atualizado pelo statLoop)
local function addNameplate(rig: Model, data: ArtistData, rarity: RarityDef, ownerName: string): TextLabel?
	local head = rig:FindFirstChild("Head")
	local adornee = if head and head:IsA("BasePart") then head else rig.PrimaryPart
	if not adornee then
		return nil
	end
	local def = ArtistCalc.GetArtist(data.Id)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromScale(9, 3.4)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.MaxDistance = LodConfig.Showcase.LabelDistance
	billboard.LightInfluence = 0
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local function label(name: string, text: string, y: number, height: number, font: Enum.Font, color: Color3): TextLabel
		local textLabel = Instance.new("TextLabel")
		textLabel.Name = name
		textLabel.BackgroundTransparency = 1
		textLabel.Position = UDim2.fromScale(0, y)
		textLabel.Size = UDim2.fromScale(1, height)
		textLabel.Font = font
		textLabel.TextScaled = true
		textLabel.TextColor3 = color
		textLabel.TextStrokeTransparency = 0.3
		textLabel.Text = text
		textLabel.Parent = billboard
		return textLabel
	end
	label("Owner", "Vitrine de " .. ownerName, 0, 0.17, Enum.Font.GothamBold, Color3.fromRGB(200, 190, 230))
	label("Name", if def then def.Name else data.Id, 0.17, 0.32, Enum.Font.FredokaOne, Color3.new(1, 1, 1))
	local rarityLabel = label("Rarity", rarity.Name .. " " .. string.rep("★", data.Stars), 0.49, 0.26, Enum.Font.GothamBold, rarity.Color)
	if rarity.Effect == "Gradient" or rarity.Effect == "Rainbow" then
		rarityLabel.TextColor3 = Color3.new(1, 1, 1)
		local gradient = Instance.new("UIGradient")
		gradient.Color = if rarity.Effect == "Rainbow" then RAINBOW else ColorSequence.new(rarity.Color, Color3.new(1, 1, 1))
		gradient.Parent = rarityLabel
	end
	return label("Hype", "", 0.75, 0.25, Enum.Font.GothamBold, Color3.fromRGB(255, 209, 102))
end

-- Cor da raridade (placeholder), luz e aura nas raridades com efeito
local function decorate(rig: Model, rarity: RarityDef)
	if rig:GetAttribute("Placeholder") == true then
		for _, descendant in rig:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= rig.PrimaryPart and descendant.Name ~= "HumanoidRootPart" then
				descendant.Color = rarity.Color
				descendant.Material = if rarity.Effect == "None" then Enum.Material.SmoothPlastic else Enum.Material.Neon
			end
		end
	end
	local root = rig.PrimaryPart
	if root and rarity.Effect ~= "None" then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 14
		light.Brightness = 2
		light.Parent = root
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "Aura"
		aura.Color = ColorSequence.new(rarity.Color)
		aura.LightEmission = 1
		aura.Rate = 8 + 30 * rarity.Aura
		aura.Lifetime = NumberRange.new(0.8, 1.4)
		aura.Speed = NumberRange.new(1, 3)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Size = NumberSequence.new(0.6, 0)
		aura.Acceleration = Vector3.new(0, 3, 0)
		aura.Parent = root
	end
end

--[[
	Linha do Hype da vitrine: "+X% Hype" (bónus do artista) e, se estiver no palco,
	"≈ N Hype/s" = a parte do Hype/s passivo atual que vem deste artista
	(Hype/s × bónus ÷ multiplicador total dos artistas).
]]
updateStat = function(player: Player, index: number)
	local labelRef = statLabels[index]
	local uid = shownUid[index]
	local data = DataService.GetProfile(player)
	local artist = if data and uid then data.Artists[uid] else nil
	if not labelRef or not labelRef.Parent or not data or not uid or not artist then
		return
	end
	local bonus = ArtistCalc.GetBonus(artist)
	local text = string.format("+%s%% Hype", NumberFormatter.format(bonus * 100))
	if table.find(data.EquippedArtists, uid) then
		local multiplier = math.max(ArtistService.GetEffects(player).HypeMultiplier, 1)
		local share = BigNum.mulNumber(EconomyService.GetHypePerSecond(player), bonus / multiplier)
		text ..= " · ≈ " .. NumberFormatter.format(share) .. " Hype/s"
	else
		text ..= " · fora do palco"
	end
	labelRef.Text = text
end

local function statLoop()
	while true do
		task.wait(STAT_INTERVAL)
		for index in statLabels do
			local owner = PlotService.GetOwner(index)
			if owner then
				updateStat(owner, index)
			end
		end
	end
end

local function footOffset(rig: Model): number
	local boxCFrame, size = rig:GetBoundingBox()
	return rig:GetPivot().Position.Y - (boxCFrame.Position.Y - size.Y / 2)
end

function ShowcaseService.Refresh(player: Player)
	local index = PlotService.GetPlotId(player)
	local data = DataService.GetProfile(player)
	if not index or not data then
		return
	end
	-- Manual com um artista que já não existe -> volta a Automático
	local showcase = data.Showcase
	if showcase.Mode == "Manual" and not data.Artists[showcase.Uid] then
		showcase.Mode = "Auto"
		showcase.Uid = ""
		IndexService.MarkDirty(player)
	end

	local folder = getFolder(index, true)
	if not folder then
		return
	end
	local spot = ensurePedestal(index, folder)
	local uid = IndexCalc.ResolveShowcase(data.Artists, showcase.Mode, showcase.Uid)
	local artist = if uid then data.Artists[uid] else nil
	local key = if uid and artist then string.format("%s|%s|%s|%d|%s", uid, artist.Id, artist.Rarity, artist.Stars, artist.Variant) else ""
	if shown[index] == key then
		return
	end
	shown[index] = key

	local old = folder:FindFirstChild("Artist")
	if old then
		old:Destroy()
	end
	statLabels[index] = nil
	shownUid[index] = nil
	local rarity = if artist then ArtistCalc.GetRarity(artist.Rarity) else nil
	if not uid or not artist or not rarity then
		return
	end
	local rig = Assets.GetArtistTemplate(artist.Id):Clone()
	rig.Name = "Artist"
	rig:SetAttribute("ArtistId", artist.Id)
	rig:SetAttribute("Rarity", artist.Rarity)
	rig:SetAttribute("Stars", artist.Stars)
	rig:SetAttribute("Variant", artist.Variant) -- visual da variante aplicado no cliente
	rig:SetAttribute("OwnerUserId", player.UserId)
	decorate(rig, rarity)
	local hypeLabel = addNameplate(rig, artist, rarity, player.DisplayName)
	if hypeLabel then
		statLabels[index] = hypeLabel
	end
	shownUid[index] = uid
	updateStat(player, index)
	rig:PivotTo(spot * CFrame.new(0, footOffset(rig), 0))
	-- Posição base para a animação no cliente (replica junto com o modelo)
	rig:SetAttribute("BaseCFrame", rig:GetPivot())
	rig.Parent = folder
	Diag.Log("Showcase", string.format("%s: vitrine com %s · %s", player.Name, artist.Id, artist.Rarity))
end

-- Agrupa vários pedidos no mesmo frame
local function schedule(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if player.Parent == Players then
			ShowcaseService.Refresh(player)
		end
	end)
end

-- Muda o modo da vitrine; devolve a mensagem para o jogador
function ShowcaseService.Set(player: Player, mode: string, uid: string): (boolean, string)
	local data = DataService.GetProfile(player)
	if not data then
		return false, "Perfil não carregado."
	end
	if mode == "Manual" then
		local artist = data.Artists[uid]
		if not artist then
			return false, "Artista não encontrado."
		end
		data.Showcase.Mode = "Manual"
		data.Showcase.Uid = uid
	else
		data.Showcase.Mode = "Auto"
		data.Showcase.Uid = ""
	end
	schedule(player)
	IndexService.MarkDirty(player)
	if mode == "Manual" then
		local artist = data.Artists[uid]
		local def = ArtistCalc.GetArtist(artist.Id)
		return true, string.format("%s está agora na tua vitrine!", if def then def.Name else artist.Id)
	end
	return true, "Vitrine em modo Automático (o teu melhor artista)."
end

function ShowcaseService.Init()
	ServerNet.Connect(RemoteDefs.Defs.SetShowcase, function(player: Player, modeArg: unknown, uidArg: unknown)
		local _, message = ShowcaseService.Set(player, modeArg :: string, uidArg :: string)
		notify(player, message)
	end)
	trove:Add(ArtistService.EquippedChanged:Connect(schedule))
	trove:Add(PlotService.PlotAssigned:Connect(function(player: Player, _index: number)
		schedule(player)
	end))
	trove:Add(PlotService.PlotReleased:Connect(function(_player: Player, index: number)
		clear(index)
	end))
end

function ShowcaseService.Start()
	for _, player in Players:GetPlayers() do
		schedule(player)
	end
	trove:Add(task.spawn(statLoop))
end

return ShowcaseService
