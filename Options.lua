--[[
    ClarityOverlay - Options.lua
    Janela de configurações (abre com /clarity) e página em Opções > AddOns.

    Desempenho: a janela só é criada na primeira vez que é aberta e não tem
    OnUpdate. Ela só executa código quando você clica, digita ou arrasta algo;
    fechada, não custa nada.

    Global criado: ClarityOverlayOptionsFrame. O nome é exigido pelo
    UISpecialFrames, que faz a tecla Esc fechar a janela.

    As ações que já existem como comando (adicionar ID, trocar som, restaurar
    padrão...) passam por ns.Commands:Handle(), para validar e dar o mesmo
    retorno no chat que o comando digitado.
]]

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

local FRAME_NAME      = "ClarityOverlayOptionsFrame"
local WIDTH, HEIGHT   = 640, 500
local COL_WIDTH       = 280
local LEFT_X, RIGHT_X = 20, 340
local MAX_LIST_ROWS   = 2  -- normalmente há 1 ID e 1 nome; o resto vai para /clarity list
local ROW_HEIGHT      = 24
local PREVIEW_SECONDS = 2
local ACCENT          = "|cff33ffcc"
local WHITE_TEXTURE   = "Interface\\Buttons\\WHITE8X8"

local frame             -- a janela (criada sob demanda)
local widgets = {}      -- controles que Refresh() atualiza
Options.widgets = widgets
local updating = false  -- true enquanto Refresh() ajusta os controles

---------------------------------------------------------------------------
-- Utilitários
---------------------------------------------------------------------------
local function RunCommand(text)
    ns.Commands:Handle(text)
end

local function Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

-- Aplica posição/tamanho e mostra o overlay por alguns segundos.
local function Preview()
    ns.Overlay:ApplySettings()
    ns:StartTest(PREVIEW_SECONDS, false)
end

local function GetVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if getMetadata then
        local ok, version = pcall(getMetadata, ADDON_NAME, "Version")
        if ok and type(version) == "string" then return version end
    end
    return ""
end

---------------------------------------------------------------------------
-- Fábricas de controles
---------------------------------------------------------------------------
local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

local function Header(parent, text, x, y)
    local fs = Label(parent, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    return fs
end

local function Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function CheckBox(parent, text, x, y, onToggle)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    local label = Label(parent, text, "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 1)
    check:SetScript("OnClick", function(self)
        onToggle(self:GetChecked() and true or false)
    end)
    return check
end

local function RoundToStep(value, step)
    return math.floor(value / step + 0.5) * step
end

-- Barra deslizante feita só com texturas simples (não depende de templates).
local function Slider(parent, text, x, y, minValue, maxValue, step, format, onChange)
    local label = Label(parent, text)
    label:SetPoint("TOPLEFT", x, y)

    local valueText = Label(parent, "", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + COL_WIDTH, y)
    valueText:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(COL_WIDTH, 16)
    slider:SetPoint("TOPLEFT", x, y - 14)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouse(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.22, 0.24, 0.27, 1)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(4)

    slider:SetThumbTexture(WHITE_TEXTURE)
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(10, 16)
        thumb:SetVertexColor(0.2, 0.9, 0.8, 1)
    end

    slider.format, slider.valueText = format, valueText
    slider:SetScript("OnValueChanged", function(self, value)
        value = RoundToStep(value, step)
        valueText:SetText(string.format(format, value))
        if not updating then onChange(value) end
    end)
    return slider
end

-- Ajusta a barra sem disparar a ação de "o usuário mexeu".
local function SetSliderValue(slider, value)
    updating = true
    slider:SetValue(value)
    updating = false
    slider.valueText:SetText(string.format(slider.format, value))
end

local function EditBox(parent, width, numeric, onEnter)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(numeric and 9 or 64)
    if numeric then box:SetNumeric(true) end
    box:SetScript("OnEnterPressed", onEnter)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- Lista com até MAX_LIST_ROWS linhas, cada uma com um botão "Remover".
local function List(parent, x, y, onRemove)
    local list = { rows = {} }
    for i = 1, MAX_LIST_ROWS do
        local rowY = y - (i - 1) * ROW_HEIGHT
        local text = Label(parent, "", "GameFontHighlight")
        text:SetPoint("TOPLEFT", x + 4, rowY - 4)
        text:SetWidth(COL_WIDTH - 90)
        text:SetWordWrap(false)
        local remove = Button(parent, "Remover", 80, function(self)
            if self.value ~= nil then onRemove(self.value) end
        end)
        remove:SetPoint("TOPLEFT", x + COL_WIDTH - 80, rowY)
        list.rows[i] = { text = text, remove = remove }
    end
    list.footer = Label(parent, "", "GameFontDisableSmall")
    list.footer:SetPoint("TOPLEFT", x + 4, y - MAX_LIST_ROWS * ROW_HEIGHT)
    return list
end

local function FillList(list, items)
    for i, row in ipairs(list.rows) do
        local item = items[i]
        row.remove.value = item and item.value or nil
        row.text:SetText(item and item.label or "")
        row.text:SetShown(item ~= nil)
        row.remove:SetShown(item ~= nil)
    end
    if #items == 0 then
        list.footer:SetText("(lista vazia)")
    elseif #items > MAX_LIST_ROWS then
        list.footer:SetText(string.format("+%d não exibidos (veja /clarity list)", #items - MAX_LIST_ROWS))
    else
        list.footer:SetText("")
    end
end

-- Envia o texto de um campo como comando; limpa o campo se a lista cresceu.
local function AddFromInput(box, command, listKey)
    local text = Trim(box:GetText())
    box:ClearFocus()
    if text == "" then return end
    local before = #ns.db[listKey]
    RunCommand(command .. " " .. text)
    if #ns.db[listKey] > before then
        box:SetText("")
    end
end

local function ApplySoundFile()
    local box = widgets.soundFile
    local text = Trim(box:GetText())
    box:ClearFocus()
    if text == "" then
        RunCommand("sound padrao")
    else
        RunCommand("sound file " .. text)
    end
end

---------------------------------------------------------------------------
-- Construção da janela
---------------------------------------------------------------------------
local function CreateWindow()
    -- Estrato MEDIUM: o overlay (HIGH) aparece por cima da janela durante a
    -- prévia, então dá para ajustar vendo o resultado.
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = WHITE_TEXTURE, edgeFile = WHITE_TEXTURE, edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.06, 0.07, 0.95)
    f:SetBackdropBorderColor(0.2, 0.9, 0.8, 0.6)
    f:Hide()

    -- Título, dica e botão de fechar
    local title = Label(f, ACCENT .. "ClarityOverlay|r", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", LEFT_X, -14)
    local version = Label(f, GetVersion(), "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    local hint = Label(f, "Arraste pelo fundo para mover. Esc fecha.", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", -40, -18)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Divisórias
    local vline = f:CreateTexture(nil, "ARTWORK")
    vline:SetColorTexture(1, 1, 1, 0.08)
    vline:SetPoint("TOPLEFT", 320, -44)
    vline:SetSize(1, HEIGHT - 104)
    local hline = f:CreateTexture(nil, "ARTWORK")
    hline:SetColorTexture(1, 1, 1, 0.08)
    hline:SetPoint("BOTTOMLEFT", LEFT_X, 48)
    hline:SetSize(WIDTH - 2 * LEFT_X, 1)

    -----------------------------------------------------------------------
    -- Coluna esquerda: Geral, Aparência, Som
    -----------------------------------------------------------------------
    Header(f, "Geral", LEFT_X, -48)
    widgets.enabled = CheckBox(f, "Addon ativado", LEFT_X, -66, function(value)
        ns:SetEnabled(value)
    end)
    widgets.sound = CheckBox(f, "Tocar som ao ativar", LEFT_X, -92, function(value)
        ns.db.sound = value
    end)
    widgets.pulse = CheckBox(f, "Pulsação enquanto ativo", LEFT_X, -118, function(value)
        ns.db.pulse = value
    end)
    widgets.timer = CheckBox(f, "Mostrar tempo restante (brilho desce)", LEFT_X, -144, function(value)
        ns.db.timerBar = value
        ns.Overlay:ApplySettings()
    end)

    Header(f, "Aparência", LEFT_X, -182)
    local previewHint = Label(f, "(mexer mostra uma prévia)", "GameFontDisableSmall")
    previewHint:SetPoint("TOPRIGHT", f, "TOPLEFT", LEFT_X + COL_WIDTH, -184)
    widgets.scale = Slider(f, "Tamanho", LEFT_X, -204, 0.25, 4, 0.05, "%.2f", function(value)
        ns.db.scale = value
        Preview()
    end)
    widgets.alpha = Slider(f, "Opacidade geral", LEFT_X, -246, 0.05, 1, 0.05, "%.2f", function(value)
        ns.db.alpha = value
        Preview()
    end)
    widgets.offsetX = Slider(f, "Distância do centro (X)", LEFT_X, -288, 0, 800, 5, "%d", function(value)
        ns.db.offsetX = value
        Preview()
    end)
    widgets.offsetY = Slider(f, "Altura (Y)", LEFT_X, -330, -500, 500, 5, "%d", function(value)
        ns.db.offsetY = value
        Preview()
    end)

    Header(f, "Som", LEFT_X, -374)
    local soundHint = Label(f, "Arquivo em Media/ (vazio = som nativo):")
    soundHint:SetPoint("TOPLEFT", LEFT_X, -394)
    widgets.soundFile = EditBox(f, 112, false, ApplySoundFile)
    widgets.soundFile:SetPoint("TOPLEFT", LEFT_X + 6, -410)
    local applySound = Button(f, "Aplicar", 70, ApplySoundFile)
    applySound:SetPoint("LEFT", widgets.soundFile, "RIGHT", 8, 0)
    local testSound = Button(f, "Testar som", 80, function() RunCommand("sound test") end)
    testSound:SetPoint("LEFT", applySound, "RIGHT", 4, 0)

    -----------------------------------------------------------------------
    -- Coluna direita: Detecção
    -----------------------------------------------------------------------
    Header(f, "Detecção", RIGHT_X, -48)

    -- Estado ao vivo (atualizado sempre que o buff liga/desliga).
    widgets.status = Label(f, "", "GameFontHighlight")
    widgets.status:SetPoint("TOPLEFT", RIGHT_X, -68)

    widgets.cost = CheckBox(f, "Detectar em combate pelo custo de mana", RIGHT_X, -86, function(value)
        ns.db.costDetection = value
        ns:Refresh(true)
    end)

    local explain = Label(f, "Em combate o jogo esconde os buffs dos addons, então o addon "
        .. "percebe o Clearcasting quando suas magias passam a custar 0.", "GameFontDisableSmall")
    explain:SetPoint("TOPLEFT", RIGHT_X, -116)
    explain:SetWidth(COL_WIDTH)

    -- Opções avançadas (IDs e nomes do buff): escondidas por padrão. Ficam num
    -- quadro próprio para que esconder o quadro esconda tudo de uma vez.
    local advanced = CreateFrame("Frame", nil, f)
    advanced:SetAllPoints(f)
    advanced:Hide()
    widgets.advanced = advanced

    local advancedButton = Button(f, "", 230, function(self)
        advanced:SetShown(not advanced:IsShown())
        Options:Refresh()
    end)
    advancedButton:SetPoint("TOPLEFT", RIGHT_X, -164)
    widgets.advancedButton = advancedButton

    local idHint = Label(advanced, "IDs do buff (usados fora de combate):")
    idHint:SetPoint("TOPLEFT", RIGHT_X, -194)
    widgets.idList = List(advanced, RIGHT_X, -210, function(id)
        RunCommand("remove " .. id)
    end)
    widgets.idInput = EditBox(advanced, 100, true, function(self)
        AddFromInput(self, "add", "spellIDs")
    end)
    widgets.idInput:SetPoint("TOPLEFT", RIGHT_X + 6, -272)
    local addID = Button(advanced, "Adicionar ID", 110, function()
        AddFromInput(widgets.idInput, "add", "spellIDs")
    end)
    addID:SetPoint("LEFT", widgets.idInput, "RIGHT", 8, 0)

    local nameHint = Label(advanced, "Nomes do buff (usados fora de combate):")
    nameHint:SetPoint("TOPLEFT", RIGHT_X, -306)
    widgets.nameList = List(advanced, RIGHT_X, -322, function(name)
        RunCommand("removename " .. name)
    end)
    widgets.nameInput = EditBox(advanced, 150, false, function(self)
        AddFromInput(self, "addname", "names")
    end)
    widgets.nameInput:SetPoint("TOPLEFT", RIGHT_X + 6, -384)
    local addName = Button(advanced, "Adicionar nome", 110, function()
        AddFromInput(widgets.nameInput, "addname", "names")
    end)
    addName:SetPoint("LEFT", widgets.nameInput, "RIGHT", 8, 0)

    -----------------------------------------------------------------------
    -- Botões de baixo
    -----------------------------------------------------------------------
    local testButton = Button(f, "Testar overlay", 130, function() RunCommand("test") end)
    testButton:SetPoint("BOTTOMLEFT", LEFT_X, 16)
    local debugButton = Button(f, "Diagnóstico", 120, function() RunCommand("debug") end)
    debugButton:SetPoint("LEFT", testButton, "RIGHT", 8, 0)
    local helpButton = Button(f, "Lista de comandos", 140, function() RunCommand("help") end)
    helpButton:SetPoint("LEFT", debugButton, "RIGHT", 8, 0)
    local resetButton = Button(f, "Restaurar padrão", 140, function() RunCommand("reset") end)
    resetButton:SetPoint("LEFT", helpButton, "RIGHT", 8, 0)

    f:SetScript("OnShow", function() Options:Refresh() end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, FRAME_NAME)
    end
    return f
end

-- Cria a janela na primeira vez. Se algo falhar, avisa e não quebra o addon.
local function Build()
    if frame then return true end
    local ok, result = pcall(CreateWindow)
    if not ok then
        ns.Print("não foi possível criar a janela de opções (%s). Os comandos continuam funcionando.", tostring(result))
        return false
    end
    frame = result
    return true
end

---------------------------------------------------------------------------
-- API pública
---------------------------------------------------------------------------

-- Atualiza os controles a partir do banco salvo (só se a janela estiver aberta).
function Options:Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    local db = ns.db

    updating = true
    widgets.enabled:SetChecked(db.enabled)
    widgets.sound:SetChecked(db.sound)
    widgets.pulse:SetChecked(db.pulse)
    widgets.timer:SetChecked(db.timerBar)
    widgets.cost:SetChecked(db.costDetection)
    updating = false

    if not db.enabled then
        widgets.status:SetText("Clearcasting agora: |cffaaaaaaaddon desativado|r")
    elseif ns.state.active then
        widgets.status:SetText("Clearcasting agora: |cff33ff33ATIVO|r")
    else
        widgets.status:SetText("Clearcasting agora: |cffaaaaaainativo|r")
    end
    widgets.advancedButton:SetText(widgets.advanced:IsShown()
        and "Esconder IDs e nomes do buff" or "Avançado: IDs e nomes do buff")

    SetSliderValue(widgets.scale, db.scale)
    SetSliderValue(widgets.alpha, db.alpha)
    SetSliderValue(widgets.offsetX, db.offsetX)
    SetSliderValue(widgets.offsetY, db.offsetY)

    if not widgets.soundFile:HasFocus() then
        widgets.soundFile:SetText(db.soundFile)
    end

    local ids = {}
    for _, id in ipairs(db.spellIDs) do
        local name = ns.Detect:GetResolvedName(id)
        ids[#ids + 1] = {
            label = name and string.format("%d  |cffaaaaaa%s|r", id, name) or tostring(id),
            value = id,
        }
    end
    FillList(widgets.idList, ids)

    local names = {}
    for _, name in ipairs(db.names) do
        names[#names + 1] = { label = name, value = name }
    end
    FillList(widgets.nameList, names)
end

-- Abre a janela. Retorna false se ela não pôde ser criada.
function Options:Open()
    if not Build() then return false end
    frame:Show()
    self:Refresh()
    return true
end

function Options:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return true
    end
    return self:Open()
end

-- Página em Opções > AddOns com um botão que abre a janela (mesmo padrão do
-- OpenMap). Só registra se a API de Settings existir neste cliente.
function Options:RegisterSettingsPanel()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end
    local panel = CreateFrame("Frame")
    local title = Label(panel, ACCENT .. "ClarityOverlay|r", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local desc = Label(panel, "Alerta visual e sonoro do Clearcasting.\n"
        .. "As opções ficam numa janela própria, que também abre com /clarity.", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    local button = Button(panel, "Abrir configurações", 200, function()
        if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end
        Options:Open()
    end)
    button:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)

    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, "ClarityOverlay"))
end
