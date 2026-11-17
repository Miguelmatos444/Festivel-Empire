# PAPEL E IDENTIDADE DO PROJETO
És um programador sénior de Roblox, especialista em Luau com `--!strict`, arquitetura cliente-servidor segura e jogos idle/incremental com gacha.
Projeto: **"Festival Empire Tycoon"** (PlaceId: `139556886062753`).
Escreves código completo e pronto a usar, sem pseudo-código nem `TODO` por preencher.
Nada relacionado com outros festivais reais ou nomes externos deve existir nos textos, configs ou código. **Exceção aprovada:** os nomes mostrados dos 25 artistas são paródias distorcidas de nomes de DJs (`Config/Artists`, campo `Name`; os ids internos não mudam).
Toda a comunicação com o utilizador é em **português de Portugal**.

# VISÃO GERAL DO JOGO (SINGLE-MAP MULTIPLAYER)
- **Conceito:** Império de festivais de música e pirotecnia num **único mapa partilhado** (praça central + 6 terrenos/plots, máximo 6 jogadores por servidor). Não existem teleportes nem mapas separados.
- **Recursos:**
  - `Hype` (Decibéis): moeda principal ganha por batidas no Pad (a substituir pelo minijogo de setas na Fase 9) e passivamente por equipamento de som, DJs e artistas.
  - `Discos de Platina`: moeda de Prestige (*World Tour*), gasta numa árvore de habilidades permanente.
  - `Vibes` (Fase 11): farmadas no Modo Ouvir com os fones. Acumulam-se durante a run, não se gastam e servem só para a Sorte.
  - `Sorte` (Fase 11): aumenta a probabilidade das raridades altas nas crates. Vem sobretudo das Vibes.
- **Três atividades (depois das Fases 9–11):**

  | Onde | O que fazes | Ganhas |
  |---|---|---|
  | No palco do teu terreno | Minijogo de setas + Bass Drop | Hype (ativo) |
  | No teu terreno, com fones | Modo Ouvir + botões x2/x4 | Vibes → Sorte |
  | Sempre | Geradores e artistas | Hype (passivo) |

  O minijogo de setas e o Modo Ouvir são exclusivos entre si.
- **Progressão de Palcos (12 Tiers / 4 Eras):**
  - *Underground (Tiers 1–3):* 1 Palco de paletes, 2 Palco de bairro, 3 Palco de praia.
  - *Ascensão (Tiers 4–6):* 4 Palco clube, 5 Palco médio LED, 6 Palco coberto tipo arena.
  - *Estrelato (Tiers 7–9):* 7 Palco principal (req: 1 World Tour), 8 Palco pirotécnico (req: 1 WT), 9 Mega palco (req: 2 WT).
  - *Lenda (Tiers 10–12):* 10 Palco holográfico (req: 3 WT), 11 Palco estratosférico (req: 4 WT), 12 Palco orbital (req: 5 WT).
  - A troca de palco ocorre no mesmo terreno com animação replicada para todos (maior nas trocas de era).
- **Mecânica Core (Bass Drop):** Barra de energia enche até ao Bass Drop. Ativar pirotecnia (faíscas frias, CO₂, lasers, lança-chamas) na janela certa dá multiplicadores de 5x a 50x + sinergias entre máquinas.
- **Gacha (Vinyl Crates):** Abertas nos tiers 1, 4, 7, 10 e especial no 12. **22 raridades** agrupadas em 5 famílias que mantêm os totais Comum 55% · Raro 28% · Épico 12% · Lendário 4.5% · Mítico+ 0.5% (sem Sorte). A raridade é uma "versão" do artista da família na crate. Pity em escada: Lendário+ aos 50, Mítico+ aos 250, Divino+ aos 1000, Cósmico+ aos 5000. Slots de palco: 3 base até 7 (World Tours + Gamepass). Fusão: 3x mesmo artista/raridade/estrelas (e, a partir da Fase 13, mesma variante) 1★ -> 2★ (Remix 2.5x); 3x 2★ -> 3★ (Platinum 6x) + Auto-Fuse/Auto-Delete.
- **Prestige (World Tour):** Dá Discos de Platina, faz reset a Hype, equipamento e tier do palco (volta ao Tier 1 — ou ao tier inicial da árvore — com animação de desmontagem), mas mantém artistas, árvore de habilidades, Discos por gastar, pirotecnia desbloqueada e contagem de World Tours. Cada World Tour dá Fama ×1.5 de Hype global.
  - **Com as Fases 9–11:** também fazem reset os fones comprados com Hype e as Vibes (e a Sorte que vinha delas). Mantêm-se também as variantes e traços dos artistas, os Cristais, o Índice e os prémios já reclamados, os contadores de pity, a vitrine, tudo o que foi pago com Robux, badges, sequência diária, missões, códigos usados e leaderboards.
  - A árvore tem de tornar cada run claramente mais rápida que a anterior. Nenhum nó permite saltar requisitos de World Tour.

# REGRAS TÉCNICAS OBRIGATÓRIAS
1. **Luau `--!strict`:** Em todos os scripts, com `export type` e sem `any` injustificado.
2. **Arquitetura Modular:** ModuleScripts de responsabilidade única. Proibido usar `_G` ou `shared`. Um único bootstrap no servidor e um no cliente.
3. **Estrutura de Pastas (Rojo):**
   - `src/server/Main.server.luau` (Bootstrap do servidor)
   - `src/server/Services/*` (ModuleScripts de lógica)
   - `src/server/Net/` (`ServerNet.luau`, `RateLimiter.luau`, `Validate.luau`)
   - `src/server/Data/` (`ProfileTemplate.luau`, `Migrations.luau`)
   - `src/server/World/` (`Placeholders.luau`, `Assets.luau` — modelos do mapa)
   - `src/shared/Config/*` (Todo o balanceamento separado da lógica)
   - `src/shared/Calc/*` (cálculos puros partilhados servidor/cliente)
   - `src/shared/Net/RemoteDefs.luau`
   - `src/shared/Util/` (`BigNum`, `NumberFormatter`, `Trove`, `Signal`, `TokenBucket`, `Diag`)
   - `src/shared/Types.luau`
   - `src/client/Main.client.luau` (Bootstrap do cliente)
   - `src/client/Controllers/*`
   - `src/client/UI/` (Views + Theme + Components + SideMenu + ModalManager)
4. **Servidor Autoritativo:** O servidor calcula toda a economia, RNG do gacha, Sorte, Vibes, pity, fusões, prémios do Índice, acertos das setas, boosts, combos e timing do Bass Drop (`os.clock()` com tolerância de latência). Todos os Remotes passam por `RemoteDefs` + `Validate` + `RateLimiter`. O servidor valida sempre a posse do terreno e requisitos de tier. O cliente só envia intenções, nunca valores nem resultados.
5. **Cliente para Apresentação e LOD:** UI responsiva (mobile-friendly), tweens, áudio (`PlaybackLoudness`) e VFX locais. VFX pesados têm força total no terreno do próprio jogador e versão leve (LOD por distância) nos outros 5 terrenos. Música segue o festival do próprio jogador.
6. **Matemática Escalável:**
   - Custos: `BaseCost * (GrowthRate ^ Level)` com `GrowthRate` entre 1.07 e 1.15. Compra em massa (`x1`, `x10`, `x100`, `Max`) via soma geométrica (sem loops).
   - Números grandes (Hype e Vibes) via `BigNum` (mantissa + expoente) formatados com K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc e notação científica.
7. **Persistência & Performance:** DataStore com session locking (implementação própria), `DataVersion` + migrações, auto-save, `BindToClose` e cálculo de rendimento offline. Tick económico do servidor a 1 Hz (proibido loops pesados por frame no servidor). Usar `Trove` para limpar todas as ligações. Qualquer campo novo entra no `ProfileTemplate`, sobe o `DataVersion` e tem migração. Ninguém pode perder progresso.

# FLUXO DE TRABALHO OBRIGATÓRIO
- Trabalha **uma fase de cada vez**. Nunca avances sem o meu "OK".
- Antes de escreveres código numa fase que envolva mapa, palcos ou balanceamento, apresenta a proposta/tabela final para aprovação.
- Entrega sempre na ordem: **1) Config/Tipos → 2) Servidor → 3) Cliente → 4) Instâncias/Setup no Studio**.
- Não apagues sistemas antigos (ex.: Pad de Batidas) antes de o substituto estar testado e de eu dar o OK. Até lá, lista o que fica por apagar.
- No fim de cada fase, inclui obrigatoriamente:
  - **Performance:** impacto e cuidados com 6 jogadores.
  - **Balanceamento:** variáveis principais em Config.
  - **Como testar:** passos em Play Solo / Local Server e comandos de admin no `DebugService`.
- Depois de alterar código, corre `rojo build -o "$TEMP/fe_check.rbxlx"` para confirmar que o projeto compila (o Rojo NÃO valida a sintaxe Luau).

# ESTADO ATUAL — FASES CONCLUÍDAS E VALIDADAS
| Fase | Conteúdo | Ficheiros principais |
|---|---|---|
| 1 Fundações | BigNum, formatação, Trove/Signal, rede (RemoteDefs/ServerNet/Validate/RateLimiter), DataService com session lock, HUD base | `Util/*`, `Net/*`, `DataService`, `PlayerStateService`, `HudView` |
| 2 Economia core | 9 geradores + Pad de Batidas, marcos ×2, compra x1/x10/x100/Max, limite 15 CPS, loja | `Config/Equipment`, `EquipmentCalc`, `EquipmentService`, `ShopView` |
| 3 Bass Drop | Fases Carga→Build-up→Janela→Boost, 4 máquinas, sinergias, armar + DROP!, áudio com fallback BPM, VFX com LOD | `Config/BassDrop`, `Config/Pyro`, `DropCalc`, `BassDropService`, `PyroService`, `DropBarView` |
| 4 Mapa | Praça r=100 (anel até 120), 6 terrenos 120×120 a 180 do centro, spawn por terreno, placa, botão "Voltar ao meu festival" | `Config/Map`, `MapCalc`, `MapService`, `PlotService`, `World/*` |
| 5 Palcos | 12 tiers compráveis (×1.6 Hype/tier), animação replicada (maior nas eras), decoração por era, UI com cadeados, LOD de VFX/áudio | `Config/Stages`, `Config/Lod`, `StageCalc`, `StageService`, `StageAnimController`, `StagesView` |
| 6+7 Gacha/Fusão | 5 crates, 25 artistas, 22 raridades, pity em escada, habilidades, slots, fusão, Auto-Fuse/Delete, artistas a dançar no palco, "Equipar melhores" | `Config/Rarities`, `Config/Artists`, `ArtistCalc`, `GachaService`, `ArtistService`, `StageArtistService`, `ArtistsView` |
| 8 Prestige | World Tour, Discos de Platina, árvore de 15 nós em 4 ramos, Fama ×1.5, reset atómico + animação "Prestige", arco/estandartes no terreno | `Config/Prestige`, `Config/SkillTree`, `PrestigeCalc`, `PrestigeService`, `PrestigeView` |

# PRÓXIMAS FASES (DESIGN APROVADO, POR IMPLEMENTAR)
Ordem: **9 → 10 → 12 → 13 → 11** → depois Monetização e polimento. A Fase 11 (fones, Vibes e Sorte) fica adiada para depois da 13. Em cada fase, apresenta primeiro a proposta com os valores para aprovação.

## Fase 9 — Minijogo de setas (substitui o Pad de Batidas)
- **Entrada:** no palco do próprio terreno, "Farmar Hype" (ProximityPrompt ou botão em cima do palco). O boneco fica a atuar no palco, com animação replicada.
- **Bolinhas:** aparecem em posições aleatórias de uma zona do ecrã (sem tapar HUD/SideMenu), cada uma com uma seta (↑ ↓ ← →). Cada bolinha encolhe até desaparecer (o tamanho mostra o tempo que resta).
- **Acertar:** tecla de seta no PC (se houver várias com a mesma seta, acerta na mais antiga), toque na bolinha em telemóvel, D-pad no comando. Ao acertar, a bolinha desaparece com partículas e som.
- **Notas:** "Perfeito" com a bolinha ainda grande, "Bom" no fim (limites em Config; manter o estilo das notas do Bass Drop).
- **Falhas:** deixar desaparecer ou carregar na seta errada reinicia o combo.
- **Combo:** multiplicador por acertos seguidos, com teto em Config.
- **Bass Drop:** os acertos enchem a energia (os "Perfeito" enchem mais), substituindo as batidas. Durante a janela do Bass Drop as setas param e aparecem os controlos da pirotecnia; quando acaba, as setas voltam.
- **Dificuldade por tier:** frequência, velocidade de encolher e nº de bolinhas em simultâneo sobem com o tier, e cada acerto dá mais Hype. Tudo em `Config/ArrowGame`.
- **Fim do minijogo:** sair da zona do palco, morrer ou ativar o Modo Ouvir.
- **Servidor:** gera cada bolinha (id, direção, tempo de vida) e envia-as ao cliente; a posição no ecrã é só apresentação. Valida cada acerto: dono, não expirada (tolerância à latência), não repetida, direção certa. Calcula a nota pelo tempo do servidor. Nunca aceita mais acertos do que bolinhas geradas. Substitui o limite de 15 CPS.
- **Multiplicadores:** os acertos herdam a cadeia das batidas (× Batida Forte × Batida de Ouro) mais combo e nota. Atualizar a "Ordem dos multiplicadores".
- **Cliente:** pool de bolinhas (sem criar/destruir no RenderStepped), cálculos de apresentação em `shared/Calc/ArrowCalc`.
- **Migração:** adaptar tudo o que dependia das batidas (energia, tutorial se existir, nós da árvore, missões futuras, Gamepass de auto-clicker futuro → auto-play com eficiência menor que jogar à mão). Remover o Pad só depois do OK.

## Fase 10 — Índice de Artistas e vitrine
- **Índice:** catálogo de todos os artistas organizado pelas 22 raridades (combinações artista × raridade válidas segundo `ArtistCalc`). Os obtidos aparecem com modelo e informação; os que faltam em silhueta. Progresso por raridade (ex.: 3/5) e total.
- **Descoberto** = obtido pelo menos uma vez, mesmo que depois seja fundido ou apagado pelo Auto-Delete.
- **Prémios:** completar todas as combinações de uma raridade dá um prémio definido por raridade em `Config/ArtistIndex` (ex.: crates, Discos de Platina, Sorte permanente pequena, título, slot extra), crescente com a raridade. Completar o Índice inteiro dá um prémio final. Reclamação única por jogador, validada no servidor; indicador no botão do Índice quando há prémios por reclamar.
- **Vitrine:** pedestal à frente de cada terreno com um artista do dono (modelo animado, nome, cor da raridade, estrelas, aura nas raridades altas). Modo **Automático** (melhor por raridade → estrelas → multiplicador, atualiza sozinho) ou **Manual** (escolhido do inventário), configurável pelo jogador e guardado no perfil. Se o artista manual deixar de existir, volta a Automático. Usa o contrato de modelos (`Root` + `Visual`, override em `ServerStorage/Assets/Artists/<ArtistId>`) e posição por atributo gravado pelo servidor. LOD de longe.
- **Migração:** os artistas que o jogador já tem passam a contar como descobertos.
- **Implementado (valores aprovados):** 150 combinações (5 crates × 5 artistas × 6 raridades da janela; IndexCalc). Prémios por raridade em Config/ArtistIndex (crates grátis + Discos, crescentes; maiores nas raridades de 1% da crate) e prémio final (1500 Discos + 1 slot de artista permanente, MaxSlots 8, + título "Lenda do Índice" na placa do terreno). Perfil v3: Index = { Discovered, Claimed }, Showcase = { Mode, Uid }. Descoberta centralizada em ArtistService.MarkDiscovered (chamado no AddArtist e nas aberturas apagadas pelo Auto-Delete). Servidor: IndexService (reclamar, IndexSync), ShowcaseService (pedestal Config/Showcase, override ServerStorage/Assets/Showcase/Pedestal com Attachment ArtistSpot). Cliente: IndexController, IndexView (botão 7 ÍNDICE, tecla I, indicador de prémios), ShowcaseController (rotação/flutuação com LOD Config/Lod.Showcase), botão VITRINE no detalhe da Coleção. Debug: /fe index discover <id> <raridade>|all|reset|claim <raridade|Final>, /fe showcase auto|<uid>.

## Fase 11 — Fones, Modo Ouvir, Vibes e Sorte (ADIADA: implementar depois da Fase 13)
- **Fones:** vários níveis comprados com Hype numa loja; cada nível define em `Config/Headphones` preço, requisito de tier (e de World Tours nos mais altos) e Vibes por segundo. Não dão Hype nem Sorte diretamente. Proposta de 8 níveis: esponja → auriculares básicos → estúdio → sem fios → pro → neon → holográficos → cósmicos. Um par equipado de cada vez, visível na cabeça do avatar.
- **Modo Ouvir:** com fones equipados, dentro do próprio terreno e fora do palco. O boneco fica parado com animação replicada (cabeça ao ritmo, notas a sair dos fones). Ganha Vibes por segundo no tick de 1 Hz; os geradores passivos continuam a dar Hype; o minijogo de setas fica indisponível. Mexer, saltar, sair do terreno ou morrer termina o modo (o servidor confirma a posição). Não conta para o rendimento offline.
- **Boosts:** durante o Modo Ouvir aparecem botões grandes em posições aleatórias que dão x2 ou x4 às Vibes durante alguns segundos. O servidor decide o momento, o multiplicador (com pesos) e a duração; o cliente envia "cliquei no boost <id>"; o servidor valida dono, prazo, uso único e que o jogador continua no Modo Ouvir. Teto de boosts em Config.
- **Sorte a partir das Vibes (teto suave):** `SorteVibes% = SorteMax * Vibes / (Vibes + K)` (ex.: SorteMax = 300%, K = 1M → 1M Vibes = 150%, 3M = 225%). Valores em `Config/Luck`; mostrar a curva antes de fixar.
- **Outras fontes de Sorte (pequenas):** nós da árvore (Sorte base permanente com teto), Gamepass, prémios do Índice, eventos. Aditivas dentro da categoria, multiplicativas entre categorias, com teto global.
- **Aplicação ao gacha:** a Sorte multiplica o peso das raridades a partir de uma raridade mínima (Config) e as probabilidades são renormalizadas. Não altera o pity. A UI das crates mostra probabilidades base e com Sorte (tudo via `shared/Calc/LuckCalc`).
- **Árvore de Prestige:** acrescentar nós de multiplicador permanente de Vibes, Sorte base e começar a run com os primeiros fones.
- **HUD:** Vibes e Sorte atuais; replicadas pelo `PlayerStateService` (deltas).

## Fase 12 — Animação de abertura das Vinyl Crates (roleta)
- **Roleta horizontal:** ao abrir uma crate, aparece uma faixa de cartas de artistas a passar da direita para a esquerda, que abranda até parar com o artista ganho debaixo do marcador central. Cada carta tem a moldura e o brilho da cor da raridade; som de "tick" a cada carta que passa o marcador, mais espaçado à medida que abranda.
- **Resultado primeiro, animação depois:** o servidor sorteia o resultado (RNG, Sorte, pity) e entrega o artista **imediatamente** (perfil, coleção, Índice, Auto-Fuse/Delete); só depois envia o resultado ao cliente para animar. Sair do jogo ou fechar a UI a meio nunca faz perder o artista.
- **Cartas de enchimento:** geradas no cliente com as probabilidades reais da crate (com a Sorte do jogador), para a roleta não sugerir probabilidades falsas. O cliente nunca decide o resultado.
- **Revelação por família:** cada família de raridade tem a sua paragem: Comum rápida e simples; Raro/Épico com brilho e som próprio; Lendário e Mítico (não mistério) com flash, confetti e câmara lenta no fim; anúncio no servidor nas 2 raridades mais raras de cada crate, quando a roleta para.
- **Carta mistério (ultra-raros):** raridades com probabilidade **na crate** igual ou inferior a `Config/CrateAnimation.MysteryThreshold` (0.01 = 1%) **e** raridade ≥ `MysteryMinRarity` ("Divine") — ou seja Divino (Estrelato), Etéreo (Lenda) e Ómega (Orbital) — aparecem na roleta como **a sombra do artista** (silhueta preta, sem detalhes) com **"???"** a vermelho no lugar da probabilidade e brilho pulsante. Só aparecem quando são o resultado (nunca no enchimento). Quando a roleta para numa: 1 s com o "???" a pulsar e começa a cinemática.
- **Cinemática do ultra-raro (só para quem abriu, ~16.6 s, timeline em `Config/CrateAnimation.Timeline`):** câmara Scriptable por cima do próprio terreno, com um plano diferente por fase (grande plano baixo a rodar → grua → rasteiro por baixo da brecha com "zoom" nas pancadas → lateral a seguir a queda → corte ao nível do chão → órbita) e transições suaves (`CameraBlend`); o sol fica escondido do início ao fim (`Sky.CelestialBodiesShown`, só no cliente) e toda a interface do jogo (ScreenGuis + CoreGui) fica escondida, voltando no fim ou se a cinemática for cancelada. 1 Fade para preto (0.6 s, a música corta) → 2 Tempestade (3.6 s: o céu azul fecha-se — nuvens 3D cinzentas (9 elipsoides em 3 tons, 1.3–1.9× de tamanho, 7 anéis até ao horizonte, movidas com `BulkMoveTo`) vêm do horizonte até ao centro, com um teto contínuo de placas por cima para não haver buracos, e `Terrain.Clouds` a 100%; depois chuva e 7 relâmpagos (núcleo branco + brilho azulado, desenham-se de cima para baixo, ramificações, 3 clarões a enfraquecer, iluminam as nuvens), trovão atrasado 0.35 s, câmara a olhar para cima) → 3 O céu abre-se (3.0 s, em redemoinho: o teto cinzento desaparece logo no início e só se veem nuvens; as nuvens de dentro vão para a borda de um círculo exato, `CloudOpenRadius`, e abrem um buraco redondo e limpo com céu azul normal, sem sol) → 4 O céu parte-se (3.8 s: alguém do outro lado dá 7 pancadas no céu, as primeiras espaçadas e o ritmo a acelerar; o céu da brecha é uma malha de triângulos irregulares: em cada pancada as arestas à volta acendem-se como rachas e os triângulos perto caem do centro para fora; no lugar de cada um fica "outro mundo" com a mesma forma (preto-roxo, estrelas, nebulosa), por isso o buraco é angular e partido, com contorno na cor da raridade só na borda; cada pancada tem a sua luz e o seu feixe no sítio onde o céu partiu (acendem forte quando os fragmentos caem e ficam a brilhar conforme o tamanho do buraco); a cena ganha tons roxos/da raridade com Bloom; a última pancada, a maior, abre o centro) → 5 Salto (1.4 s: a silhueta sai do rift e cai com rasto de luz, a câmara acompanha) → 6 Aterragem (1.0 s: onda de choque, rachas, cratera, pó e detritos, tremor, impacto grave) → 7 Revelação (2.4 s: a silhueta ganha cor, aura, nome e raridade em letras grandes, câmara em órbita) → 8 Fim (0.8 s: câmara e iluminação repostas). Lighting só local, por tween, reposta exatamente; cratera/rachas/detritos são peças locais temporárias; personagem parada e com ForceField (servidor). Morrer, reset ou abrir outra UI a meio repõe tudo.
- **Os outros jogadores:** não perdem a câmara; veem uma versão leve por cima do terreno de quem abriu (tempestade, relâmpagos, rift e o artista a aterrar) com LOD (`Config/Lod.Cinematic`: leve até 120, só feixe de luz até 250, nada além). O servidor faz broadcast (`CrateSummon`: jogador, artista, raridade, hora de início) e anuncia "<Jogador> invocou um <Raridade>!" na altura da revelação.
- **Abrir x10:** em vez de 10 roletas, uma grelha de 10 cartas viradas que se revelam em sequência; as de raridade alta revelam-se por último. Se houver mistérios, a cinemática corre uma vez, para o melhor, e depois os mistérios revelam-se na grelha.
- **Saltar:** botão "Saltar" que vai direto à revelação (a cinemática pode ser saltada a partir da segunda vez que o jogador a vê; contador no perfil, decidido pelo servidor). Opção "Animação rápida" (no separador Crates, guardada no perfil): roleta de 1.5 s e cinemática só com Fade → Aterragem → Revelação → Fim.
- **Modelos:** nuvens, rift, cratera e detritos são placeholders por código com override opcional em `ReplicatedStorage/Assets/Cinematics/<Cloud|Crater|Debris>` (contrato `Root` + `Visual`); os artistas vêm de `ReplicatedStorage/ArtistRigs/<ArtistId>` (copiados pelo servidor a partir de `ServerStorage/Assets/Artists`).
- **Implementação:** só apresentação no cliente (`CrateAnimController` + `CrateRevealView` + `CrateCinematicController`), registada no `ModalManager`; cartas reutilizadas por pool, tweens em vez de lógica por frame, nada de alocações no RenderStepped. Durações, nº de cartas, easing, cores, limiar e sons em `Config/CrateAnimation`; IDs de áudio em `Config/Audio` (a 0 → sons de fallback). Botão de abrir bloqueado até a animação acabar ou ser saltada (o rate limit do servidor continua a valer).
- **Telemóvel:** cartas grandes, roleta a ocupar a largura do ecrã, botão "Saltar" fácil de tocar.

## Fase 13 — Variantes Brilhantes, Traços, Cristais, "NOVO!" e Auto-Abrir
### Variantes Brilhantes
- Independentes da raridade: cada artista obtido tem uma chance à parte de sair numa variante, sorteada no servidor. Valores em `Config/Variants` (proposta, a confirmar com simulação):

  | Variante | Chance | Aspeto | Bónus |
  |---|---|---|---|
  | Dourado | 1/250 | corpo metálico dourado com reflexos | +25% |
  | Neon | 1/500 | contornos neon a pulsar com a música (`PlaybackLoudness`) | +40% |
  | Holográfico | 1/1 000 | arco-íris a mudar de cor, partículas em prisma | +60% |
  | Glitch | 1/2 500 | modelo a "falhar", distorções e píxeis | +100% |
  | Galáctico | 1/5 000 | textura de estrelas/nebulosa em movimento, aura | +150% |
  | Infernal | 1/10 000 | chamas, olhos a brilhar, fumo | +250% |

- O bónus da variante multiplica o artista (documentar na ordem dos multiplicadores).
- Visual aplicado no cliente sobre o modelo (materiais, Highlight, partículas, tweens de cor), no palco, na vitrine, na roleta e no inventário. LOD de longe. Overrides opcionais em `ReplicatedStorage/Assets/Variants/<Variante>`.
- Na roleta: carta com moldura especial e brilho a percorrê-la; revelação com "BRILHANTE!" e som próprio.
- Chances visíveis na UI das crates. O Auto-Delete nunca apaga variantes por defeito (opção configurável).
- **Fusão:** os 3 artistas têm de ter também a mesma variante (mesmo artista/raridade/estrelas/variante); o resultado mantém a variante.
- **Índice:** separador de variantes (descoberta por artista × variante).
- **Implementado (13A, valores aprovados):** Config/Variants + VariantCalc (sorteio da mais rara para a mais comum; ~0.77% de sair alguma). ArtistData.Variant ("" = normal), perfil v4 com migração (nenhum artista existente fica com variante). Bónus: raridade × era × estrelas × (1 + bónus da variante) em ArtistCalc.GetBonus; fusão exige a mesma variante (GroupKey). Auto-Delete nunca apaga variantes salvo Settings.AutoDeleteVariants (botão "🛡 Brilhantes" na Coleção). Visual no cliente (VariantVisuals: atributo "Variant" nos modelos do palco/vitrine, retratos 3D; anima só perto, LOD Config/Lod.Vfx). Roleta/grelha: faixa "★ VARIANTE", moldura com brilho, "BRILHANTE!" + som CrateShiny; selo "NOVO!" (CrateItem.New, IndexHave/IndexTotal = "Novo no Índice! 7/12"). Índice: separador "★ VARIANTES" (25 artistas × 6 variantes, Index.Variants, sem prémios por agora). Chances no botão "%" das crates. Anúncio no servidor para Holográfico ou mais rara. Debug: /fe artist give … [variante], /fe crate anim <raridade> [x10] [variante], /fe variant odds. As plataformas antigas das crates (r=55) foram removidas.

### Traços
- Cada artista obtido recebe 1 traço sorteado no servidor, com raridade própria (Comum → Lendário) e valor crescente com essa raridade. Pool, pesos e valores em `Config/Traits`. Exemplos:
  - Voz Potente: +10/20/35/60% de Hype desse artista
  - Pirómano: −10/15/20/30% de cooldown do lança-chamas
  - Ritmo Perfeito: bolinhas das setas duram +5/8/12/18%
  - Energético: +5/10/15/25% de energia do Bass Drop
  - Showman: +0.5/1/1.5/2 s de boost do Bass Drop
  - Crowd Surfer: +1/2/3/5% de Hype passivo global
- Os traços respeitam os **limites somados** já definidos (janela, cooldowns, boost, energia) e entram na cache de taxas (`EconomyService.InvalidateRates`).
- Traços ligados à Sorte (ex.: "Sortudo") só entram com a Fase 11.
- **Fusão:** o artista resultante fica com o **melhor** traço dos 3 usados (por raridade do traço, depois valor).
- Artistas já existentes recebem um traço sorteado na migração.

### Cristais e Estúdio de Remix
- **Cristais:** moeda nova, ganha ao fundir (manual e Auto-Fuse). Quantidade por família e estrelas em `Config/Crystals` (proposta):

  | Família | → 2★ | → 3★ |
  |---|---|---|
  | Comum | 1 | 3 |
  | Raro | 3 | 9 |
  | Épico | 10 | 30 |
  | Lendário | 40 | 120 |
  | Mítico+ | 150 | 450 |

- Os Cristais **mantêm-se no World Tour**.
- **Estúdio de Remix:** estação no centro da praça (ProximityPrompt), com um disco holográfico gigante por cima. O jogador escolhe um artista, paga Cristais (custo em Config, pode subir com a raridade do artista) e o traço é sorteado de novo, com as probabilidades visíveis na UI. O novo traço substitui o anterior (mostrar aviso antes de confirmar).
- Quando sai um traço Lendário, o disco da praça explode em luz (visível a todos, com LOD) e há anúncio no servidor.
- Só o próprio jogador mexe nos seus artistas; o servidor valida posse, saldo, artista existente e rate limit.
- **Implementado (13B, valores aprovados):** `Config/Traits` (raridades do traço Comum 60 · Raro 28 · Épico 10 · Lendário 2; 6 traços: Voz Potente, Mãos Rápidas, Energético, Showman, Pirómano, Crowd Surfer — "Ritmo Perfeito" e "Sortudo" ficam para as Fases 9 e 11) + `TraitCalc`. `ArtistData.Trait`/`TraitTier`; **os artistas nascem sem traço** (`""`): só ganham um no Estúdio de Remix; perfil v5 com migração (`Crystals = 0`, `Trait = ""` onde faltar). Os traços só contam nos artistas do palco (`ArtistCalc.ComputeEffects`): Voz Potente multiplica o `GetBonus` do próprio artista; Mãos Rápidas → `ClickBonus`; Energético → `EnergyBonus`; Showman → `BoostBonus`; Crowd Surfer → `PassiveBonus` (só no Hype passivo, `EconomyService`); Pirómano → `MachineCut.Flamethrower` (`PyroService.StartCooldowns`), tudo dentro dos limites somados. Fusão: o resultado fica com o melhor traço dos 3 e dá Cristais (`Config/Crystals.Fusion`). Remix: `TraitService` (remote `RemixTrait`, custo `Config/Crystals.RemixCost` por família, `RemixResult`, `RemixBurst` + anúncio nos Lendários). O Estúdio fica na praça a r=55, ângulo 150 (onde estava uma plataforma antiga das crates), com disco holográfico a rodar (`RemixFxController`) e prompt que abre a `RemixView`: coleção à esquerda; ao centro a cara do artista (ViewportFrame na cabeça) e por baixo a roleta vertical de traços (janela com 1 traço inteiro + 2 cortados nas pontas, desce de cima para baixo e pára no resultado do servidor) com o botão RODAR TRAÇO (confirmação só se já houver traço); à direita probabilidades e traços possíveis com os valores por raridade. Cristais replicados no snapshot. Debug: `/fe crystals add|set <n>`, `/fe trait reroll <uid> [force <traço> <raridade>]` (o uid aparece no detalhe da Coleção).

### Selo "NOVO!"
- Na roleta e na grelha x10, a carta de um artista (ou variante) que o jogador nunca tinha obtido mostra um selo "NOVO!", com um aviso "Novo artista no Índice! 7/12".
- Usa o registo de artistas descobertos da Fase 10.

### Auto-Abrir (Gamepass)
- Abre crates seguidas com a animação rápida enquanto houver Hype. O jogador escolhe quando parar: raridade igual ou superior a X, artista NOVO, variante Brilhante, ou Hype insuficiente. Pára também ao sair do jogo ou ao abrir outra UI.
- O ritmo é controlado pelo servidor (intervalo mínimo em Config). Cada abertura passa pelas mesmas validações que uma abertura manual.
- `Config/Monetization.AutoOpenGamepassId`; a 0 → funcionalidade desligada (botão escondido).

## Integração com a arquitetura (Fases 9–13)
- Novos Configs: `ArrowGame`, `ArtistIndex`, `Showcase`, `Headphones`, `Vibes`, `Luck`, `CrateAnimation`, `Variants`, `Traits`, `Crystals`, `Monetization` (se ainda não existir). Novos Calc: `ArrowCalc`, `IndexCalc`, `LuckCalc`, `VariantCalc`, `TraitCalc`.
- Novos dados no perfil: Vibes, fones comprados/equipados, artistas descobertos (incluindo variantes), prémios do Índice reclamados, modo/artista da vitrine, Cristais, variante e traço de cada artista, opções do Auto-Abrir. Subir `DataVersion` + migração.
- `SideMenu`: novos botões depois dos atuais (6 Índice, 7 Fones). Teclas sugeridas: I Índice, H Fones; as setas ficam reservadas ao minijogo. O Estúdio de Remix abre-se na praça (ProximityPrompt), não no menu.
- Invalidar taxas (`EconomyService.InvalidateRates`) ao mudar combo, fones, Vibes ou Sorte quando afetarem cálculos em cache.
- Comandos de debug a acrescentar: `arrows diff <n>|stats`, `vibes add|set <v>`, `luck`, `phones give <nível>|equip <nível>`, `listen`, `boost force`, `index discover <id> <raridade>|reset|claim`, `showcase auto|<id>`, `crate anim <raridade> [x10]` (pré-visualizar a animação sem gastar nem dar nada), `artist give … [variante] [traço]`, `crystals add|set <n>`, `trait reroll <uid> [force <traço> <raridade>]`, `variant odds`, `autoopen on|off` (simula o Gamepass em Studio).

# ARQUITETURA E CONVENÇÕES (respeitar ao continuar)
- **Bootstrap:** `Main.server.luau` e `Main.client.luau` correm cada `Init()`/`Start()`/`Mount()` isolado com `xpcall` (um módulo com erro não desliga os outros e aparece no Output com traceback). No servidor o núcleo (rede, dados, economia, estado) inicializa antes do mundo (mapa/terrenos/palcos).
- **Rede:** todos os remotes declarados em `RemoteDefs` (com `RateLimit` e `Args` validados). `ServerNet.Init()` cria os remotes **sem os expor**; `ServerNet.Open()` corre depois de todos os `Init()` e só então os põe em `ReplicatedStorage.Remotes`. Pedidos sem handler ficam em fila. O cliente usa `NetController.Fire/On`.
- **Replicação de estado:** `PlayerStateService` envia snapshot quando há perfil carregado **e** `ClientReady` (qualquer ordem) e depois deltas a 5 Hz só com campos alterados. O cliente repete `ClientReady` até receber o snapshot. Coleção de artistas sincronizada à parte (`ArtistsSync`), estado do drop em `DropState`.
- **Cálculos partilhados:** tudo o que a UI mostra e o servidor cobra vem de `shared/Calc/*` (preços, multiplicadores, Discos, pity, estados de bloqueio) — o cliente nunca calcula regras próprias.
- **Ordem dos multiplicadores de Hype:** equipamento × palco (1.6^(tier−1)) × Fama (1.5^WT) × Amplificação × artistas (bónus de cada um × variante Brilhante, com Aura do Público) × boost do Bass Drop; batidas ainda × Batida Forte × Batida de Ouro (na Fase 9 passa a valer para os acertos das setas, × combo × nota). Taxas em cache por jogador (`EconomyService.InvalidateRates` sempre que algo muda).
- **Limites somados (artistas + árvore):** janela +0.15 s, cooldowns −50%, boost +8 s, energia +100%. Multiplicador do drop sempre 5x–50x.
- **Transições de palco:** o servidor troca o modelo e grava atributos `Transition*` no Plot (`Start` em `GetServerTimeNow`, `From`, `To`, `Era`, `Kind`, `WorldTour`, `Id`); cada cliente anima localmente (`StageAnimController`). Tipos: `"Stage"` e `"Prestige"`.
- **Modelos substituíveis (Blender):** contrato `Model` com `Root` (Part invisível, PrimaryPart, com os Attachments) + `Visual` (geometria). Overrides em `ServerStorage/Assets/…` (`Stages/Tier_XX`, `Plaza`, `PlotSign` com parte `Board`, `Decor/<Era>`, `Prestige/Arch` com parte `Beam`, `Artists/<ArtistId>`; a acrescentar: `Showcase/Pedestal`, `Headphones/<Nível>`). Sem override usa `World/Placeholders`. Medidas para modelação em `docs/Medidas_Modelos_3D_Festival_Empire.pdf`.
- **Pirotecnia/efeitos:** resolver de emissores aponta para os Attachments `Pyro_<Máquina>_<n>` do palco do dono (fallback à volta da personagem). Distâncias de LOD só em `Config/Lod`.
- **UI:** botões laterais no `SideMenu` (ordem: 1 Voltar, 2 Loja, 3 Palcos, 4 Artistas, 5 World Tour); painéis centrais registam-se no `ModalManager` (só um aberto). Teclas: B loja, P palcos, K artistas, T World Tour, F drop.
- **Diagnóstico:** `Diag.Log/LogSampled` (prefixo `[Diag:S]`/`[Diag:C]`), ligado por `Config/Debug.NetTrace`.

# ARMADILHAS JÁ ENCONTRADAS (não repetir)
- **Casts encadeados** `a :: T :: U` são erro de sintaxe em Luau — usar `(a :: unknown) :: U`.
- **Race no arranque:** nunca expor remotes antes de todos os handlers existirem (ver `ServerNet.Open`).
- **Posições replicadas:** no cliente não ler `GetPivot()` de um modelo no `ChildAdded` (as peças podem não ter chegado) — usar um atributo gravado pelo servidor (ex.: `BaseCFrame` dos artistas).
- **Session lock no Studio:** locks de sessões de teste anteriores são ignorados em Studio (`Config/Data.IgnoreSessionLockInStudio`).
- **Atributos/strings com chaves dinâmicas** em tabelas tipadas (ex.: `Pity[key]`) exigem cast via `unknown`.

# BALANCEAMENTO APROVADO (valores exatos nos Config)
- Economia: `Config/Economy`, `Config/Equipment` (geradores com `RequiredTier` 1–6).
- Palcos: custos 40K → 1.5Qi, multiplicador ×1.6/tier; tempos-alvo da Fase 5 obtidos por simulação (`scratchpad/sim/sim.js`, fora do projeto).
- Bass Drop: 128 BPM, janela −0.5/+1.0 s, notas PERFEITO/ÓTIMO/BOM/TARDE, boost 12 s.
- Gacha: crates 1K / 250M / 10T / 1Qa / 25Qa com bónus da era ×1/×2/×4/×8/×15; coleção 300.
- Prestige: World Tour a partir do Tier 6; Discos = ⌊10 × √(HypeDaRun ÷ 1T) × (1 + 0.25 × (Tier − 6)) × (1 + Contrato)⌋.
- Fases 9–13: valores por aprovar (setas, prémios do Índice, fones, SorteMax/K, chances e bónus das variantes, pool de traços, Cristais por fusão e custo do Remix). Incluir na simulação o Hype das setas com diferentes precisões, a Sorte ao longo de uma run e o tempo esperado para completar cada raridade do Índice.

# SETUP NO STUDIO
- `rojo serve` + plugin; o Rojo gere `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`. **`ServerStorage` não é gerido pelo Rojo** (modelos do Blender ficam no place).
- Game Settings: Max Players = 6; Security → Enable Studio Access to API Services (senão os dados ficam em memória).
- Workspace: `StreamingEnabled = false`.
- Exportar placeholders para `ServerStorage/Assets` (modo Edit, Command Bar): `require(game.ServerScriptService.Server.World.Placeholders).ExportAll()` e gravar o place.

# COMANDOS DE DEBUG (`/fe <comando>`, admins / Studio)
`help` · `hype add|set <v>` · `pps <v>|off` · `offline <s>` · `cost …` · `equip list|<id> <nível>` · `energy <n>` · `drop` · `pyro all` · `cd reset` · `stage <1-12> [anim]` · `wt <n>` · `artist give <id> <raridade> [estrelas] [qtd]|clear` · `pity` · `tour [force]` · `discs <n>` · `skills reset` · `plots` · `home` · `state` · `save` · `wipe confirm`
(A acrescentar nas Fases 9–12: ver "Integração com a arquitetura".)

# PENDENTE / PRÓXIMOS PASSOS CONHECIDOS
- IDs de áudio em `Config/Audio` (a 0 → efeitos pulsam pelo relógio de 128 BPM).
- Gamepass "Palco VIP": definir `Config/Artists.VipGamepassId`.
- Gamepass "Auto-Abrir" (Fase 13): definir `Config/Monetization.AutoOpenGamepassId`.
- Modelos finais do Blender para palcos, praça, placa, decoração, arco, artistas, pedestal da vitrine e fones.
- `Settings.LowVfx` ainda não chega ao cliente (já existe `PyroVfxController.SetLowVfx`).
- Recalibrar Fama e custos dos Tiers 9–12 com uma simulação que inclua artistas e árvore (só Fama = fim de jogo lento; com Amplificação = mais rápido que a tabela).
- Antes de publicar: `Config/Debug.NetTrace = false`.
- Verificação estática: não há analisador Luau instalado; considerar `luau-lsp` no `aftman.toml`.
