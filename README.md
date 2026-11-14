# ClarityOverlay

Alerta visual e sonoro para o **Clearcasting** (o proc do *Omen of Clarity*) no **WoW: Forever**,
no estilo do *Spell Activation Overlay* do Retail. Quando o buff aparece, dois arcos verde-azulados
surgem ao lado do personagem com um fade suave e um som toca uma única vez. Quando o buff acaba ou é
consumido, os arcos somem.

O addon só **mostra** informação. Ele não usa, não lança e não sugere habilidades.

---

## Instalação

1. Copie a pasta `ClarityOverlay` para:

   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```

   O resultado deve ser `...\_forever_\Interface\AddOns\ClarityOverlay\ClarityOverlay.toc`.
   O nome da pasta precisa ser exatamente `ClarityOverlay`.
2. **Feche e abra o jogo.** Arquivos novos só são reconhecidos quando o cliente inicia; um `/reload` não basta.
3. Na seleção de personagem, abra **AddOns** e confirme que o *ClarityOverlay* está marcado.
   Se aparecer "Desatualizado", marque **Carregar AddOns desatualizados**.

## Sobre o Clearcasting no Forever

Segundo a base do Wowhead para o Forever:

- **Omen of Clarity** ([16864](https://www.wowhead.com/forever/spell=16864/omen-of-clarity)) é uma
  aura **passiva** que, ao ser acionada, dispara o Clearcasting.
- **Clearcasting** ([16870](https://www.wowhead.com/forever/spell=16870/clearcasting)) é um buff de
  **15 segundos** que zera o custo de mana da próxima magia do druida.

O spellID padrão do addon já é o `16870`, então não deve ser preciso configurar nada.

## Como o addon enxerga o Clearcasting em combate

Em combate, o Forever esconde os buffs de todos os addons (veja *Limitações*). O custo das magias,
porém, continua visível, e o Clearcasting zera o custo de **todas** as magias de druida. Então, em
combate, o addon olha o custo de sete magias de referência (Healing Touch, Rejuvenation, Regrowth,
Moonfire, Claw, Shred e Maul). Se todas que normalmente custam algo passam a custar 0, o Clearcasting
está ativo.

- Isso foi confirmado no jogo com `/clarity sonda`: o custo continua legível em combate e cai para 0
  durante o proc.
- O addon aprende o custo normal de cada magia sozinho, fora do proc. Logo depois de entrar no jogo,
  ele precisa ver o custo normal pelo menos uma vez.
- Para não dar falso positivo, uma magia isolada custando 0 não basta: precisam ser todas.
- Isso só funciona para **druida**. Para outras classes, o overlay funciona só fora de combate.
- É um caminho indireto: se um patch esconder também o custo das magias, a detecção em combate para
  de funcionar (sem erro). Ela pode ser desligada com `/clarity custo off` ou na janela.

Fora de combate o addon continua lendo o buff diretamente (spellID 16870 e nome "Clearcasting").

## Barra de tempo (quanto falta do Clearcasting)

Cada arco funciona como uma barra de tempo, sem cronômetro. Quando o Clearcasting ativa, o arco
aparece inteiro e brilhante; ao longo dos **15 segundos** do buff, a parte brilhante vai descendo
de cima para baixo. A parte que já passou não some: fica apagada (cerca de 25% do brilho), com um
degradê suave na transição. Quando o buff acaba ou é gasto, o arco desaparece com o fade.

- Em combate o jogo esconde o tempo restante do buff, então o addon conta 15 segundos a partir do
  momento em que detecta o proc. Fora de combate (e ao sair de combate) ele usa o tempo exato.
- Se o Clearcasting for renovado em combate sem ser gasto antes, o addon não tem como perceber; a
  contagem chega ao fim e o arco fica todo apagado (mas visível) até o buff sumir.
- `/clarity test` mostra a barra descendo em 3 segundos, para você ver o efeito.
- Para desligar: caixa "Mostrar tempo restante" na janela, ou `/clarity tempo off`.

## Janela de configurações

Digite `/clarity` para abrir ou fechar a janela. Ela também aparece em **Opções → AddOns →
ClarityOverlay**, com um botão "Abrir configurações". Na janela dá para:

- marcar/desmarcar **Addon ativado**, **Tocar som** e **Pulsação**;
- ajustar **tamanho**, **opacidade** e **posição** em barras deslizantes, com prévia na hora;
- trocar o arquivo de som e testar o som;
- ver ao vivo se o Clearcasting está **ativo** e ligar/desligar a **detecção em combate pelo custo
  de mana**;
- no botão **Avançado**, ver, adicionar e remover os **IDs** e **nomes** do buff (usados fora de
  combate; normalmente não precisa mexer);
- usar os botões **Testar overlay**, **Diagnóstico**, **Lista de comandos** e **Restaurar padrão**.

A janela só é criada na primeira vez que você a abre e não roda nada enquanto está fechada, então
não pesa no desempenho. Arraste pelo fundo para mover; **Esc** fecha.

## Ajustar posição e tamanho

1. Digite `/clarity test`. O overlay aparece por 3 segundos, com som.
2. Ajuste e repita até ficar bom. Cada ajuste já mostra uma prévia de 3 segundos:
   - `/clarity offset 180 40`: **X** é a distância de cada arco até o centro da tela; **Y** é a altura
     (positivo = para cima). O padrão é `150 50`.
   - `/clarity scale 1.3`: tamanho (de 0.25 a 4). O padrão é `1`.
   - `/clarity alpha 0.7`: opacidade (de 0.05 a 1). O padrão é `0.85`.
   - `/clarity pulse off`: desliga a pulsação.

## Comandos

| Comando | O que faz |
|---|---|
| `/clarity` | Abre/fecha a janela de configurações |
| `/clarity help` | Mostra a lista de comandos no chat |
| `/clarity on` / `off` | Ativa/desativa o addon |
| `/clarity test` | Simula o overlay por 3 segundos |
| `/clarity sound on` / `off` | Liga/desliga o som |
| `/clarity sound test` | Toca o som agora (mesmo com o som desligado) |
| `/clarity sound file <arquivo.ogg>` | Usa um som próprio (veja abaixo) |
| `/clarity sound padrao` | Volta ao som nativo |
| `/clarity scale <número>` | Tamanho (0.25 a 4) |
| `/clarity offset <x> <y>` | Posição (distância horizontal e altura) |
| `/clarity alpha <número>` | Opacidade (0.05 a 1) |
| `/clarity pulse on` / `off` | Pulsação enquanto o buff está ativo |
| `/clarity custo on` / `off` | Detecção em combate pelo custo das magias (padrão: ligada) |
| `/clarity tempo on` / `off` | Barra de tempo: o brilho do arco desce conforme o buff acaba (padrão: ligada) |
| `/clarity add <spellID>` | Adiciona um spellID à detecção |
| `/clarity remove <spellID>` | Remove um spellID |
| `/clarity addname <nome>` | Adiciona um nome de buff à detecção (útil para outros idiomas) |
| `/clarity removename <nome>` | Remove um nome |
| `/clarity list` | Mostra a configuração atual |
| `/clarity debug` | Lista seus buffs atuais com índice, nome e spellID |
| `/clarity sonda` | Liga/desliga o teste de combate: ao fim de cada luta, mostra no chat o que o jogo deixou o addon ver |
| `/clarity reset` | Restaura aparência e som (mantém as listas de detecção) |
| `/clarity reset tudo` | Restaura tudo, inclusive as listas |

### Sobre "Omen of Clarity"

O nome "Omen of Clarity" **não** está na lista padrão de nomes. No Forever, *Omen of Clarity* é a
aura passiva que fica sempre ativa e dispara o *Clearcasting*, que é o proc que interessa. Se o addon
casasse pelo nome "Omen of Clarity", o overlay ficaria aceso o tempo todo.

## Trocar as texturas

As texturas ficam em `Media/`. Cada arco é feito de duas camadas, mais a faísca:

- `ClarityLeftCore.tga` / `ClarityRightCore.tga`: a **linha central** do arco, que é a barra de
  tempo (desce conforme o buff acaba);
- `ClarityLeftGlow.tga` / `ClarityRightGlow.tga`: o **brilho em volta**, que não é cortado e só
  perde força com o tempo;
- `ClaritySpark.tga` (64x64): a **faísca** que desliza pela linha central marcando o nível.

Para trocar, substitua os arquivos **mantendo os mesmos nomes**. A faísca segue a geometria da arte
incluída; com uma arte de formato diferente, ajuste `ARC_CX`, `ARC_CY`, `ARC_RX` e `ARC_RY` em
`Overlay.lua` ou desligue a barra de tempo. Requisitos:

- formato **TGA 32 bits com canal alfa** (ou BLP, se você alterar os caminhos em `Overlay.lua`);
- dimensões em **potência de 2** (ex.: 128x256, 256x256, 512x512);
- a arte é exibida em 128x256 (largura x altura, na escala 1), com blend mode **ADD**: preto vira
  transparente e cores claras brilham.

Depois de substituir, use `/reload`. Se a textura não mudar, reinicie o jogo.

As texturas incluídas foram geradas por `Tools/generate_textures.py` (Python 3 puro, sem dependências).
Para mudar a cor, edite `COLOR_LOW`, `COLOR_MID` e `COLOR_HOT` no script e rode:

```
python Tools/generate_textures.py --preview previa.png
```

A pasta `Tools/` não é carregada pelo jogo e pode ser apagada se você quiser.

## Trocar o som

Por padrão o addon toca o som nativo do Spell Activation Overlay (`SOUNDKIT.UI_POWER_AURA_GENERIC`).
Se ele não existir no cliente, usa o som de alerta de raide. Para usar um som próprio:

1. Coloque o arquivo `.ogg` (ou `.mp3`) em `ClarityOverlay\Media\`, por exemplo `Media\ding.ogg`.
2. **Reinicie o jogo** (arquivo novo).
3. Digite `/clarity sound file ding.ogg`.

Também é possível usar um caminho completo ou um **FileDataID** numérico de um som do próprio jogo:
`/clarity sound file 567458`. Se o arquivo não tocar, o addon avisa e volta ao som nativo.
O som usa o canal **Master**, então toca mesmo com os efeitos sonoros desligados.

## Como a detecção funciona

A cada evento `UNIT_AURA` do jogador (registrado com `RegisterUnitEvent`, sem polling), o addon tenta,
nesta ordem:

1. `C_UnitAuras.GetPlayerAuraBySpellID` para cada spellID cadastrado;
2. `C_UnitAuras.GetAuraDataBySpellName` para cada nome (se a função existir no cliente);
3. uma varredura dos buffs com `C_UnitAuras.GetAuraDataByIndex`, comparando spellID e nome.

Toda leitura passa por `pcall` e `issecretvalue`. Se o cliente devolver valores restritos
("secret values"), o addon considera o buff ausente, sem gerar erro de Lua. O estado também é
reavaliado ao entrar no mundo (`PLAYER_ENTERING_WORLD`, cobrindo login e `/reload`) e ao sair de
combate (`PLAYER_REGEN_ENABLED`). O som só toca quando o buff passa de ausente para ativo. Na
sincronização do login/reload, o overlay aparece em silêncio.

## Limitações conhecidas

- **Combate e "secret values":** o Forever usa o cliente do Midnight. Pelas notas de API da Blizzard
  (patch 12.1.0), enquanto as auras estão restritas (combate, encontros, M+, PvP):
  - as APIs que leem auras **por índice** dão erro quando chamadas por addons;
  - as APIs **por spellID ou nome** continuam funcionando, mas só devolvem dados legíveis para auras
    que a Blizzard marcou como "não secretas";
  - o evento `UNIT_AURA` chega com todos os dados secretos.

  **Testado no jogo:** o Clearcasting não está liberado. Em combate a busca por spellID devolve
  "ausente" mesmo com o buff ativo. Por isso o addon usa o custo das magias em combate (veja *Como o
  addon enxerga o Clearcasting em combate*). Se a Blizzard liberar o buff no futuro, a leitura direta
  volta a funcionar sozinha.
- O overlay é filho do `UIParent`, então some junto com a interface (Alt+Z).
