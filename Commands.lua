--[[
    ClarityOverlay - Commands.lua
    Slash commands (/clarity). Todas as mensagens em português do Brasil.

    Observação: no chat do WoW o caractere "|" inicia códigos de cor; para
    exibir uma barra vertical literal é preciso escrever "||".
]]

local ADDON_NAME, ns = ...

local Commands = {}
ns.Commands = Commands

local Print = ns.Print

local TEST_SECONDS = 3
local SCALE_MIN, SCALE_MAX = 0.25, 4
local ALPHA_MIN, ALPHA_MAX = 0.05, 1
local OFFSET_LIMIT = 2000

---------------------------------------------------------------------------
-- Utilitários
---------------------------------------------------------------------------

-- Converte texto em número aceitando vírgula decimal ("1,5"). nil se inválido.
local function ToNumber(text)
    if type(text) ~= "string" then return nil end
    local normalized = text:gsub(",", ".")
    return tonumber(normalized)
end

local function OnOffText(value)
    return value and "|cff33ff33ligado|r" or "|cffff5555desligado|r"
end

local function IsDefaultKeyword(word)
    word = ns.Lower(word)
    return word == "padrao" or word == "padrão" or word == "default" or word == "nativo"
end

local function SplitFirst(text)
    local first, rest = text:match("^(%S*)%s*(.-)%s*$")
    return ns.Lower(first or ""), rest or ""
end

-- Depois de mudar as listas: recria as buscas e reavalia o buff.
local function DetectionChanged()
    ns.Detect:Rebuild()
    ns:Refresh(false)
end

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------
local handlers = {}

local HELP_LINES = {
    "|cffffd200/clarity|r - abre/fecha a janela de configurações",
    "|cffffd200/clarity help|r - mostra esta lista",
    "|cffffd200/clarity on||off|r - ativa/desativa o addon",
    "|cffffd200/clarity test|r - mostra o overlay por 3 s para ajustar a posição",
    "|cffffd200/clarity sound on||off|r - liga/desliga o som de alerta",
    "|cffffd200/clarity sound test|r - toca o som de alerta agora",
    "|cffffd200/clarity sound file <arquivo.ogg>|r - usa um som próprio da pasta Media/ (ou um FileDataID)",
    "|cffffd200/clarity sound padrao|r - volta ao som nativo",
    "|cffffd200/clarity scale <0.25-4>|r - tamanho do overlay",
    "|cffffd200/clarity offset <x> <y>|r - distância horizontal do centro e altura",
    "|cffffd200/clarity alpha <0.05-1>|r - opacidade",
    "|cffffd200/clarity pulse on||off|r - pulsação enquanto o buff está ativo",
    "|cffffd200/clarity custo on||off|r - detectar em combate pelo custo das magias",
    "|cffffd200/clarity tempo on||off|r - o brilho do arco desce conforme o buff acaba",
    "|cffffd200/clarity add <spellID>|r / |cffffd200remove <spellID>|r - IDs detectados",
    "|cffffd200/clarity addname <nome>|r / |cffffd200removename <nome>|r - nomes detectados",
    "|cffffd200/clarity list|r - mostra a configuração atual",
    "|cffffd200/clarity debug|r - lista seus buffs atuais com spellID",
    "|cffffd200/clarity sonda|r - liga/desliga o teste de combate (o que o jogo deixa o addon ver)",
    "|cffffd200/clarity reset|r - restaura aparência e som (mantém as listas)",
    "|cffffd200/clarity reset tudo|r - restaura tudo, inclusive as listas",
}

function handlers.help()
    Print("comandos disponíveis:")
    local chat = DEFAULT_CHAT_FRAME
    for _, line in ipairs(HELP_LINES) do
        if chat and chat.AddMessage then
            chat:AddMessage("  " .. line)
        else
            print("  " .. line)
        end
    end
end
handlers.ajuda = handlers.help

function handlers.config()
    if not ns.Options:Open() then handlers.help() end
end
handlers.opcoes = handlers.config
handlers["opções"] = handlers.config
handlers.options = handlers.config

function handlers.sonda()
    if ns.Probe then
        ns.Probe:Toggle()
    else
        Print("a sonda não foi carregada. Feche e abra o jogo (arquivo novo no addon).")
    end
end
handlers.probe = handlers.sonda

function handlers.on()
    ns:SetEnabled(true)
    Print("addon |cff33ff33ativado|r.")
end
handlers.ligar = handlers.on

function handlers.off()
    ns:SetEnabled(false)
    Print("addon |cffff5555desativado|r. O overlay não aparece até você usar /clarity on.")
end
handlers.desligar = handlers.off

function handlers.test()
    ns:StartTest(TEST_SECONDS, true, true)
    Print("teste: overlay visível por %d segundos (a barra de tempo desce durante o teste).", TEST_SECONDS)
end
handlers.teste = handlers.test

function handlers.sound(args)
    local db = ns.db
    local sub, rest = SplitFirst(args)

    if sub == "on" then
        db.sound = true
        Print("som %s.", OnOffText(true))
    elseif sub == "off" then
        db.sound = false
        Print("som %s.", OnOffText(false))
    elseif sub == "test" or sub == "teste" then
        if not ns:PlayAlertSound(true) then
            Print("não foi possível tocar o som.")
        end
    elseif sub == "file" or sub == "arquivo" then
        if rest == "" then
            Print("uso: /clarity sound file <arquivo.ogg> (coloque o arquivo na pasta Media/ do addon)")
        elseif IsDefaultKeyword(rest) then
            db.soundFile = ""
            Print("usando o som nativo.")
        else
            db.soundFile = rest
            local result = ns:PlayAlertSound(true)
            if result == "custom" then
                Print("som próprio definido: %s", rest)
            else
                Print("som definido como \"%s\", mas o arquivo não tocou. Confira o nome e reinicie o jogo "
                    .. "(arquivos novos só são reconhecidos ao abrir o cliente). Até lá, o som nativo será usado.", rest)
            end
        end
    elseif IsDefaultKeyword(sub) then
        db.soundFile = ""
        Print("usando o som nativo.")
    else
        Print("som: %s, arquivo: %s", OnOffText(db.sound), db.soundFile ~= "" and db.soundFile or "nativo")
        Print("uso: /clarity sound on||off||test||padrao, ou /clarity sound file <arquivo.ogg>")
    end
end
handlers.som = handlers.sound

function handlers.scale(args)
    local db = ns.db
    local value = ToNumber(args:match("^(%S+)"))
    if not value or value < SCALE_MIN or value > SCALE_MAX then
        Print("uso: /clarity scale <%.2f a %.0f> (atual: %.2f)", SCALE_MIN, SCALE_MAX, db.scale)
        return
    end
    db.scale = value
    ns.Overlay:ApplySettings()
    ns:StartTest(TEST_SECONDS, false)
    Print("escala: %.2f", value)
end
handlers.escala = handlers.scale

function handlers.offset(args)
    local db = ns.db
    local xText, yText = args:match("^(%S+)%s+(%S+)")
    local x, y = ToNumber(xText), ToNumber(yText)
    if not x or not y or math.abs(x) > OFFSET_LIMIT or math.abs(y) > OFFSET_LIMIT then
        Print("uso: /clarity offset <x> <y> (atual: %d %d). X = distância de cada lado até o centro; Y = altura.",
            db.offsetX, db.offsetY)
        return
    end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    db.offsetX, db.offsetY = x, y
    ns.Overlay:ApplySettings()
    ns:StartTest(TEST_SECONDS, false)
    Print("posição: X = %d, Y = %d", x, y)
end
handlers.posicao = handlers.offset

function handlers.alpha(args)
    local db = ns.db
    local value = ToNumber(args:match("^(%S+)"))
    if not value or value < ALPHA_MIN or value > ALPHA_MAX then
        Print("uso: /clarity alpha <%.2f a %.0f> (atual: %.2f)", ALPHA_MIN, ALPHA_MAX, db.alpha)
        return
    end
    db.alpha = value
    ns.Overlay:ApplySettings()
    ns:StartTest(TEST_SECONDS, false)
    Print("opacidade: %.2f", value)
end
handlers.opacidade = handlers.alpha

function handlers.pulse(args)
    local db = ns.db
    local sub = SplitFirst(args)
    if sub == "on" then
        db.pulse = true
    elseif sub == "off" then
        db.pulse = false
    else
        Print("uso: /clarity pulse on||off (atual: %s)", OnOffText(db.pulse))
        return
    end
    Print("pulsação %s.", OnOffText(db.pulse))
end

function handlers.custo(args)
    local db = ns.db
    local sub = SplitFirst(args)
    if sub == "on" then
        db.costDetection = true
    elseif sub == "off" then
        db.costDetection = false
    else
        Print("uso: /clarity custo on||off (atual: %s)", OnOffText(db.costDetection))
        return
    end
    ns:Refresh(true)
    Print("detecção em combate pelo custo das magias %s.", OnOffText(db.costDetection))
end
handlers.cost = handlers.custo

function handlers.tempo(args)
    local db = ns.db
    local sub = SplitFirst(args)
    if sub == "on" then
        db.timerBar = true
    elseif sub == "off" then
        db.timerBar = false
    else
        Print("uso: /clarity tempo on||off (atual: %s)", OnOffText(db.timerBar))
        return
    end
    ns.Overlay:ApplySettings()
    Print("barra de tempo %s.", OnOffText(db.timerBar))
end
handlers.timer = handlers.tempo

function handlers.reset(args)
    local all = SplitFirst(args)
    local includeLists = (all == "tudo" or all == "all")
    ns:ResetDB(includeLists)
    if includeLists then
        Print("todas as configurações foram restauradas, inclusive as listas de detecção.")
    else
        Print("aparência e som restaurados. Listas de detecção mantidas (use /clarity reset tudo para restaurá-las).")
    end
end

function handlers.add(args)
    local db = ns.db
    local text = args:match("^(%d+)$")
    local id = text and tonumber(text)
    if not id or id <= 0 then
        Print("uso: /clarity add <spellID> (descubra o número com /clarity debug)")
        return
    end
    for _, existing in ipairs(db.spellIDs) do
        if existing == id then
            Print("o spellID %d já está na lista.", id)
            return
        end
    end
    db.spellIDs[#db.spellIDs + 1] = id
    DetectionChanged()

    local name = ns.Detect.GetSpellName(id)
    if name then
        Print("spellID %d (%s) adicionado.", id, name)
    else
        Print("spellID %d adicionado, mas o cliente não reconheceu essa magia. Confira o número.", id)
    end
end

function handlers.remove(args)
    local db = ns.db
    local text = args:match("^(%d+)$")
    local id = text and tonumber(text)
    if not id then
        Print("uso: /clarity remove <spellID>")
        return
    end
    for i, existing in ipairs(db.spellIDs) do
        if existing == id then
            table.remove(db.spellIDs, i)
            DetectionChanged()
            Print("spellID %d removido.", id)
            return
        end
    end
    Print("o spellID %d não está na lista.", id)
end
handlers.remover = handlers.remove

function handlers.addname(args)
    local db = ns.db
    local name = args:match("^%s*(.-)%s*$")
    if not name or name == "" then
        Print("uso: /clarity addname <nome do buff>")
        return
    end
    local key = ns.Lower(name)
    for _, existing in ipairs(db.names) do
        if ns.Lower(existing) == key then
            Print("o nome \"%s\" já está na lista.", existing)
            return
        end
    end
    db.names[#db.names + 1] = name
    DetectionChanged()
    Print("nome \"%s\" adicionado.", name)
end

function handlers.removename(args)
    local db = ns.db
    local name = args:match("^%s*(.-)%s*$")
    if not name or name == "" then
        Print("uso: /clarity removename <nome do buff>")
        return
    end
    local key = ns.Lower(name)
    for i, existing in ipairs(db.names) do
        if ns.Lower(existing) == key then
            table.remove(db.names, i)
            DetectionChanged()
            Print("nome \"%s\" removido.", existing)
            return
        end
    end
    Print("o nome \"%s\" não está na lista.", name)
end

-- Lista os spellIDs no formato "16870 (Clearcasting), ...".
local function DescribeSpellIDs()
    local parts = {}
    for _, id in ipairs(ns.db.spellIDs) do
        local name = ns.Detect:GetResolvedName(id)
        parts[#parts + 1] = string.format("%d (%s)", id, name or "desconhecido neste cliente")
    end
    return #parts > 0 and table.concat(parts, ", ") or "(nenhum)"
end

local function DescribeNames()
    local names = ns.Detect:GetEffectiveNames()
    return #names > 0 and table.concat(names, ", ") or "(nenhum)"
end

function handlers.list()
    local db = ns.db
    Print("configuração atual:")
    Print("  addon: %s", db.enabled and "|cff33ff33ativado|r" or "|cffff5555desativado|r")
    Print("  spellIDs: %s", DescribeSpellIDs())
    Print("  nomes (incluindo os nomes localizados dos IDs): %s", DescribeNames())
    Print("  som: %s; arquivo: %s; canal: %s", OnOffText(db.sound),
        db.soundFile ~= "" and db.soundFile or "nativo", tostring(db.soundChannel))
    Print("  escala: %.2f; posição: X = %d, Y = %d; opacidade: %.2f; pulsação: %s",
        db.scale, db.offsetX, db.offsetY, db.alpha, OnOffText(db.pulse))
    Print("  detecção em combate pelo custo das magias: %s", OnOffText(db.costDetection))
    Print("  barra de tempo: %s", OnOffText(db.timerBar))
end
handlers.lista = handlers.list

local PROBE_TEXT = {
    found       = "|cff33ff33encontrado|r",
    absent      = "|cffaaaaaaausente|r",
    secret      = "|cffff5555restrito|r",
    error       = "|cffff5555erro (bloqueado pelo cliente)|r",
    unavailable = "|cffaaaaaaAPI indisponível|r",
}

local COST_TEXT = {
    active   = "|cff33ff33indica buff ATIVO (custo 0)|r",
    inactive = "custo normal (buff inativo)",
    learning = "|cffaaaaaaaprendendo o custo normal das magias|r",
    off      = "|cffaaaaaadesligada|r",
}

function handlers.debug()
    local chat = DEFAULT_CHAT_FRAME
    local secret = ns.Detect.AurasAreSecret()

    if secret ~= nil then
        Print("auras restritas pelo cliente agora: %s", secret and "|cffff5555sim (em combate)|r" or "|cff33ff33não|r")
    end

    if secret then
        -- Em combate o cliente bloqueia a lista completa de buffs para addons.
        Print("lista completa de buffs: bloqueada pelo cliente agora (normal em combate).")
    else
        local rows, apiName, errors = ns.Detect:GetDebugRows()
        Print("buffs atuais do jogador (API: %s):", apiName)
        if #rows == 0 then
            Print("  (nenhum buff encontrado)")
        end
        for _, row in ipairs(rows) do
            local line = string.format("  #%d  %s  |cffaaaaaa(spellID: %s)|r%s",
                row.index, row.name, row.spellID, row.match and "  |cff33ff33<< DETECTADO|r" or "")
            if chat and chat.AddMessage then chat:AddMessage(line) else print(line) end
        end
        if errors > 0 then
            Print("alguns buffs não puderam ser lidos (restrição do cliente).")
        end
    end

    -- Busca por spellID (no Forever, só enxerga o buff fora de combate).
    Print("busca direta por spellID (fora de combate):")
    for _, probe in ipairs(ns.Detect:ProbeSpellIDs()) do
        local line = string.format("  %d (%s): %s", probe.id, probe.name or "nome desconhecido",
            PROBE_TEXT[probe.status] or probe.status)
        if chat and chat.AddMessage then chat:AddMessage(line) else print(line) end
    end

    Print("nomes usados: %s", DescribeNames())
    Print("custo das magias (detecção em combate): %s", COST_TEXT[ns.Detect:CostStatus()] or "?")
    Print("estado: %s", ns.Detect:IsActive() and "|cff33ff33buff ATIVO|r" or "buff inativo")
    Print("dica: em combate o Forever esconde os buffs dos addons; ali a detecção usa o custo das magias.")
end

---------------------------------------------------------------------------
-- Registro
---------------------------------------------------------------------------
function Commands:Handle(msg)
    if not ns.db then return end
    msg = type(msg) == "string" and msg:match("^%s*(.-)%s*$") or ""
    local cmd, args = SplitFirst(msg)

    local handler = handlers[cmd]
    if cmd == "" then
        -- Sem argumentos: abre/fecha a janela (ou mostra a ajuda se ela falhar).
        if not (ns.Options and ns.Options:Toggle()) then handlers.help() end
    elseif not handler then
        Print("comando desconhecido: \"%s\". Digite /clarity help para ver a lista.", cmd)
    else
        handler(args)
    end

    -- Mantém a janela de opções em dia com o que o comando mudou.
    if ns.Options then ns.Options:Refresh() end
end

function Commands:Register()
    -- O sistema de slash commands do cliente exige estes dois globais.
    _G.SLASH_CLARITYOVERLAY1 = "/clarity"
    SlashCmdList["CLARITYOVERLAY"] = function(msg)
        Commands:Handle(msg)
    end
end
