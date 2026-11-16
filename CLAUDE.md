# PAPEL E IDENTIDADE DO PROJETO
És um programador sénior de Roblox, especialista em Luau com `--!strict`, arquitetura cliente-servidor segura e jogos idle/incremental com gacha.
Projeto: **"Festival Empire Tycoon"** (PlaceId: `139556886062753`).
Escreves código completo e pronto a usar, sem pseudo-código nem `TODO` por preencher.
Nada relacionado com outros festivais reais ou nomes externos deve existir nos textos, configs ou código.
Toda a comunicação com o utilizador é em **português de Portugal**.

# VISÃO GERAL DO JOGO (SINGLE-MAP MULTIPLAYER)
- **Conceito:** Império de festivais de música e pirotecnia num **único mapa partilhado** (praça central + 6 terrenos/plots, máximo 6 jogadores por servidor). Não existem teleportes nem mapas separados.
- **Recursos:**
  - `Hype` (Decibéis): moeda principal ganha por cliques (batidas) e passivamente por equipamento de som, DJs e artistas.
  - `Discos de Platina`: moeda de Prestige (*World Tour*), gasta numa árvore de habilidades permanente.
- **Progressão de Palcos (12 Tiers / 4 Eras):**
  - *Underground (Tiers 1–3):* 1 Palco de paletes, 2 Palco de bairro, 3 Palco de praia.
  - *Ascensão (Tiers 4–6):* 4 Palco clube, 5 Palco médio LED, 6 Palco coberto tipo arena.
  - *Estrelato (Tiers 7–9):* 7 Palco principal (req: 1 World Tour), 8 Palco pirotécnico (req: 1 WT), 9 Mega palco (req: 2 WT).
  - *Lenda (Tiers 10–12):* 10 Palco holográfico (req: 3 WT), 11 Palco estratosférico (req: 4 WT), 12 Palco orbital (req: 5 WT).
  - A troca de palco ocorre no mesmo terreno com animação replicada para todos (maior nas trocas de era).
- **Mecânica Core (Bass Drop):** Barra de energia enche até ao Bass Drop. Ativar pirotecnia (faíscas frias, CO₂, lasers, lança-chamas) na janela certa dá multiplicadores de 5x a 50x + sinergias entre máquinas.
- **Gacha (Vinyl Crates):** Abertas nos tiers 1, 4, 7, 10 e especial no 12. **22 raridades** agrupadas em 5 famílias que mantêm os totais Comum 55% · Raro 28% · Épico 12% · Lendário 4.5% · Mítico+ 0.5%. A raridade é uma "versão" do artista da família na crate. Pity em escada: Lendário+ aos 50, Mítico+ aos 250, Divino+ aos 1000, Cósmico+ aos 5000. Slots de palco: 3 base até 7 (World Tours + Gamepass). Fusão: 3x mesmo artista/raridade/estrelas 1★ -> 2★ (Remix 2.5x); 3x 2★ -> 3★ (Platinum 6x) + Auto-Fuse/Auto-Delete.
- **Prestige (World Tour):** Dá Discos de Platina, faz reset a Hype, equipamento e tier do palco (volta ao Tier 1 — ou ao tier inicial da árvore — com animação de desmontagem), mas mantém artistas, árvore de habilidades, Discos por gastar, pirotecnia desbloqueada e contagem de World Tours. Cada World Tour dá Fama ×1.5 de Hype global.

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
4. **Servidor Autoritativo:** O servidor calcula toda a economia, RNG do gacha, pity, fusões, combos e timing do Bass Drop (`os.clock()` com tolerância de latência). Todos os Remotes passam por `RemoteDefs` + `Validate` + `RateLimiter`. O servidor valida sempre a posse do terreno e requisitos de tier.
5. **Cliente para Apresentação e LOD:** UI responsiva (mobile-friendly), tweens, áudio (`PlaybackLoudness`) e VFX locais. VFX pesados têm força total no terreno do próprio jogador e versão leve (LOD por distância) nos outros 5 terrenos. Música segue o festival do próprio jogador.
6. **Matemática Escalável:**
   - Custos: `BaseCost * (GrowthRate ^ Level)` com `GrowthRate` entre 1.07 e 1.15. Compra em massa (`x1`, `x10`, `x100`, `Max`) via soma geométrica (sem loops).
   - Números grandes via `BigNum` (mantissa + expoente) formatados com K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc e notação científica.
7. **Persistência & Performance:** DataStore com session locking (implementação própria), `DataVersion` + migrações, auto-save, `BindToClose` e cálculo de rendimento offline. Tick económico do servidor a 1 Hz (proibido loops pesados por frame no servidor). Usar `Trove` para limpar todas as ligações.

# FLUXO DE TRABALHO OBRIGATÓRIO
- Trabalha **uma fase de cada vez**. Nunca avances sem o meu "OK".
- Antes de escreveres código numa fase que envolva mapa, palcos ou balanceamento, apresenta a proposta/tabela final para aprovação.
- Entrega sempre na ordem: **1) Config/Tipos → 2) Servidor → 3) Cliente → 4) Instâncias/Setup no Studio**.
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
| 9+10 Monetização/Retenção | 4 Gamepasses (Palco VIP, Auto-Batida no servidor, Hype ×2, Agente de Tour), 5 Developer Products (ProcessReceipt idempotente), "Bem-vindo de volta", leaderboards globais na praça, diário 7 dias (20 h / 48 h), 3 missões diárias + 2 semanais por sinais, códigos com expiração/limite global, 10 Badges | `Config/Monetization`, `Config/Retention`, `Config/Codes`, `Config/Badges`, `Config/Leaderboards`, `RetentionCalc`, `RewardService`, `MonetizationService`, `RetentionService`, `AchievementService`, `LeaderboardService`, `MissionsView`, `VipPage`, `WelcomeBackView` |

# ARQUITETURA E CONVENÇÕES (respeitar ao continuar)
- **Bootstrap:** `Main.server.luau` e `Main.client.luau` correm cada `Init()`/`Start()`/`Mount()` isolado com `xpcall` (um módulo com erro não desliga os outros e aparece no Output com traceback). No servidor o núcleo (rede, dados, economia, estado) inicializa antes do mundo (mapa/terrenos/palcos).
- **Rede:** todos os remotes declarados em `RemoteDefs` (com `RateLimit` e `Args` validados). `ServerNet.Init()` cria os remotes **sem os expor**; `ServerNet.Open()` corre depois de todos os `Init()` e só então os põe em `ReplicatedStorage.Remotes`. Pedidos sem handler ficam em fila. O cliente usa `NetController.Fire/On`.
- **Replicação de estado:** `PlayerStateService` envia snapshot quando há perfil carregado **e** `ClientReady` (qualquer ordem) e depois deltas a 5 Hz só com campos alterados. O cliente repete `ClientReady` até receber o snapshot. Coleção de artistas sincronizada à parte (`ArtistsSync`), estado do drop em `DropState`.
- **Cálculos partilhados:** tudo o que a UI mostra e o servidor cobra vem de `shared/Calc/*` (preços, multiplicadores, Discos, pity, estados de bloqueio) — o cliente nunca calcula regras próprias.
- **Ordem dos multiplicadores de Hype:** equipamento × palco (1.6^(tier−1)) × Fama (1.5^WT) × Amplificação × artistas (com Aura do Público) × boost do Bass Drop; batidas ainda × Batida Forte × Batida de Ouro. Taxas em cache por jogador (`EconomyService.InvalidateRates` sempre que algo muda).
- **Limites somados (artistas + árvore):** janela +0.15 s, cooldowns −50%, boost +8 s, energia +100%. Multiplicador do drop sempre 5x–50x.
- **Transições de palco:** o servidor troca o modelo e grava atributos `Transition*` no Plot (`Start` em `GetServerTimeNow`, `From`, `To`, `Era`, `Kind`, `WorldTour`, `Id`); cada cliente anima localmente (`StageAnimController`). Tipos: `"Stage"` e `"Prestige"`.
- **Modelos substituíveis (Blender):** contrato `Model` com `Root` (Part invisível, PrimaryPart, com os Attachments) + `Visual` (geometria). Overrides em `ServerStorage/Assets/…` (`Stages/Tier_XX`, `Plaza`, `PlotSign` com parte `Board`, `Decor/<Era>`, `Prestige/Arch` com parte `Beam`, `Artists/<ArtistId>`). Sem override usa `World/Placeholders`. Medidas para modelação em `docs/Medidas_Modelos_3D_Festival_Empire.pdf`.
- **Pirotecnia/efeitos:** resolver de emissores aponta para os Attachments `Pyro_<Máquina>_<n>` do palco do dono (fallback à volta da personagem). Distâncias de LOD só em `Config/Lod`.
- **UI:** botões laterais no `SideMenu` (112×88; ordem: 1 Voltar, 2 Loja, 3 Palcos, 4 Artistas, 5 World Tour, 6 Missões); painéis centrais registam-se no `ModalManager` (só um aberto). Teclas: B loja, P palcos, K artistas, T World Tour, M missões, F drop, V loja VIP. Botão dourado "★ VIP" no canto superior direito (`VipButtonView`) abre a loja no separador VIP.
- **Sinais de jogo** (para missões/conquistas, nunca progresso vindo do cliente): `EconomyService.Clicked(player, n)`, `BassDropService.DropSucceeded(player, grade)`, `EquipmentService.Purchased`, `GachaService.CratesOpened`, `ArtistService.Fused`, `StageService.StageChanged/StagePlaced`, `PrestigeService.WorldTourCompleted`, `RetentionService.DailyClaimed`.
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

# SETUP NO STUDIO
- `rojo serve` + plugin; o Rojo gere `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`. **`ServerStorage` não é gerido pelo Rojo** (modelos do Blender ficam no place).
- Game Settings: Max Players = 6; Security → Enable Studio Access to API Services (senão os dados ficam em memória).
- Workspace: `StreamingEnabled = false`.
- Exportar placeholders para `ServerStorage/Assets` (modo Edit, Command Bar): `require(game.ServerScriptService.Server.World.Placeholders).ExportAll()` e gravar o place.

# COMANDOS DE DEBUG (`/fe <comando>`, admins / Studio)
`help` · `hype add|set <v>` · `pps <v>|off` · `offline <s>` · `cost …` · `equip list|<id> <nível>` · `energy <n>` · `drop` · `pyro all` · `cd reset` · `stage <1-12> [anim]` · `wt <n>` · `artist give <id> <raridade> [estrelas] [qtd]|clear` · `pity` · `tour [force]` · `discs <n>` · `skills reset` · `daily reset|skip|break` · `missions complete|reroll` · `product <key>` · `gamepass <key> on|off` · `plots` · `home` · `state` · `save` · `wipe confirm`

# PENDENTE / PRÓXIMOS PASSOS CONHECIDOS
- IDs de áudio em `Config/Audio` (a 0 → efeitos pulsam pelo relógio de 128 BPM).
- IDs reais no site do Roblox: Gamepasses e Developer Products (`Config/Monetization`; o Palco VIP usa `Config/Artists.VipGamepassId`) e Badges (`Config/Badges`). Com id 0 aparecem como "Em breve".
- Modelos finais do Blender para palcos, praça, placa, decoração, arco e artistas.
- `Settings.LowVfx` ainda não chega ao cliente (já existe `PyroVfxController.SetLowVfx`).
- Recalibrar Fama e custos dos Tiers 9–12 com uma simulação que inclua artistas e árvore (só Fama = fim de jogo lento; com Amplificação = mais rápido que a tabela).
- Antes de publicar: `Config/Debug.NetTrace = false`.
- Verificação estática: não há analisador Luau instalado; considerar `luau-lsp` no `aftman.toml`.
