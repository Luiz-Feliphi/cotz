AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- Toda a lógica de adicionar/remover pontos acontece via ix.command.Send,
-- disparado do lado do cliente (ver PrimaryAttack/SecondaryAttack em shared.lua
-- e cl_init.lua). O servidor não precisa fazer nada extra aqui: as permissões
-- e a lógica de spawn continuam 100% nos comandos originais de cada plugin.

function SWEP:Deploy()
	return true
end
