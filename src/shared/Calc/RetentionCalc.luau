--!strict
--[[
	RetentionCalc
	Regras puras de retenção partilhadas por servidor e UI:
	dias/semanas UTC, estado da recompensa diária (20 h / 48 h), sorteio
	determinístico das missões por jogador e textos das recompensas.
]]

local Types = require(script.Parent.Parent.Types)
local RetentionConfig = require(script.Parent.Parent.Config.Retention)

type DailyData = Types.DailyData
type DailyStatus = Types.DailyStatus
type MissionDef = Types.MissionDef
type MissionData = Types.MissionData
type RewardDef = Types.RewardDef

local DAY = 86400

local RetentionCalc = {}

-- Tempo ----------------------------------------------------------------------

function RetentionCalc.GetDayIndex(now: number): number
	return math.floor(now / DAY)
end

-- Semanas começam à segunda-feira (o dia 0 do epoch Unix foi uma quinta-feira)
function RetentionCalc.GetWeekIndex(now: number): number
	return math.floor((RetentionCalc.GetDayIndex(now) + 3) / 7)
end

function RetentionCalc.SecondsUntilDailyReset(now: number): number
	return DAY - (now % DAY)
end

function RetentionCalc.SecondsUntilWeeklyReset(now: number): number
	local nextWeekStart = ((RetentionCalc.GetWeekIndex(now) + 1) * 7 - 3) * DAY
	return math.max(0, nextWeekStart - now)
end

-- Recompensa diária ------------------------------------------------------------------

function RetentionCalc.GetDailyStatus(daily: DailyData, now: number): DailyStatus
	local days = #RetentionConfig.DailyRewards
	if daily.LastClaim <= 0 then
		return { CanClaim = true, NextDay = 1, SecondsUntilClaim = 0, StreakLost = false }
	end
	local elapsed = now - daily.LastClaim
	local continuing = daily.Streak % days + 1
	if elapsed < RetentionConfig.ClaimCooldown then
		return {
			CanClaim = false,
			NextDay = continuing,
			SecondsUntilClaim = RetentionConfig.ClaimCooldown - elapsed,
			StreakLost = false,
		}
	elseif elapsed <= RetentionConfig.StreakWindow then
		return { CanClaim = true, NextDay = continuing, SecondsUntilClaim = 0, StreakLost = false }
	end
	return { CanClaim = true, NextDay = 1, SecondsUntilClaim = 0, StreakLost = daily.Streak > 0 }
end

-- Missões ----------------------------------------------------------------------

-- Escolhe `count` missões do grupo, sempre as mesmas para o mesmo jogador e período
function RetentionCalc.PickMissions(pool: { MissionDef }, count: number, userId: number, periodIndex: number): { MissionData }
	local rng = Random.new((userId % 1000003) * 10007 + periodIndex)
	local ids: { string } = {}
	for _, def in pool do
		table.insert(ids, def.Id)
	end
	for index = #ids, 2, -1 do
		local swap = rng:NextInteger(1, index)
		ids[index], ids[swap] = ids[swap], ids[index]
	end
	local result: { MissionData } = {}
	for index = 1, math.min(count, #ids) do
		table.insert(result, { Id = ids[index], Progress = 0, Claimed = false })
	end
	return result
end

-- Recompensas -------------------------------------------------------------------

function RetentionCalc.DescribeIncome(minutes: number): string
	if minutes >= 60 and minutes % 60 == 0 then
		return string.format("%d h de rendimento", minutes // 60)
	elseif minutes >= 60 then
		return string.format("%d h %d min de rendimento", minutes // 60, minutes % 60)
	end
	return string.format("%d min de rendimento", minutes)
end

function RetentionCalc.DescribeReward(reward: RewardDef): string
	local parts: { string } = {}
	local minutes = reward.IncomeMinutes
	if minutes and minutes > 0 then
		table.insert(parts, RetentionCalc.DescribeIncome(minutes))
	end
	local crates = reward.Crates
	if crates and crates > 0 then
		table.insert(parts, if crates == 1 then "1 crate grátis" else crates .. " crates grátis")
	end
	local discs = reward.Discs
	if discs and discs > 0 then
		table.insert(parts, discs .. " Discos de Platina")
	end
	if reward.FillEnergy then
		table.insert(parts, "barra do Bass Drop cheia")
	end
	return table.concat(parts, " + ")
end

return table.freeze(RetentionCalc)
