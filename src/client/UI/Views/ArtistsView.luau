--!strict
--[[
	ArtistsView
	Painel central "ARTISTAS" com dois separadores:
	  CRATES   — as 5 Vinyl Crates (cadeado por tier), abertura x1/x10, pity atual,
	             botão "%" com as probabilidades de cada crate (ArtistCalc.GetCrateOdds)
	             e opção "Animação rápida". A revelação (roleta, grelha x10, cinemática)
	             é da CrateRevealView.
	  COLEÇÃO  — grelha de artistas (equipados primeiro, raridade mais alta primeiro),
	             detalhe com bónus e habilidades, equipar/desequipar, cadeado, fundir,
	             Fundir tudo, Auto-Fuse e Auto-Delete ("apagar até…")
	Abre com o botão "ARTISTAS" (canto superior direito), tecla K, D-pad ↑ do comando,
	ou ao pisar a Zona das Crates
	no centro (fecha ao sair, se foi a zona a abri-lo e ainda estiver em CRATES).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local ArtistsConfig = require(ReplicatedStorage.Shared.Config.Artists)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local StageCalc = require(ReplicatedStorage.Shared.Calc.StageCalc)
local PrestigeCalc = require(ReplicatedStorage.Shared.Calc.PrestigeCalc)

local Client = script.Parent.Parent.Parent
local StateController = require(Client.Controllers.StateController)
local ArtistController = require(Client.Controllers.ArtistController)
local CrateZoneController = require(Client.Controllers.CrateZoneController)
local CrateAnimController = require(Client.Controllers.CrateAnimController)
local VariantCalc = require(ReplicatedStorage.Shared.Calc.VariantCalc)
local TraitCalc = require(ReplicatedStorage.Shared.Calc.TraitCalc)
local VariantsConfig = require(ReplicatedStorage.Shared.Config.Variants)
local IndexController = require(Client.Controllers.IndexController)
local AutoOpenController = require(Client.Controllers.AutoOpenController)
local AutoOpenView = require(script.Parent.AutoOpenView)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local ModalManager = require(script.Parent.Parent.ModalManager)
local SideMenu = require(script.Parent.Parent.SideMenu)

type ArtistData = Types.ArtistData
type ArtistsSync = Types.ArtistsSync
type CrateDef = Types.CrateDef
type CrateOdd = Types.CrateOdd
type CrateResult = Types.CrateResult
type RarityDef = Types.RarityDef
type Snapshot = Types.PlayerStateSnapshot

export type Tab = "Crates" | "Collection"

type CrateCard = {
	Def: CrateDef,
	Info: TextLabel,
	One: TextButton,
	Ten: TextButton,
	Lock: TextLabel,
	Odds: TextButton,
	Auto: TextButton, -- Auto-Abrir (só com o Gamepass)
}

local PANEL_SIZE = Vector2.new(740, 640)
local HEADER = 64
local DETAILS_HEIGHT = 118
local STAGE_ROW_Y = 72
local STAGE_ROW_HEIGHT = 68
local GRID_Y = STAGE_ROW_Y + STAGE_ROW_HEIGHT + 8
local TOGGLE_KEY = Enum.KeyCode.K
local TOGGLE_GAMEPAD = Enum.KeyCode.DPadUp
local CRATE_REVEAL_MODAL = "CrateReveal" -- nome registado pela CrateRevealView

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 255, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(40, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 200)),
})

local ArtistsView = {}

local activeTrove: Trove.Trove? = nil
local setOpenImpl: ((boolean) -> ())? = nil
local setTabImpl: ((Tab) -> ())? = nil
local isOpen = false

-- Helpers --------------------------------------------------------------------

local function rarityOf(data: ArtistData): RarityDef
	return RaritiesConfig.ById[data.Rarity] or RaritiesConfig.List[1]
end

local function applyRarityStyle(target: GuiObject, rarity: RarityDef)
	local existing = target:FindFirstChildOfClass("UIGradient")
	if existing then
		existing:Destroy()
	end
	target.BackgroundColor3 = rarity.Color
	if rarity.Effect == "Gradient" or rarity.Effect == "Rainbow" then
		local gradient = Instance.new("UIGradient")
		gradient.Color = if rarity.Effect == "Rainbow" then RAINBOW else ColorSequence.new(rarity.Color, Color3.new(1, 1, 1))
		gradient.Rotation = 45
		gradient.Parent = target
	end
end

local function textButton(name: string, text: string, color: Color3, size: UDim2): TextButton
	local button = Components.makeButton(name, color)
	button.Size = size
	button.Font = Theme.Fonts.Display
	button.TextColor3 = Theme.Colors.Text
	button.TextScaled = true
	button.Text = text
	Components.addCorner(button, UDim.new(0, 10))
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = button
	return button
end

local function shake(target: GuiObject)
	target.Rotation = 5
	TweenService:Create(target, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
end

local function sortedUids(sync: ArtistsSync): { string }
	local equippedSet: { [string]: boolean } = {}
	for _, uid in sync.Equipped do
		equippedSet[uid] = true
	end
	local uids: { string } = {}
	for uid in sync.Artists do
		table.insert(uids, uid)
	end
	table.sort(uids, function(a: string, b: string): boolean
		local artistA, artistB = sync.Artists[a], sync.Artists[b]
		local equippedA, equippedB = equippedSet[a] == true, equippedSet[b] == true
		if equippedA ~= equippedB then
			return equippedA
		end
		local rarityA, rarityB = ArtistCalc.GetRarityIndex(artistA.Rarity), ArtistCalc.GetRarityIndex(artistB.Rarity)
		if rarityA ~= rarityB then
			return rarityA > rarityB
		end
		if artistA.Stars ~= artistB.Stars then
			return artistA.Stars > artistB.Stars
		end
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return uids
end

local function effectsSummary(sync: ArtistsSync): string
	local effects = sync.Effects
	local parts = { "Hype ×" .. NumberFormatter.format(effects.HypeMultiplier) }
	if effects.ClickBonus > 0 then
		table.insert(parts, string.format("Batida +%d%%", math.floor(effects.ClickBonus * 100 + 0.5)))
	end
	if effects.EnergyBonus > 0 then
		table.insert(parts, string.format("Energia +%d%%", math.floor(effects.EnergyBonus * 100 + 0.5)))
	end
	if effects.WindowBonus > 0 then
		table.insert(parts, string.format("Janela +%.2fs", effects.WindowBonus))
	end
	if effects.BoostBonus > 0 then
		table.insert(parts, string.format("Boost +%.1fs", effects.BoostBonus))
	end
	if effects.PassiveBonus > 0 then
		table.insert(parts, string.format("Passivo +%d%%", math.floor(effects.PassiveBonus * 100 + 0.5)))
	end
	if effects.CooldownCut > 0 then
		table.insert(parts, string.format("Cooldowns −%d%%", math.floor(effects.CooldownCut * 100 + 0.5)))
	end
	if effects.AutoPyroMask ~= 0 then
		table.insert(parts, "Pirotecnia automática")
	end
	if #effects.SaveDrops > 0 then
		table.insert(parts, "Salva-Drop ×" .. #effects.SaveDrops)
	end
	return table.concat(parts, "  ·  ")
end

local function formatChance(chance: number): string
	local value = chance * 100
	if math.abs(value - math.floor(value + 0.5)) < 1e-6 then
		return string.format("%d%%", math.floor(value + 0.5))
	end
	return string.format("%.2f%%", value)
end

local function windowLabel(crate: CrateDef): string
	local first, last = ArtistCalc.GetCrateWindow(crate)
	return RaritiesConfig.List[first].Name .. " → " .. RaritiesConfig.List[last].Name
end

local function autoDeleteLabel(upTo: number): string
	if upTo <= 0 then
		return "Auto-Delete: OFF"
	end
	return "Apagar até: " .. RaritiesConfig.List[upTo].Name
end

-- Montagem -------------------------------------------------------------------

function ArtistsView.Mount()
	if activeTrove then
		return
	end
	local trove = Trove.new()
	activeTrove = trove

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Botão ARTISTAS (menu lateral, por baixo de PALCOS) --------------------
	local toggleGui = trove:Add(Instance.new("ScreenGui"))
	toggleGui.Name = "ArtistsToggleGui"
	toggleGui.ResetOnSpawn = false
	toggleGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local toggleHolder = Components.makeFrame("ArtistsToggle")
	toggleHolder.Size = UDim2.fromOffset(112, 100)
	trove:Add(toggleHolder)

	local toggleScale = Instance.new("UIScale")
	toggleScale.Parent = toggleHolder

	local toggleButton = Components.makeButton("Button", Theme.Colors.Panel)
	toggleButton.Size = UDim2.fromScale(1, 1)
	Components.addCorner(toggleButton, UDim.new(0, 22))
	Components.addStroke(toggleButton, Theme.Colors.Gold, 3)
	toggleButton.Parent = toggleHolder

	local toggleLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Text, 22)
	toggleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleLabel.Position = UDim2.fromScale(0.5, 0.42)
	toggleLabel.Size = UDim2.new(0.9, 0, 0, 28)
	toggleLabel.Text = "ARTISTAS"
	Components.addStroke(toggleLabel, Theme.Colors.Background, 2)
	toggleLabel.Parent = toggleButton

	local toggleHint = Components.makeLabel("Hint", Theme.Fonts.Body, Theme.Colors.TextMuted, 16)
	toggleHint.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleHint.Position = UDim2.fromScale(0.5, 0.74)
	toggleHint.Size = UDim2.new(0.8, 0, 0, 18)
	toggleHint.Text = "[K]"
	toggleHint.Visible = UserInputService.KeyboardEnabled
	toggleHint.Parent = toggleButton

	SideMenu.Attach(toggleHolder, 4)

	-- Painel ---------------------------------------------------------------
	local panelGui = trove:Add(Instance.new("ScreenGui"))
	panelGui.Name = "ArtistsPanelGui"
	panelGui.ResetOnSpawn = false
	panelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	panelGui.ScreenInsets = Enum.ScreenInsets.None
	panelGui.DisplayOrder = 10

	local overlay = Components.makeButton("Overlay", Theme.Colors.Overlay)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.Parent = panelGui

	local panelHolder = Components.makeFrame("PanelHolder")
	panelHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	panelHolder.Position = UDim2.fromScale(0.5, 0.5)
	panelHolder.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panelHolder.Visible = false
	panelHolder.Parent = panelGui

	local fitScale = Instance.new("UIScale")
	fitScale.Parent = panelHolder

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	Components.addCorner(panel, UDim.new(0, 20))
	Components.addStroke(panel, Theme.Colors.Gold, 3)
	panel.Parent = panelHolder

	local popScale = Instance.new("UIScale")
	popScale.Parent = panel

	local closeButton = textButton("Close", "X", Theme.Colors.Danger, UDim2.fromOffset(46, 46))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 12)
	closeButton.Parent = panel

	local tabBar = Components.makeFrame("Tabs")
	tabBar.Position = UDim2.fromOffset(20, 12)
	tabBar.Size = UDim2.new(1, -100, 0, 46)
	tabBar.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local tabButtons: { [Tab]: TextButton } = {
		Crates = textButton("Crates", "VINYL CRATES", Theme.Colors.Background, UDim2.new(0.5, -4, 1, 0)),
		Collection = textButton("Collection", "COLEÇÃO", Theme.Colors.Background, UDim2.new(0.5, -4, 1, 0)),
	}
	tabButtons.Crates.LayoutOrder = 1
	tabButtons.Collection.LayoutOrder = 2
	tabButtons.Crates.Parent = tabBar
	tabButtons.Collection.Parent = tabBar

	local function makePage(name: string): Frame
		local page = Components.makeFrame(name)
		page.Position = UDim2.fromOffset(0, HEADER)
		page.Size = UDim2.new(1, 0, 1, -HEADER)
		page.Visible = false
		page.Parent = panel
		return page
	end
	local cratesPage = makePage("CratesPage")
	local collectionPage = makePage("CollectionPage")

	-- ======================= CRATES =======================
	local pityLabel = Components.makeLabel("Pity", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
	pityLabel.Position = UDim2.fromOffset(20, 4)
	pityLabel.Size = UDim2.new(1, -260, 0, 20)
	pityLabel.TextXAlignment = Enum.TextXAlignment.Left
	pityLabel.Parent = cratesPage

	-- "Animação rápida" (guardada no perfil pelo servidor)
	local fastButton = textButton("FastAnim", "Animação rápida: OFF", Theme.Colors.Background, UDim2.fromOffset(220, 24))
	fastButton.AnchorPoint = Vector2.new(1, 0)
	fastButton.Position = UDim2.new(1, -20, 0, 2)
	fastButton.Parent = cratesPage
	trove:Connect(fastButton.Activated, function()
		local snapshot = StateController.Get()
		local enabled = snapshot ~= nil and snapshot.FastCrateAnim == true
		if not CrateAnimController.SetFast(not enabled) then
			shake(fastButton)
		end
	end)

	local crateList = Instance.new("ScrollingFrame")
	crateList.Name = "Crates"
	crateList.Position = UDim2.fromOffset(16, 30)
	crateList.Size = UDim2.new(1, -32, 1, -46)
	crateList.BackgroundTransparency = 1
	crateList.BorderSizePixel = 0
	crateList.ScrollBarThickness = 6
	crateList.ScrollBarImageColor3 = Theme.Colors.Gold
	crateList.CanvasSize = UDim2.new()
	crateList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	crateList.Parent = cratesPage
	local crateLayout = Instance.new("UIListLayout")
	crateLayout.Padding = UDim.new(0, 8)
	crateLayout.SortOrder = Enum.SortOrder.LayoutOrder
	crateLayout.Parent = crateList
	local cratePadding = Instance.new("UIPadding")
	cratePadding.PaddingRight = UDim.new(0, 10)
	cratePadding.Parent = crateList

	-- Probabilidades de uma crate (janela por cima da lista)
	local odds = Instance.new("Frame")
	odds.Name = "Odds"
	odds.Size = UDim2.fromScale(1, 1)
	odds.BackgroundColor3 = Theme.Colors.Background
	odds.BackgroundTransparency = 0.03
	odds.BorderSizePixel = 0
	odds.Visible = false
	odds.ZIndex = 30
	odds.Active = true
	Components.addCorner(odds, UDim.new(0, 16))
	odds.Parent = cratesPage

	local oddsTitle = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 26)
	oddsTitle.Position = UDim2.fromOffset(20, 8)
	oddsTitle.Size = UDim2.new(1, -40, 0, 30)
	oddsTitle.ZIndex = 31
	oddsTitle.Parent = odds

	local oddsList = Components.makeFrame("Rows")
	oddsList.Position = UDim2.fromOffset(40, 46)
	oddsList.Size = UDim2.new(1, -80, 0, 6 * 44)
	oddsList.ZIndex = 31
	oddsList.Parent = odds
	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.Padding = UDim.new(0, 6)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = oddsList

	local oddsArtists = Components.makeLabel("Artists", Theme.Fonts.Body, Theme.Colors.Text, 15)
	oddsArtists.Position = UDim2.new(0, 40, 0, 46 + 6 * 44 + 8)
	oddsArtists.Size = UDim2.new(1, -80, 0, 40)
	oddsArtists.TextWrapped = true
	oddsArtists.TextXAlignment = Enum.TextXAlignment.Left
	oddsArtists.TextYAlignment = Enum.TextYAlignment.Top
	oddsArtists.ZIndex = 31
	oddsArtists.Parent = odds

	local oddsPity = Components.makeLabel("Pity", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
	oddsPity.Position = UDim2.new(0, 40, 0, 46 + 6 * 44 + 52)
	oddsPity.Size = UDim2.new(1, -80, 0, 22)
	oddsPity.TextXAlignment = Enum.TextXAlignment.Left
	oddsPity.ZIndex = 31
	oddsPity.Parent = odds

	local oddsVariants = Components.makeLabel("Variants", Theme.Fonts.Body, Theme.Colors.Highlight, 14)
	oddsVariants.Position = UDim2.new(0, 40, 0, 46 + 6 * 44 + 80)
	oddsVariants.Size = UDim2.new(1, -80, 0, 40)
	oddsVariants.TextWrapped = true
	oddsVariants.TextXAlignment = Enum.TextXAlignment.Left
	oddsVariants.TextYAlignment = Enum.TextYAlignment.Top
	oddsVariants.ZIndex = 31
	do
		local parts: { string } = {}
		for _, variant in VariantsConfig.List do
			table.insert(parts, string.format("%s 1/%d", variant.Name, variant.Chance))
		end
		oddsVariants.Text = string.format("Variantes Brilhantes (cada artista, %.2f%% no total): %s", VariantCalc.GetAnyChance() * 100, table.concat(parts, " · "))
	end
	oddsVariants.Parent = odds

	local oddsClose = textButton("Close", "FECHAR", Theme.Colors.Accent, UDim2.fromOffset(220, 48))
	oddsClose.AnchorPoint = Vector2.new(0.5, 1)
	oddsClose.Position = UDim2.new(0.5, 0, 1, -12)
	oddsClose.ZIndex = 31
	oddsClose.Parent = odds

	local oddsCrate: CrateDef? = nil

	local function renderOdds()
		local crate = oddsCrate
		if not crate then
			return
		end
		oddsTitle.Text = "Probabilidades · " .. crate.Name
		for _, child in oddsList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for _, odd: CrateOdd in ArtistCalc.GetCrateOdds(crate) do
			local row = Instance.new("Frame")
			row.Name = odd.Rarity.Id
			row.LayoutOrder = odd.Slot
			row.Size = UDim2.new(1, 0, 0, 38)
			row.BorderSizePixel = 0
			row.ZIndex = 32
			Components.addCorner(row, UDim.new(0, 10))
			applyRarityStyle(row, odd.Rarity)
			row.Parent = oddsList

			local name = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 20)
			name.Position = UDim2.fromOffset(14, 0)
			name.Size = UDim2.new(0.7, -14, 1, 0)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.ZIndex = 33
			name.Text = odd.Rarity.Name
			Components.addStroke(name, Theme.Colors.Background, 2)
			name.Parent = row

			local chance = Components.makeLabel("Chance", Theme.Fonts.Display, Theme.Colors.Text, 20)
			chance.AnchorPoint = Vector2.new(1, 0)
			chance.Position = UDim2.new(1, -14, 0, 0)
			chance.Size = UDim2.new(0.3, 0, 1, 0)
			chance.TextXAlignment = Enum.TextXAlignment.Right
			chance.ZIndex = 33
			chance.Text = formatChance(odd.Chance)
			Components.addStroke(chance, Theme.Colors.Background, 2)
			chance.Parent = row
		end

		local artists = ArtistCalc.GetCrateArtists(crate)
		local names: { string } = {}
		for _, def in artists do
			table.insert(names, def.Name)
		end
		oddsArtists.Text = string.format(
			"Artistas (%s cada): %s",
			formatChance(if #artists > 0 then 1 / #artists else 0),
			table.concat(names, ", ")
		)

		local levels = ArtistCalc.GetCratePityLevels(crate)
		if #levels == 0 then
			oddsPity.Text = "Pity: nenhum patamar conta nesta crate."
		else
			local snapshot = StateController.Get()
			local sync = ArtistController.Get()
			local skills = PrestigeCalc.GetSkillEffects(if snapshot then snapshot.SkillTree else {})
			local counters: { [string]: number } = if sync then (sync.Pity :: unknown) :: { [string]: number } else {}
			local parts: { string } = {}
			for _, level in levels do
				local threshold = ArtistCalc.GetPityThreshold(level, skills.PityReduction)
				table.insert(parts, string.format("%s %d/%d", level.Label, counters[level.Key] or 0, threshold))
			end
			oddsPity.Text = "Pity nesta crate: " .. table.concat(parts, "  ·  ")
		end
	end

	local function openOdds(crate: CrateDef)
		oddsCrate = crate
		renderOdds()
		odds.Visible = true
	end

	trove:Connect(oddsClose.Activated, function()
		oddsCrate = nil
		odds.Visible = false
	end)

	local crateCards: { CrateCard } = {}
	for index, crate in ArtistsConfig.Crates do
		local card = Instance.new("Frame")
		card.Name = crate.Id
		card.LayoutOrder = index
		card.Size = UDim2.new(1, 0, 0, 92)
		card.BackgroundColor3 = Theme.Colors.Background
		card.BorderSizePixel = 0
		Components.addCorner(card, UDim.new(0, 14))
		Components.addStroke(card, Theme.Colors.Gold, 1.5).Transparency = 0.4
		card.Parent = crateList

		local title = Components.makeLabel("Title", Theme.Fonts.Display, Theme.Colors.Gold, 22)
		title.Position = UDim2.fromOffset(16, 10)
		title.Size = UDim2.new(1, -400, 0, 26)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = crate.Name
		title.TextColor3 = crate.Color
		title.Parent = card

		local info = Components.makeLabel("Info", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
		info.Position = UDim2.fromOffset(16, 40)
		info.Size = UDim2.new(1, -400, 0, 40)
		info.TextWrapped = true
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextYAlignment = Enum.TextYAlignment.Top
		info.Parent = card

		local one = textButton("One", "x1", Theme.Colors.Success, UDim2.fromOffset(112, 64))
		one.AnchorPoint = Vector2.new(1, 0.5)
		one.Position = UDim2.new(1, -132, 0.5, 0)
		one.Parent = card

		local ten = textButton("Ten", "x10", Theme.Colors.Success, UDim2.fromOffset(112, 64))
		ten.AnchorPoint = Vector2.new(1, 0.5)
		ten.Position = UDim2.new(1, -12, 0.5, 0)
		ten.Parent = card

		local lock = Components.makeLabel("Lock", Theme.Fonts.Display, Theme.Colors.TextMuted, 20)
		lock.AnchorPoint = Vector2.new(1, 0.5)
		lock.Position = UDim2.new(1, -12, 0.5, 0)
		lock.Size = UDim2.fromOffset(230, 40)
		lock.Visible = false
		lock.Parent = card

		local oddsButton = textButton("Odds", "%", Theme.Colors.Accent, UDim2.fromOffset(48, 48))
		oddsButton.AnchorPoint = Vector2.new(1, 0.5)
		oddsButton.Position = UDim2.new(1, -254, 0.5, 0)
		oddsButton.Parent = card
		trove:Connect(oddsButton.Activated, function()
			openOdds(crate)
		end)

		-- Auto-Abrir (Gamepass): abre o painel das condições
		local autoButton = textButton("Auto", "AUTO", Theme.Colors.Gold, UDim2.fromOffset(72, 48))
		autoButton.AnchorPoint = Vector2.new(1, 0.5)
		autoButton.Position = UDim2.new(1, -312, 0.5, 0)
		autoButton.TextColor3 = Theme.Colors.Background
		autoButton.Visible = false
		autoButton.Parent = card
		trove:Connect(autoButton.Activated, function()
			AutoOpenView.OpenConfig(crate)
		end)

		local entry: CrateCard = { Def = crate, Info = info, One = one, Ten = ten, Lock = lock, Odds = oddsButton, Auto = autoButton }
		table.insert(crateCards, entry)

		for _, pair in { { one, 1 }, { ten, 10 } } do
			local button = pair[1] :: TextButton
			local count = pair[2] :: number
			trove:Connect(button.Activated, function()
				local snapshot = StateController.Get()
				if not snapshot or snapshot.StageTier < crate.RequiredTier then
					shake(button)
					return
				end
				local cut = PrestigeCalc.GetSkillEffects(snapshot.SkillTree).CrateCostCut
				local cost = BigNum.fromNumber(crate.Cost * count * (1 - math.clamp(cut, 0, 0.9)))
				if BigNum.lt(BigNum.deserialize(snapshot.Hype), cost) or not ArtistController.OpenCrate(crate.Id, count) then
					shake(button)
				end
			end)
		end
	end

	-- A revelação dos resultados (roleta, grelha x10, cinemática) é da CrateRevealView

	-- ======================= COLEÇÃO =======================
	local topBar = Components.makeFrame("TopBar")
	topBar.Position = UDim2.fromOffset(16, 4)
	topBar.Size = UDim2.new(1, -32, 0, 40)
	topBar.Parent = collectionPage
	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.Padding = UDim.new(0, 8)
	topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Parent = topBar

	local slotsLabel = Components.makeLabel("Slots", Theme.Fonts.Display, Theme.Colors.Gold, 18)
	slotsLabel.LayoutOrder = 1
	slotsLabel.Size = UDim2.fromOffset(112, 34)
	slotsLabel.TextXAlignment = Enum.TextXAlignment.Left
	slotsLabel.Parent = topBar

	local autoFuseButton = textButton("AutoFuse", "Auto-Fuse: OFF", Theme.Colors.Background, UDim2.fromOffset(150, 36))
	autoFuseButton.LayoutOrder = 2
	autoFuseButton.Parent = topBar

	local autoDeleteButton = textButton("AutoDelete", "Auto-Delete: OFF", Theme.Colors.Background, UDim2.fromOffset(170, 36))
	autoDeleteButton.LayoutOrder = 3
	autoDeleteButton.Parent = topBar

	local fuseAllButton = textButton("FuseAll", "FUNDIR TUDO", Theme.Colors.Accent, UDim2.fromOffset(130, 36))
	fuseAllButton.LayoutOrder = 4
	fuseAllButton.Parent = topBar

	-- O Auto-Delete nunca apaga variantes Brilhantes, salvo se o jogador ligar isto
	local variantsButton = textButton("Variants", "🛡 Brilhantes", Theme.Colors.Background, UDim2.fromOffset(112, 36))
	variantsButton.LayoutOrder = 5
	variantsButton.Parent = topBar

	local effectsLabel = Components.makeLabel("Effects", Theme.Fonts.Body, Theme.Colors.Highlight, 14)
	effectsLabel.Position = UDim2.fromOffset(18, 48)
	effectsLabel.Size = UDim2.new(1, -36, 0, 18)
	effectsLabel.TextXAlignment = Enum.TextXAlignment.Left
	effectsLabel.Parent = collectionPage

	-- Fila "NO PALCO": slots 1..7 (equipados, vazios ou bloqueados) + EQUIPAR MELHORES
	local stageRow = Instance.new("Frame")
	stageRow.Name = "StageRow"
	stageRow.Position = UDim2.fromOffset(16, STAGE_ROW_Y)
	stageRow.Size = UDim2.new(1, -32, 0, STAGE_ROW_HEIGHT)
	stageRow.BackgroundColor3 = Theme.Colors.Background
	stageRow.BorderSizePixel = 0
	Components.addCorner(stageRow, UDim.new(0, 12))
	Components.addStroke(stageRow, Theme.Colors.Gold, 1.5).Transparency = 0.3
	stageRow.Parent = collectionPage

	local stageRowLabel = Components.makeLabel("Label", Theme.Fonts.Display, Theme.Colors.Gold, 14)
	stageRowLabel.Position = UDim2.fromOffset(10, 4)
	stageRowLabel.Size = UDim2.fromOffset(60, STAGE_ROW_HEIGHT - 8)
	stageRowLabel.TextWrapped = true
	stageRowLabel.Text = "NO\nPALCO"
	stageRowLabel.Parent = stageRow

	local slotStrip = Components.makeFrame("Slots")
	slotStrip.Position = UDim2.fromOffset(74, 6)
	slotStrip.Size = UDim2.new(1, -(74 + 186), 1, -12)
	slotStrip.Parent = stageRow
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.Padding = UDim.new(0, 6)
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	slotLayout.Parent = slotStrip

	local equipBestButton = textButton("EquipBest", "EQUIPAR MELHORES", Theme.Colors.Success, UDim2.fromOffset(172, 52))
	equipBestButton.AnchorPoint = Vector2.new(1, 0.5)
	equipBestButton.Position = UDim2.new(1, -8, 0.5, 0)
	equipBestButton.Parent = stageRow

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(16, GRID_Y)
	grid.Size = UDim2.new(1, -32, 1, -(GRID_Y + DETAILS_HEIGHT + 16))
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = Theme.Colors.Gold
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = collectionPage
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(104, 112)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingRight = UDim.new(0, 10)
	gridPadding.PaddingTop = UDim.new(0, 2)
	gridPadding.Parent = grid

	local emptyLabel = Components.makeLabel("Empty", Theme.Fonts.Body, Theme.Colors.TextMuted, 18)
	emptyLabel.Position = UDim2.fromOffset(16, GRID_Y + 40)
	emptyLabel.Size = UDim2.new(1, -32, 0, 40)
	emptyLabel.Text = "Ainda não tens artistas. Abre uma Vinyl Crate!"
	emptyLabel.Visible = false
	emptyLabel.Parent = collectionPage

	-- Detalhe do artista selecionado
	local details = Instance.new("Frame")
	details.Name = "Details"
	details.AnchorPoint = Vector2.new(0, 1)
	details.Position = UDim2.new(0, 16, 1, -12)
	details.Size = UDim2.new(1, -32, 0, DETAILS_HEIGHT)
	details.BackgroundColor3 = Theme.Colors.Background
	details.BorderSizePixel = 0
	Components.addCorner(details, UDim.new(0, 14))
	details.Parent = collectionPage

	local detailName = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 22)
	detailName.Position = UDim2.fromOffset(14, 8)
	detailName.Size = UDim2.new(1, -260, 0, 26)
	detailName.TextXAlignment = Enum.TextXAlignment.Left
	detailName.Parent = details

	local detailText = Instance.new("TextLabel")
	detailText.Name = "Text"
	detailText.BackgroundTransparency = 1
	detailText.Position = UDim2.fromOffset(14, 36)
	detailText.Size = UDim2.new(1, -380, 1, -42)
	detailText.Font = Theme.Fonts.Body
	detailText.TextSize = 14
	detailText.TextWrapped = true
	detailText.TextXAlignment = Enum.TextXAlignment.Left
	detailText.TextYAlignment = Enum.TextYAlignment.Top
	detailText.TextColor3 = Theme.Colors.TextMuted
	detailText.Text = "Seleciona um artista para ver o detalhe."
	detailText.Parent = details

	local equipButton = textButton("Equip", "EQUIPAR", Theme.Colors.Success, UDim2.fromOffset(112, 46))
	equipButton.AnchorPoint = Vector2.new(1, 0)
	equipButton.Position = UDim2.new(1, -126, 0, 10)
	equipButton.Parent = details

	local lockButton = textButton("Lock", "🔒", Theme.Colors.Panel, UDim2.fromOffset(112, 46))
	lockButton.AnchorPoint = Vector2.new(1, 0)
	lockButton.Position = UDim2.new(1, -10, 0, 10)
	lockButton.Parent = details

	local fuseButton = textButton("Fuse", "FUNDIR 3→1", Theme.Colors.Accent, UDim2.fromOffset(228, 44))
	fuseButton.AnchorPoint = Vector2.new(1, 1)
	fuseButton.Position = UDim2.new(1, -10, 1, -10)
	fuseButton.Parent = details

	-- Vitrine: põe/tira este artista do pedestal à frente do terreno
	local showcaseButton = textButton("Showcase", "VITRINE", Theme.Colors.Highlight, UDim2.fromOffset(112, 44))
	showcaseButton.AnchorPoint = Vector2.new(1, 1)
	showcaseButton.Position = UDim2.new(1, -246, 1, -10)
	showcaseButton.Parent = details

	-- Estado / desenho ---------------------------------------------------------
	local currentTab: Tab = "Crates"
	local openedByZone = false -- o painel atual foi aberto pela Zona das Crates
	local selectedUid: string? = nil
	local collectionDirty = true

	local function refreshCrates()
		local snapshot = StateController.Get()
		local sync = ArtistController.Get()
		local skills = PrestigeCalc.GetSkillEffects(if snapshot then snapshot.SkillTree else {})
		if sync then
			local counters = (sync.Pity :: unknown) :: { [string]: number }
			local parts: { string } = {}
			for _, level in RaritiesConfig.PityLadder do
				local threshold = ArtistCalc.GetPityThreshold(level, skills.PityReduction)
				table.insert(parts, string.format("%s %d/%d", level.Label, counters[level.Key] or 0, threshold))
			end
			pityLabel.Text = "Pity — " .. table.concat(parts, "  ·  ")
		end
		if odds.Visible then
			renderOdds()
		end
		local fast = snapshot ~= nil and snapshot.FastCrateAnim == true
		fastButton.Text = if fast then "Animação rápida: ON" else "Animação rápida: OFF"
		fastButton.BackgroundColor3 = if fast then Theme.Colors.Success else Theme.Colors.Background
		local budget = if snapshot then BigNum.deserialize(snapshot.Hype) else BigNum.ZERO
		local tier = if snapshot then snapshot.StageTier else 1
		local costFactor = 1 - math.clamp(skills.CrateCostCut, 0, 0.9)
		local ownsAuto = AutoOpenController.Owns()
		for _, card in crateCards do
			local crate = card.Def
			local unlocked = tier >= crate.RequiredTier
			card.One.Visible = unlocked
			card.Ten.Visible = unlocked
			card.Lock.Visible = not unlocked
			card.Auto.Visible = unlocked and ownsAuto
			if unlocked then
				local unitCost = crate.Cost * costFactor
				card.Info.Text = string.format(
					"%s · %s por abertura · bónus da era ×%d",
					windowLabel(crate),
					NumberFormatter.format(unitCost),
					crate.EraFactor
				)
				card.One.Text = "x1  " .. NumberFormatter.format(unitCost)
				card.Ten.Text = "x10  " .. NumberFormatter.format(unitCost * 10)
				card.One.BackgroundColor3 = if BigNum.gte(budget, BigNum.fromNumber(unitCost))
					then Theme.Colors.Success
					else Theme.Colors.Disabled
				card.Ten.BackgroundColor3 = if BigNum.gte(budget, BigNum.fromNumber(unitCost * 10))
					then Theme.Colors.Success
					else Theme.Colors.Disabled
			else
				card.Info.Text = string.format("%s · bónus da era ×%d", windowLabel(crate), crate.EraFactor)
				card.Lock.Text = string.format("🔒 Tier %d · %s", crate.RequiredTier, StageCalc.GetDef(crate.RequiredTier).Name)
			end
		end
	end

	local function refreshDetails(sync: ArtistsSync)
		local uid = selectedUid
		local artist = if uid then sync.Artists[uid] else nil
		equipButton.Visible = artist ~= nil
		lockButton.Visible = artist ~= nil
		fuseButton.Visible = artist ~= nil
		showcaseButton.Visible = artist ~= nil
		if not uid or not artist then
			detailName.Text = "Detalhe"
			detailText.Text = "Seleciona um artista para ver o detalhe."
			return
		end
		local def = ArtistCalc.GetArtist(artist.Id)
		local rarity = rarityOf(artist)
		detailName.Text = string.format("%s · %s %s", if def then def.Name else artist.Id, rarity.Name, string.rep("★", artist.Stars))
		detailName.TextColor3 = rarity.Color

		local lines = { string.format("Bónus de Hype: +%s%%", NumberFormatter.format(ArtistCalc.GetBonus(artist) * 100)) }
		local variant = VariantCalc.Get(artist.Variant)
		if variant then
			table.insert(lines, string.format("Variante Brilhante: %s (+%d%% ao bónus)", variant.Name, math.floor(variant.Bonus * 100 + 0.5)))
		end
		table.insert(lines, "Traço: " .. TraitCalc.Describe(artist.Trait, artist.TraitTier) .. "  (uid " .. uid .. ")")
		for _, ability in ArtistCalc.GetAbilities(artist) do
			table.insert(lines, ArtistCalc.DescribeAbility(ability))
		end
		if artist.Stars < ArtistsConfig.MaxStars then
			local copies = 0
			local key = ArtistCalc.GroupKey(artist)
			for _, other in sync.Artists do
				if ArtistCalc.GroupKey(other) == key and not other.Locked then
					copies += 1
				end
			end
			table.insert(lines, string.format("Cópias iguais para fundir: %d/%d", copies, ArtistsConfig.FuseCount))
			fuseButton.BackgroundColor3 = if copies >= ArtistsConfig.FuseCount and not artist.Locked
				then Theme.Colors.Accent
				else Theme.Colors.Disabled
			fuseButton.Text = string.format("FUNDIR → %d★", artist.Stars + 1)
		else
			table.insert(lines, "Estrelas máximas (Platinum).")
			fuseButton.BackgroundColor3 = Theme.Colors.Disabled
			fuseButton.Text = "MÁXIMO"
		end
		detailText.Text = table.concat(lines, "\n")

		local equipped = table.find(sync.Equipped, uid) ~= nil
		equipButton.Text = if equipped then "DESEQUIPAR" else "EQUIPAR"
		equipButton.BackgroundColor3 = if equipped
			then Theme.Colors.Danger
			elseif #sync.Equipped < sync.Slots then Theme.Colors.Success
			else Theme.Colors.Disabled
		lockButton.Text = if artist.Locked then "🔒 PROTEGIDO" else "🔓 LIVRE"
		local index = IndexController.Get()
		local onShowcase = index ~= nil and index.ShowcaseUid == uid
		local manual = onShowcase and index ~= nil and index.Showcase.Mode == "Manual"
		showcaseButton.Text = if manual then "✓ VITRINE" elseif onShowcase then "VITRINE (AUTO)" else "VITRINE"
		showcaseButton.BackgroundColor3 = if manual then Theme.Colors.Success else Theme.Colors.Highlight
	end

	local gridTrove = trove:Extend() -- tiles e ligações da grelha, limpos a cada reconstrução

	local function rebuildGrid(sync: ArtistsSync)
		collectionDirty = false
		gridTrove:Clean()
		local uids = sortedUids(sync)
		emptyLabel.Visible = #uids == 0
		if selectedUid and not sync.Artists[selectedUid] then
			selectedUid = nil
		end

		for order, uid in uids do
			local artist = sync.Artists[uid]
			local rarity = rarityOf(artist)
			local def = ArtistCalc.GetArtist(artist.Id)
			local equipped = table.find(sync.Equipped, uid) ~= nil

			local tile = gridTrove:Add(Components.makeButton("Artist_" .. uid, Theme.Colors.Background))
			tile.LayoutOrder = order
			Components.addCorner(tile, UDim.new(0, 12))
			local stroke = Components.addStroke(tile, if uid == selectedUid then Theme.Colors.Gold else rarity.Color, if uid == selectedUid then 3 else 1.5)
			stroke.Transparency = 0
			tile.Parent = grid

			local band = Instance.new("Frame")
			band.Name = "Band"
			band.Size = UDim2.new(1, 0, 0, 30)
			band.BorderSizePixel = 0
			Components.addCorner(band, UDim.new(0, 12))
			applyRarityStyle(band, rarity)
			band.Parent = tile

			local rarityLabel = Components.makeLabel("Rarity", Theme.Fonts.Display, Theme.Colors.Text, 15)
			rarityLabel.Size = UDim2.new(1, -8, 0, 26)
			rarityLabel.Position = UDim2.fromOffset(4, 2)
			rarityLabel.Text = rarity.Name
			Components.addStroke(rarityLabel, Theme.Colors.Background, 1.5)
			rarityLabel.Parent = band

			local nameLabel = Components.makeLabel("Name", Theme.Fonts.Body, Theme.Colors.Text, 14)
			nameLabel.Position = UDim2.fromOffset(4, 34)
			nameLabel.Size = UDim2.new(1, -8, 0, 36)
			nameLabel.TextWrapped = true
			nameLabel.Text = if def then def.Name else artist.Id
			nameLabel.Parent = tile

			local starsLabel = Components.makeLabel("Stars", Theme.Fonts.Display, Theme.Colors.Gold, 16)
			starsLabel.Position = UDim2.fromOffset(4, 72)
			starsLabel.Size = UDim2.new(1, -8, 0, 18)
			starsLabel.Text = string.rep("★", artist.Stars) .. string.rep("☆", ArtistsConfig.MaxStars - artist.Stars)
			starsLabel.Parent = tile

			local tags: { string } = {}
			if equipped then
				table.insert(tags, "NO PALCO")
			end
			if artist.Locked then
				table.insert(tags, "🔒")
			end
			local variant = VariantCalc.Get(artist.Variant)
			if variant then
				table.insert(tags, "★" .. variant.Name)
				stroke.Color = if uid == selectedUid then Theme.Colors.Gold else variant.Color
				stroke.Thickness = 3
			end
			local tagLabel = Components.makeLabel("Tags", Theme.Fonts.Body, Theme.Colors.Success, 12)
			tagLabel.Position = UDim2.fromOffset(4, 92)
			tagLabel.Size = UDim2.new(1, -8, 0, 16)
			tagLabel.Text = table.concat(tags, " ")
			tagLabel.Parent = tile

			gridTrove:Connect(tile.Activated, function()
				selectedUid = uid
				local latest = ArtistController.Get()
				if latest then
					task.defer(rebuildGrid, latest) -- adiado: não destruir o botão dentro do seu próprio evento
				end
			end)
		end

		-- Fila "NO PALCO"
		for slot = 1, ArtistsConfig.MaxSlots do
			local uid = sync.Equipped[slot]
			local artist = if uid then sync.Artists[uid] else nil
			local unlocked = slot <= sync.Slots

			local slotButton = gridTrove:Add(Components.makeButton("Slot_" .. slot, Theme.Colors.Panel))
			slotButton.LayoutOrder = slot
			slotButton.Size = UDim2.fromOffset(52, 52)
			Components.addCorner(slotButton, UDim.new(0, 10))
			slotButton.Parent = slotStrip

			local slotLabel = Components.makeLabel("Label", Theme.Fonts.Body, Theme.Colors.Text, 11)
			slotLabel.Size = UDim2.new(1, -4, 1, -4)
			slotLabel.Position = UDim2.fromOffset(2, 2)
			slotLabel.TextWrapped = true
			slotLabel.Parent = slotButton

			if uid and artist then
				local rarity = rarityOf(artist)
				local def = ArtistCalc.GetArtist(artist.Id)
				applyRarityStyle(slotButton, rarity)
				local stroke = Components.addStroke(slotButton, if uid == selectedUid then Theme.Colors.Gold else Theme.Colors.Text, if uid == selectedUid then 3 else 1)
				stroke.Transparency = if uid == selectedUid then 0 else 0.5
				slotLabel.Text = (if def then def.Name else artist.Id) .. "\n" .. string.rep("★", artist.Stars)
				Components.addStroke(slotLabel, Theme.Colors.Background, 1.5)
				gridTrove:Connect(slotButton.Activated, function()
					selectedUid = uid
					local latest = ArtistController.Get()
					if latest then
						task.defer(rebuildGrid, latest)
					end
				end)
			elseif unlocked then
				slotLabel.Text = "vazio"
				slotLabel.TextColor3 = Theme.Colors.TextMuted
				Components.addStroke(slotButton, Theme.Colors.TextMuted, 1).Transparency = 0.5
			else
				slotButton.BackgroundColor3 = Theme.Colors.Disabled
				slotLabel.Text = "🔒"
				slotLabel.TextColor3 = Theme.Colors.TextMuted
			end
		end

		slotsLabel.Text = string.format("Palco: %d/%d slots", #sync.Equipped, sync.Slots)
		autoFuseButton.Text = if sync.AutoFuse then "Auto-Fuse: ON" else "Auto-Fuse: OFF"
		autoFuseButton.BackgroundColor3 = if sync.AutoFuse then Theme.Colors.Success else Theme.Colors.Background
		autoDeleteButton.Text = autoDeleteLabel(sync.AutoDeleteUpTo)
		autoDeleteButton.BackgroundColor3 = if sync.AutoDeleteUpTo > 0 then Theme.Colors.Danger else Theme.Colors.Background
		variantsButton.Text = if sync.AutoDeleteVariants then "🗑 Brilhantes" else "🛡 Brilhantes"
		variantsButton.BackgroundColor3 = if sync.AutoDeleteVariants then Theme.Colors.Danger else Theme.Colors.Success
		effectsLabel.Text = effectsSummary(sync)
		refreshDetails(sync)
	end

	local function refreshCollection()
		local sync = ArtistController.Get()
		if sync and isOpen and currentTab == "Collection" then
			rebuildGrid(sync)
		else
			collectionDirty = true
		end
	end

	-- Ações da coleção -------------------------------------------------------------
	trove:Connect(equipButton.Activated, function()
		local sync = ArtistController.Get()
		local uid = selectedUid
		if not sync or not uid then
			return
		end
		if table.find(sync.Equipped, uid) then
			ArtistController.Unequip(uid)
		elseif #sync.Equipped >= sync.Slots then
			shake(equipButton)
		else
			ArtistController.Equip(uid)
		end
	end)
	trove:Connect(lockButton.Activated, function()
		local sync = ArtistController.Get()
		local uid = selectedUid
		local artist = if sync and uid then sync.Artists[uid] else nil
		if uid and artist then
			ArtistController.SetLock(uid, not artist.Locked)
		end
	end)
	trove:Connect(fuseButton.Activated, function()
		local uid = selectedUid
		if not uid or fuseButton.BackgroundColor3 == Theme.Colors.Disabled then
			shake(fuseButton)
			return
		end
		ArtistController.Fuse(uid)
	end)
	trove:Connect(showcaseButton.Activated, function()
		local uid = selectedUid
		if not uid then
			return
		end
		local index = IndexController.Get()
		local manualHere = index ~= nil and index.Showcase.Mode == "Manual" and index.Showcase.Uid == uid
		local ok = if manualHere then IndexController.SetShowcase("Auto") else IndexController.SetShowcase("Manual", uid)
		if not ok then
			shake(showcaseButton)
		end
	end)
	trove:Connect(fuseAllButton.Activated, function()
		ArtistController.Fuse("all")
	end)
	trove:Connect(equipBestButton.Activated, function()
		local sync = ArtistController.Get()
		local hasArtists = sync ~= nil and next(sync.Artists) ~= nil
		if not hasArtists or not ArtistController.EquipBest() then
			shake(equipBestButton)
		end
	end)
	trove:Connect(autoFuseButton.Activated, function()
		local sync = ArtistController.Get()
		if sync then
			ArtistController.SetAutoFuse(not sync.AutoFuse)
		end
	end)
	trove:Connect(variantsButton.Activated, function()
		local sync = ArtistController.Get()
		if sync then
			ArtistController.SetAutoDeleteVariants(not sync.AutoDeleteVariants)
		end
	end)
	trove:Connect(autoDeleteButton.Activated, function()
		local sync = ArtistController.Get()
		if sync then
			ArtistController.SetAutoDelete((sync.AutoDeleteUpTo + 1) % (ArtistsConfig.AutoDeleteMaxIndex + 1))
		end
	end)

	-- Separadores / abrir / fechar --------------------------------------------------
	local function setTab(tab: Tab)
		currentTab = tab
		cratesPage.Visible = tab == "Crates"
		collectionPage.Visible = tab == "Collection"
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == tab then Theme.Colors.Accent else Theme.Colors.Background
		end
		if tab == "Crates" then
			refreshCrates()
		elseif collectionDirty then
			refreshCollection()
		end
	end
	setTabImpl = setTab

	local function setOpen(open: boolean)
		if isOpen == open then
			return
		end
		isOpen = open
		if open then
			ModalManager.NotifyOpened("Artists")
			overlay.Visible = true
			panelHolder.Visible = true
			popScale.Scale = 0.85
			TweenService:Create(popScale, Theme.Tween.Toast, { Scale = 1 }):Play()
			TweenService:Create(overlay, Theme.Tween.Fast, { BackgroundTransparency = Theme.Shop.OverlayTransparency }):Play()
			setTab(currentTab)
		else
			openedByZone = false
			ModalManager.NotifyClosed("Artists")
			local closing = TweenService:Create(popScale, Theme.Tween.FadeOut, { Scale = 0.85 })
			TweenService:Create(overlay, Theme.Tween.FadeOut, { BackgroundTransparency = 1 }):Play()
			closing.Completed:Once(function()
				if not isOpen then
					overlay.Visible = false
					panelHolder.Visible = false
				end
			end)
			closing:Play()
		end
	end
	setOpenImpl = setOpen
	ModalManager.Register("Artists", function()
		setOpen(false)
	end)
	trove:Add(function()
		ModalManager.Unregister("Artists")
	end)

	for name, button in tabButtons do
		trove:Connect(button.Activated, function()
			setTab(name)
		end)
	end
	trove:Connect(toggleButton.Activated, function()
		setOpen(not isOpen)
	end)
	trove:Connect(closeButton.Activated, function()
		setOpen(false)
	end)
	trove:Connect(overlay.Activated, function()
		setOpen(false)
	end)
	trove:Connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == TOGGLE_KEY or input.KeyCode == TOGGLE_GAMEPAD then
			setOpen(not isOpen)
		end
	end)

	-- Zona das Crates: abre ao entrar; fecha ao sair só se foi a zona a abrir e ainda
	-- estiver em CRATES. Fechar à mão dentro da zona não reabre até sair e voltar.
	trove:Add(CrateZoneController.Entered:Connect(function()
		-- Nunca abrir por cima da abertura de uma crate (cancelaria a roleta/cinemática)
		if ModalManager.GetActive() == CRATE_REVEAL_MODAL then
			return
		end
		if not isOpen then
			setTab("Crates")
			setOpen(true)
			openedByZone = true
		end
	end))
	trove:Add(CrateZoneController.Exited:Connect(function()
		if openedByZone and isOpen and currentTab == "Crates" then
			setOpen(false)
		end
		openedByZone = false
	end))

	-- A vitrine mudou (botão VITRINE no detalhe)
	trove:Add(IndexController.Changed:Connect(function()
		local sync = ArtistController.Get()
		if sync and isOpen and currentTab == "Collection" then
			refreshDetails(sync)
		end
	end))
	trove:Add(ArtistController.Changed:Connect(function(_sync: ArtistsSync)
		refreshCollection()
		if isOpen and currentTab == "Crates" then
			refreshCrates()
		end
	end))
	-- A CrateRevealView abre por cima (e fecha este painel pelo ModalManager)
	trove:Add(ArtistController.CrateOpened:Connect(function(_result: CrateResult)
		oddsCrate = nil
		odds.Visible = false
	end))
	trove:Add(StateController.Changed:Connect(function(_snapshot: Snapshot)
		if isOpen and currentTab == "Crates" then
			refreshCrates()
		end
	end))

	local function updateScales()
		fitScale.Scale = Components.fitScale(panelGui.AbsoluteSize, PANEL_SIZE, Theme.Shop.ScreenFill)
		toggleScale.Scale = Components.computeScale(toggleGui.AbsoluteSize)
	end
	trove:Connect(panelGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)
	trove:Connect(toggleGui:GetPropertyChangedSignal("AbsoluteSize"), updateScales)

	toggleGui.Parent = playerGui
	panelGui.Parent = playerGui
	updateScales()
	setTab("Crates")
end

function ArtistsView.Open(tab: Tab?)
	local setTab = setTabImpl
	if tab and setTab then
		setTab(tab)
	end
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(true)
	end
end

function ArtistsView.Close()
	local setOpen = setOpenImpl
	if setOpen then
		setOpen(false)
	end
end

return ArtistsView
