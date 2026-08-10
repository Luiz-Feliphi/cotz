PLUGIN.name = "Spawn Menu: Items"
PLUGIN.author = "Rune Knight + Luiz Feliphi"
PLUGIN.description = "Adds a tab to the spawn menu which players can use to spawn items."
PLUGIN.license = [[Copyright 2021 Rune Knight

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License. To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/4.0/ or send a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.]]

--[[
	STEAM: https://steamcommunity.com/profiles/76561198028996329/
	DISCORD: Rune Knight#5972
]]
CAMI.RegisterPrivilege({
    Name = "Spawn Menu: Items - Spawning",
    MinAccess = "superadmin"
})

function PLUGIN:GetExpectedIcon(s)
    local i = {
        ["Ammunition"] = "icon16/tab.png",
        ["Clothing"] = "icon16/user_suit.png",
        ["Consumables"] = "icon16/pill.png",
        ["Medical"] = "icon16/heart.png",
        ["misc"] = "icon16/error.png",
        ["Permits"] = "icon16/note.png",
        ["Storage"] = "icon16/package.png",
        ["Weapons"] = "icon16/gun.png",
    }
    return hook.Run("GetIconsForSpawnMenuItems", s) or i[s] or "icon16/folder.png"
end

if SERVER then
    util.AddNetworkString("spawnmenuspawnitem")
    util.AddNetworkString("spawnmenugiveitem")
    ix.log.AddType("spawnmenuspawnitem", function(client, name) return string.format("%s has spawned \"%s\".", client:GetCharacter():GetName(), tostring(name)) end)

    net.Receive("spawnmenuspawnitem", function(len, client)
        local u = net.ReadString()
        if not CAMI.PlayerHasAccess(client, "Spawn Menu: Items - Spawning", nil) then return end

        for _, t in pairs(ix.item.list) do
            if t.uniqueID == u then
                ix.item.Spawn(t.uniqueID, client:GetShootPos() + client:GetAimVector() * 84 + Vector(0, 0, 16))
                ix.log.Add(client, "spawnmenuspawnitem", t.name)
                break
            end
        end
    end)

    net.Receive("spawnmenugiveitem", function(len, client)
        local u = net.ReadString()
        if not CAMI.PlayerHasAccess(client, "Spawn Menu: Items - Spawning", nil) then return end

        for _, t in pairs(ix.item.list) do
            if t.uniqueID == u then
                client:GetCharacter():GetInventory():Add(t.uniqueID)
                ix.log.Add(client, "spawnmenuspawnitem", t.name)
                client:Notify("You have given yourself a " .. t.name .. ". Check your inventory.")
                break
            end
        end
    end)
else
    function PLUGIN:InitializedPlugins()
        if SERVER then return end
        RunConsoleCommand("spawnmenu_reload")
    end

    local PLUGIN = PLUGIN
    
    -- CONFIGURAÇÃO DE TAMANHO VISUAL DOS ÍCONES (96x96 pixels)
    local TAMANHO_CUSTOM = 74

    spawnmenu.AddCreationTab("Items", function()
        local p = vgui.Create("SpawnmenuContentPanel")
        local t = p.ContentNavBar.Tree
        local l = {}

        -- Tabela temporária para podermos consultar os itens rapidamente na pesquisa
        local itemSearchCache = {}

        -- Organiza e armazena os dados dos itens do Helix
        for uid, i in pairs(ix.item.list) do
            local c = i.category
            l[c] = l[c] or {}
            table.insert(l[c], i)
            
            -- Salva no cache com o formato que o GMod espera para criar ícones
            itemSearchCache[string.lower(i.name)] = {
                nicename = i.name,
                spawnname = i.uniqueID
            }
        end

        -- 1. CRIAÇÃO DA BARRA DE PESQUISA (Baseada no modelo enviado)
        local searchBar = p:Add("DTextEntry")
        searchBar:Dock(TOP)
        searchBar:DockMargin(5, 5, 5, 5)
        searchBar:SetUpdateOnType(true)
        
        -- Visual Dark customizado
        searchBar.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255)) --35, 35, 35, 255
            self:DrawTextEntryText(Color(35, 35, 35), Color(50, 150, 255), Color(180, 180, 180))
        end
        searchBar:SetPlaceholderText(" Pesquisar itens no CoTZ... (Ex: pda)")

        -- Monta a árvore de categorias na esquerda
        for c, i in SortedPairs(l) do
            local icon16 = PLUGIN:GetExpectedIcon(c)
            local node = t:AddNode(L(c), icon16)

            node.DoClick = function(self)
                if self.PropPanel and IsValid(self.PropPanel) then
                    self.PropPanel:Remove()
                    self.PropPanel = nil
                end

                self.PropPanel = vgui.Create("ContentContainer", p)
                self.PropPanel:SetVisible(false)
                self.PropPanel:SetTriggerSpawnlistChange(false)

                searchBar:SetText("") -- Reseta o texto ao trocar de categoria

                for _, tData in SortedPairsByMemberValue(i, "name") do
                    spawnmenu.CreateContentIcon("item", self.PropPanel, {
                        nicename = (tData.GetName and tData:GetName()) or tData.name,
                        spawnname = tData.uniqueID,
                    })
                end

                -- keep a reference to the currently active panel on "p" so the
                -- search bar (OnValueChange below) can actually find it
                p.PropPanel = self.PropPanel

                p:SwitchPanel(self.PropPanel)
            end
        end

        -- 2. LÓGICA DE FILTRAGEM INTEGRADA (RefreshResults)
        searchBar.OnValueChange = function(textentry, strText)
            local query = string.lower(strText)
            
            -- Se apagar a barra de pesquisa, força um clique na categoria para recarregar tudo normal
            if (query == "") then
                -- CORREÇÃO: Usa a função correta da DTree para pegar o nó selecionado, ou o primeiro nó da lista
                local activeNode = t:GetSelectedItem() or t:Root():GetChildNode(0)
                if IsValid(activeNode) then activeNode:InternalDoClick() end
                return
            end

            if (!IsValid(p.PropPanel)) then return end
            
            -- Limpa os ícones anteriores da tela (Igual ao self.Canvas:Clear() do seu exemplo)
            p.PropPanel:Clear()

            -- Varre o cache de itens verificando se o nome contém o texto digitado
            for itemName, itemData in pairs(itemSearchCache) do
                if (string.find(itemName, query, 1, true)) then
                    -- Recria os novos ícones encontrados diretamente na tela (Igual ao self:CreateIcon)
                    spawnmenu.CreateContentIcon("item", p.PropPanel, {
                        nicename = itemData.nicename,
                        spawnname = itemData.spawnname,
                    })
                end
            end
        end

        local FirstNode = t:Root():GetChildNode(0)
        if IsValid(FirstNode) then
            FirstNode:InternalDoClick()
        end

        return p
    end, "icon16/cog_add.png", 201)

    -- 3. INTERCEPTADOR NATIVO DO TAMANHO DO ÍCONE
    spawnmenu.AddContentType("item", function(p, data)
        local n = data.nicename
        local u = data.spawnname
        
        local icon = vgui.Create("SpawnIcon", p)
        icon:SetWide(TAMANHO_CUSTOM)
        icon:SetTall(TAMANHO_CUSTOM)
        icon:InvalidateLayout(true)
        
        local t = ix.item.list
        local i = t[u]
        icon:SetModel((i.GetModel and i:GetModel()) or i.model)
        icon:SetTooltip(n)

        if (IsValid(p) and p.SetSpaceX) then
            p:SetSpaceX(8)
            p:SetSpaceY(8)
        end

        icon.OnMousePressed = function(this, code)
            surface.PlaySound("ui/buttonclickrelease.wav")
            if not CAMI.PlayerHasAccess(LocalPlayer(), "Spawn Menu: Items - Spawning", nil) then return end

            if code == MOUSE_LEFT then
                net.Start("spawnmenuspawnitem")
                net.WriteString(u)
                net.SendToServer()
            elseif code == MOUSE_RIGHT then
                net.Start("spawnmenugiveitem")
                net.WriteString(u)
                net.SendToServer()
            end
        end

        icon:InvalidateLayout(true)

        if IsValid(p) then
            p:Add(icon)
        end

        return icon
    end)
end
