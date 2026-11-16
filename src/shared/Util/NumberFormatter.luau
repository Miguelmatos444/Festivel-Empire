--!strict
--[[
	NumberFormatter
	Formatação legível de números (BigNum ou number) e de durações.
	Sufixos: K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc; a partir de 1e36 usa notação científica.
]]

local BigNum = require(script.Parent.BigNum)

type BigNum = BigNum.BigNum

local SUFFIXES: { string } = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local NumberFormatter = {}

NumberFormatter.Suffixes = table.freeze(SUFFIXES)

local function trimZeros(text: string): string
	if string.find(text, ".", 1, true) then
		text = (string.gsub(text, "0+$", ""))
		text = (string.gsub(text, "%.$", ""))
	end
	return text
end

-- Mais casas decimais para valores pequenos: 1.25K, 12.5K, 125K
local function formatScaled(value: number): string
	local decimals = if value < 10 then 2 elseif value < 100 then 1 else 0
	return trimZeros(string.format("%." .. decimals .. "f", value))
end

local function scientific(m: number, e: number): string
	local text = string.format("%.2f", m)
	if (tonumber(text) or 0) >= 10 then
		e += 1
		text = string.format("%.2f", m / 10)
	end
	return trimZeros(text) .. "e" .. e
end

function NumberFormatter.format(value: BigNum | number): string
	local n: BigNum
	if type(value) == "number" then
		if value ~= value then
			return "0"
		elseif value == math.huge then
			return "∞"
		elseif value == -math.huge then
			return "-∞"
		end
		n = BigNum.fromNumber(value)
	else
		n = value
	end

	if n.m == 0 then
		return "0"
	end

	local sign = if n.m < 0 then "-" else ""
	local m = math.abs(n.m)
	local e = n.e

	if e < 0 then
		return sign .. trimZeros(string.format("%.2f", m * 10 ^ e))
	end

	local group = e // 3
	if group < #SUFFIXES then
		local scaled = m * 10 ^ (e - group * 3)
		local text = formatScaled(scaled)
		-- O arredondamento pode empurrar para o grupo seguinte (ex.: 999.99K -> 1M)
		if (tonumber(text) or 0) >= 1000 then
			group += 1
			text = formatScaled(scaled / 1000)
		end
		if group < #SUFFIXES then
			return sign .. text .. SUFFIXES[group + 1]
		end
	end

	return sign .. scientific(m, e)
end

-- Inteiro com separador de milhares (ex.: 1 234 567)
function NumberFormatter.formatInteger(value: number): string
	local text = string.format("%d", math.floor(value))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1 ")))
	formatted = (string.gsub(formatted, "^(%-?) ", "%1"))
	return formatted
end

-- Duração compacta: "1d 3h", "2h 15m", "4m 10s", "30s"
function NumberFormatter.formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local days = s // 86400
	local hours = (s % 86400) // 3600
	local minutes = (s % 3600) // 60
	local secs = s % 60
	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

-- Interpreta texto como "1500", "2.5M", "3qa", "1.5e40". Devolve nil se inválido.
function NumberFormatter.parse(text: string): BigNum?
	local s = (string.gsub(text, "%s", ""))

	local mantissaText, exponentText = string.match(s, "^(%-?%d*%.?%d+)[eE]([%+%-]?%d+)$")
	if mantissaText and exponentText then
		local m = tonumber(mantissaText)
		local e = tonumber(exponentText)
		if m and e then
			return BigNum.new(m, e)
		end
		return nil
	end

	local numberText, suffix = string.match(s, "^(%-?%d*%.?%d+)(%a*)$")
	if not numberText or not suffix then
		return nil
	end
	local n = tonumber(numberText)
	if not n then
		return nil
	end
	if suffix == "" then
		return BigNum.fromNumber(n)
	end
	local lowered = string.lower(suffix)
	for index, candidate in SUFFIXES do
		if index > 1 and string.lower(candidate) == lowered then
			return BigNum.new(n, (index - 1) * 3)
		end
	end
	return nil
end

return table.freeze(NumberFormatter)
