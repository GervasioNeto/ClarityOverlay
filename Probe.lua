--[[
    ClarityOverlay - Probe.lua
    Sonda de combate (/clarity sonda). Durante um combate, anota o que o cliente
    deixa um addon enxergar, para saber se existe algum caminho para mostrar o
    Clearcasting em combate. Não muda o comportamento do overlay.

    Caminhos testados:
      1. Busca do Clearcasting por spellID (a detecção normal do addon).
      2. Custo de mana/energia/raiva de magias de druida, que cai para 0 com o
         Clearcasting ativo.
      3. Eventos de alerta de feitiço da própria Blizzard
         (SPELL_ACTIVATION_OVERLAY_* e SPELL_ACTIVATION_OVERLAY_GLOW_*).
    Também informa se algumas funções de exibição do Midnight existem.

    Desligada, a sonda não registra nenhum evento (custo zero).
]]

local ADDON_NAME, ns = ...

local Probe = {}
ns.Probe = Probe

local IsSecret    = ns.Detect.IsSecret
local ReadCost    = ns.Detect.ReadCost
local COST_SPELLS = ns.Detect.COST_SPELLS

local OVERLAY_EVENTS = { "SPELL_ACTIVATION_OVERLAY_SHOW", "SPELL_ACTIVATION_OVERLAY_HIDE" }
local GLOW_EVENTS    = { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }

local frame = CreateFrame("Frame")
local armed, inCombat = false, false
local stats
local eventAvailable = {}  -- [evento] = true se o cliente aceitou o registro

local function Now()
    return GetTime and GetTime() or 0
end

local function NewStats()
    return {
        start   = Now(),
        samples = 0,
        id      = { found = 0, absent = 0, secret = 0, error = 0, unavailable = 0 },
        cost    = {},  -- [spellID] = { min, max, secret, error, none }
        events  = {},  -- [evento] = { count, secret, ids = { [spellID] = true } }
    }
end

local function ChatLine(text)
    local chat = DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage then chat:AddMessage(text) else print(text) end
end

---------------------------------------------------------------------------
-- Coleta
---------------------------------------------------------------------------

local function Sample()
    stats.samples = stats.samples + 1

    for _, result in ipairs(ns.Detect:ProbeSpellIDs()) do
        stats.id[result.status] = (stats.id[result.status] or 0) + 1
    end

    for _, spellID in ipairs(COST_SPELLS) do
        local entry = stats.cost[spellID]
        if not entry then
            entry = { secret = 0, error = 0, none = 0 }
            stats.cost[spellID] = entry
        end
        local ok, result = pcall(ReadCost, spellID)
        if not ok then
            entry.error = entry.error + 1
        elseif type(result) == "number" then
            entry.min = entry.min and math.min(entry.min, result) or result
            entry.max = entry.max and math.max(entry.max, result) or result
        elseif result == "secret" then
            entry.secret = entry.secret + 1
        else
            entry.none = entry.none + 1
        end
    end
end

local function RecordEvent(event, spellID)
    local entry = stats.events[event]
    if not entry then
        entry = { count = 0, secret = 0, ids = {} }
        stats.events[event] = entry
    end
    entry.count = entry.count + 1
    if IsSecret(spellID) then
        entry.secret = entry.secret + 1
    elseif type(spellID) == "number" then
        entry.ids[spellID] = true
    end
end

---------------------------------------------------------------------------
-- Relatório
---------------------------------------------------------------------------
local function YesNo(value)
    return value and "|cff33ff33sim|r" or "|cffff5555não|r"
end

local function DescribeEvents(names)
    if not eventAvailable[names[1]] then
        return "|cffaaaaaaevento não existe neste cliente|r"
    end
    local count, secret, ids = 0, 0, {}
    for _, event in ipairs(names) do
        local entry = stats.events[event]
        if entry then
            count, secret = count + entry.count, secret + entry.secret
            for id in pairs(entry.ids) do ids[#ids + 1] = id end
        end
    end
    if count == 0 then return "nenhum evento" end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = string.format("%d (%s)", id, ns.Detect.GetSpellName(id) or "?")
    end
    local text = string.format("|cff33ff33%d evento(s)|r", count)
    if #parts > 0 then text = text .. ", spellIDs: " .. table.concat(parts, ", ") end
    if secret > 0 then text = text .. string.format(", %d restritos", secret) end
    return text
end

local function DescribeCosts()
    local readable, secret, errors, zeroNames = 0, 0, 0, {}
    for _, spellID in ipairs(COST_SPELLS) do
        local entry = stats.cost[spellID]
        if entry then
            if entry.min then readable = readable + 1 end
            secret, errors = secret + entry.secret, errors + entry.error
            if entry.min == 0 and entry.max and entry.max > 0 then
                zeroNames[#zeroNames + 1] = ns.Detect.GetSpellName(spellID) or tostring(spellID)
            end
        end
    end
    local status
    if readable > 0 then
        status = string.format("|cff33ff33legível|r (%d de %d magias)", readable, #COST_SPELLS)
        if secret > 0 then status = status .. ", às vezes restrito" end
    elseif secret > 0 then
        status = "|cffff5555restrito|r"
    elseif errors > 0 then
        status = "|cffff5555erro (bloqueado)|r"
    else
        status = "sem dados"
    end
    local zero = #zeroNames > 0 and (YesNo(true) .. " (" .. table.concat(zeroNames, ", ") .. ")") or YesNo(false)
    return status, zero
end

local function NativeOverlayInfo()
    local frameExists = SpellActivationOverlayFrame ~= nil
    local option = "?"
    if C_CVar and C_CVar.GetCVar then
        local ok, value = pcall(C_CVar.GetCVar, "displaySpellActivationOverlays")
        if ok and type(value) == "string" then option = value end
    end
    return frameExists, option
end

local function Report()
    local id = stats.id
    ns.Print("sonda: resultado do combate (%d s, %d leituras):", math.floor(Now() - stats.start), stats.samples)
    ChatLine(string.format("  1) Clearcasting por spellID: encontrado %dx, ausente %dx, restrito %dx, erro %dx",
        id.found, id.absent, id.secret, id.error))

    local costStatus, zero = DescribeCosts()
    ChatLine("  2) Custo das magias em combate: " .. costStatus)
    ChatLine("      custo caiu para 0 durante o combate: " .. zero)

    ChatLine("  3) Alerta de feitiço da Blizzard: " .. DescribeEvents(OVERLAY_EVENTS))
    ChatLine("      brilho de botão da Blizzard: " .. DescribeEvents(GLOW_EVENTS))
    local nativeFrame, nativeOption = NativeOverlayInfo()
    ChatLine(string.format("      alertas nativos: quadro existe %s, opção = %s", YesNo(nativeFrame), nativeOption))

    ChatLine(string.format("  4) Funções de exibição: SetAlphaFromBoolean %s, GetAuraDuration %s",
        YesNo(frame.SetAlphaFromBoolean ~= nil),
        YesNo(C_UnitAuras ~= nil and C_UnitAuras.GetAuraDuration ~= nil)))
    ns.Print("fim do relatório. A sonda continua ligada; /clarity sonda desliga.")
end

---------------------------------------------------------------------------
-- Eventos e controle
---------------------------------------------------------------------------
frame:SetScript("OnEvent", function(self, event, arg1)
    if not armed then return end
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        stats = NewStats()
        Sample()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Sem leitura aqui: o relatório só conta o que foi visto DENTRO do combate.
        if inCombat then
            inCombat = false
            Report()
        end
    elseif event == "UNIT_AURA" then
        -- Em combate o payload é secreto; não olhamos arg1, só amostramos.
        if inCombat then Sample() end
    else
        RecordEvent(event, arg1)
    end
end)

function Probe:IsArmed()
    return armed
end

function Probe:Start()
    armed, inCombat = true, false
    stats = NewStats()
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if frame.RegisterUnitEvent then
        frame:RegisterUnitEvent("UNIT_AURA", "player")
    else
        frame:RegisterEvent("UNIT_AURA")
    end
    -- Eventos que podem não existir (ou estar bloqueados) neste cliente.
    for _, list in ipairs({ OVERLAY_EVENTS, GLOW_EVENTS }) do
        for _, event in ipairs(list) do
            eventAvailable[event] = pcall(frame.RegisterEvent, frame, event) and true or false
        end
    end
    ns.Print("sonda |cff33ff33ligada|r. Entre em combate, lute até o Clearcasting aparecer nos seus buffs "
        .. "e então saia do combate. O resultado aparece aqui no chat.")
end

function Probe:Stop()
    armed, inCombat = false, false
    frame:UnregisterAllEvents()
    ns.Print("sonda |cffff5555desligada|r.")
end

function Probe:Toggle()
    if armed then self:Stop() else self:Start() end
end
