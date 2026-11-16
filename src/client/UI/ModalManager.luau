--!strict
--[[
	ModalManager
	Garante que só um painel central (loja, palcos, …) está aberto de cada vez.
	Cada View regista a sua função de fecho e avisa quando abre (e, opcionalmente,
	quando fecha, para GetActive() saber que já não há painel aberto).
]]

local ModalManager = {}

local closers: { [string]: () -> () } = {}
local active: string? = nil

function ModalManager.Register(name: string, close: () -> ())
	closers[name] = close
end

function ModalManager.Unregister(name: string)
	closers[name] = nil
	if active == name then
		active = nil
	end
end

-- Chamar quando um painel abre: fecha todos os outros
function ModalManager.NotifyOpened(name: string)
	active = name
	for other, close in closers do
		if other ~= name then
			close()
		end
	end
	active = name
end

-- Chamar quando um painel fecha (opcional para Views antigas)
function ModalManager.NotifyClosed(name: string)
	if active == name then
		active = nil
	end
end

-- Painel aberto mais recentemente (nil se nenhum, ou se não avisou o fecho)
function ModalManager.GetActive(): string?
	return active
end

return table.freeze(ModalManager)
