# Prompt para o Claude Code — Cosméticos de raridade + artistas novos

> Colar no Claude Code do projeto. Segue o `CLAUDE.md`: apresentar primeiro a proposta com valores
> para aprovação, depois Config/Tipos → Servidor → Cliente → Setup no Studio.

---

Quero uma fase nova, **"Cosméticos de raridade"**, e uma proposta de **10 artistas novos**.
Os modelos já estão feitos no Blender e exportados em `Models/FBX` (ver `Models/README.md`).
Primeiro apresenta a proposta (tabela por raridade e valores de Config) e espera pelo meu OK.

## 1. O que já existe (modelos)

**Kits de raridade** — `Models/FBX/RarityKits/<RarityId>.fbx`, um por raridade de `Rare` a `Omega`
(19 ficheiros; Common, Uncommon e Notable não têm kit). Importados para
`ServerStorage/Assets/RarityKits/<RarityId>`.

- A origem do kit é o **centro da cabeça** do artista. Há uma peça invisível `KitOrigin` nesse ponto
  (usar como PrimaryPart do kit).
- Cada kit tem fones gigantes e, nas raridades altas, coroas, auréolas, asas, vinis, estrelas, planetas…
- **O nome de cada peça diz a animação** (podem combinar-se vários prefixos, ex.: `Float_Spin_CrownBand`):

  | Prefixo | Animação (cliente) |
  |---|---|
  | `Spin_` | roda sobre o próprio eixo vertical (Y do Roblox) |
  | `Orbit_` | anda à volta da cabeça (à volta do `KitOrigin`) |
  | `Float_` | sobe e desce suavemente (seno) |
  | `Flap_` | asas: roda alguns graus para a frente e para trás à volta do ombro mais próximo |
  | `Pulse_` | material Neon com brilho/transparência a pulsar ao ritmo (128 BPM ou `PlaybackLoudness`) |
  | `FXPoint_<Efeito>` | peça invisível: origem de partículas desse efeito |

- Efeitos usados nos `FXPoint_`: `Sparkle`, `Stars`, `GoldSparkle`, `Fire`, `Embers`, `Feathers`, `Glow`,
  `Stardust`, `Galaxy`, `Mist`, `Smoke`, `Beams`, `Rainbow`.

**Artistas** — `Models/FBX/Artists/<ArtistId>.fbx` (25, já existentes). Cada artista tem agora uma ou mais
peças invisíveis `HeadAnchor`, `HeadAnchor2`, `HeadAnchor3`… (bandas/duplas têm uma por boneco), no
centro de cada cabeça. **Escala do kit = `HeadAnchor.Size.X / 1.26`** (1.26 = cabeça de tamanho normal).

## 2. Servidor (proposta)

- `Config/RarityCosmetics`: para cada `RarityId` → `Kit` (nome do modelo ou nil), velocidades
  (`SpinSpeed`, `OrbitSpeed`, `FloatAmplitude`, `FlapAngle`, `PulseSpeed`) e `ParticleScale`
  (multiplicador da taxa de partículas). Valores a crescer com a raridade; Ómega no máximo.
- `Assets.GetRarityKitTemplate(rarityId): Model?` (em `World/Assets`, como os outros overrides; sem
  modelo → sem kit, sem erro).
- No `StageArtistService`, depois de colocar o rig: para cada `HeadAnchor*` do rig, clonar o kit,
  `ScaleTo(anchor.Size.X / 1.26)`, `PivotTo(anchor.CFrame)` e **meter o kit dentro do rig** (para o
  `PivotTo` da dança o levar junto). Tudo ancorado, sem colisões. Esconder `HeadAnchor`, `KitOrigin` e
  `FXPoint_*` (Transparency 1).
- Manter os efeitos atuais (`Effect` Glow/Gradient/Rainbow, PointLight, nameplate).

## 3. Cliente (proposta)

- Animar as peças por prefixo **dentro do mesmo ciclo do `ArtistDanceController`** (para não lutar com o
  `PivotTo` da dança): guardar no início o offset de cada peça em relação ao `BaseCFrame` do rig e, em cada
  frame, `peça.CFrame = pivotDoRig * offset * animação`. Sem criar instâncias por frame.
- Partículas: criar `ParticleEmitter` (ou `PointLight` no `Glow`, `Beam` no `Beams`) a partir de cada
  `FXPoint_<Efeito>` com presets num Config (cor, tamanho, velocidade, vida). Taxa × `ParticleScale`.
- LOD: animação e partículas só dentro de `Config/Lod.StageAnimation.MaxDistance`; força total no
  terreno do próprio jogador, versão leve nos outros 5; respeitar `PyroVfxController.SetLowVfx` / LowVfx.
  Teto de emissores ativos por cliente.

## 4. Artistas novos (proposta — precisa do teu OK no balanceamento)

Modelos prontos em `Models/FBX/Artists_Proposta/` (só passam para `Artists/` depois de aprovados).
Proposta: +2 por crate, nas famílias Comum e Raro (as que menos mexem no jogo). Habilidades dos Raros
por definir por ti, no mesmo estilo das existentes.

| ArtistId | Nome | Crate | Família |
|---|---|---|---|
| RuiRiff | Rui Riff | Underground | Common |
| BiaBatida | Bia Batida | Underground | Rare |
| DjFaisca | DJ Faísca | Ascensao | Common |
| MimiMixer | Mimi Mixer | Ascensao | Rare |
| GravesUnidos | Os Graves Unidos | Estrelato | Common |
| EstrelaSonica | Estrela Sónica | Estrelato | Rare |
| PixelPedro | Pixel Pedro | Lenda | Common |
| QuasarQuim | Quasar Quim | Lenda | Rare |
| AstroAna | Astro Ana | Orbital | Common |
| MeteoroMax | Meteoro Max | Orbital | Rare |

Pontos a validar: probabilidade de cada artista dentro da família (passa a dividir por 2), tamanho da
coleção (300), Índice de Artistas da Fase 10 (mais combinações), migração (nada a migrar se só se
acrescentam ids).

## 5. Setup no Studio

O `Models/StudioSetup.luau` já prepara `RarityKits` (PrimaryPart = `KitOrigin`, esconde marcadores,
Neon nas peças `Pulse_`/`Neon_`) e esconde os `HeadAnchor` dos artistas.

## 6. No fim da fase

Performance (6 jogadores, até 7 artistas por palco, Ómega com ~40 peças animadas), Config principal e
como testar: `/fe artist give <id> <raridade>` com Rare, Legendary, Mythic, Divine, Cosmic e Omega.
Atualizar no `CLAUDE.md` o contrato de modelos (`RarityKits/<RarityId>`, `HeadAnchor`).
