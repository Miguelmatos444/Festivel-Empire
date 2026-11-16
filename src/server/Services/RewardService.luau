--!strict
--[[
	RewardService
	Entrega de recompensas (diário, missões, códigos, Developer Products):
	  IncomeMinutes -> minutos do Hype/s passivo atual (sem boost), com mínimo de
	                   MinIncomeClicksPerSecond batidas/s para jogadores sem geradores
	  Discs         -> Discos de Platina
	  Crates        -> aberturas grátis da melhor crate desbloqueada
	  FillEnergy    -> barra do Bass Drop cheia (agora ou na próxima carga)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RetentionConfig = require(ReplicatedStorage.Shared.Config.Retention)
local BigNum = require(ReplicatedStorage.Shared.Util.BigNum)
local NumberFormatter = require(ReplicatedStorage.Shared.Util.NumberFormatter)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local GachaService = require(script.Parent.GachaService)
local BassDropService = require(script.Parent.BassDropService)

type BigNum = BigNum.BigNum
type RewardDef = Types.RewardDef

local RewardService = {}

function RewardService.GetIncomeAmount(player: Player, minutes: number): BigNum
	local perSecond = EconomyService.GetHypePerSecond(player)
	local minimum = BigNum.mulNumber(EconomyService.GetHypePerClick(player), RetentionConfig.MinIncomeClicksPerSecond)
	return BigNum.mulNumber(BigNum.max(perSecond, minimum), minutes * 60)
end

-- Entrega a recompensa e devolve a descrição do que foi dado (ex.: "+1.2M Hype · 1 crate")
function RewardService.Grant(player: Player, reward: RewardDef): string
	local data = DataService.GetProfile(player)
	if not data then
		return ""
	end
	local parts: { string } = {}

	local minutes = reward.IncomeMinutes
	if minutes and minutes > 0 then
		local amount = RewardService.GetIncomeAmount(player, minutes)
		EconomyService.AddHype(player, amount)
		table.insert(parts, "+" .. NumberFormatter.format(amount) .. " Hype")
	end

	local discs = reward.Discs
	if discs and discs > 0 then
		data.PlatinumDiscs += discs
		data.TotalDiscsEarned += discs
		PlayerStateService.MarkDirty(player)
		table.insert(parts, "+" .. discs .. " Discos de Platina")
	end

	if reward.FillEnergy then
		BassDropService.FillEnergy(player)
		table.insert(parts, "barra do Bass Drop cheia")
	end

	local crates = reward.Crates
	if crates and crates > 0 then
		local opened = GachaService.OpenFree(player, crates)
		if opened > 0 then
			table.insert(parts, opened .. (if opened == 1 then " crate grátis" else " crates grátis"))
		end
	end

	return table.concat(parts, " · ")
end

return table.freeze(RewardService)
