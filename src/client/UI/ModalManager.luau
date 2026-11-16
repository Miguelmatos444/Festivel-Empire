--!strict
--[[
	ModalManager
	Garante que só um painel central (loja, palcos, …) está aberto de cada vez.
	Cada View regista a sua função de fecho e avisa quando abre.
]]

local ModalManager = {}

local closers: { [string]: () -> () } = {}

function ModalManager.Register(name: string, close: () -> ())
	closers[name] = close
end

function ModalManager.Unregister(name: string)
	closers[name] = nil
end

-- Chamar quando um painel abre: fecha todos os outros
function ModalManager.NotifyOpened(name: string)
	for other, close in closers do
		if other ~= name then
			close()
		end
	end
end

return table.freeze(ModalManager)
