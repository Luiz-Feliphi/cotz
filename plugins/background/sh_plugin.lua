local PLUGIN = PLUGIN

PLUGIN.name = "Backgrounds"
PLUGIN.author = "gumlefar"
PLUGIN.description = "Lets you add a background to a character, instilling special properties in them."

ix.backgrounds = ix.backgrounds or {}

ix.util.Include("sh_definitions.lua")

-- TEXTURAS DOS COMPONENTES (Substitua pelos caminhos reais das suas imagens .png)
local MATERIAL_COMBO      = Material("cotz/panels/button3_1.png", "noclamp smooth")  -- Textura do Botão
local MATERIAL_DESCRICAO = Material("cotz/panels/buttontab.png", "noclamp smooth")   -- Textura da Descrição

-- =========================================================================
-- CRIAÇÃO DAS FONTES COM CONTORNO (CLIENT-SIDE)
-- =========================================================================
if (CLIENT) then
	-- Fonte para o ComboBox (Baseada na stalkerregulartitlefont do STALKER schema)
	surface.CreateFont("stalkerregulartitlefont_outline", {
		font = "stalkerregulartitlefont", -- Se o seu servidor usa outra fonte padrão, mude o nome aqui
		size = 18,
		weight = 500,
		outline = true,
	})

	-- Fonte para o título "Description" (Baseada na stalkertitlefont)
	surface.CreateFont("stalkertitlefont_outline", {
		font = "stalkertitlefont",
		size = 22,
		weight = 700,
		outline = true,
	})

	-- Fonte para o texto corrido da descrição (Baseada na stalkerregularfont)
	surface.CreateFont("stalkerregularfont_outline", {
		font = "stalkerregularfont",
		size = 16,
		weight = 400,
		outline = true,
	})
end

-- Will run all the characters background OnCreated functions
function PLUGIN:OnCharacterCreated(client, character)
	local backgrounds = character:GetBackgrounds()
	if (backgrounds != nil) then
		for background, _ in pairs(backgrounds) do
			local bck = ix.backgrounds[background]
			if (bck) then
				local func = bck.OnCreated or (function(client, char) return true end)
				func(client, character)
			end
		end
	end
end

if (SERVER) then
	-- Will run all the characters backgrounds OnLoaded functions
	function PLUGIN:CharacterLoaded(character)
		local backgrounds = character:GetBackgrounds()

		if (backgrounds != nil) then
			for background, _ in pairs(backgrounds) do
				local bck = ix.backgrounds[background]
				if (bck) then
					local func = bck.OnLoaded or (function(char) return true end)
					func(character)
				end
			end
		end
	end

	-- Will run all the characters backgrounds OnLoaded functions
	function PLUGIN:PlayerSpawn( player )
		local character = player:GetCharacter()
		if( !character ) then return end

		local backgrounds = character:GetBackgrounds()

		if (backgrounds != nil) then
			for background, _ in pairs(backgrounds) do
				local bck = ix.backgrounds[background]
				if (bck) then
					local func = bck.OnLoaded or (function(char) return true end)
					func(character)
				end
			end
		end
	end
end

ix.char.RegisterVar("backgrounds", {
	field = "background",
	fieldType = ix.type.string,
	default = {},
	category = "attributes",
	bNoDisplay = false,
	OnValidate = function(self, value, payload)
		--if (!ix.backgrounds[value]) then
		--	return false, "invalid", "background"
		--end

		return value
	end,
	OnDisplay = function(self, container, payload)
		local panel = container:Add("DPanel")
		panel:Dock(FILL)
		panel.Paint = function(panel, width, height)
			return false
		end
		
		local combo = panel:Add("DComboBox")
		combo:Dock(TOP)
		combo:DockMargin(0, 0, container:GetWide()*0.7, combo:GetTall())
		
		-- AQUI: Modificado para usar a nova fonte com contorno do Combo
		combo:SetFont("stalkerregulartitlefont")
		
		combo:SizeToContents()
		combo:SetTextColor(Color(255, 255, 255))

		-- 1. PINTURA DO BOTÃO COMBO BOX
		combo.Paint = function(panel, width, height)
			derma.SkinFunc("DrawImportantBackground", 0, 0, width, height, Color(255, 255, 255, 25))
			
			surface.SetMaterial(MATERIAL_COMBO)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRect(0, 0, width, height)
		end

		local labeltitle = panel:Add("DLabel")
		labeltitle:Dock(TOP)
		labeltitle:SetText("Description")
		
		-- AQUI: Modificado para usar a nova fonte com contorno do Título
		labeltitle:SetFont("stalkertitlefont_outline")
		
		labeltitle:SizeToContents()
		labeltitle.Paint = function(panel, width, height)
			return false
		end

		local label = panel:Add("DLabel")
		label:Dock(FILL)
		label:SetWrap(true)
		label:SetText("Select a Background for your character above.")
		
		-- AQUI: Modificado para usar a nova fonte com contorno da Descrição
		label:SetFont("stalkerregularfont")
		
		label:SetContentAlignment(7)
		label:SetTall(container:GetTall()*0.5)
		label:SizeToContents()
		label:SetTextColor(Color(220, 220, 220))

		-- 2. PINTURA DO LAYOUT DA DESCRIÇÃO
		label.Paint = function(panel, width, height)
			--derma.SkinFunc("DrawImportantBackground", 0, 0, width, height, Color(255, 255, 255, 25))
			
			surface.SetMaterial(MATERIAL_DESCRICAO)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRect(0, 0, width, height)
		end
		

		for bkid, bkstruct in SortedPairs(ix.backgrounds) do	
			combo:AddChoice(bkstruct.name, bkid)
		end

		combo.OnSelect = function( self, index, value )
			local dat = self:GetOptionData(index)

			labeltitle:Show()

			if (ix.backgrounds[dat]) then
				payload:Set("backgrounds", {[dat] = true})
				label:SetText(ix.backgrounds[dat].description)
				label:SetTextInset(30,30)
				label:InvalidateLayout(true)
			end
		end
		
		combo:ChooseOption(combo:GetOptionText(4), 4)

		return panel
	end,
})

local CHAR = ix.meta.character or {}

-- Helper to add background
function CHAR:AddBackground(background)
	local data = self:GetBackgrounds() or {}
	data[background] = true
	self:SetBackgrounds(data)

end

-- Helper to remove background
function CHAR:RemoveBackground(background)
	local data = self:GetBackgrounds() or {}
	data[background] = nil
	self:SetBackgrounds(data)
end
