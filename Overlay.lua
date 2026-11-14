--[[
    ClarityOverlay - Overlay.lua
    Frame e texturas do aviso visual: fade-in, fade-out, pulsação e a "barra de
    tempo" do Clearcasting.

    Cada arco é feito de camadas (texturas geradas por Tools/generate_textures.py):
      * glow    -> o brilho em volta. Nunca é cortado; só perde força aos poucos
                   ao longo da duração (o arco nunca some enquanto o buff existe).
      * core    -> a linha central, que é a barra de tempo. É desenhada em três
                   fatias verticais da mesma textura:
                     fill    - parte de baixo, brilho total (o tempo que resta);
                     dim     - parte de cima, quase apagada e acinzentada (o tempo
                               que já passou), como um trilho;
                     feather - faixa curta em degradê logo acima do nível.
      * spark   -> uma faísca que desliza pela linha central marcando o nível.
    O nível desce de cima para baixo ao longo da duração do buff.

    As animações usam um OnUpdate que só roda enquanto o frame está visível
    (frames ocultos não recebem OnUpdate). Ou seja: nada roda enquanto o buff
    não está ativo. A detecção do buff é feita só por eventos (Core.lua).
]]

local ADDON_NAME, ns = ...

local Overlay = {}
ns.Overlay = Overlay

-- Texturas (TGA 32 bits com alfa). Para trocar, substitua os arquivos em
-- Media/ mantendo os nomes, ou gere novas com Tools/generate_textures.py.
local TEXTURES = {
    { core = ns.MEDIA_PATH .. "ClarityLeftCore.tga",  glow = ns.MEDIA_PATH .. "ClarityLeftGlow.tga"  },
    { core = ns.MEDIA_PATH .. "ClarityRightCore.tga", glow = ns.MEDIA_PATH .. "ClarityRightGlow.tga" },
}
local TEXTURE_SPARK = ns.MEDIA_PATH .. "ClaritySpark.tga"

-- Tamanho de cada lado em unidades de interface, com escala 1.0.
local BASE_WIDTH, BASE_HEIGHT = 128, 256
local SPARK_SIZE = 40

local FADE_IN_TIME  = 0.15  -- segundos
local FADE_OUT_TIME = 0.20  -- segundos
local PULSE_PERIOD  = 1.6   -- segundos por ciclo de pulsação
local PULSE_MIN     = 0.70  -- alfa relativo no ponto mais fraco da pulsação

-- Faixa vertical da imagem onde o arco está desenhado (0 = topo, 1 = base).
local ART_TOP, ART_BOTTOM = 0.06, 0.94
-- Geometria da linha central, em coordenadas de exibição 128x256 do lado
-- esquerdo (mesmos valores de CX, CY, RX, RY em Tools/generate_textures.py).
local ARC_CX, ARC_CY, ARC_RX, ARC_RY = 150, 128, 122, 124

local CORE_EMPTY_ALPHA = 0.10                -- trilho: o que já passou da linha central
local CORE_EMPTY_TINT  = { 0.55, 0.62, 0.62 } -- trilho levemente acinzentado
local CORE_FEATHER     = 0.04                -- altura da faixa em degradê (fração da imagem)
local FEATHER_ALPHA_GRADIENT = 1 - CORE_EMPTY_ALPHA
local FEATHER_ALPHA_FLAT     = 0.45          -- se o cliente não tiver degradê
local GLOW_MIN = 0.45                        -- força do brilho em volta no fim do tempo

local cos, pi, min, max, abs, sqrt = math.cos, math.pi, math.min, math.max, math.abs, math.sqrt

local frame
local sides = {}            -- { holder, glow, fill, dim, feather, spark, mirrored }
Overlay.sides = sides
local mode      = "hidden"  -- "hidden" | "fadein" | "shown" | "fadeout"
local progress  = 0         -- 0 = invisível, 1 = totalmente visível
local pulseTime = 0
local timerExpiration, timerDuration  -- nil = sem barra de tempo (arco cheio)
local lastLevel

-- Curva suave (ease-in-out) para o fade.
local function Smooth(x)
    return x * x * (3 - 2 * x)
end

---------------------------------------------------------------------------
-- Barra de tempo
---------------------------------------------------------------------------

-- Mostra só a fatia vertical [top, bottom] da arte (0 = topo, 1 = base),
-- na mesma posição em que ela fica na imagem inteira.
local function ShowSlice(tex, holder, top, bottom)
    if bottom - top <= 0.002 then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -top * holder.height)
    tex:SetSize(holder.width, (bottom - top) * holder.height)
    tex:SetTexCoord(0, 1, top, bottom)
    tex:Show()
end

-- Fração do tempo que resta (0 a 1), ou nil se não há barra de tempo.
local function Remaining()
    if not (ns.db and ns.db.timerBar) or not timerExpiration or not timerDuration or timerDuration <= 0 then
        return nil
    end
    local remaining = (timerExpiration - GetTime()) / timerDuration
    if remaining > 1 then return 1 elseif remaining < 0 then return 0 end
    return remaining
end

-- Ponto da linha central na altura `level`, dentro do holder, e a força da
-- faísca (some perto das pontas do arco).
local function SparkPosition(side, level)
    local v = level * BASE_HEIGHT
    local s = max(-1, min(1, (v - ARC_CY) / ARC_RY))
    local u = ARC_CX - ARC_RX * sqrt(1 - s * s)
    local scaleX = side.holder.width / BASE_WIDTH
    local scaleY = side.holder.height / BASE_HEIGHT
    local x = u * scaleX
    if side.mirrored then x = side.holder.width - x end
    local fade = min(1, (level - ART_TOP) / 0.08, (ART_BOTTOM - level) / 0.08)
    return x, -v * scaleY, max(0, fade)
end

local function UpdateLevel(force)
    local remaining = Remaining()
    local level = remaining and (ART_TOP + (1 - remaining) * (ART_BOTTOM - ART_TOP)) or 0
    if not force and lastLevel and abs(level - lastLevel) < 0.002 then return end
    lastLevel = level

    local alpha = ns.db and ns.db.alpha or 1
    local glowAlpha = alpha
    if remaining then
        glowAlpha = alpha * (GLOW_MIN + (1 - GLOW_MIN) * remaining)
    end

    for _, side in ipairs(sides) do
        local holder = side.holder
        side.glow:SetAlpha(glowAlpha)
        ShowSlice(side.fill, holder, level, 1)
        ShowSlice(side.dim, holder, 0, level)
        ShowSlice(side.feather, holder, max(0, level - CORE_FEATHER), level)

        if remaining then
            local x, y, fade = SparkPosition(side, level)
            if fade > 0.01 then
                side.spark:ClearAllPoints()
                side.spark:SetPoint("CENTER", holder, "TOPLEFT", x, y)
                side.spark:SetAlpha(alpha * fade)
                side.spark:Show()
            else
                side.spark:Hide()
            end
        else
            side.spark:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Animação
---------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
    if mode == "fadein" then
        progress = min(1, progress + elapsed / FADE_IN_TIME)
        if progress >= 1 then mode = "shown" end
    elseif mode == "fadeout" then
        progress = max(0, progress - elapsed / FADE_OUT_TIME)
        if progress <= 0 then
            mode = "hidden"
            self:SetAlpha(0)
            self:Hide()  -- a partir daqui o OnUpdate para de rodar
            return
        end
    end

    local pulse = 1
    if ns.db and ns.db.pulse then
        pulseTime = (pulseTime + elapsed) % PULSE_PERIOD
        pulse = PULSE_MIN + (1 - PULSE_MIN) * (0.5 + 0.5 * cos(2 * pi * pulseTime / PULSE_PERIOD))
    end

    self:SetAlpha(Smooth(progress) * pulse)
    UpdateLevel(false)
end

---------------------------------------------------------------------------
-- Criação e configuração
---------------------------------------------------------------------------
local function CreateLayer(holder, file, layer, sublevel)
    local tex = holder:CreateTexture(nil, layer, nil, sublevel)
    tex:SetTexture(file)
    tex:SetBlendMode("ADD")
    return tex
end

-- Degradê vertical de transparência: opaco embaixo, transparente em cima.
local function ApplyFeatherGradient(tex)
    if not (tex.SetGradient and CreateColor) then return false end
    local ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
    return ok
end

local function CreateSide(files, mirrored)
    local holder = CreateFrame("Frame", nil, frame)
    local side = {
        holder   = holder,
        mirrored = mirrored,
        glow     = CreateLayer(holder, files.glow, "ARTWORK", 0),
        dim      = CreateLayer(holder, files.core, "ARTWORK", 1),
        feather  = CreateLayer(holder, files.core, "ARTWORK", 2),
        fill     = CreateLayer(holder, files.core, "ARTWORK", 3),
        spark    = CreateLayer(holder, TEXTURE_SPARK, "OVERLAY", 0),
    }
    side.glow:SetAllPoints(holder)
    side.dim:SetVertexColor(CORE_EMPTY_TINT[1], CORE_EMPTY_TINT[2], CORE_EMPTY_TINT[3])
    side.featherAlpha = ApplyFeatherGradient(side.feather) and FEATHER_ALPHA_GRADIENT or FEATHER_ALPHA_FLAT
    side.spark:Hide()
    return side
end

function Overlay:Create()
    if frame then return end

    -- Frame sem nome (não cria global), cobrindo a tela, acima da maior parte
    -- da interface e sem capturar o mouse.
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(false)
    frame:SetAlpha(0)
    frame:Hide()

    sides[1] = CreateSide(TEXTURES[1], false)
    sides[2] = CreateSide(TEXTURES[2], true)

    frame:SetScript("OnUpdate", OnUpdate)
    self:ApplySettings()
end

-- Aplica escala, posição e opacidade do banco salvo.
function Overlay:ApplySettings()
    if not frame or not ns.db then return end
    local db = ns.db
    local width, height = BASE_WIDTH * db.scale, BASE_HEIGHT * db.scale
    local offsets = { -db.offsetX, db.offsetX }

    for i, side in ipairs(sides) do
        local holder = side.holder
        holder.width, holder.height = width, height
        holder:ClearAllPoints()
        holder:SetSize(width, height)
        holder:SetPoint("CENTER", frame, "CENTER", offsets[i], db.offsetY)
        side.fill:SetAlpha(db.alpha)
        side.dim:SetAlpha(db.alpha * CORE_EMPTY_ALPHA)
        side.feather:SetAlpha(db.alpha * side.featherAlpha)
        side.spark:SetSize(SPARK_SIZE * db.scale, SPARK_SIZE * db.scale)
    end
    UpdateLevel(true)
end

-- Define a barra de tempo. expiration no relógio de GetTime(); nil = arco cheio.
function Overlay:SetTimer(expiration, duration)
    timerExpiration, timerDuration = expiration, duration
    UpdateLevel(true)
end

function Overlay:FadeIn()
    if not frame or mode == "shown" or mode == "fadein" then return end
    if mode == "hidden" then
        progress, pulseTime = 0, 0
        frame:SetAlpha(0)
    end
    -- Vindo de um fade-out pela metade, continua do alfa atual.
    mode = "fadein"
    frame:Show()
end

function Overlay:FadeOut()
    if not frame or mode == "hidden" or mode == "fadeout" then return end
    mode = "fadeout"
end

function Overlay:IsVisible()
    return mode ~= "hidden"
end
