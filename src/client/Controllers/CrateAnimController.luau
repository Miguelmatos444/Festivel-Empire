--!strict
--[[
	CrateAnimController
	Liga os resultados do servidor à apresentação da abertura das crates:
	  - fila de CrateResult (a CrateRevealView vai buscando com PopNext)
	  - cartas da roleta: enchimento com as probabilidades reais da crate
	    (CrateAnimCalc.BuildFiller, sem cartas mistério) + a carta ganha do servidor
	  - definições replicadas ("Animação rápida", LowVfx) e o pedido para mudar a primeira
	  - cinemática do dono (RunCinematic) e versão leve dos outros (CrateSummon)
	O cliente nunca decide resultados: o artista já foi entregue antes de isto correr.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
local CrateAnimConfig = require(ReplicatedStorage.Shared.Config.CrateAnimation)
local ArtistCalc = require(ReplicatedStorage.Shared.Calc.ArtistCalc)
local CrateAnimCalc = require(ReplicatedStorage.Shared.Calc.CrateAnimCalc)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)
local TokenBucket = require(ReplicatedStorage.Shared.Util.TokenBucket)
local NetController = require(script.Parent.NetController)
local StateController = require(script.Parent.StateController)
local ArtistController = require(script.Parent.ArtistController)
local CrateCinematicController = require(script.Parent.CrateCinematicController)

type CrateResult = Types.CrateResult
type CrateItem = Types.CrateItem
type CrateSummon = Types.CrateSummon
type FillerCard = CrateAnimCalc.FillerCard

export type RouletteCard = {
	ArtistId: string,
	Rarity: string,
	Mystery: boolean,
}

local CrateAnimController = {}

local resultQueued: Signal.Signal<()> = Signal.new()

-- Disparado quando chega um resultado novo à fila
CrateAnimController.ResultQueued = resultQueued

local trove = Trove.new()
local queue: { CrateResult } = {}
local rng = Random.new()
local settingsBucket = TokenBucket.new(2, 3)

function CrateAnimController.PopNext(): CrateResult?
	return table.remove(queue, 1)
end

function CrateAnimController.HasQueued(): boolean
	return #queue > 0
end

function CrateAnimController.ClearQueue()
	table.clear(queue)
end

function CrateAnimController.IsFast(): boolean
	local snapshot = StateController.Get()
	return snapshot ~= nil and snapshot.FastCrateAnim == true
end

function CrateAnimController.IsLowVfx(): boolean
	local snapshot = StateController.Get()
	return snapshot ~= nil and snapshot.LowVfx == true
end

-- Pede ao servidor para ligar/desligar a "Animação rápida" (guardada no perfil)
function CrateAnimController.SetFast(enabled: boolean): boolean
	if not settingsBucket:TryConsume() then
		return false
	end
	NetController.Fire(RemoteDefs.Defs.SetFastCrateAnim, enabled)
	return true
end

-- Faixa completa da roleta: enchimento aleatório com a carta ganha em WinnerIndex
function CrateAnimController.BuildRoulette(crateId: string, winner: CrateItem): { RouletteCard }
	local roulette = CrateAnimConfig.Roulette
	local crate = ArtistCalc.GetCrate(crateId)
	local cards: { RouletteCard } = {}
	local filler: { FillerCard } = if crate then CrateAnimCalc.BuildFiller(rng, crate, roulette.CardCount) else {}
	for index = 1, roulette.CardCount do
		if index == roulette.WinnerIndex then
			table.insert(cards, { ArtistId = winner.ArtistId, Rarity = winner.Rarity, Mystery = winner.Mystery == true })
		else
			local card = filler[index] or { ArtistId = winner.ArtistId, Rarity = winner.Rarity }
			table.insert(cards, { ArtistId = card.ArtistId, Rarity = card.Rarity, Mystery = false })
		end
	end
	return cards
end

-- Corre a cinemática do próprio jogador para `item`
function CrateAnimController.RunCinematic(item: CrateItem, canSkip: boolean, onDone: (completed: boolean) -> ())
	CrateCinematicController.Play({
		ArtistId = item.ArtistId,
		Rarity = item.Rarity,
		CanSkip = canSkip,
		Fast = CrateAnimController.IsFast(),
		LowVfx = CrateAnimController.IsLowVfx(),
	}, onDone)
end

function CrateAnimController.CancelCinematic()
	CrateCinematicController.Cancel()
end

function CrateAnimController.Init()
	trove:Add(ArtistController.CrateOpened:Connect(function(result: CrateResult)
		table.insert(queue, result)
		resultQueued:Fire()
	end))
	trove:Add(NetController.On(RemoteDefs.Defs.CrateSummon, function(payload: unknown)
		CrateCinematicController.PlayLight(payload :: CrateSummon, CrateAnimController.IsLowVfx())
	end))
end

return CrateAnimController
