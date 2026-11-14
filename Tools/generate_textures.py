#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gerador das texturas do ClarityOverlay.

Cria em Media/ (TGA 32 bits com alfa, sem compressão; Python puro, sem
Pillow nem numpy):
  * ClarityLeftCore.tga / ClarityRightCore.tga  (256x256) - a linha central do
    arco. É a "barra de tempo": desce conforme o buff acaba.
  * ClarityLeftGlow.tga / ClarityRightGlow.tga  (256x256) - o brilho em volta
    (névoa, línguas de energia, faíscas). Não é cortado; só perde força.
  * ClaritySpark.tga                            (64x64)   - a faísca que
    desliza pela linha central marcando o nível da barra.

A arte dos arcos é feita para ser exibida em 128x256 (largura x altura) no
jogo; as contas são feitas nessas "coordenadas de tela" e amostradas no
arquivo 256x256. A imagem é simétrica na vertical, então a orientação do TGA
não importa. A geometria do arco (CX, CY, RX, RY) é repetida em Overlay.lua
para posicionar a faísca: se mudar aqui, mude lá também.

Uso:
    python generate_textures.py                       # grava em ../Media
    python generate_textures.py --out PASTA           # grava em outra pasta
    python generate_textures.py --preview previa.png  # também gera uma prévia PNG

Para mudar a cor, altere COLOR_LOW / COLOR_MID / COLOR_HOT e rode de novo.
"""

import argparse
import math
import os
import struct
import zlib

SIZE = 256                       # dimensão do arquivo dos arcos (potência de 2)
SPARK_SIZE = 64                  # dimensão do arquivo da faísca
VIEW_W, VIEW_H = 128.0, 256.0    # tamanho de exibição no jogo (escala 1.0)
SUPERSAMPLE = 2                  # amostras por eixo em cada pixel (antisserrilhado)

# Paleta verde-azulada (R, G, B de 0 a 1), do brilho fraco ao núcleo quente.
COLOR_LOW = (0.03, 0.52, 0.50)
COLOR_MID = (0.16, 0.95, 0.80)
COLOR_HOT = (0.88, 1.00, 0.96)

# Arco "(" do lado esquerdo: trecho de uma elipse cujo centro fica à direita
# da textura (onde estaria o personagem). Mesmos valores em Overlay.lua.
CX, CY = 150.0, 128.0
RX, RY = 122.0, 124.0
R_AVG = (RX + RY) / 2.0
ARC_HALF = math.radians(64.0)    # meia abertura do arco, a partir do ponto mais à esquerda

# "Línguas" de energia saindo para fora do arco:
# (posição 0..1 ao longo do arco, comprimento, força, curvatura)
WISPS = [
    (0.00, 18.0, 0.45, 0.0),
    (0.20, 22.0, 0.42, 5.0),
    (0.41, 25.0, 0.40, 6.0),
    (0.62, 17.0, 0.34, 5.0),
    (0.82, 11.0, 0.26, 3.0),
]

# Faíscas soltas: (posição 0..1 ao longo do arco, distância radial (+ fora, - dentro), raio, força)
SPARKS = [
    (0.08, -10.0, 1.7, 0.85),
    (0.30, 9.0, 1.4, 0.75),
    (0.50, -7.0, 1.5, 0.80),
    (0.69, 14.0, 1.2, 0.60),
    (0.88, -5.0, 1.2, 0.55),
]


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def lerp3(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def spark_centers():
    """Converte as faíscas soltas para coordenadas de tela (metade de cima e espelho embaixo)."""
    centers = []
    for pos, radial, radius, strength in SPARKS:
        ang = math.pi - pos * ARC_HALF
        for sign in (1.0, -1.0):
            a = sign * ang
            x = CX + (RX + radial) * math.cos(a)
            y = CY + (RY + radial) * math.sin(a)
            centers.append((x, y, radius, strength))
    return centers


SPARK_CENTERS = spark_centers()


def field_parts(u, v):
    """Intensidades (núcleo, brilho) no ponto (u, v) em coordenadas de tela."""
    nx = (u - CX) / RX
    ny = (v - CY) / RY
    r = math.hypot(nx, ny)
    d = (r - 1.0) * R_AVG                      # distância ao arco; < 0 = lado do personagem
    off = math.pi - abs(math.atan2(ny, nx))    # 0 no meio do arco, cresce para as pontas
    s = off / ARC_HALF

    taper = (1.0 - s * s) ** 1.5 if s < 1.0 else 0.0   # cheio no meio, some nas pontas
    core = 0.0
    glow = 0.0

    if taper > 0.0:
        thick = 0.35 + 0.65 * taper
        wave = 0.80 + 0.20 * math.sin(off * 23.0) * math.sin(off * 7.0 + 1.3)

        # Núcleo: a linha central (a "barra de tempo").
        core += 1.25 * taper * math.exp(-(d / (3.4 * thick)) ** 2)

        # Brilho em volta.
        halo = 0.60 * wave * math.exp(-(d / (11.0 * thick)) ** 2)
        haze_sigma = 26.0 * thick * (1.5 if d < 0.0 else 1.0)   # halo mais largo para dentro
        haze = 0.32 * math.exp(-(d / haze_sigma) ** 2)
        glow += taper * (halo + haze)

        # Segunda linha, interna e mais fina (decoração do brilho).
        d2 = d + 13.0 * thick
        glow += 0.35 * (taper ** 2) * math.exp(-(d2 / (1.6 * thick)) ** 2)

        # Línguas de energia para fora (d > 0), afinando e curvando para as pontas.
        for pos, length, strength, bend in WISPS:
            if d < -4.0 or d > length + 2.0:
                continue
            k = min(1.0, max(0.0, d) / length)
            arc_dist = (off - pos * ARC_HALF) * R_AVG - bend * k * k
            if abs(arc_dist) > 14.0:
                continue
            width = 3.2 * (1.0 - 0.6 * k)
            along = (1.0 - k) ** 1.6 if d >= 0.0 else math.exp(-(d / 2.0) ** 2)
            glow += strength * taper * along * math.exp(-(arc_dist / width) ** 2)

    # Faíscas soltas.
    for x, y, radius, strength in SPARK_CENTERS:
        dx, dy = u - x, v - y
        dist2 = dx * dx + dy * dy
        if dist2 > (5.0 * radius) ** 2:
            continue
        glow += strength * math.exp(-dist2 / (radius * radius))

    # Some suavemente perto das bordas da textura (sem cortes duros).
    edge = smoothstep(0.0, 10.0, min(u, VIEW_W - u, v, VIEW_H - v))
    return core * edge, glow * edge


def shade(val):
    """Converte intensidade em (r, g, b, a) 0..255. Cor não pré-multiplicada (blend ADD)."""
    alpha = 1.0 - math.exp(-val * 1.5)          # saturação suave
    heat = min(1.0, val / 1.6)
    if heat < 0.5:
        rgb = lerp3(COLOR_LOW, COLOR_MID, heat * 2.0)
    else:
        rgb = lerp3(COLOR_MID, COLOR_HOT, (heat - 0.5) * 2.0)
    return (
        int(round(rgb[0] * 255)),
        int(round(rgb[1] * 255)),
        int(round(rgb[2] * 255)),
        int(round(max(0.0, min(1.0, alpha)) * 255)),
    )


def render_arc_layers():
    """Linhas (de cima para baixo) do núcleo e do brilho do lado esquerdo."""
    core_rows, glow_rows = [], []
    n = SUPERSAMPLE
    inv = 1.0 / (n * n)
    for py in range(SIZE):
        core_row, glow_row = [], []
        for px in range(SIZE):
            core_acc = glow_acc = 0.0
            for j in range(n):
                v = (py + (j + 0.5) / n) * (VIEW_H / SIZE)
                for i in range(n):
                    u = (px + (i + 0.5) / n) * (VIEW_W / SIZE)
                    c, g = field_parts(u, v)
                    core_acc += c
                    glow_acc += g
            core_row.append(shade(core_acc * inv))
            glow_row.append(shade(glow_acc * inv))
        core_rows.append(core_row)
        glow_rows.append(glow_row)
    return core_rows, glow_rows


def render_spark():
    """Faísca: ponto quente no centro com halo suave e um leve brilho em cruz."""
    rows = []
    c = (SPARK_SIZE - 1) / 2.0
    for py in range(SPARK_SIZE):
        row = []
        for px in range(SPARK_SIZE):
            dx, dy = (px - c) / c, (py - c) / c          # -1..1
            r = math.hypot(dx, dy)
            val = 1.6 * math.exp(-(r / 0.16) ** 2) + 0.55 * math.exp(-(r / 0.45) ** 2)
            val += 0.35 * math.exp(-(dy / 0.06) ** 2) * math.exp(-(dx / 0.75) ** 2)   # traço horizontal
            val += 0.35 * math.exp(-(dx / 0.06) ** 2) * math.exp(-(dy / 0.75) ** 2)   # traço vertical
            val *= smoothstep(1.0, 0.85, r)                                            # sem borda dura
            row.append(shade(val))
        rows.append(row)
    return rows


def mirror(rows):
    return [list(reversed(row)) for row in rows]


def write_tga(path, rows):
    """TGA 32 bits sem compressão, origem no canto inferior esquerdo (padrão do formato)."""
    height, width = len(rows), len(rows[0])
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    data = bytearray(header)
    for row in reversed(rows):
        for r, g, b, a in row:
            data += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(data)


def write_png(path, width, height, rgb_rows):
    """PNG RGB simples (sem dependências), usado só para a prévia."""
    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = bytearray()
    for row in rgb_rows:
        raw.append(0)
        for r, g, b in row:
            raw += bytes((r, g, b))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


# ---------------------------------------------------------------------------
# Prévia: simula a barra de tempo como o Overlay.lua desenha (mesmas constantes).
# ---------------------------------------------------------------------------
ART_TOP, ART_BOTTOM = 0.06, 0.94
CORE_EMPTY_ALPHA = 0.10
CORE_EMPTY_TINT = (0.55, 0.62, 0.62)
CORE_FEATHER = 0.04
GLOW_MIN = 0.45
SPARK_VIEW = 40.0
OPACITY = 0.85


def spark_position(level):
    """Ponto da linha central na altura `level` (0 = topo, 1 = base), em coordenadas de tela."""
    v = level * VIEW_H
    s = max(-1.0, min(1.0, (v - CY) / RY))
    u = CX - RX * math.sqrt(1.0 - s * s)
    fade = min(1.0, (level - ART_TOP) / 0.08, (ART_BOTTOM - level) / 0.08)
    return u, v, max(0.0, fade)


def write_preview(path, core, glow, spark):
    """Arco esquerdo em quatro momentos: 100%, 66%, 33% e 0% do tempo restante."""
    states = (1.0, 0.66, 0.33, 0.0)
    cell = 150
    w, h = cell * len(states), 290
    bg = (24, 30, 22)
    canvas = [[list(bg) for _ in range(w)] for _ in range(h)]

    def add(x, y, rgba, mult, tint=(1.0, 1.0, 1.0)):
        if 0 <= x < w and 0 <= y < h and mult > 0:
            for c in range(3):
                canvas[y][x][c] = min(255, int(canvas[y][x][c] + rgba[c] * tint[c] * rgba[3] / 255.0 * mult))

    for k, remaining in enumerate(states):
        level = ART_TOP + (1.0 - remaining) * (ART_BOTTOM - ART_TOP)
        x0, y0 = k * cell + 10, 16
        glow_mult = OPACITY * (GLOW_MIN + (1.0 - GLOW_MIN) * remaining)
        for ty in range(int(VIEW_H)):
            frac = (ty + 0.5) / VIEW_H
            if frac >= level:
                core_mult, tint = OPACITY, (1.0, 1.0, 1.0)
            else:
                core_mult, tint = OPACITY * CORE_EMPTY_ALPHA, CORE_EMPTY_TINT
                if frac >= level - CORE_FEATHER:
                    core_mult += OPACITY * (1.0 - CORE_EMPTY_ALPHA) * (1.0 - (level - frac) / CORE_FEATHER)
            for tx in range(int(VIEW_W)):
                for layer, mult, tnt in ((glow, glow_mult, (1, 1, 1)), (core, core_mult, tint)):
                    p1, p2 = layer[ty][tx * 2], layer[ty][tx * 2 + 1]
                    avg = tuple((p1[c] + p2[c]) / 2.0 for c in range(4))
                    add(x0 + tx, y0 + ty, avg, mult, tnt)
        if 0.0 < remaining < 1.0:
            su, sv, fade = spark_position(level)
            for sy in range(int(SPARK_VIEW)):
                for sx in range(int(SPARK_VIEW)):
                    p = spark[int(sy * SPARK_SIZE / SPARK_VIEW)][int(sx * SPARK_SIZE / SPARK_VIEW)]
                    add(int(x0 + su - SPARK_VIEW / 2 + sx), int(y0 + sv - SPARK_VIEW / 2 + sy), p, OPACITY * fade)
    write_png(path, w, h, canvas)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="Gera as texturas do ClarityOverlay.")
    parser.add_argument("--out", default=os.path.join(here, "..", "Media"), help="pasta de saída")
    parser.add_argument("--preview", help="caminho de um PNG de prévia (opcional)")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    core, glow = render_arc_layers()
    spark = render_spark()
    write_tga(os.path.join(args.out, "ClarityLeftCore.tga"), core)
    write_tga(os.path.join(args.out, "ClarityRightCore.tga"), mirror(core))
    write_tga(os.path.join(args.out, "ClarityLeftGlow.tga"), glow)
    write_tga(os.path.join(args.out, "ClarityRightGlow.tga"), mirror(glow))
    write_tga(os.path.join(args.out, "ClaritySpark.tga"), spark)
    print("Texturas geradas em", os.path.abspath(args.out))
    if args.preview:
        write_preview(args.preview, core, glow, spark)
        print("Prévia:", os.path.abspath(args.preview))


if __name__ == "__main__":
    main()
