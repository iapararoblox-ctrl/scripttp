--[[
    MARCADORES DE TELETRANSPORTE v2 para Delta (Mobile/PC)

    NOVEDADES:
    - Diseño nuevo: tema oscuro, tarjetas, pestañas y avisos flotantes
    - Optimizado para móvil: botones grandes, tamaño adaptado a la pantalla,
      tamaño de interfaz ajustable (70% a 150%)
    - Pestaña "Juegos": guarda los marcadores por juego, copia / importa,
      borra datos de cada juego y ve los de otros juegos
    - Compatible con los marcadores guardados en la v1 (se migran solos)

    Pestañas: Marcadores | Juegos | Ajustes
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME       = "TPMarkersGUI"
local FILE           = "TeleportMarkers.json" -- Archivo de guardado (mismo que la v1)
local MAX_MARKERS    = 40                     -- Máximo de marcadores por juego
local DEFAULT_OFFSET = 3                      -- Altura extra al teletransportarte (studs)
local HEADER_H       = 46                     -- Alto de la cabecera

-- Colores del tema (cámbialos para personalizar)
local C = {
    Bg     = Color3.fromRGB(16, 18, 26),
    Card   = Color3.fromRGB(28, 31, 43),
    Btn    = Color3.fromRGB(44, 48, 64),
    Accent = Color3.fromRGB(90, 130, 255),
    Green  = Color3.fromRGB(46, 160, 105),
    Red    = Color3.fromRGB(200, 70, 80),
    Amber  = Color3.fromRGB(214, 150, 40),
    Text   = Color3.fromRGB(235, 238, 245),
    Sub    = Color3.fromRGB(150, 158, 178),
}

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local CoreGui            = game:GetService("CoreGui")
local HttpService        = game:GetService("HttpService")
local TweenService       = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace          = game:GetService("Workspace")

local player   = Players.LocalPlayer
local placeKey = tostring(game.PlaceId)

----------------------------------------------------------------
-- PADRE DE LA GUI + LIMPIEZA
----------------------------------------------------------------
local function getGuiParent()
    local ok, ui = pcall(function() return gethui and gethui() end)
    if ok and ui then return ui end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then return CoreGui end
    return player:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
local old = guiParent:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

----------------------------------------------------------------
-- DATOS (guardar / cargar por juego)
----------------------------------------------------------------
-- store.Places[PlaceId] = { Name = "Nombre del juego", Markers = { {Name=, CF={12 números}} } }
local store = { Places = {}, Offset = DEFAULT_OFFSET, Scale = 100, Alpha = 0 }

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

-- Asegura el formato nuevo (migra el formato antiguo, que era una lista directa)
local function ensurePlace(key)
    local p = store.Places[key]
    if type(p) ~= "table" then
        p = { Markers = {} }
    elseif type(p.Markers) ~= "table" then
        p = { Markers = p }
    end
    store.Places[key] = p
    return p
end

pcall(function()
    if isfile and isfile(FILE) then
        local data = HttpService:JSONDecode(readfile(FILE))
        if type(data) == "table" then
            if type(data.Places) == "table" then store.Places = data.Places end
            if type(data.Offset) == "number" then store.Offset = data.Offset end
            if type(data.Scale) == "number" then store.Scale = data.Scale end
            if type(data.Alpha) == "number" then store.Alpha = data.Alpha end
        end
    end
end)

for key in pairs(store.Places) do ensurePlace(key) end
store.Offset = clamp(store.Offset, 0, 50)
store.Scale  = clamp(store.Scale, 70, 150)
store.Alpha  = clamp(store.Alpha, 0, 60)

local place   = ensurePlace(placeKey)
local markers = place.Markers
local gameName = place.Name or ("Juego " .. placeKey)

local function save()
    pcall(function() writefile(FILE, HttpService:JSONEncode(store)) end)
end

local function validCF(t)
    if type(t) ~= "table" or #t ~= 12 then return false end
    for i = 1, 12 do
        if type(t[i]) ~= "number" then return false end
    end
    return true
end

----------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------
local running, minimized = true, false
local lastCF = nil -- posición anterior al último teletransporte
local connections = {}
local refreshers = {}

local function track(c) table.insert(connections, c) return c end

----------------------------------------------------------------
-- HELPERS DE INTERFAZ
----------------------------------------------------------------
local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = obj
    return c
end

local function makeButton(parent, text, size, pos, color)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = pos or UDim2.new()
    b.BackgroundColor3 = color or C.Btn
    b.Text = text
    b.TextColor3 = C.Text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.AutoButtonColor = true
    b.Parent = parent
    corner(b, 10)
    return b
end

local function makeLabel(parent, text, size, pos, textSize, color)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos or UDim2.new()
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or C.Text
    l.Font = Enum.Font.Gotham
    l.TextSize = textSize or 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
end

local function makeBox(parent, size, pos, placeholder)
    local t = Instance.new("TextBox")
    t.Size = size
    t.Position = pos
    t.BackgroundColor3 = C.Card
    t.Text = ""
    t.PlaceholderText = placeholder or ""
    t.PlaceholderColor3 = C.Sub
    t.TextColor3 = C.Text
    t.Font = Enum.Font.Gotham
    t.TextSize = 14
    t.ClearTextOnFocus = false
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = parent
    corner(t, 10)
    local pad = Instance.new("UIPadding", t)
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
    return t
end

local function makeStroke(obj, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Transparency = transparency or 0
    s.Thickness = thickness or 1
    s.Parent = obj
    return s
end

-- Arrastrar: handle = zona que se toca, target = lo que se mueve, onTap = acción si fue un toque corto
local function makeDraggable(handle, target, onTap)
    local dragging, moved, dragStart, startPos = false, false, nil, nil
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart, startPos = input.Position, target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved and onTap then onTap() end
                end
            end)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            if d.Magnitude > 6 then moved = true end
            if moved then
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                            startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end))
end

-- Botón de borrado con confirmación: 1er toque arma, 2º toque ejecuta
local function confirmable(btn, idleText, action)
    local armed = false
    local idleColor = btn.BackgroundColor3
    btn.Activated:Connect(function()
        if not armed then
            armed = true
            btn.Text = "¿Seguro?"
            btn.BackgroundColor3 = C.Red
            task.delay(2, function()
                if btn.Parent and armed then
                    armed = false
                    btn.Text = idleText
                    btn.BackgroundColor3 = idleColor
                end
            end)
        else
            armed = false
            btn.Text = idleText
            btn.BackgroundColor3 = idleColor
            action()
        end
    end)
end

----------------------------------------------------------------
-- INTERFAZ: ventana, cabecera, pestañas
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Position = UDim2.new(0, 10, 0, 56)
frame.BackgroundColor3 = C.Bg
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
corner(frame, 16)
makeStroke(frame, C.Accent, 0.6, 1.5)
local uiScale = Instance.new("UIScale", frame)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C.Card
header.BorderSizePixel = 0
header.Active = true
header.Parent = frame
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(60, 80, 160), C.Card)
grad.Rotation = 0
grad.Parent = header

local title = makeLabel(header, "📍 Marcadores TP", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16)
title.Font = Enum.Font.GothamBold
local subtitle = makeLabel(header, gameName, UDim2.new(1, -90, 0, 16), UDim2.new(0, 14, 0, 26), 11, C.Sub)

local minBtn   = makeButton(header, "–", UDim2.fromOffset(32, 32), UDim2.new(1, -78, 0.5, -16), C.Btn)
local closeBtn = makeButton(header, "✕", UDim2.fromOffset(32, 32), UDim2.new(1, -40, 0.5, -16), C.Red)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -HEADER_H)
body.Position = UDim2.new(0, 0, 0, HEADER_H)
body.BackgroundTransparency = 1
body.Parent = frame

-- Barra de pestañas
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 38)
tabBar.Position = UDim2.new(0, 8, 0, 8)
tabBar.BackgroundTransparency = 1
tabBar.Parent = body
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -62)
content.Position = UDim2.new(0, 8, 0, 54)
content.BackgroundTransparency = 1
content.Parent = body

local function newPage()
    local p = Instance.new("Frame")
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.Visible = false
    p.Parent = content
    return p
end

local function newScroll(parent, pos, size)
    local s = Instance.new("ScrollingFrame")
    s.Size = size or UDim2.new(1, 0, 1, 0)
    s.Position = pos or UDim2.new()
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 3
    s.ScrollBarImageColor3 = C.Accent
    s.CanvasSize = UDim2.new()
    s.AutomaticCanvasSize = Enum.AutomaticSize.Y
    s.ScrollingDirection = Enum.ScrollingDirection.Y
    s.Parent = parent
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 6)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = s
    local pad = Instance.new("UIPadding", s)
    pad.PaddingRight = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    return s
end

local pageMarkers  = newPage()
local pageGames    = newPage()
local pageSettings = newPage()

local tabs = {}
local function selectTab(i)
    for idx, t in ipairs(tabs) do
        t.page.Visible = (idx == i)
        t.btn.BackgroundColor3 = (idx == i) and C.Accent or C.Card
        t.btn.TextColor3 = (idx == i) and Color3.fromRGB(255, 255, 255) or C.Sub
    end
end

local function addTab(text, page)
    local b = makeButton(tabBar, text, UDim2.new(1 / 3, -4, 1, 0), nil, C.Card)
    b.TextSize = 13
    table.insert(tabs, { btn = b, page = page })
    local idx = #tabs
    b.Activated:Connect(function() selectTab(idx) end)
end

addTab("📍 Marcadores", pageMarkers)
addTab("🎮 Juegos", pageGames)
addTab("⚙ Ajustes", pageSettings)

----------------------------------------------------------------
-- AVISOS FLOTANTES (se ven aunque el panel esté oculto)
----------------------------------------------------------------
local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint = Vector2.new(0.5, 1)
toastLabel.Position = UDim2.new(0.5, 0, 1, -28)
toastLabel.Size = UDim2.fromOffset(0, 36)
toastLabel.AutomaticSize = Enum.AutomaticSize.X
toastLabel.BackgroundColor3 = C.Bg
toastLabel.BackgroundTransparency = 1
toastLabel.TextTransparency = 1
toastLabel.TextColor3 = C.Text
toastLabel.Font = Enum.Font.GothamBold
toastLabel.TextSize = 14
toastLabel.ZIndex = 50
toastLabel.Parent = gui
corner(toastLabel, 18)
local toastPad = Instance.new("UIPadding", toastLabel)
toastPad.PaddingLeft, toastPad.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
local toastStroke = makeStroke(toastLabel, C.Accent, 1, 1.5)

local toastToken = 0
local function toast(text)
    toastToken += 1
    local my = toastToken
    toastLabel.Text = text
    local info = TweenInfo.new(0.2)
    TweenService:Create(toastLabel, info, { BackgroundTransparency = 0.1, TextTransparency = 0 }):Play()
    TweenService:Create(toastStroke, info, { Transparency = 0.2 }):Play()
    task.delay(2.2, function()
        if toastToken == my and toastLabel.Parent then
            TweenService:Create(toastLabel, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
            TweenService:Create(toastStroke, info, { Transparency = 1 }):Play()
        end
    end)
end

----------------------------------------------------------------
-- BOTÓN FLOTANTE (mostrar / ocultar el panel)
----------------------------------------------------------------
local floatBtn = Instance.new("TextButton")
floatBtn.Size = UDim2.fromOffset(52, 52)
floatBtn.Position = UDim2.new(1, -68, 0.6, 0)
floatBtn.BackgroundColor3 = C.Accent
floatBtn.Text = "📍"
floatBtn.TextSize = 24
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
floatBtn.AutoButtonColor = false
floatBtn.ZIndex = 20
floatBtn.Parent = gui
corner(floatBtn, 26)
makeStroke(floatBtn, Color3.fromRGB(255, 255, 255), 0.2, 2)
local fg = Instance.new("UIGradient")
fg.Color = ColorSequence.new(Color3.fromRGB(120, 160, 255), Color3.fromRGB(70, 100, 220))
fg.Rotation = 90
fg.Parent = floatBtn

----------------------------------------------------------------
-- LÓGICA: teletransporte
----------------------------------------------------------------
local function getHRP()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleportToMarker(m)
    if not validCF(m.CF) then toast("⚠ Marcador dañado") return end
    local hrp = getHRP()
    if not hrp then toast("⚠ No hay personaje") return end
    lastCF = hrp.CFrame
    hrp.AssemblyLinearVelocity = Vector3.zero -- evita arrastrar la velocidad de caída
    hrp.CFrame = CFrame.new(table.unpack(m.CF)) + Vector3.new(0, store.Offset, 0)
    toast("✔ " .. m.Name)
end

----------------------------------------------------------------
-- PESTAÑA 1: MARCADORES
----------------------------------------------------------------
local rebuildMarkers, rebuildGames -- se definen más abajo

local nameBox = makeBox(pageMarkers, UDim2.new(1, 0, 0, 40), UDim2.new(), "Nombre del marcador (opcional)")
local saveBtn = makeButton(pageMarkers, "📍  Guardar posición actual", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 46), C.Green)
saveBtn.TextSize = 15
local backBtn = makeButton(pageMarkers, "↩  Volver a donde estaba", UDim2.new(1, 0, 0, 38), UDim2.new(0, 0, 0, 96), C.Amber)

local markerScroll = newScroll(pageMarkers, UDim2.new(0, 0, 0, 142), UDim2.new(1, 0, 1, -142))

local emptyLabel = makeLabel(pageMarkers, "Aún no hay marcadores.\nMuévete a un lugar y pulsa Guardar.",
    UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 0, 170), 13, C.Sub)
emptyLabel.TextWrapped = true
emptyLabel.TextXAlignment = Enum.TextXAlignment.Center

local function addMarker()
    local hrp = getHRP()
    if not hrp then toast("⚠ No hay personaje") return end
    if #markers >= MAX_MARKERS then toast("⚠ Máximo " .. MAX_MARKERS .. " marcadores") return end
    local name = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Punto " .. (#markers + 1) end
    name = string.sub(name, 1, 24)
    -- Se guarda la posición real (la altura extra se aplica al viajar)
    table.insert(markers, { Name = name, CF = { hrp.CFrame:GetComponents() } })
    nameBox.Text = ""
    save()
    rebuildMarkers()
    rebuildGames()
    toast("💾 Guardado: " .. name)
end

function rebuildMarkers()
    for _, c in ipairs(markerScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    emptyLabel.Visible = (#markers == 0)

    for i, m in ipairs(markers) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 52)
        row.BackgroundTransparency = 1
        row.LayoutOrder = i
        row.Parent = markerScroll

        -- Tarjeta tocable: un toque = teletransportar
        local go = Instance.new("TextButton")
        go.Size = UDim2.new(1, -54, 1, 0)
        go.BackgroundColor3 = C.Card
        go.Text = ""
        go.AutoButtonColor = true
        go.Parent = row
        corner(go, 10)

        local nameL = makeLabel(go, m.Name, UDim2.new(1, -16, 0, 22), UDim2.new(0, 12, 0, 6), 15)
        nameL.Font = Enum.Font.GothamBold
        local coords = "?"
        if validCF(m.CF) then
            coords = string.format("%.0f, %.0f, %.0f", m.CF[1], m.CF[2], m.CF[3])
        end
        makeLabel(go, coords, UDim2.new(1, -16, 0, 16), UDim2.new(0, 12, 0, 28), 11, C.Sub)
        go.Activated:Connect(function() teleportToMarker(m) end)

        local del = makeButton(row, "🗑", UDim2.new(0, 48, 1, 0), UDim2.new(1, -48, 0, 0), C.Btn)
        del.TextSize = 18
        confirmable(del, "🗑", function()
            local idx = table.find(markers, m)
            if idx then table.remove(markers, idx) end
            save()
            rebuildMarkers()
            rebuildGames()
            toast("Marcador borrado")
        end)
    end
end

saveBtn.Activated:Connect(addMarker)

backBtn.Activated:Connect(function()
    if not lastCF then toast("Aún no hay posición anterior") return end
    local hrp = getHRP()
    if not hrp then toast("⚠ No hay personaje") return end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = lastCF -- vuelve exacto, sin altura extra
    lastCF = nil
    toast("↩ Has vuelto")
end)

----------------------------------------------------------------
-- PESTAÑA 2: JUEGOS (guardado por juego)
----------------------------------------------------------------
local gamesScroll = newScroll(pageGames)

-- Tarjeta del juego actual
local curCard = Instance.new("Frame")
curCard.Size = UDim2.new(1, 0, 0, 74)
curCard.BackgroundColor3 = C.Card
curCard.LayoutOrder = 1
curCard.Parent = gamesScroll
corner(curCard, 12)
makeStroke(curCard, C.Accent, 0.5, 1.5)
local curTag  = makeLabel(curCard, "JUEGO ACTUAL", UDim2.new(1, -20, 0, 14), UDim2.new(0, 12, 0, 8), 10, C.Accent)
curTag.Font = Enum.Font.GothamBold
local curName = makeLabel(curCard, gameName, UDim2.new(1, -20, 0, 22), UDim2.new(0, 12, 0, 22), 16)
curName.Font = Enum.Font.GothamBold
local curInfo = makeLabel(curCard, "", UDim2.new(1, -20, 0, 16), UDim2.new(0, 12, 0, 48), 12, C.Sub)

-- Copiar / Borrar todo
local actRow = Instance.new("Frame")
actRow.Size = UDim2.new(1, 0, 0, 40)
actRow.BackgroundTransparency = 1
actRow.LayoutOrder = 2
actRow.Parent = gamesScroll
local copyBtn  = makeButton(actRow, "📋 Copiar", UDim2.new(0.5, -3, 1, 0), UDim2.new(), C.Accent)
local clearBtn = makeButton(actRow, "🗑 Borrar todo", UDim2.new(0.5, -3, 1, 0), UDim2.new(0.5, 3, 0, 0), C.Btn)

-- Importar
local importBox = makeBox(gamesScroll, UDim2.new(1, 0, 0, 40), UDim2.new(), "Pega aquí marcadores copiados")
importBox.LayoutOrder = 3
local importBtn = makeButton(gamesScroll, "⬇ Importar a este juego", UDim2.new(1, 0, 0, 40), UDim2.new(), C.Green)
importBtn.LayoutOrder = 4

local otherTag = makeLabel(gamesScroll, "OTROS JUEGOS GUARDADOS", UDim2.new(1, 0, 0, 22), UDim2.new(), 11, C.Sub)
otherTag.Font = Enum.Font.GothamBold
otherTag.LayoutOrder = 5

local noOthers = makeLabel(gamesScroll, "Aún no guardaste marcadores en otros juegos.",
    UDim2.new(1, 0, 0, 34), UDim2.new(), 12, C.Sub)
noOthers.TextWrapped = true
noOthers.LayoutOrder = 6

function rebuildGames()
    curName.Text = gameName
    curInfo.Text = string.format("%d / %d marcadores  ·  ID %s", #markers, MAX_MARKERS, placeKey)

    for _, c in ipairs(gamesScroll:GetChildren()) do
        if c.Name == "GameRow" then c:Destroy() end
    end

    local others = {}
    for key, p in pairs(store.Places) do
        if key ~= placeKey and type(p.Markers) == "table" and #p.Markers > 0 then
            table.insert(others, { Key = key, Name = p.Name or ("Juego " .. key), Count = #p.Markers })
        end
    end
    table.sort(others, function(a, b) return a.Name:lower() < b.Name:lower() end)
    noOthers.Visible = (#others == 0)

    for i, g in ipairs(others) do
        local row = Instance.new("Frame")
        row.Name = "GameRow"
        row.Size = UDim2.new(1, 0, 0, 54)
        row.BackgroundColor3 = C.Card
        row.LayoutOrder = 10 + i
        row.Parent = gamesScroll
        corner(row, 10)

        makeLabel(row, g.Name, UDim2.new(1, -110, 0, 22), UDim2.new(0, 12, 0, 7), 14).Font = Enum.Font.GothamBold
        makeLabel(row, g.Count .. " marcadores · ID " .. g.Key, UDim2.new(1, -110, 0, 16), UDim2.new(0, 12, 0, 29), 11, C.Sub)

        local del = makeButton(row, "Borrar", UDim2.fromOffset(84, 34), UDim2.new(1, -92, 0.5, -17), C.Btn)
        del.TextSize = 12
        confirmable(del, "Borrar", function()
            store.Places[g.Key] = nil
            save()
            rebuildGames()
            toast("Datos de " .. g.Name .. " borrados")
        end)
    end
end

copyBtn.Activated:Connect(function()
    if #markers == 0 then toast("No hay marcadores que copiar") return end
    if not setclipboard then toast("⚠ Tu ejecutor no soporta copiar") return end
    local ok = pcall(function() setclipboard(HttpService:JSONEncode(markers)) end)
    toast(ok and "📋 Copiado al portapapeles" or "⚠ No se pudo copiar")
end)

confirmable(clearBtn, "🗑 Borrar todo", function()
    table.clear(markers)
    save()
    rebuildMarkers()
    rebuildGames()
    toast("Marcadores de este juego borrados")
end)

importBtn.Activated:Connect(function()
    local text = importBox.Text
    if text == "" then toast("Pega primero los marcadores") return end
    local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
    if not ok or type(data) ~= "table" then toast("⚠ Texto no válido") return end
    local added = 0
    for _, m in ipairs(data) do
        if #markers >= MAX_MARKERS then break end
        if type(m) == "table" and type(m.Name) == "string" and validCF(m.CF) then
            table.insert(markers, { Name = string.sub(m.Name, 1, 24), CF = m.CF })
            added += 1
        end
    end
    importBox.Text = ""
    if added > 0 then
        save()
        rebuildMarkers()
        rebuildGames()
    end
    toast("⬇ Importados: " .. added)
end)

----------------------------------------------------------------
-- PESTAÑA 3: AJUSTES
----------------------------------------------------------------
local settingsScroll = newScroll(pageSettings)
local layoutFrame -- se define abajo

local function addStepper(order, text, get, set, mn, mx, step, suffix)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = C.Card
    row.LayoutOrder = order
    row.Parent = settingsScroll
    corner(row, 10)

    makeLabel(row, text, UDim2.new(1, -160, 1, 0), UDim2.new(0, 12, 0, 0), 13)
    local minus = makeButton(row, "–", UDim2.fromOffset(40, 36), UDim2.new(1, -152, 0.5, -18), C.Btn)
    local val = makeLabel(row, "", UDim2.fromOffset(56, 36), UDim2.new(1, -108, 0.5, -18), 13)
    val.TextXAlignment = Enum.TextXAlignment.Center
    val.Font = Enum.Font.GothamBold
    local plus = makeButton(row, "+", UDim2.fromOffset(40, 36), UDim2.new(1, -48, 0.5, -18), C.Btn)

    local function refresh() val.Text = tostring(get()) .. suffix end
    local function change(delta)
        set(clamp(get() + delta, mn, mx))
        refresh()
        save()
    end
    minus.Activated:Connect(function() change(-step) end)
    plus.Activated:Connect(function() change(step) end)
    table.insert(refreshers, refresh)
    refresh()
end

addStepper(1, "Altura extra al viajar", function() return store.Offset end,
    function(v) store.Offset = v end, 0, 50, 1, " st")
addStepper(2, "Tamaño de interfaz", function() return store.Scale end,
    function(v) store.Scale = v; layoutFrame() end, 70, 150, 10, "%")
addStepper(3, "Transparencia", function() return store.Alpha end,
    function(v) store.Alpha = v; frame.BackgroundTransparency = v / 100 end, 0, 60, 10, "%")

local resetBtn = makeButton(settingsScroll, "Restaurar ajustes", UDim2.new(1, 0, 0, 40), UDim2.new(), C.Btn)
resetBtn.LayoutOrder = 4
resetBtn.Activated:Connect(function()
    store.Offset, store.Scale, store.Alpha = DEFAULT_OFFSET, 100, 0
    frame.BackgroundTransparency = 0
    layoutFrame()
    for _, f in ipairs(refreshers) do f() end
    save()
    toast("Ajustes restaurados")
end)

local canSave = (writefile ~= nil and readfile ~= nil)
local infoLabel = makeLabel(settingsScroll,
    canSave and "💾 Guardado automático activo: los marcadores se guardan por juego."
    or "⚠ Tu ejecutor no soporta writefile/readfile: los marcadores no se guardarán al cerrar.",
    UDim2.new(1, 0, 0, 52), UDim2.new(), 12, canSave and C.Sub or C.Amber)
infoLabel.TextWrapped = true
infoLabel.TextTruncate = Enum.TextTruncate.None
infoLabel.TextYAlignment = Enum.TextYAlignment.Top
infoLabel.LayoutOrder = 5

----------------------------------------------------------------
-- DISEÑO ADAPTABLE (móvil / PC)
----------------------------------------------------------------
local expandedW, expandedH = 320, 420

function layoutFrame()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    local sc = store.Scale / 100
    uiScale.Scale = sc
    expandedW = clamp(vp.X * 0.92 / sc, 250, 340)
    expandedH = clamp(vp.Y * 0.80 / sc, 230, 470)
    frame.Size = minimized and UDim2.fromOffset(expandedW, HEADER_H) or UDim2.fromOffset(expandedW, expandedH)
end

do
    local cam = Workspace.CurrentCamera
    if cam then
        track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutFrame))
    end
end

----------------------------------------------------------------
-- CONTROLES DE VENTANA
----------------------------------------------------------------
minBtn.Activated:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    minBtn.Text = minimized and "+" or "–"
    layoutFrame()
end)

makeDraggable(header, frame)
makeDraggable(floatBtn, floatBtn, function() -- toque corto = mostrar/ocultar panel
    frame.Visible = not frame.Visible
end)

closeBtn.Activated:Connect(function()
    running = false
    save()
    for _, c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
end)

----------------------------------------------------------------
-- INICIO
----------------------------------------------------------------
frame.BackgroundTransparency = store.Alpha / 100
layoutFrame()
selectTab(1)
rebuildMarkers()
rebuildGames()
toast("📍 " .. #markers .. " marcadores en este juego")

-- Obtiene el nombre real del juego sin bloquear el resto
task.spawn(function()
    local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
    if ok and type(info) == "table" and type(info.Name) == "string" and running then
        place.Name = info.Name
        gameName = info.Name
        subtitle.Text = gameName
        save()
        rebuildGames()
    end
end)
