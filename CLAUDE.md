# PAPEL E IDENTIDADE DO PROJETO
És um programador sénior de Roblox, especialista em Luau com `--!strict`, arquitetura cliente-servidor segura e jogos idle/incremental com gacha.
Projeto: **"Festival Empire Tycoon"** (PlaceId: `139556886062753`).
Escreves código completo e pronto a usar, sem pseudo-código nem `TODO` por preencher.
Nada relacionado com outros festivais reais ou nomes externos deve existir nos textos, configs ou código.
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
- **Gacha (Vinyl Crates):** Abertas nos tiers 1, 4, 7, 10 e especial no 12. **22 raridades** agrupadas em 5 famílias que mantêm os totais Comum 55% · Raro 28% · Épico 12% · Lendário 4.5% · Mítico+ 0.5% (sem Sorte). A raridade é uma "versão" do artista da família na crate. Pity em escada: Lendário+ aos 50, Mítico+ aos 250, Divino+ aos 1000, Cósmico+ aos 5000. Slots de palco: 3 base até 7 (World Tours + Gamepass). Fusão: 3x mesmo artista/raridade/estrelas 1★ -> 2★ (Remix 2.5x); 3x 2★ -> 3★ (Platinum 6x) + Auto-Fuse/Auto-Delete.
- **Prestige (World Tour):** Dá Discos de Platina, faz reset a Hype, equipamento e tier do palco (volta ao Tier 1 — ou ao tier inicial da árvore — com animação de desmontagem), mas mantém artistas, árvore de habilidades, Discos por gastar, pirotecnia desbloqueada e contagem de World Tours. Cada World Tour dá Fama ×1.5 de Hype global.
  - **Com as Fases 9–11:** também fazem reset os fones comprados com Hype e as Vibes (e a Sorte que vinha delas). Mantêm-se também o Índice e os prémios já reclamados, os contadores de pity, a vitrine, tudo o que foi pago com Robux, badges, sequência diária, missões, códigos usados e leaderboards.
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
Ordem: 9 → 10 → 11 → depois Monetização e polimento. Em cada fase, apresenta primeiro a proposta com os valores para aprovação.

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

## Fase 11 — Fones, Modo Ouvir, Vibes e Sorte
- **Fones:** vários níveis comprados com Hype numa loja; cada nível define em `Config/Headphones` preço, requisito de tier (e de World Tours nos mais altos) e Vibes por segundo. Não dão Hype nem Sorte diretamente. Proposta de 8 níveis: esponja → auriculares básicos → estúdio → sem fios → pro → neon → holográficos → cósmicos. Um par equipado de cada vez, visível na cabeça do avatar.
- **Modo Ouvir:** com fones equipados, dentro do próprio terreno e fora do palco. O boneco fica parado com animação replicada (cabeça ao ritmo, notas a sair dos fones). Ganha Vibes por segundo no tick de 1 Hz; os geradores passivos continuam a dar Hype; o minijogo de setas fica indisponível. Mexer, saltar, sair do terreno ou morrer termina o modo (o servidor confirma a posição). Não conta para o rendimento offline.
- **Boosts:** durante o Modo Ouvir aparecem botões grandes em posições aleatórias que dão x2 ou x4 às Vibes durante alguns segundos. O servidor decide o momento, o multiplicador (com pesos) e a duração; o cliente envia "cliquei no boost <id>"; o servidor valida dono, prazo, uso único e que o jogador continua no Modo Ouvir. Teto de boosts em Config.
- **Sorte a partir das Vibes (teto suave):** `SorteVibes% = SorteMax * Vibes / (Vibes + K)` (ex.: SorteMax = 300%, K = 1M → 1M Vibes = 150%, 3M = 225%). Valores em `Config/Luck`; mostrar a curva antes de fixar.
- **Outras fontes de Sorte (pequenas):** nós da árvore (Sorte base permanente com teto), Gamepass, prémios do Índice, eventos. Aditivas dentro da categoria, multiplicativas entre categorias, com teto global.
- **Aplicação ao gacha:** a Sorte multiplica o peso das raridades a partir de uma raridade mínima (Config) e as probabilidades são renormalizadas. Não altera o pity. A UI das crates mostra probabilidades base e com Sorte (tudo via `shared/Calc/LuckCalc`).
- **Árvore de Prestige:** acrescentar nós de multiplicador permanente de Vibes, Sorte base e começar a run com os primeiros fones.
- **HUD:** Vibes e Sorte atuais; replicadas pelo `PlayerStateService` (deltas).

## Integração com a arquitetura (Fases 9–11)
- Novos Configs: `ArrowGame`, `ArtistIndex`, `Showcase`, `Headphones`, `Vibes`, `Luck`. Novos Calc: `ArrowCalc`, `IndexCalc`, `LuckCalc`.
- Novos dados no perfil: Vibes, fones comprados/equipados, artistas descobertos, prémios do Índice reclamados, modo/artista da vitrine. Subir `DataVersion` + migração.
- `SideMenu`: novos botões depois dos atuais (6 Índice, 7 Fones). Teclas sugeridas: I Índice, H Fones; as setas ficam reservadas ao minijogo.
- Invalidar taxas (`EconomyService.InvalidateRates`) ao mudar combo, fones, Vibes ou Sorte quando afetarem cálculos em cache.
- Comandos de debug a acrescentar: `arrows diff <n>|stats`, `vibes add|set <v>`, `luck`, `phones give <nível>|equip <nível>`, `listen`, `boost force`, `index discover <id> <raridade>|reset|claim`, `showcase auto|<id>`.
| 9+10 Monetização/Retenção | 4 Gamepasses (Palco VIP, Auto-Batida no servidor, Hype ×2, Agente de Tour), 5 Developer Products (ProcessReceipt idempotente), "Bem-vindo de volta", leaderboards globais na praça, diário 7 dias (20 h / 48 h), 3 missões diárias + 2 semanais por sinais, códigos com expiração/limite global, 10 Badges | `Config/Monetization`, `Config/Retention`, `Config/Codes`, `Config/Badges`, `Config/Leaderboards`, `RetentionCalc`, `RewardService`, `MonetizationService`, `RetentionService`, `AchievementService`, `LeaderboardService`, `MissionsView`, `VipPage`, `WelcomeBackView` |
| 11+12 Ambiente/Social (por validar) | Público por terreno com LOD (reage à música, explode nos drops), decoração da praça com luzes ao ritmo, danças dos artistas por família (ou AnimationId), música por era com crossfade; bónus de amigos/grupo/Likes, visitar festivais, ❤ Like (1 por festival/dia, máx. 5), evento global Headliner (2 h, 10 min, Hype ×2, energia ×1.5) | `Config/Ambience`, `Config/Social`, `SocialCalc`, `SocialService`, `CrowdController`, `AmbienceController`, `SocialController`, `FestivalsView`, `SocialHudView`, `VipButtonView` |

# ARQUITETURA E CONVENÇÕES (respeitar ao continuar)
- **Bootstrap:** `Main.server.luau` e `Main.client.luau` correm cada `Init()`/`Start()`/`Mount()` isolado com `xpcall` (um módulo com erro não desliga os outros e aparece no Output com traceback). No servidor o núcleo (rede, dados, economia, estado) inicializa antes do mundo (mapa/terrenos/palcos).
- **Rede:** todos os remotes declarados em `RemoteDefs` (com `RateLimit` e `Args` validados). `ServerNet.Init()` cria os remotes **sem os expor**; `ServerNet.Open()` corre depois de todos os `Init()` e só então os põe em `ReplicatedStorage.Remotes`. Pedidos sem handler ficam em fila. O cliente usa `NetController.Fire/On`.
- **Replicação de estado:** `PlayerStateService` envia snapshot quando há perfil carregado **e** `ClientReady` (qualquer ordem) e depois deltas a 5 Hz só com campos alterados. O cliente repete `ClientReady` até receber o snapshot. Coleção de artistas sincronizada à parte (`ArtistsSync`), estado do drop em `DropState`.
- **Cálculos partilhados:** tudo o que a UI mostra e o servidor cobra vem de `shared/Calc/*` (preços, multiplicadores, Discos, pity, estados de bloqueio) — o cliente nunca calcula regras próprias.
- **Ordem dos multiplicadores de Hype:** equipamento × palco (1.6^(tier−1)) × Fama (1.5^WT) × Amplificação × artistas (com Aura do Público) × boost do Bass Drop; batidas ainda × Batida Forte × Batida de Ouro (na Fase 9 passa a valer para os acertos das setas, × combo × nota). Taxas em cache por jogador (`EconomyService.InvalidateRates` sempre que algo muda).
- **Limites somados (artistas + árvore):** janela +0.15 s, cooldowns −50%, boost +8 s, energia +100%. Multiplicador do drop sempre 5x–50x.
- **Transições de palco:** o servidor troca o modelo e grava atributos `Transition*` no Plot (`Start` em `GetServerTimeNow`, `From`, `To`, `Era`, `Kind`, `WorldTour`, `Id`); cada cliente anima localmente (`StageAnimController`). Tipos: `"Stage"` e `"Prestige"`.
- **Modelos substituíveis (Blender):** contrato `Model` com `Root` (Part invisível, PrimaryPart, com os Attachments) + `Visual` (geometria). Overrides em `ServerStorage/Assets/…` (`Stages/Tier_XX`, `Plaza`, `PlazaDecor`, `PlotSign` com parte `Board`, `Decor/<Era>`, `Prestige/Arch` com parte `Beam`, `Artists/<ArtistId>`; a acrescentar: `Showcase/Pedestal`, `Headphones/<Nível>`). Sem override usa `World/Placeholders`. Medidas para modelação em `docs/Medidas_Modelos_3D_Festival_Empire.pdf`.
- **Pirotecnia/efeitos:** resolver de emissores aponta para os Attachments `Pyro_<Máquina>_<n>` do palco do dono (fallback à volta da personagem). Distâncias de LOD só em `Config/Lod`.
- **UI:** botões laterais no `SideMenu` (112×88; ordem: 1 Voltar, 2 Loja, 3 Palcos, 4 Artistas, 5 World Tour, 6 Missões, 7 Festivais; a coluna encolhe com UIScale se não couber no ecrã); painéis centrais registam-se no `ModalManager` (só um aberto). Teclas: B loja, P palcos, K artistas, T World Tour, M missões, G festivais, F drop, V loja VIP. Canto superior direito: botão "★ VIP" (`VipButtonView`) e, por baixo, faixa do Headliner + botão ❤ LIKE (`SocialHudView`).
- **Multiplicadores extra:** `EconomyService.SetMultiplier(player, fonte, valor)` (fonte "Social" = amigos × grupo × Likes × Headliner, depois do Gamepass ×2) e `BassDropService.SetEnergyMultiplier(player, fonte, valor)` (fonte "Headliner"). Reutilizar para o tutorial.
- **Ambiente (só cliente):** público em `Workspace/ClientCrowds` movido com `BulkMoveTo`; partes com atributo `RhythmLight = true` mudam de cor ao ritmo; Headliner calculado por `SocialCalc.ReadHeadliner(GetServerTimeNow(), ReplicatedStorage)` (overrides de debug em atributos de ReplicatedStorage). Atributos públicos dos jogadores: `FE_StageTier`, `FE_WorldTours`, `FE_Likes`.
- **Sinais de jogo** (para missões/conquistas, nunca progresso vindo do cliente): `EconomyService.Clicked(player, n)`, `BassDropService.DropSucceeded(player, grade)`, `EquipmentService.Purchased`, `GachaService.CratesOpened`, `ArtistService.Fused`, `StageService.StageChanged/StagePlaced`, `PrestigeService.WorldTourCompleted`, `RetentionService.DailyClaimed`, `SocialService.LikeGiven(quem, dono)`, `SocialService.HeadlinerChanged(ativo)`.
- **Recompensas:** tudo passa por `RewardService.Grant` (IncomeMinutes = minutos do Hype/s passivo atual com mínimo de 5 batidas/s; Discs; Crates = aberturas grátis da melhor crate; FillEnergy).
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
- Fases 9–11: valores por aprovar (setas, prémios do Índice, fones, SorteMax/K). Incluir na simulação o Hype das setas com diferentes precisões, a Sorte ao longo de uma run e o tempo esperado para completar cada raridade do Índice.

# SETUP NO STUDIO
- `rojo serve` + plugin; o Rojo gere `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`. **`ServerStorage` não é gerido pelo Rojo** (modelos do Blender ficam no place).
- Game Settings: Max Players = 6; Security → Enable Studio Access to API Services (senão os dados ficam em memória).
- Workspace: `StreamingEnabled = false`.
- Exportar placeholders para `ServerStorage/Assets` (modo Edit, Command Bar): `require(game.ServerScriptService.Server.World.Placeholders).ExportAll()` e gravar o place.

# COMANDOS DE DEBUG (`/fe <comando>`, admins / Studio)
`help` · `hype add|set <v>` · `pps <v>|off` · `offline <s>` · `cost …` · `equip list|<id> <nível>` · `energy <n>` · `drop` · `pyro all` · `cd reset` · `stage <1-12> [anim]` · `wt <n>` · `artist give <id> <raridade> [estrelas] [qtd]|clear` · `pity` · `tour [force]` · `discs <n>` · `skills reset` · `plots` · `home` · `state` · `save` · `wipe confirm`
(A acrescentar nas Fases 9–11: ver "Integração com a arquitetura".)
`help` · `hype add|set <v>` · `pps <v>|off` · `offline <s>` · `cost …` · `equip list|<id> <nível>` · `energy <n>` · `drop` · `pyro all` · `cd reset` · `stage <1-12> [anim]` · `wt <n>` · `artist give <id> <raridade> [estrelas] [qtd]|clear` · `pity` · `tour [force]` · `discs <n>` · `skills reset` · `daily reset|skip|break` · `missions complete|reroll` · `product <key>` · `gamepass <key> on|off` · `social` · `friends <n>|off` · `likes <n>|reset` · `headliner start|stop` · `visit <1-6>` · `plots` · `home` · `state` · `save` · `wipe confirm`

# PENDENTE / PRÓXIMOS PASSOS CONHECIDOS
- IDs de áudio em `Config/Audio` (a 0 → efeitos pulsam pelo relógio de 128 BPM).
- Gamepass "Palco VIP": definir `Config/Artists.VipGamepassId`.
- Modelos finais do Blender para palcos, praça, placa, decoração, arco, artistas, pedestal da vitrine e fones.
- IDs reais no site do Roblox: Gamepasses e Developer Products (`Config/Monetization`; o Palco VIP usa `Config/Artists.VipGamepassId`) e Badges (`Config/Badges`). Com id 0 aparecem como "Em breve".
- Modelos finais do Blender para palcos, praça, placa, decoração, arco e artistas.
- `Config/Social.Group.GroupId` (0 = bónus de grupo desligado) e IDs de música por era em `Config/Audio.EraMusic`.
- `Settings.LowVfx` ainda não chega ao cliente (já existe `PyroVfxController.SetLowVfx`).
- Recalibrar Fama e custos dos Tiers 9–12 com uma simulação que inclua artistas e árvore (só Fama = fim de jogo lento; com Amplificação = mais rápido que a tabela).
- Antes de publicar: `Config/Debug.NetTrace = false`.
- Verificação estática: não há analisador Luau instalado; considerar `luau-lsp` no `aftman.toml`.
