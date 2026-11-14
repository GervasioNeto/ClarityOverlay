--[[
    ClarityOverlay - Core.lua
    Inicialização, SavedVariables, eventos e som de alerta.

    Todo o estado do addon fica no namespace privado `ns` (segundo valor de `...`).
    Globais criados pelo addon:
      * ClarityOverlayDB                                    -> SavedVariables (.toc)
      * SLASH_CLARITYOVERLAY1 / SlashCmdList.CLARITYOVERLAY -> exigidos pelo sistema
        de slash commands do cliente (ver Commands.lua)
      * ClarityOverlayOptionsFrame                          -> janela de opções; o nome
        é exigido para a tecla Esc fechá-la (ver Options.lua)

    Este addon só MOSTRA informação (overlay + som). Ele não usa, lança nem
    sugere habilidades.
]]

local ADDON_NAME, ns = ...

ns.MEDIA_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

---------------------------------------------------------------------------
-- Configuração padrão
---------------------------------------------------------------------------
ns.defaults = {
    enabled      = true,      -- addon ligado (desligado: nunca mostra o overlay real)
    sound        = true,      -- tocar som quando o buff aparece
    soundFile    = "",        -- "" = som nativo; "arquivo.ogg" (em Media/) ou FileDataID numérico
    soundChannel = "Master",  -- canal de áudio ("Master" toca mesmo com os efeitos sonoros desligados)
    scale        = 1.0,       -- multiplicador do tamanho das texturas
    offsetX      = 150,       -- distância horizontal do centro da tela (esquerda = -X, direita = +X)
    offsetY      = 50,        -- deslocamento vertical a partir do centro da tela
    alpha        = 0.85,      -- opacidade máxima do overlay (0.05 a 1)
    pulse        = true,      -- pulsação leve enquanto o buff estiver ativo
    costDetection = true,     -- detectar em combate pelo custo das magias (ver Detect.lua)
    timerBar     = true,      -- o brilho do arco desce conforme o buff acaba

    -- Clearcasting no Forever (confirmado em wowhead.com/forever/spell=16870):
    -- buff de 15 s que zera o custo de mana da próxima magia do druida.
    spellIDs     = { 16870 },

    -- O nome localizado de cada spellID acima é adicionado automaticamente.
    -- "Omen of Clarity" (16864) NÃO entra por padrão: no Forever ele é a aura
    -- PASSIVA que dispara o Clearcasting e fica sempre ativa, então casar por esse
    -- nome deixaria o overlay aceso o tempo todo.
    names        = { "Clearcasting" },
}

-- Duração do Clearcasting no Forever (wowhead.com/forever/spell=16870).
-- Usada em combate, quando o cliente esconde o tempo restante da aura.
ns.BUFF_DURATION = 15

-- Chaves das listas de detecção (preservadas por "/clarity reset").
ns.LIST_KEYS = { spellIDs = true, names = true }

-- Estado em tempo de execução (não é salvo).
ns.state = {
    active     = false,  -- buff detectado no jogador
    testing    = false,  -- simulação via /clarity test
    expiration = nil,    -- quando o buff acaba (relógio de GetTime())
    duration   = nil,    -- duração total do buff
}

---------------------------------------------------------------------------
-- Utilitários
---------------------------------------------------------------------------
local CHAT_PREFIX = "|cff33ffccClarityOverlay|r: "

-- Mensagem no chat. Só aplica string.format quando há argumentos extras,
-- para que um "%" no texto não gere erro.
function ns.Print(msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    local chat = DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage then
        chat:AddMessage(CHAT_PREFIX .. msg)
    else
        print(CHAT_PREFIX .. msg)
    end
end

-- Minúsculas só para A-Z. string.lower depende da localidade do sistema e
-- pode alterar bytes de letras acentuadas em UTF-8 ("opções", nomes em pt-BR).
function ns.Lower(text)
    return (text:gsub("[A-Z]", string.lower))
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end
ns.DeepCopy = DeepCopy

---------------------------------------------------------------------------
-- SavedVariables
---------------------------------------------------------------------------
local function InitDB()
    if type(ClarityOverlayDB) ~= "table" then
        ClarityOverlayDB = {}
    end
    local db = ClarityOverlayDB

    -- Preenche chaves ausentes e corrige tipos inválidos.
    for key, default in pairs(ns.defaults) do
        if type(db[key]) ~= type(default) then
            db[key] = DeepCopy(default)
        end
    end

    -- Sanitiza as listas (o arquivo pode ter sido editado à mão).
    local ids, seen = {}, {}
    for _, id in ipairs(db.spellIDs) do
        id = tonumber(id)
        if id and id > 0 then
            id = math.floor(id)
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    db.spellIDs = ids

    local names = {}
    for _, name in ipairs(db.names) do
        if type(name) == "string" and name:match("%S") then
            names[#names + 1] = name
        end
    end
    db.names = names

    ns.db = db
end

-- Restaura os padrões. Por padrão mantém as listas de detecção; com
-- includeLists = true restaura tudo.
function ns:ResetDB(includeLists)
    for key, default in pairs(self.defaults) do
        if includeLists or not self.LIST_KEYS[key] then
            self.db[key] = DeepCopy(default)
        end
    end
    self.Detect:Rebuild()
    self.Overlay:ApplySettings()
    self:Refresh(false)
end

---------------------------------------------------------------------------
-- Som
---------------------------------------------------------------------------
local FALLBACK_SOUNDKIT_ID = 23287  -- valor de SOUNDKIT.UI_POWER_AURA_GENERIC no Retail
local RAID_WARNING_ID      = 8959   -- valor de SOUNDKIT.RAID_WARNING no Retail

local function TryPlaySound(kitID, channel)
    if not PlaySound or not kitID then return false end
    local ok, willPlay = pcall(PlaySound, kitID, channel)
    return ok and willPlay and true or false
end

-- Toca o alerta. force = true ignora a opção "som desligado" (usado por
-- "/clarity sound test"). Retorna "custom", "default" ou nil (não tocou).
function ns:PlayAlertSound(force)
    local db = self.db
    if not db or (not db.sound and not force) then return nil end
    local channel = db.soundChannel

    -- 1) Som próprio: nome de arquivo em Media/, caminho completo ou FileDataID.
    if db.soundFile ~= "" and PlaySoundFile then
        local target = tonumber(db.soundFile) or db.soundFile
        if type(target) == "string" and not target:find("[\\/]") then
            target = self.MEDIA_PATH .. target
        end
        local ok, willPlay = pcall(PlaySoundFile, target, channel)
        if ok and willPlay then return "custom" end
        -- Arquivo inválido ou ausente: cai para o som nativo abaixo.
    end

    -- 2) Som nativo (o mesmo "ding" do Spell Activation Overlay do Retail).
    local kits = type(SOUNDKIT) == "table" and SOUNDKIT or {}
    if TryPlaySound(kits.UI_POWER_AURA_GENERIC or FALLBACK_SOUNDKIT_ID, channel) then
        return "default"
    end
    if TryPlaySound(kits.RAID_WARNING or RAID_WARNING_ID, channel) then
        return "default"
    end
    return nil
end

---------------------------------------------------------------------------
-- Estado e visibilidade
---------------------------------------------------------------------------
function ns:UpdateVisibility()
    if self.state.active or self.state.testing then
        self.Overlay:FadeIn()
    else
        self.Overlay:FadeOut()
    end
end

-- Atualiza o tempo restante do buff para a barra de tempo.
-- Fora de combate usa o tempo exato da aura. Em combate o cliente esconde esse
-- tempo, então um proc novo começa a contar BUFF_DURATION a partir de agora.
-- Limitação: se o buff for renovado em combate sem passar por "inativo", a
-- contagem não reinicia; ao chegar a zero o arco fica todo apagado, mas visível,
-- até o buff sumir (e corrige ao sair de combate).
function ns:SyncTimer(isNewProc)
    local expiration, duration = self.Detect:GetExactTiming()
    if expiration then
        self.state.expiration, self.state.duration = expiration, duration
    elseif isNewProc or not self.state.expiration then
        self.state.duration = self.BUFF_DURATION
        self.state.expiration = GetTime() + self.BUFF_DURATION
    end
    self.Overlay:SetTimer(self.state.expiration, self.state.duration)
end

-- Relê os buffs e atualiza o overlay. O som só toca na transição
-- inativo -> ativo, nunca a cada UNIT_AURA enquanto o buff continua.
function ns:Refresh(silent)
    if not self.db then return end
    local active = self.db.enabled and self.Detect:IsActive() or false
    if active then
        self:SyncTimer(not self.state.active)
    end
    if active == self.state.active then return end
    self.state.active = active
    if active and not silent then
        self:PlayAlertSound(false)
    end
    self:UpdateVisibility()
    -- Atualiza a linha "Clearcasting agora" da janela (se estiver aberta).
    if self.Options then self.Options:Refresh() end
end

-- Liga/desliga o addon. Ao ligar com o buff já ativo, o overlay aparece sem som.
function ns:SetEnabled(enabled)
    self.db.enabled = enabled and true or false
    self:Refresh(true)
    if self.Options then self.Options:Refresh() end
end

-- Mostra o overlay por `duration` segundos sem precisar do buff.
-- drain = true: a barra de tempo desce ao longo do teste (mostra o efeito);
-- false: arco cheio (usado nas prévias de tamanho/posição).
local testToken = 0
function ns:StartTest(duration, withSound, drain)
    testToken = testToken + 1
    local token = testToken
    duration = duration or 3

    self.state.testing = true
    -- Com o buff real ativo, a barra continua mostrando o tempo real.
    if not self.state.active then
        if drain then
            self.Overlay:SetTimer(GetTime() + duration, duration)
        else
            self.Overlay:SetTimer(nil)
        end
    end
    self.Overlay:ApplySettings()
    self:UpdateVisibility()
    if withSound then
        self:PlayAlertSound(false)
    end

    C_Timer.After(duration, function()
        if token ~= testToken then return end  -- um teste mais novo assumiu
        ns.state.testing = false
        ns:UpdateVisibility()
    end)
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local unitEventFiltered = false  -- true se o cliente já filtra UNIT_AURA para "player"

-- Até o primeiro PLAYER_ENTERING_WORLD terminar, as checagens são silenciosas:
-- se o buff já estiver ativo no login ou após /reload, o overlay aparece,
-- mas o som não toca.
local loginSyncDone = false

local function CheckAuras()
    ns:Refresh(not loginSyncDone)
end

-- Uma segunda checagem logo depois de cada UNIT_AURA, para o caso de o custo
-- das magias ser recalculado um instante depois da mudança de aura.
local recheckPending = false
local function ScheduleRecheck()
    if recheckPending then return end
    recheckPending = true
    C_Timer.After(0.15, function()
        recheckPending = false
        CheckAuras()
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")

        InitDB()
        ns.Detect:Rebuild()
        ns.Overlay:Create()
        ns.Commands:Register()
        -- Página em Opções > AddOns. Se falhar, os comandos continuam funcionando.
        pcall(ns.Options.RegisterSettingsPanel, ns.Options)

        -- Só auras do jogador. RegisterUnitEvent existe no cliente moderno;
        -- o fallback filtra a unidade no próprio handler.
        if self.RegisterUnitEvent then
            self:RegisterUnitEvent("UNIT_AURA", "player")
            unitEventFiltered = true
        else
            self:RegisterEvent("UNIT_AURA")
        end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Ao sair de combate as auras voltam a ser legíveis: ressincroniza.
        self:RegisterEvent("PLAYER_REGEN_ENABLED")

    elseif not ns.db then
        return

    elseif event == "UNIT_AURA" then
        -- Em combate o payload do UNIT_AURA é inteiramente secreto (inclusive a
        -- unidade), e comparar arg1 geraria erro. Com RegisterUnitEvent só chegam
        -- eventos do jogador, então nem precisamos olhar arg1.
        if not unitEventFiltered and not ns.Detect.IsSecret(arg1) and arg1 ~= "player" then
            return
        end
        CheckAuras()
        ScheduleRecheck()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Os nomes localizados das magias podem não estar prontos no ADDON_LOADED.
        ns.Detect:Rebuild()
        CheckAuras()
        loginSyncDone = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        CheckAuras()
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
