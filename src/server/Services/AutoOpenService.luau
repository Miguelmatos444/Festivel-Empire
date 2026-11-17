--!strict
--[[
	AutoOpenService
	Auto-Abrir (Fase 13C, Gamepass "AutoOpen"). O SERVIDOR controla o ritmo:
	  - StartAutoOpen(crateId, count, stopSlot, stopNew, stopShiny): valida a posse do
	    Gamepass, grava as condições no perfil (Settings.AutoOpen) e começa o ciclo
	  - cada abertura passa por GachaService.Open (as mesmas validações de uma abertura
	    manual: tier, coleção, Hype, pity, Auto-Delete/Fuse) e usa a animação rápida
	  - intervalo mínimo entre aberturas em Config/Monetization.AutoOpen.Interval, também
	    entre arranques (recomeçar não abre mais depressa)
	  - pára: raridade na posição StopSlot da crate ou acima, artista NOVO, variante
	    Brilhante, carta mistério (sempre), Hype insuficiente / coleção cheia (sempre),
	    MaxOpens, morte, sair do jogo, StopAutoOpen (o cliente envia-o ao abrir outra UI)
	O motivo da paragem só chega ao cliente quando a animação desse resultado acaba,
	para não estragar a surpresa da roleta.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.Monetization)
local ArtistsConfig = require(ReplicatedStorage.Shared.Config.Artists)
local RaritiesConfig = require(ReplicatedStorage.Shared.Config.Rarities)
local CrateAnimConfig = require(ReplicatedStorage.Shared.Config.CrateAnimation)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local Diag = require(ReplicatedStorage.Shared.Util.Diag)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local CrateAnimCalc = require(ReplicatedStorage.Shared.Calc.CrateAnimCalc)
local VariantCalc = require(ReplicatedStorage.Shared.Calc.VariantCalc)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local MonetizationService = require(script.Parent.MonetizationService)
local GachaService = require(script.Parent.GachaService)

type CrateItem = Types.CrateItem
type AutoOpenState = Types.AutoOpenState
type AutoOpenSettings = Types.AutoOpenSettings

type Run = {
	CrateId: string,
	Count: number,
	Rules: AutoOpenSettings,
	Opened: number,
	Best: string,
	Trove: Trove.Trove,
}

local AUTO = MonetizationConfig.AutoOpen
local GAMEPASS_KEY = "AutoOpen"

local AutoOpenService = {}

local trove = Trove.new()
local runs: { [Player]: Run } = {}
local lastOpenAt: { [Player]: number } = {}

local function notify(player: Player, text: string)
	local notice: Types.Notice = { Kind = "Info", Text = text }
	PlayerStateService.Notify(player, notice)
end

local function sendState(player: Player, run: Run, running: boolean, reason: string?)
	local state: AutoOpenState = {
		Running = running,
		CrateId = run.CrateId,
		Count = run.Count,
		Opened = run.Opened,
		Best = run.Best,
		Reason = reason,
	}
	ServerNet.FireClient(RemoteDefs.Defs.AutoOpenState, player, state)
end

local function intervalFor(count: number): number
	return AUTO.Interval[count] or AUTO.Interval[1]
end

-- Segundos até a animação deste resultado mostrar a carta (rápida, como no Auto-Abrir)
local function revealDelay(items: { CrateItem }?): number
	if not items or #items == 0 then
		return 0
	end
	local base = CrateAnimCalc.GetCinematicDelay(#items, true, false) - CrateAnimConfig.MysteryPause
	if CrateAnimCalc.GetBestMystery(items) then
		local phases = CrateAnimCalc.GetPhases(true)
		return base + CrateAnimConfig.MysteryPause + (CrateAnimCalc.GetPhaseStart(phases, "Reveal") or 0)
	end
	return math.max(base, 0)
end

-- Pára o ciclo; o motivo chega ao cliente quando a animação de `items` mostrar a carta
local function stop(player: Player, reason: string, items: { CrateItem }?)
	local run = runs[player]
	if not run then
		return
	end
	runs[player] = nil
	run.Trove:Destroy()
	local text = string.format("Auto-Abrir parou ao fim de %d aberturas: %s", run.Opened, reason)
	Diag.Log("AutoOpen", string.format("%s: %s", player.Name, text))
	task.delay(revealDelay(items), function()
		-- Se entretanto recomeçou, não apaga a barra do novo ciclo
		if player.Parent == Players and runs[player] == nil then
			sendState(player, run, false, reason)
			notify(player, text)
		end
	end)
end

-- Motivo para parar depois destes resultados (nil = continua)
local function checkStop(run: Run, items: { CrateItem }): string?
	local crate = ArtistCalc.GetCrate(run.CrateId)
	local rules = run.Rules
	local bestReason: string? = nil
	for _, item in items do
		local rarity = RaritiesConfig.ById[item.Rarity]
		local rarityName = if rarity then rarity.Name else item.Rarity
		if item.Mystery then
			return "carta mistério! " .. rarityName
		end
		local slot = if crate then ArtistCalc.GetCrateSlot(crate, item.Rarity) else nil
		if rules.StopSlot > 0 and slot and slot >= rules.StopSlot then
			bestReason = bestReason or string.format("saiu um %s!", rarityName)
		end
		local variant = VariantCalc.Get(item.Variant)
		if rules.StopShiny and variant then
			bestReason = bestReason or string.format("saiu uma variante Brilhante (%s)!", variant.Name)
		end
		if rules.StopNew and item.New then
			bestReason = bestReason or "artista NOVO no Índice!"
		end
	end
	return bestReason
end

local function step(player: Player, run: Run)
	if runs[player] ~= run then
		return
	end
	lastOpenAt[player] = os.clock()
	local ok, message, items = GachaService.Open(player, run.CrateId, run.Count, true)
	if not ok or not items then
		stop(player, message or "não foi possível abrir.", nil)
		return
	end
	run.Opened += run.Count
	for _, item in items do
		local index = RaritiesConfig.IndexById[item.Rarity] or 0
		if index > (RaritiesConfig.IndexById[run.Best] or 0) then
			run.Best = item.Rarity
		end
	end
	local reason = checkStop(run, items)
	if reason then
		stop(player, reason, items)
		return
	end
	if run.Opened >= AUTO.MaxOpens then
		stop(player, string.format("limite de %d aberturas (carrega outra vez para continuar).", AUTO.MaxOpens), items)
		return
	end
	sendState(player, run, true, nil)
	task.delay(intervalFor(run.Count), step, player, run)
end

function AutoOpenService.IsRunning(player: Player): boolean
	return runs[player] ~= nil
end

function AutoOpenService.Stop(player: Player, reason: string?)
	stop(player, reason or "paraste o Auto-Abrir.", nil)
end

function AutoOpenService.Start(player: Player, crateId: string, count: number, stopSlot: number, stopNew: boolean, stopShiny: boolean): (boolean, string?)
	if not MonetizationService.Owns(player, GAMEPASS_KEY) then
		return false, "O Auto-Abrir precisa do Gamepass na loja VIP."
	end
	local data = DataService.GetProfile(player)
	local crate = ArtistCalc.GetCrate(crateId)
	if not data or not crate then
		return false, "Crate indisponível."
	end
	if not table.find(ArtistsConfig.OpenCounts, count) then
		return false, "Quantidade inválida."
	end
	if data.StageTier < crate.RequiredTier then
		return false, string.format("%s requer o Tier %d.", crate.Name, crate.RequiredTier)
	end
	local rules: AutoOpenSettings = {
		Count = count,
		StopSlot = math.clamp(stopSlot, 0, #ArtistsConfig.SlotOdds),
		StopNew = stopNew,
		StopShiny = stopShiny,
	}
	data.Settings.AutoOpen = rules
	PlayerStateService.MarkDirty(player)

	local previous = runs[player]
	if previous then
		runs[player] = nil
		previous.Trove:Destroy()
	end
	local run: Run = { CrateId = crateId, Count = count, Rules = table.clone(rules), Opened = 0, Best = "", Trove = Trove.new() }
	runs[player] = run

	-- Morrer pára o Auto-Abrir
	local function watchCharacter(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			run.Trove:Connect(humanoid.Died, function()
				stop(player, "morreste.", nil)
			end)
		end
	end
	if player.Character then
		watchCharacter(player.Character)
	end
	run.Trove:Connect(player.CharacterAdded, function()
		stop(player, "a personagem voltou a aparecer.", nil)
	end)

	sendState(player, run, true, nil)
	-- O intervalo também conta entre arranques: recomeçar não abre mais depressa
	local last = lastOpenAt[player]
	local wait = if last then math.max(0, last + intervalFor(count) - os.clock()) else 0
	task.delay(wait, step, player, run)
	Diag.Log("AutoOpen", string.format("%s começou: %s x%d (pára em %d, novo=%s, brilhante=%s)", player.Name, crateId, count, rules.StopSlot, tostring(stopNew), tostring(stopShiny)))
	return true, nil
end

function AutoOpenService.Init()
	ServerNet.Connect(RemoteDefs.Defs.StartAutoOpen, function(player: Player, crateArg: unknown, countArg: unknown, slotArg: unknown, newArg: unknown, shinyArg: unknown)
		local ok, message = AutoOpenService.Start(player, crateArg :: string, countArg :: number, slotArg :: number, newArg :: boolean, shinyArg :: boolean)
		if not ok and message then
			notify(player, message)
		end
	end)
	ServerNet.Connect(RemoteDefs.Defs.StopAutoOpen, function(player: Player)
		AutoOpenService.Stop(player, nil)
	end)
	-- Perder o Gamepass (debug /fe autoopen off) pára o ciclo
	trove:Add(MonetizationService.Changed:Connect(function(player: Player)
		if runs[player] and not MonetizationService.Owns(player, GAMEPASS_KEY) then
			stop(player, "Gamepass desativado.", nil)
		end
	end))
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		local run = runs[player]
		if run then
			runs[player] = nil
			run.Trove:Destroy()
		end
		lastOpenAt[player] = nil
	end)
end

return AutoOpenService
