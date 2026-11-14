--[[
    ClarityOverlay - Detect.lua
    Detecção do buff Clearcasting (proc do Omen of Clarity) no jogador.

    Estratégia, em ordem (a primeira que encontrar o buff encerra a busca).
    Os passos 1 a 3 leem as auras e só funcionam fora de combate no Forever;
    o passo 4 (custo das magias) é o que funciona em combate.
      1. C_UnitAuras.GetPlayerAuraBySpellID(id) para cada spellID configurado.
         Só testa se a aura existe; não compara nenhum campo dela.
      2. C_UnitAuras.GetAuraDataBySpellName("player", nome, "HELPFUL") para cada
         nome, se essa função existir no cliente.
      3. Varredura dos buffs com C_UnitAuras.GetAuraDataByIndex (ou UnitAura /
         UnitBuff em clientes sem C_UnitAuras), comparando spellID e nome
         (sem diferenciar maiúsculas/minúsculas).
      4. Custo das magias de druida: com o Clearcasting ativo, todas custam 0.

    Valores "secretos" (Midnight / Forever): em combate os campos das auras
    podem vir restritos, e comparar ou fazer contas com eles gera erro de Lua.
    Por isso toda leitura passa por pcall() e por IsSecret(). Se não der para
    ler, o resultado é "não encontrado", em silêncio. É melhor perder um aviso
    do que deixar um aviso falso preso na tela.
]]

local ADDON_NAME, ns = ...

local Detect = {}
ns.Detect = Detect

local pcall, type, pairs, ipairs, tostring = pcall, type, pairs, ipairs, tostring
local strlower = ns.Lower  -- só A-Z; seguro para nomes acentuados em UTF-8

-- Limite de segurança da varredura por índice.
local MAX_AURA_INDEX = 100
-- Erros seguidos que encerram a varredura (API inteira restrita).
local MAX_CONSECUTIVE_ERRORS = 5

-- Tabelas de busca, reconstruídas a partir do ClarityOverlayDB em Rebuild().
local spellSet = {}  -- [spellID] = true
local nameSet  = {}  -- [nome em minúsculas] = true
local nameList = {}  -- nomes como digitados/resolvidos (busca direta por nome)
local resolved = {}  -- [spellID] = nome localizado (só para exibição)

---------------------------------------------------------------------------
-- Proteção contra valores secretos
---------------------------------------------------------------------------

-- true se o valor for secreto. issecretvalue() só existe em clientes com o
-- sistema de valores secretos; nos outros, nada é secreto.
local function IsSecret(value)
    local check = issecretvalue
    if type(check) ~= "function" then return false end
    local ok, result = pcall(check, value)
    if not ok then return true end  -- na dúvida, trate como restrito
    return result == true
end
Detect.IsSecret = IsSecret

-- true se o cliente informa que as auras estão restritas agora (ex.: em combate).
-- nil se o cliente não tem essa API.
function Detect.AurasAreSecret()
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return nil end
    local ok, result = pcall(C_Secrets.ShouldAurasBeSecret)
    if not ok or IsSecret(result) then return nil end
    return result == true
end

---------------------------------------------------------------------------
-- Nomes de magias (localizados pelo próprio cliente)
---------------------------------------------------------------------------
local function SpellNameRaw(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if type(name) == "string" and name ~= "" then return name end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    if GetSpellInfo then  -- API antiga, pode não existir
        local name = GetSpellInfo(spellID)
        if type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

-- Nome localizado de um spellID, ou nil se o cliente não o conhecer.
function Detect.GetSpellName(spellID)
    local ok, name = pcall(SpellNameRaw, spellID)
    if ok and not IsSecret(name) and type(name) == "string" then
        return name
    end
    return nil
end

---------------------------------------------------------------------------
-- Listas de detecção
---------------------------------------------------------------------------
local function AddName(name)
    if type(name) ~= "string" then return end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return end
    local key = strlower(name)
    if not nameSet[key] then
        nameSet[key] = true
        nameList[#nameList + 1] = name
    end
end

-- Recria as tabelas de busca a partir do banco salvo. Chame após qualquer
-- mudança nas listas.
function Detect:Rebuild()
    spellSet, nameSet, nameList, resolved = {}, {}, {}, {}
    local db = ns.db
    if not db then return end

    for _, id in ipairs(db.spellIDs) do
        spellSet[id] = true
        local name = Detect.GetSpellName(id)
        if name then
            resolved[id] = name
            AddName(name)  -- nome no idioma do cliente
        end
    end
    for _, name in ipairs(db.names) do
        AddName(name)
    end
end

function Detect:GetResolvedName(spellID)
    return resolved[spellID]
end

-- Nomes efetivamente usados na detecção (configurados + resolvidos dos IDs).
function Detect:GetEffectiveNames()
    local copy = {}
    for i, name in ipairs(nameList) do copy[i] = name end
    return copy
end

---------------------------------------------------------------------------
-- Funções de leitura. Todas podem gerar erro com valores secretos, por isso
-- só são chamadas via pcall().
---------------------------------------------------------------------------

-- Compara spellID/nome de uma aura com as listas.
local function AuraMatches(spellID, name)
    if not IsSecret(spellID) and spellID and spellSet[spellID] then
        return true
    end
    if not IsSecret(name) and type(name) == "string" and nameSet[strlower(name)] then
        return true
    end
    return false
end

local function HasPlayerAuraByID(spellID)
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if IsSecret(aura) then return false end
    return aura ~= nil
end

local function HasPlayerAuraByName(name)
    local aura = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
    if IsSecret(aura) then return false end
    return aura ~= nil
end

-- Marca uma aura que existe mas não pôde ser lida.
local RESTRICTED = "restricted"

-- Retorno: nil = não há aura nesse índice (fim da lista); RESTRICTED = aura
-- ilegível; true/false = casou ou não.
local function CheckModernIndex(index)
    local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
    if IsSecret(aura) then return RESTRICTED end
    if aura == nil then return nil end
    return AuraMatches(aura.spellId, aura.name)
end

-- Clientes sem C_UnitAuras: UnitAura/UnitBuff, spellID na 10ª posição.
local function CheckLegacyIndex(index)
    local query = UnitAura or UnitBuff
    local name, _, _, _, _, _, _, _, _, spellID = query("player", index, "HELPFUL")
    if IsSecret(name) then return RESTRICTED end
    if name == nil then return nil end
    return AuraMatches(spellID, name)
end

local function GetIndexReader()
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return CheckModernIndex
    elseif UnitAura or UnitBuff then
        return CheckLegacyIndex
    end
    return nil
end

---------------------------------------------------------------------------
-- Detecção pelo custo das magias (o caminho que funciona em combate)
--
-- Em combate o Forever esconde as auras dos addons, mas o custo das magias
-- continua legível (confirmado com /clarity sonda). O Clearcasting reduz em
-- 100% o custo de todas as magias de druida, então "todas as magias de
-- referência custando 0" indica o buff ativo.
--
-- É um caminho indireto: se a Blizzard bloquear a leitura de custo num patch,
-- ele simplesmente para de detectar (sem erro de Lua).
---------------------------------------------------------------------------

-- Magias afetadas pelo Clearcasting segundo o Wowhead do Forever (rank 1),
-- cobrindo forma normal (mana), gato (energia) e urso (raiva).
local COST_SPELLS = {
    5185,  -- Healing Touch
    774,   -- Rejuvenation
    8936,  -- Regrowth
    8921,  -- Moonfire
    1082,  -- Claw
    5221,  -- Shred
    6807,  -- Maul
}
Detect.COST_SPELLS = COST_SPELLS

-- Mínimo de magias custando 0 para considerar o buff ativo (evita falso
-- positivo de algum efeito que zere só uma magia).
local MIN_ZERO_COST_SPELLS = 2

-- Maior custo legível já visto de cada magia (o custo "normal", sem o buff).
local normalCost = {}

-- Custo atual de uma magia. Pode gerar erro (chame via pcall).
-- Retorna um número, ou "secret" / "none" / "unavailable".
function Detect.ReadCost(spellID)
    local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    if not getCost then return "unavailable" end
    local costs = getCost(spellID)
    if IsSecret(costs) then return "secret" end
    if type(costs) ~= "table" then return "none" end
    local first = costs[1]
    if IsSecret(first) then return "secret" end
    if type(first) ~= "table" then return "none" end
    local cost = first.cost
    if IsSecret(cost) then return "secret" end
    if type(cost) ~= "number" then return "none" end
    return cost
end

-- true se o custo das magias indica Clearcasting ativo. Também aprende o
-- custo normal de cada magia sempre que ele aparece acima de zero.
local function CostSaysActive()
    local zeros, paid = 0, 0
    for _, spellID in ipairs(COST_SPELLS) do
        local ok, cost = pcall(Detect.ReadCost, spellID)
        if ok and type(cost) == "number" then
            if cost > 0 then
                paid = paid + 1
                if not normalCost[spellID] or cost > normalCost[spellID] then
                    normalCost[spellID] = cost
                end
            elseif normalCost[spellID] then
                zeros = zeros + 1  -- custava algo e agora custa 0
            end
        end
    end
    return paid == 0 and zeros >= MIN_ZERO_COST_SPELLS
end

-- Tempo exato do buff (expiração no relógio de GetTime() e duração), lido
-- da aura. Só funciona fora de combate no Forever; em combate retorna nil.
local function ReadTiming(spellID)
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if IsSecret(aura) or aura == nil then return nil end
    local expiration, duration = aura.expirationTime, aura.duration
    if IsSecret(expiration) or IsSecret(duration) then return nil end
    if type(expiration) == "number" and type(duration) == "number" and expiration > 0 and duration > 0 then
        return expiration, duration
    end
    return nil
end

function Detect:GetExactTiming()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    for id in pairs(spellSet) do
        local ok, expiration, duration = pcall(ReadTiming, id)
        if ok and expiration then return expiration, duration end
    end
    return nil
end

-- Para o /clarity debug: "active", "inactive", "learning" ou "off".
function Detect:CostStatus()
    if not (ns.db and ns.db.costDetection) then return "off" end
    if CostSaysActive() then return "active" end
    for _ in pairs(normalCost) do return "inactive" end
    return "learning"
end

---------------------------------------------------------------------------
-- API pública
---------------------------------------------------------------------------

-- true se o buff estiver ativo no jogador. Sempre retorna um booleano comum
-- e nunca gera erro de Lua.
function Detect:IsActive()
    local api = C_UnitAuras

    -- 1) Busca direta por spellID.
    if api and api.GetPlayerAuraBySpellID then
        for id in pairs(spellSet) do
            local ok, found = pcall(HasPlayerAuraByID, id)
            if ok and found == true then return true end
        end
    end

    -- 2) Busca direta por nome (se o cliente tiver essa função).
    if api and api.GetAuraDataBySpellName then
        for _, name in ipairs(nameList) do
            local ok, found = pcall(HasPlayerAuraByName, name)
            if ok and found == true then return true end
        end
    end

    -- 3) Varredura de todos os buffs. Com auras secretas (combate) as APIs por
    -- índice dão erro de Lua por definição (notas do patch 12.1.0), então nem tenta.
    local reader = GetIndexReader()
    if reader and Detect.AurasAreSecret() ~= true then
        local errors = 0
        for i = 1, MAX_AURA_INDEX do
            local ok, result = pcall(reader, i)
            if ok and result ~= RESTRICTED then
                errors = 0
                if result == nil then break end
                if result == true then return true end
            else
                -- Aura ilegível: ignora e segue para a próxima. Muitas seguidas
                -- indicam que a lista inteira está restrita.
                errors = errors + 1
                if errors >= MAX_CONSECUTIVE_ERRORS then break end
            end
        end
    end

    -- 4) Custo das magias: o único sinal que o cliente deixa ver em combate.
    if ns.db and ns.db.costDetection and CostSaysActive() then
        return true
    end

    return false
end

-- Diagnóstico da busca direta por spellID, a única que o cliente permite em
-- combate. Status: "found" | "absent" | "secret" | "error" | "unavailable".
local function ProbeID(spellID)
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    if IsSecret(aura) then return "secret" end
    if aura == nil then return "absent" end
    return "found"
end

function Detect:ProbeSpellIDs()
    local out = {}
    local available = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    for _, id in ipairs(ns.db.spellIDs) do
        local status = "unavailable"
        if available then
            local ok, result = pcall(ProbeID, id)
            status = ok and result or "error"
        end
        out[#out + 1] = { id = id, name = resolved[id], status = status }
    end
    return out
end

-- Texto seguro para o chat a partir de um valor que pode ser secreto.
local function SafeText(value)
    if IsSecret(value) then return "|cffff8080<restrito>|r" end
    if value == nil then return "?" end
    return tostring(value)
end

local function DescribeModern(index)
    local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
    if IsSecret(aura) then return { name = SafeText(aura), spellID = "?", match = false, restricted = true } end
    if aura == nil then return nil end
    local ok, match = pcall(AuraMatches, aura.spellId, aura.name)
    return { name = SafeText(aura.name), spellID = SafeText(aura.spellId), match = ok and match == true }
end

local function DescribeLegacy(index)
    local query = UnitAura or UnitBuff
    local name, _, _, _, _, _, _, _, _, spellID = query("player", index, "HELPFUL")
    if IsSecret(name) then return { name = SafeText(name), spellID = "?", match = false, restricted = true } end
    if name == nil then return nil end
    local ok, match = pcall(AuraMatches, spellID, name)
    return { name = SafeText(name), spellID = SafeText(spellID), match = ok and match == true }
end

-- Lista os buffs atuais para o /clarity debug.
-- Retorna: rows ({index, name, spellID, match}), nome da API usada, nº de erros.
function Detect:GetDebugRows()
    local rows, errors, consecutive = {}, 0, 0
    local describe, apiName
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        describe, apiName = DescribeModern, "C_UnitAuras.GetAuraDataByIndex"
    elseif UnitAura then
        describe, apiName = DescribeLegacy, "UnitAura"
    elseif UnitBuff then
        describe, apiName = DescribeLegacy, "UnitBuff"
    else
        return rows, "nenhuma disponível", 0
    end

    for i = 1, MAX_AURA_INDEX do
        local ok, row = pcall(describe, i)
        if ok and row == nil then break end  -- fim da lista
        if not ok then
            row = { name = "|cffff8080<erro de leitura>|r", spellID = "?", match = false, restricted = true }
        end
        row.index = i
        rows[#rows + 1] = row

        if row.restricted then
            -- Muitas auras ilegíveis seguidas: a lista inteira está restrita.
            errors = errors + 1
            consecutive = consecutive + 1
            if consecutive >= MAX_CONSECUTIVE_ERRORS then break end
        else
            consecutive = 0
        end
    end
    return rows, apiName, errors
end
