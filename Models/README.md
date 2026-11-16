# Modelos 3D — Festival Empire

Feitos no Blender segundo `docs/Medidas_Modelos_3D_Festival_Empire.pdf`.
1 unidade do Blender = 1 stud. Ficheiro de trabalho: `Blender/FestivalEmpire_Models.blend`.

## Pastas
| Pasta | Conteúdo | Destino no Studio |
|---|---|---|
| `FBX/Stages` | `Tier_01.fbx` … `Tier_12.fbx` | `ServerStorage/Assets/Stages` |
| `FBX/World` | `Plaza.fbx`, `PlotSign.fbx` | `ServerStorage/Assets` |
| `FBX/Pyro` | `ColdSparks`, `CO2Cannon`, `Lasers`, `Flamethrower` (nomes = ids de `Config/Pyro`) | `ServerStorage/Assets/Props` (aparecem no palco quando a máquina é desbloqueada) |
| `FBX/Equipment` | colunas T1–T4, DJBooth, VinylCrate | `ServerStorage/Assets/Props` (colunas da era ao lado do palco, mesa de DJ, crates nos postos da praça) |
| `FBX/Festival` | `Festival_FoodTruck`, `Festival_EntranceArch`, `Festival_FerrisWheel` | `ServerStorage/Assets/Props` (praça; substituem as roulottes/arcos placeholder) |
| `FBX/Decor` | `Underground`, `Ascensão`, `Estrelato`, `Lenda` (só alas laterais e margens do público) | `ServerStorage/Assets/Decor` |
| `FBX/Prestige` | `Arch.fbx` (30 × 17 × 2, com `Beam`) | `ServerStorage/Assets/Prestige` |
| `FBX/Artists` | 25 artistas, um ficheiro por `ArtistId`, estilo boneco Roblox, com `HumanoidRootPart` | `ServerStorage/Assets/Artists` |
| `FBX/RarityKits` | 19 kits (Rare → Omega): fones, coroas, auréolas, asas com peças animáveis | `ServerStorage/Assets/RarityKits` (já ligado no código: `Config/RarityCosmetics`) |
| `FBX/Artists_Proposta` | 10 artistas novos (proposta, à espera de Config) | — |
| `FBX/Garage`, `Beach`, `Arena`, `Orbital` | adereços soltos (já usados dentro da `Decor`) | opcional |

Os adereços em `Props` são escalados pelo código (`Config/Dressing`), por isso a escala do FBX não importa;
basta o nome do modelo ser igual ao do ficheiro e a frente estar virada para -Z.

## Cada FBX
- Uma malha por material (`Body`, `Dark`, `Wood`…), mais `Neon_<Cor>`, `LEDScreen` e `Holo` separados. Máximo 4 804 triângulos por malha.
- Palcos, praça e placa têm uma peça `Root` (invisível) com o tamanho da caixa; a placa tem a peça `Board`.
- Origem: palcos na frente-centro-chão; praça no centro; placa na base; adereços na base, ao centro.
- Nada fica por cima dos pontos de pirotecnia (verificado por script nos 12 palcos).

## Importar
1. Studio (modo Edit, `rojo serve` ligado) → Import 3D → escolher **vários FBX de uma vez** (ficam no Workspace com o nome do ficheiro). Confirmar que o tamanho bate com a tabela do PDF (ex.: Tier_03 = 36 × 16 × 20).
2. Se a frente não estiver virada para -Z (o público), rodar 180°.
3. Correr `Models/SortImports.luau` no Command Bar: move cada modelo para a pasta certa de `ServerStorage/Assets` (os placeholders com o mesmo nome vão para `ServerStorage/Assets_Antigos`, nada é apagado).
4. Correr `Models/StudioSetup.luau` no Command Bar: esconde Root/HumanoidRootPart, ancora, aplica Neon/Holo, cria os Attachments dos palcos e da praça (CrateStation, Leaderboard).
5. Gravar o place.
