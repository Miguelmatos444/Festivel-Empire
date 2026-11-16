--!strict
--[[
	MonetizationService
	Gamepasses (posse em cache, compra durante a sessão) e Developer Products.
	  - Hype ×2      -> EconomyService.SetGamepassMultiplier
	  - Auto-Batida  -> o SERVIDOR aplica AutoClicksPerSecond batidas a cada segundo
	                    (sem remotes do cliente); liga/desliga com SetAutoClick
	  - Agente de Tour -> GetDiscBonus (lido pelo PrestigeService)
	  - Palco VIP    -> slots tratados pelo ArtistService (mesmo id)
	ProcessReceipt idempotente: os últimos PurchaseId ficam no perfil; só devolve
	PurchaseGranted depois de gravar. Perfil por carregar -> NotProcessedYet (o Roblox repete).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.Monetization)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local RewardService = require(script.Parent.RewardService)

local MonetizationService = {}

local changed: Signal.Signal<Player> = Signal.new()

-- Posse de Gamepasses ou preferência de Auto-Batida mudou
MonetizationService.Changed = changed

local trove = Trove.new()
local owned: { [Player]: { [string]: boolean } } = {}

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

-- Gamepasses -------------------------------------------------------------------

local function applyEffects(player: Player)
	local map = owned[player] or {}
	EconomyService.SetGamepassMultiplier(player, if map.DoubleHype then MonetizationConfig.DoubleHypeMultiplier else 1)
	changed:Fire(player)
end

function MonetizationService.Owns(player: Player, key: string): boolean
	local map = owned[player]
	return map ~= nil and map[key] == true
end

function MonetizationService.GetOwnedMap(player: Player): { [string]: boolean }
	return table.clone(owned[player] or {})
end

function MonetizationService.GetDiscBonus(player: Player): number
	return if MonetizationService.Owns(player, "TourAgent") then MonetizationConfig.TourAgentDiscBonus else 0
end

-- Debug: força a posse (testar sem IDs reais)
function MonetizationService.DebugSetOwned(player: Player, key: string, value: boolean)
	local map = owned[player] or {}
	owned[player] = map
	map[key] = if value then true else nil
	applyEffects(player)
end

local function refreshOwnership(player: Player)
	local map: { [string]: boolean } = {}
	for _, def in MonetizationConfig.Gamepasses do
		if def.Id > 0 then
			local ok, result = pcall(function(): boolean
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
			end)
			if ok and result then
				map[def.Key] = true
			end
		end
	end
	if player.Parent == Players then
		owned[player] = map
		applyEffects(player)
	end
end

-- Auto-Batida ------------------------------------------------------------------

function MonetizationService.SetAutoClick(player: Player, enabled: boolean)
	local data = DataService.GetProfile(player)
	if not data then
		return
	end
	if enabled and not MonetizationService.Owns(player, "AutoClicker") then
		notify(player, "A Auto-Batida precisa do Gamepass na loja VIP.")
		enabled = false
	end
	data.AutoClick = enabled
	changed:Fire(player)
end

local function autoClickLoop()
	while true do
		task.wait(1)
		for player, map in owned do
			if map.AutoClicker then
				local data = DataService.GetProfile(player)
				if data and data.AutoClick then
					EconomyService.ApplyClicks(player, MonetizationConfig.AutoClicksPerSecond)
				end
			end
		end
	end
end

-- Developer Products -------------------------------------------------------------

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	-- `any`: o Roblox entrega o recibo como dicionário não tipado
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = if player then DataService.GetProfile(player) else nil
	if not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(data.Receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- já entregue antes
	end
	local product = MonetizationConfig.ProductById[receipt.ProductId]
	if not product then
		warn("[MonetizationService] Produto desconhecido: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local description = RewardService.Grant(player, product.Reward)
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > MonetizationConfig.MaxStoredReceipts do
		table.remove(data.Receipts, 1)
	end
	notify(player, string.format("Obrigado! %s: %s", product.Name, description))
	Diag.Log("Monetization", string.format("%s comprou %s (%s)", player.Name, product.Key, purchaseId))

	-- Só confirma depois de gravar; se falhar, o recibo já está no perfil (não duplica)
	if not DataService.SaveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Debug: entrega a recompensa de um produto sem compra
function MonetizationService.DebugGrantProduct(player: Player, key: string): string?
	for _, product in MonetizationConfig.Products do
		if product.Key == key then
			return RewardService.Grant(player, product.Reward)
		end
	end
	return nil
end

-- Ciclo de vida --------------------------------------------------------------

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	ServerNet.Connect(RemoteDefs.Defs.SetAutoClick, function(player: Player, enabledArg: unknown)
		MonetizationService.SetAutoClick(player, enabledArg :: boolean)
	end)

	trove:Connect(MarketplaceService.PromptGamePassPurchaseFinished, function(player: Player, gamepassId: number, purchased: boolean)
		if not purchased then
			return
		end
		for _, def in MonetizationConfig.Gamepasses do
			if def.Id > 0 and def.Id == gamepassId then
				local map = owned[player] or {}
				owned[player] = map
				map[def.Key] = true
				applyEffects(player)
				notify(player, def.Name .. " ativo! " .. def.Description)
			end
		end
	end)

	trove:Add(DataService.ProfileLoaded:Connect(function(player: Player)
		applyEffects(player)
	end))
	trove:Connect(Players.PlayerAdded, function(player: Player)
		task.spawn(refreshOwnership, player)
	end)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		owned[player] = nil
	end)
end

function MonetizationService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(refreshOwnership, player)
	end
	trove:Add(task.spawn(autoClickLoop))
end

return MonetizationService
