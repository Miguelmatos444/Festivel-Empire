--!strict
--[[
	ArrowCalc
	Cálculos puros do minijogo de setas, partilhados servidor/cliente:
	dificuldade por tier, notas, combo, Hype/energia por acerto e zona do palco.
	O servidor usa-os para cobrar; o cliente só para mostrar.
]]

local ArrowGameConfig = require(script.Parent.Parent.Config.ArrowGame)
local MapConfig = require(script.Parent.Parent.Config.Map)
local MapCalc = require(script.Parent.MapCalc)
local Types = require(script.Parent.Parent.Types)

type ArrowTierDef = Types.ArrowTierDef
type ArrowGradeDef = Types.ArrowGradeDef
type ArrowGrade = Types.ArrowGrade

local ArrowCalc = {}

local gradeByName: { [string]: ArrowGradeDef } = {}
for _, def in ArrowGameConfig.Grades do
	gradeByName[def.Grade] = def
end

function ArrowCalc.GetTierDef(tier: number): ArrowTierDef
	local tiers = ArrowGameConfig.Tiers
	return tiers[math.clamp(math.floor(tier), 1, #tiers)]
end

function ArrowCalc.GetGradeDef(grade: ArrowGrade): ArrowGradeDef
	return gradeByName[grade]
end

-- Fração do tempo de vida já passada (pode sair de [0, 1] se cedo/tarde)
function ArrowCalc.GetProgress(now: number, spawnAt: number, lifetime: number): number
	return (now - spawnAt) / lifetime
end

-- Nota para um progresso em [0, 1]; nil = expirada
function ArrowCalc.GradeProgress(progress: number): ArrowGradeDef?
	local clamped = math.max(progress, 0)
	for _, def in ArrowGameConfig.Grades do
		if clamped <= def.MaxProgress then
			return def
		end
	end
	return nil
end

-- Multiplicador para um combo de `combo` acertos seguidos (já a contar com o atual)
function ArrowCalc.GetComboMultiplier(combo: number): number
	local combo_ = ArrowGameConfig.Combo
	return math.min(1 + math.max(combo, 0) * combo_.PerHit, combo_.MaxMultiplier)
end

-- Fator aplicado ao Hype por batida num acerto manual
function ArrowCalc.GetHitFactor(tier: number, grade: ArrowGrade, combo: number): number
	return ArrowCalc.GetTierDef(tier).HitValue * ArrowCalc.GetGradeDef(grade).Factor * ArrowCalc.GetComboMultiplier(combo)
end

-- Fator de um acerto do Auto-Play (nota e combo fixos)
function ArrowCalc.GetAutoHitFactor(tier: number): number
	local auto = ArrowGameConfig.AutoPlay
	return ArrowCalc.GetTierDef(tier).HitValue * ArrowCalc.GetGradeDef(auto.Grade).Factor * auto.ComboMultiplier
end

-- Energia do Bass Drop por acerto (antes dos multiplicadores de energia)
function ArrowCalc.GetEnergy(spawnInterval: number, grade: ArrowGrade): number
	return ArrowCalc.GetGradeDef(grade).EnergyPerInterval * spawnInterval
end

--[[
	true se a posição (mundo) está em cima do palco do tier indicado no terreno `plotIndex`.
	Pegada = Config/Stages (Width × Depth) a partir de StageFront, com StageMargin dos lados e
	atrás (à frente não, para quem está no público não contar); a personagem tem de estar acima
	de StageMinHeight (em cima do estrado) e abaixo do topo do palco + StageMaxHeightExtra.
]]
function ArrowCalc.IsOnStage(plotIndex: number, tier: number, position: Vector3): boolean
	local plots = MapConfig.Plots
	local def = MapCalc.GetStageDef(tier)
	local margin = ArrowGameConfig.StageMargin
	local localPosition = MapCalc.GetPlotCFrame(plotIndex):PointToObjectSpace(position)
	local depth = localPosition.Z + plots.Depth / 2
	return math.abs(localPosition.X) <= def.Width / 2 + margin
		and depth >= plots.StageFront
		and depth <= plots.StageFront + def.Depth + margin
		and localPosition.Y >= ArrowGameConfig.StageMinHeight
		and localPosition.Y <= def.Height + ArrowGameConfig.StageMaxHeightExtra
end

return table.freeze(ArrowCalc)
