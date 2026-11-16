--!strict
--[[
	BigNum
	Números grandes imutáveis no formato mantissa + expoente (base 10).
	  valor = m * 10^e,  com 1 <= |m| < 10  (ou m = 0, e = 0)

	Todas as funções devolvem novos valores congelados; nunca mutam os argumentos.
	Inclui helpers de custo exponencial com soma geométrica (sem loops).
]]

local Types = require(script.Parent.Parent.Types)

export type BigNum = Types.BigNumData

local BigNum = {}

-- Acima desta diferença de expoentes, a parcela menor é irrelevante numa soma.
local NEGLIGIBLE_EXPONENT_GAP = 17
-- Arredondamento da mantissa a 15 dígitos significativos (remove ruído de vírgula flutuante).
local MANTISSA_PRECISION = 1e14

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function make(m: number, e: number): BigNum
	return table.freeze({ m = m, e = e })
end

local ZERO = make(0, 0)
local ONE = make(1, 0)

BigNum.ZERO = ZERO
BigNum.ONE = ONE

local function normalize(m: number, e: number): BigNum
	if m == 0 then
		return ZERO
	end
	assert(isFinite(m) and isFinite(e), "BigNum: valor não finito")

	-- Garante expoente inteiro (passa a parte fracionária para a mantissa)
	local eInt = math.floor(e)
	if eInt ~= e then
		m *= 10 ^ (e - eInt)
		e = eInt
	end

	-- Desloca a mantissa para [1, 10). Feito em dois passos para evitar 10^±309.
	local shift = math.floor(math.log10(math.abs(m)))
	if shift ~= 0 then
		local half = shift // 2
		m = (m / 10 ^ half) / 10 ^ (shift - half)
		e += shift
	end

	m = math.round(m * MANTISSA_PRECISION) / MANTISSA_PRECISION
	local absM = math.abs(m)
	if absM >= 10 then
		m /= 10
		e += 1
	elseif absM < 1 then
		m *= 10
		e -= 1
	end

	return make(m, e)
end

-- Construção / conversão ----------------------------------------------------

function BigNum.new(m: number, e: number): BigNum
	return normalize(m, e)
end

function BigNum.fromNumber(n: number): BigNum
	return normalize(n, 0)
end

-- Devolve 10^l
function BigNum.fromLog10(l: number): BigNum
	assert(isFinite(l), "BigNum.fromLog10: valor não finito")
	local e = math.floor(l)
	return normalize(10 ^ (l - e), e)
end

function BigNum.toNumber(a: BigNum): number
	if a.m == 0 then
		return 0
	end
	if a.e > 308 then
		return if a.m > 0 then math.huge else -math.huge
	end
	if a.e < -323 then
		return 0
	end
	return a.m * 10 ^ a.e
end

function BigNum.serialize(a: BigNum): BigNum
	return { m = a.m, e = a.e }
end

-- Lê dados não confiáveis (DataStore/rede). Valores inválidos tornam-se ZERO.
function BigNum.deserialize(value: unknown): BigNum
	if type(value) ~= "table" then
		return ZERO
	end
	local t = value :: { [string]: unknown }
	local m, e = t.m, t.e
	if type(m) ~= "number" or type(e) ~= "number" or not isFinite(m) or not isFinite(e) then
		return ZERO
	end
	return normalize(m, e)
end

-- Predicados ----------------------------------------------------------------

function BigNum.isZero(a: BigNum): boolean
	return a.m == 0
end

function BigNum.isNegative(a: BigNum): boolean
	return a.m < 0
end

function BigNum.isPositive(a: BigNum): boolean
	return a.m > 0
end

-- Aritmética ----------------------------------------------------------------

function BigNum.neg(a: BigNum): BigNum
	if a.m == 0 then
		return ZERO
	end
	return make(-a.m, a.e)
end

function BigNum.add(a: BigNum, b: BigNum): BigNum
	if a.m == 0 then
		return b
	end
	if b.m == 0 then
		return a
	end
	if a.e >= b.e then
		local gap = a.e - b.e
		if gap > NEGLIGIBLE_EXPONENT_GAP then
			return a
		end
		return normalize(a.m + b.m / 10 ^ gap, a.e)
	else
		local gap = b.e - a.e
		if gap > NEGLIGIBLE_EXPONENT_GAP then
			return b
		end
		return normalize(b.m + a.m / 10 ^ gap, b.e)
	end
end

function BigNum.sub(a: BigNum, b: BigNum): BigNum
	return BigNum.add(a, BigNum.neg(b))
end

function BigNum.mul(a: BigNum, b: BigNum): BigNum
	if a.m == 0 or b.m == 0 then
		return ZERO
	end
	return normalize(a.m * b.m, a.e + b.e)
end

function BigNum.div(a: BigNum, b: BigNum): BigNum
	assert(b.m ~= 0, "BigNum.div: divisão por zero")
	if a.m == 0 then
		return ZERO
	end
	return normalize(a.m / b.m, a.e - b.e)
end

function BigNum.mulNumber(a: BigNum, n: number): BigNum
	return BigNum.mul(a, BigNum.fromNumber(n))
end

function BigNum.divNumber(a: BigNum, n: number): BigNum
	return BigNum.div(a, BigNum.fromNumber(n))
end

-- log10 de um valor positivo
function BigNum.log10(a: BigNum): number
	assert(a.m > 0, "BigNum.log10: o valor tem de ser positivo")
	return a.e + math.log10(a.m)
end

-- a ^ p (a >= 0)
function BigNum.pow(a: BigNum, p: number): BigNum
	if p == 0 then
		return ONE
	end
	if a.m == 0 then
		return ZERO
	end
	return BigNum.fromLog10(BigNum.log10(a) * p)
end

-- base ^ p para base numérica positiva, sem overflow
function BigNum.powNumber(base: number, p: number): BigNum
	assert(base > 0, "BigNum.powNumber: base tem de ser positiva")
	if p == 0 then
		return ONE
	end
	return BigNum.fromLog10(math.log10(base) * p)
end

function BigNum.floor(a: BigNum): BigNum
	if a.m == 0 or a.e >= 15 then
		return a -- acima de 1e15 a parte fracionária já não é representável
	end
	return BigNum.fromNumber(math.floor(BigNum.toNumber(a)))
end

-- Comparação ----------------------------------------------------------------

-- Devolve -1, 0 ou 1
function BigNum.compare(a: BigNum, b: BigNum): number
	local signA = if a.m > 0 then 1 elseif a.m < 0 then -1 else 0
	local signB = if b.m > 0 then 1 elseif b.m < 0 then -1 else 0
	if signA ~= signB then
		return if signA > signB then 1 else -1
	end
	if signA == 0 then
		return 0
	end
	if a.e ~= b.e then
		return if (a.e > b.e) == (signA > 0) then 1 else -1
	end
	if a.m == b.m then
		return 0
	end
	return if a.m > b.m then 1 else -1
end

function BigNum.eq(a: BigNum, b: BigNum): boolean
	return a.m == b.m and a.e == b.e
end

function BigNum.lt(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) < 0
end

function BigNum.lte(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) <= 0
end

function BigNum.gt(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) > 0
end

function BigNum.gte(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) >= 0
end

function BigNum.max(a: BigNum, b: BigNum): BigNum
	return if BigNum.compare(a, b) >= 0 then a else b
end

function BigNum.min(a: BigNum, b: BigNum): BigNum
	return if BigNum.compare(a, b) <= 0 then a else b
end

-- Custos exponenciais (soma geométrica) ------------------------------------
--[[
	Custo do nível L: BaseCost * Rate^L
	Custo de comprar `count` níveis a partir de L:
	    BaseCost * Rate^L * (Rate^count - 1) / (Rate - 1)
	Máximo comprável com orçamento H:
	    n = floor( log_Rate( 1 + H * (Rate - 1) / (BaseCost * Rate^L) ) )
]]

local function firstLevelCost(baseCost: number, rate: number, level: number): BigNum
	assert(baseCost > 0, "BigNum: baseCost tem de ser positivo")
	assert(rate >= 1, "BigNum: rate tem de ser >= 1")
	return BigNum.fromLog10(math.log10(baseCost) + level * math.log10(rate))
end

function BigNum.geometricCost(baseCost: number, rate: number, level: number, count: number): BigNum
	if count <= 0 then
		return ZERO
	end
	local first = firstLevelCost(baseCost, rate, level)
	if rate == 1 then
		return BigNum.mulNumber(first, count)
	end
	local factor = BigNum.divNumber(BigNum.sub(BigNum.powNumber(rate, count), ONE), rate - 1)
	return BigNum.mul(first, factor)
end

function BigNum.maxAffordable(baseCost: number, rate: number, level: number, budget: BigNum): number
	if budget.m <= 0 then
		return 0
	end
	local first = firstLevelCost(baseCost, rate, level)
	local n: number
	if rate == 1 then
		n = math.floor(BigNum.toNumber(BigNum.div(budget, first)))
	else
		local x = BigNum.add(ONE, BigNum.div(BigNum.mulNumber(budget, rate - 1), first))
		n = math.floor(BigNum.log10(x) / math.log10(rate))
	end
	n = math.max(n, 0)

	-- Correção de arredondamento de vírgula flutuante (no máximo um passo em cada sentido)
	if n > 0 and BigNum.gt(BigNum.geometricCost(baseCost, rate, level, n), budget) then
		n -= 1
	elseif BigNum.lte(BigNum.geometricCost(baseCost, rate, level, n + 1), budget) then
		n += 1
	end
	return n
end

return table.freeze(BigNum)
