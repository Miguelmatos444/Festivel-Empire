# Modelos 3D — Festival Empire

Feitos no Blender segundo `docs/Medidas_Modelos_3D_Festival_Empire.pdf`.
1 unidade do Blender = 1 stud. Ficheiro de trabalho: `Blender/FestivalEmpire_Models.blend`.

## Pastas
| Pasta | Conteúdo | Destino no Studio |
|---|---|---|
| `FBX/Stages` | `Tier_01.fbx` … `Tier_12.fbx` | `ServerStorage/Assets/Stages` |
| `FBX/World` | `Plaza.fbx`, `PlotSign.fbx` | `ServerStorage/Assets` |
| `FBX/Pyro` | `ColdSparks`, `CO2Cannon`, `Lasers`, `Flamethrower` (nomes = ids de `Config/Pyro`) | a combinar |
| `FBX/Equipment` | colunas T1–T4, DJBooth, VinylCrate | a combinar |
| `FBX/Garage`, `Beach`, `Arena`, `Festival`, `Orbital` | decoração | a combinar |

## Cada FBX
- Uma malha por material (`Body`, `Dark`, `Wood`…), mais `Neon_<Cor>`, `LEDScreen` e `Holo` separados. Máximo 4 804 triângulos por malha.
- Palcos, praça e placa têm uma peça `Root` (invisível) com o tamanho da caixa; a placa tem a peça `Board`.
- Origem: palcos na frente-centro-chão; praça no centro; placa na base; adereços na base, ao centro.
- Nada fica por cima dos pontos de pirotecnia (verificado por script nos 12 palcos).

## Importar
1. Studio → Import 3D → escolher o FBX. Confirmar que o tamanho bate com a tabela do PDF (ex.: Tier_03 = 36 × 16 × 20).
2. Pôr o modelo na pasta de destino com o nome do ficheiro.
3. Se a frente não estiver virada para -Z (o público), rodar 180°.
4. Correr `Models/StudioSetup.luau` no Command Bar: esconde o Root, ancora, aplica Neon e cria os Attachments.
