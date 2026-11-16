--!strict
--[[
	VipPage
	Conteúdo do separador "VIP" da loja: Gamepasses (ATIVO / comprar) e Developer
	Products. Preços em Robux lidos do Roblox (cache); IDs a 0 aparecem como "Em breve".
	A compra é feita pelo Roblox; o servidor entrega (ProcessReceipt / compra de Gamepass).
	Caixas da sorte (produtos com Random = true): probabilidades exatas visíveis antes de
	comprar (ArtistCalc.GetOdds) e secção escondida a quem o Roblox proíbe itens aleatórios
	pagos (PolicyService.ArePaidRandomItemsRestricted; na dúvida, escondida).
]]

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.Monetization)
local PaidCratesConfig = require(ReplicatedStorage.Shared.Config.PaidCrates)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local Client = script.Parent.Parent.Parent
local RetentionController = require(Client.Controllers.RetentionController)
local StateController = require(Client.Controllers.StateController)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)

type Row = {
	Key: string,
	Id: number,
	IsGamepass: boolean,
	Button: TextButton,
}

local CARD_HEIGHT = 78
local LUCKY_COLOR = Color3.fromRGB(120, 255, 150)
local FAMILY_LABELS: { { string } } = {
	{ "Common", "Comum" },
	{ "Rare", "Raro" },
	{ "Epic", "Épico" },
	{ "Legendary", "Lendário" },
	{ "Mythic", "Mítico+" },
}

local VipPage = {}

local function percent(chance: number): string
	local value = chance * 100
	if value >= 10 then
		return string.format("%.1f%%", value)
	elseif value >= 0.1 then
		return string.format("%.2f%%", value)
	end
	return string.format("%.4f%%", value)
end

-- Probabilidades do produto (nil se não for aleatório)
local function getProductOdds(def: Types.ProductDef): { ArtistCalc.RarityOdds }?
	local paid = def.Reward.PaidCrate
	if paid then
		local minIndex, luck = ArtistCalc.GetPaidCrateRoll(paid.Kind)
		return ArtistCalc.GetOdds(minIndex, luck)
	end
	if def.Reward.LuckMinutes then
		return ArtistCalc.GetOdds(1, ArtistCalc.GetPotionLuck(math.huge, 0))
	end
	return nil
end

local function familySummary(odds: { ArtistCalc.RarityOdds }): string
	local families = ArtistCalc.GetFamilyOdds(odds)
	local parts: { string } = {}
	for _, entry in FAMILY_LABELS do
		local chance = families[entry[1]]
		if chance and chance > 0 then
			table.insert(parts, entry[2] .. " " .. percent(chance))
		end
	end
	return table.concat(parts, " · ")
end

local function fullOdds(odds: { ArtistCalc.RarityOdds }): string
	local parts: { string } = {}
	for _, entry in odds do
		table.insert(parts, entry.Rarity.Name .. " " .. percent(entry.Chance))
	end
	return table.concat(parts, " · ")
end

-- true só se o Roblox confirmar que este jogador pode comprar itens aleatórios pagos
local function canBuyRandomItems(): boolean
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(Players.LocalPlayer)
	end)
	if not ok or type(info) ~= "table" then
		return false
	end
	return (info :: { [string]: unknown }).ArePaidRandomItemsRestricted == false
end

local function section(parent: Instance, text: string, order: number)
	local label = Components.makeLabel("Section", Theme.Fonts.Display, Theme.Colors.Gold, 20)
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 26)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
end

local function card(parent: Instance, order: number, name: string, description: string, accent: Color3): TextButton
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BorderSizePixel = 0
	Components.addCorner(frame, UDim.new(0, 14))
	Components.addStroke(frame, accent, 1.5).Transparency = 0.3
	frame.Parent = parent

	local nameLabel = Components.makeLabel("Name", Theme.Fonts.Display, Theme.Colors.Text, 20)
	nameLabel.Position = UDim2.fromOffset(16, 10)
	nameLabel.Size = UDim2.new(1, -210, 0, 24)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = name
	nameLabel.Parent = frame

	local descriptionLabel = Components.makeLabel("Description", Theme.Fonts.Body, Theme.Colors.TextMuted, 15)
	descriptionLabel.Position = UDim2.fromOffset(16, 38)
	descriptionLabel.Size = UDim2.new(1, -210, 0, 32)
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.Text = description
	descriptionLabel.Parent = frame

	local button = Components.makeButton("Buy", Theme.Colors.Disabled)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.fromOffset(170, 54)
	button.Font = Theme.Fonts.Display
	button.TextColor3 = Theme.Colors.Text
	button.TextScaled = true
	Components.addCorner(button, UDim.new(0, 12))
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 20
	constraint.Parent = button
	button.Parent = frame
	return button
end

-- Constrói o separador dentro de `page` e devolve a função de atualização
function VipPage.Build(page: Instance, trove: Trove.Trove): () -> ()
	local list = Instance.new("ScrollingFrame")
	list.Name = "VipList"
	list.Position = UDim2.fromOffset(16, 6)
	list.Size = UDim2.new(1, -32, 1, -22)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Colors.Gold
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = list

	local rows: { Row } = {}
	section(list, "GAMEPASSES (permanentes)", 0)
	for index, def in MonetizationConfig.Gamepasses do
		local button = card(list, index, def.Name, def.Description, Theme.Colors.Gold)
		table.insert(rows, { Key = def.Key, Id = def.Id, IsGamepass = true, Button = button })
		trove:Connect(button.Activated, function()
			if not RetentionController.Owns(def.Key) then
				RetentionController.PromptGamepass(def.Id)
			end
		end)
	end
	section(list, "PACOTES", 100)
	for index, def in MonetizationConfig.Products do
		if not def.Random then
			local button = card(list, 100 + index, def.Name, def.Description, Theme.Colors.Highlight)
			table.insert(rows, { Key = def.Key, Id = def.Id, IsGamepass = false, Button = button })
			trove:Connect(button.Activated, function()
				RetentionController.PromptProduct(def.Id)
			end)
		end
	end

	-- Caixas da sorte: escondidas até o Roblox confirmar que este jogador as pode comprar
	local luckyItems: { GuiObject } = {}
	local luckySection = Components.makeLabel("Section", Theme.Fonts.Display, Theme.Colors.Gold, 20)
	luckySection.LayoutOrder = 200
	luckySection.Size = UDim2.new(1, 0, 0, 26)
	luckySection.TextXAlignment = Enum.TextXAlignment.Left
	luckySection.Text = "CAIXAS DA SORTE"
	luckySection.Visible = false
	luckySection.Parent = list
	table.insert(luckyItems, luckySection)

	local potionLabel = Components.makeLabel("Potion", Theme.Fonts.Body, LUCKY_COLOR, 16)
	potionLabel.LayoutOrder = 201
	potionLabel.Size = UDim2.new(1, 0, 0, 20)
	potionLabel.TextXAlignment = Enum.TextXAlignment.Left
	potionLabel.Visible = false
	potionLabel.Parent = list

	local order = 202
	for _, def in MonetizationConfig.Products do
		local odds = getProductOdds(def)
		if def.Random and odds then
			local button = card(list, order, def.Name, def.Description .. " " .. familySummary(odds), LUCKY_COLOR)
			local cardFrame = button.Parent :: Frame
			cardFrame.Visible = false
			table.insert(luckyItems, cardFrame)
			table.insert(rows, { Key = def.Key, Id = def.Id, IsGamepass = false, Button = button })
			trove:Connect(button.Activated, function()
				RetentionController.PromptProduct(def.Id)
			end)

			-- Todas as raridades (expande ao tocar)
			local oddsToggle = Components.makeButton("OddsToggle", Theme.Colors.Panel)
			oddsToggle.LayoutOrder = order + 1
			oddsToggle.Size = UDim2.new(1, 0, 0, 26)
			oddsToggle.Font = Theme.Fonts.Body
			oddsToggle.TextSize = 15
			oddsToggle.TextColor3 = Theme.Colors.TextMuted
			oddsToggle.Text = "▸ Probabilidades de todas as raridades"
			oddsToggle.Visible = false
			Components.addCorner(oddsToggle, UDim.new(0, 8))
			oddsToggle.Parent = list
			table.insert(luckyItems, oddsToggle)

			local oddsLabel = Instance.new("TextLabel")
			oddsLabel.Name = "Odds"
			oddsLabel.BackgroundTransparency = 1
			oddsLabel.LayoutOrder = order + 2
			oddsLabel.Size = UDim2.new(1, 0, 0, 0)
			oddsLabel.AutomaticSize = Enum.AutomaticSize.Y
			oddsLabel.Font = Theme.Fonts.Body
			oddsLabel.TextSize = 14
			oddsLabel.TextColor3 = Theme.Colors.TextMuted
			oddsLabel.TextWrapped = true
			oddsLabel.TextXAlignment = Enum.TextXAlignment.Left
			oddsLabel.Text = fullOdds(odds) .. " (o pity continua a contar como numa crate normal)"
			oddsLabel.Visible = false
			oddsLabel.Parent = list
			trove:Connect(oddsToggle.Activated, function()
				oddsLabel.Visible = not oddsLabel.Visible
				oddsToggle.Text = (if oddsLabel.Visible then "▾" else "▸") .. " Probabilidades de todas as raridades"
			end)
			order += 3
		end
	end

	-- Tempo restante da Poção da Sorte
	local luckyAllowed = false
	local function refreshPotion()
		local snapshot = StateController.Get()
		local remaining = if snapshot then snapshot.LuckUntil - os.time() else 0
		potionLabel.Visible = luckyAllowed and remaining > 0
		if remaining > 0 then
			potionLabel.Text = string.format(
				"🍀 Poção ativa: sorte ×%d durante mais %d min",
				PaidCratesConfig.LuckPotion.Multiplier,
				math.ceil(remaining / 60)
			)
		end
	end
	trove:Add(StateController.Changed:Connect(refreshPotion))
	trove:Add(task.spawn(function()
		luckyAllowed = canBuyRandomItems()
		for _, item in luckyItems do
			item.Visible = luckyAllowed
		end
		while true do
			refreshPotion()
			task.wait(15)
		end
	end))

	local function refresh()
		for _, row in rows do
			if row.IsGamepass and RetentionController.Owns(row.Key) then
				row.Button.Text = "✓ ATIVO"
				row.Button.BackgroundColor3 = Theme.Colors.AccentDark
			else
				row.Button.Text = RetentionController.GetPriceText(row.Id, row.IsGamepass)
				row.Button.BackgroundColor3 = if row.Id > 0 then Theme.Colors.Success else Theme.Colors.Disabled
			end
		end
	end

	trove:Add(RetentionController.Changed:Connect(function()
		task.spawn(refresh)
	end))
	return refresh
end

return VipPage
