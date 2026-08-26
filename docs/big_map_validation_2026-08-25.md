# Validação do Mapa Grande — 2026-08-25

## Status

Conjunto em novo congelamento técnico para a bateria de performance. As
execuções registradas antes do gate de pan/zoom são evidência histórica e não
aprovam a correção atual. O release permanece **NÃO APROVADO**, inclusive pelo
bloqueio de segurança da API de negócio descrito em
`security_block_openapi_active_example_2026-08-25.md`.

Não foram executados login, `/auth/me`, pesquisa autenticada, paginação de veículos, equipamentos, Arya/Linksolutions, PCK, commit, tag, push ou publicação.

## Escopo validado

- início em Imperatriz com OpenStreetMap como única base;
- zoom e arraste sem opção ou dependência visual de satélite/Esri;
- busca sintética exata por placa formatada/compacta e por número de série;
- colisão placa/série tratada como ambígua, sem escolher o primeiro veículo;
- estados `loading`, `found`, `not_found` e `error` conectados à interface;
- foco da seleção no canvas/lista com zoom mínimo e preservação quando possível;
- coordenadas `0,0` rejeitadas, coordenada individual igual a zero aceita e limites geográficos verificados;
- filtros oficiais de ERB por prestadora, tecnologia, município e situação;
- clusters nacionais em zoom distante, clusters regionais em zoom intermediário e ERBs individuais em zoom próximo;
- consulta apenas das células visíveis e vizinhas, troca de viewport e recuperação após evicção;
- atualização de veículos separada do índice e dos tiles de ERB;
- atualização comum preserva cena, câmera, filtros, tiles, ERBs e seleção;
- pan/zoom solicita somente chaves OSM ausentes e reutiliza bytes/texturas;
- marcadores de veículo verde, vermelho e amarelo e marcadores de ERB separados;
- estados sem dados, sem posição e erro de fonte sem criar pontos fictícios;
- Estoque, navegação e Sair em fixture offline que bloqueia HTTP, API, SGA e Firebase.

## Fonte e índice Anatel

- fonte oficial: `https://www.anatel.gov.br/dadosabertos/paineis_de_dados/outorga_e_licenciamento/estacoes_smp.zip`;
- data oficial da fonte (Last-Modified): `Tue, 25 Aug 2026 10:56:40 GMT`;
- ZIP: 91.381.047 bytes;
- SHA-256 do ZIP: `976C4BB3ABFC8F777D54D595DF1D944E12550FE653CB67EFB649ECABF8903051`;
- 3.292.893 linhas lidas e 3.285.081 linhas selecionadas;
- 291.348 registros estação/geração e 115.018 ERBs físicas;
- 27 UFs e tecnologias 2G, 3G, 4G e 5G;
- 3.366 células z10 e três arquivos agregados z4/z6/z8;
- 3.369/3.369 arquivos conferidos por hash e tamanho, sem falhas;
- índice: 153.414.196 bytes; diretório completo: 155.907.528 bytes;
- maior célula: 6.704.209 bytes e 12.591 registros;
- SHA-256 do manifesto: `46023754CAB593816D7B1FB2724B4D080D3535ED0A9E7A6F05E6D9D5986B3FBA`;
- SHA-256 agregado do conteúdo: `683B0101CBF2A95A05EB9C7FF8BF90DFACF33040F272209DDE70E9BCD3E655B9`;
- pico medido do gerador: 113.954.816 bytes.

O catálogo regional permanece apenas como fallback explícito. Presença/licenciamento de ERB não representa intensidade de sinal em tempo real.

## Testes executados

### Godot offline

Análise/parse/import: **OK**. Único aviso observado: um `project.godot` aninhado preexistente em backup foi ignorado.

Matriz histórica anterior ao gate atual: **10/10 OK na rodada anterior**. A nova execução completa permanece pendente e somente ela poderá validar o conjunto de performance atual.

1. `anatel_national_index_test.gd`;
2. `anatel_catalog_test.gd` (compatibilidade do fallback regional);
3. `big_map_module_test.gd`;
4. `big_map_tracking_view_test.gd`;
5. `vehicle_location_search_test.gd`;
6. `vehicle_location_integration_test.gd`;
7. `big_map_tracking_controller_test.gd`;
8. `big_map_incremental_tile_test.gd`;
9. `main_scene_smoke_test.gd`;
10. `main_scene_stock_exit_smoke_test.gd` com fixture offline.

O teste nacional carregou a maior célula em 2.609 ms, com delta/pico medido de 86.473.148 bytes. A consulta final manteve duas células, 2.327 registros e 1.212.343 bytes de JSON de origem no cache. Limites LRU, troca de viewport, descarte e recuperação passaram.

Evidência histórica anterior ao novo gate: o teste incremental percorreu carga inicial, viewport idêntico, pan,
retorno e zoom. Resultado: 18 solicitações sintéticas totais, 22 hits e 18
entradas. O viewport idêntico e o retorno fizeram zero downloads/decodes novos;
o pan solicitou somente os blocos sem cache. A atualização comum do controller
manteve `map_view_revision` e o contador de reload inalterados.

### Python offline

Matriz Python histórica: **7/7 OK em 15,953 s**; deve ser repetida após o novo
congelamento antes de qualquer aprovação.

- inserção/UPSERT e partição sintética do gerador;
- integridade dos 3.369 arquivos nacionais;
- manifesto, proveniência, contagens e limites geográficos;
- ausência de diretórios `backup-*` e `building-*`;
- hashes, RGBA 256x256 e sidecars `.import` dos quatro marcadores compactos v3;
- exclusões de exportação para v1/v2/v2r1, v3 selected/review,
  debug/teste/temporários,
  `__pycache__` e `.pyc`.

### Rede pública de tiles

- OpenStreetMap: HTTP 200, 4.298 bytes, textura decodificada;
- nenhum endpoint Esri/satélite faz parte da configuração ou dos testes finais.

Esses testes não acessam a API de negócio.

### Renderização e janela real — evidência histórica

- `map_visual_test.gd`: **OK**, OpenStreetMap, 56/56 tiles, 365 ERBs oficiais no recorte, proveniência válida e agulha verde posicionada;
- evidência histórica anterior ao gate: o rebuild antigo continha cinco veículos sintéticos e não representa mais o estado inicial;
- rebuild atual: **OK**, OpenStreetMap, 42/42 tiles, zero veículos, 365 ERBs oficiais no recorte, proveniência válida e navegação sem carga pendente;
- repetição do mesmo viewport no rebuild: 42 hits, zero download novo e zero alteração da camada de veículos/ERBs;
- inspeção atual dos assets compactos v3 confirmou transparência e sidecars; o
  canvas usa 34/40/48/56 px por zoom, seleção +8 px e hit-area mínima de 28 px;
- a janela isolada histórica foi encerrada; a verificação pré-bateria registra
  `ZERO_PROCESSOS_GODOT`;
- capturas antigas com veículos sintéticos e bolhas foram invalidadas; novas
  capturas z10/z13/z16 permanecem pendentes e não podem ser usadas como aprovação;
- nenhuma janela permanece aberta. Uma nova execução isolada, autoencerrável e
  com renderer real ainda deve validar pan/zoom, seleção e filtros.

## Separação Mapa Grande versus Estoque

As alterações de `inventory_dashboard.gd` estão restritas a compatibilidade de localização/API/tile e validação geográfica; não há hunk visual de Estoque. A cena principal passou a usar o controller do Mapa Grande. O smoke de Estoque/Sair usa subclasse offline e afirma zero chamadas externas.

`big_map_tracking_layout.gd` é o controller ativo, apesar do nome histórico, e herda o `inventory_dashboard.gd` monolítico. Essa herança é um contrato de compatibilidade e uma dívida técnica; não representa independência completa do dashboard legado.

## Inventário funcional principal

Estado Git no congelamento: 20 arquivos rastreados modificados e 3.470
arquivos não rastreados (34 grupos no `git status`), incluindo os 3.369
arquivos do índice nacional, scripts/testes novos, documentação, assets e
sidecars do Godot. Nenhum desses arquivos foi commitado.

- controller/view/canvas: `src/features/big_map/big_map_tracking_layout.gd`, `big_map_tracking_view.gd`, `big_map_canvas.gd`;
- índice nacional: `src/features/big_map/anatel_national_index.gd` e `data/anatel_smp_national_index/`;
- busca e normalização: `src/features/location/vehicle_location_integration.gd`;
- configuração/tiles/status: `big_map_config.gd`, `map_tile_provider.gd`, `vehicle_status_resolver.gd`;
- assets de veículos: `assets/maps/agulha_localizacao_{verde,vermelha,amarela}.svg`;
- assets de ERB em produção: `assets/maps/erb_markers_v3/production/compact/`;
- gerador: `tools/build_anatel_national_index.py`;
- documentação: `docs/anatel_smp_audit_2026-08-25.json`, `anatel_smp_data_source.md`, `anatel_smp_national_index.md` e este relatório;
- testes: scripts Godot, fixtures offline e testes Python em `tests/`.

Somente os quatro PNGs compactos de
`assets/maps/erb_markers_v3/production/compact/` são referenciados pelo runtime.
As famílias v1/v2/v2r1, variantes v3 selected/review, diretórios `_debug`,
caches `__pycache__` e arquivos `.pyc` estão explicitamente excluídos do preset.
Nenhum PCK foi gerado e nenhum artefato histórico foi apagado.

## Bloqueio remanescente

**PROBLEMA ENCONTRADO**

- Arquivo/Origem: documentação OpenAPI pública da API;
- Problema: exemplo de login contém credencial ativa e permite emissão de JWT;
- Impacto: acesso indevido ao escopo real de veículos/localizações;
- Ação recomendada: rotação/desativação, auditoria de logs/tokens, exemplo inerte e revisão de acesso.

Após o aceite administrativo, a validação conectada deverá ser repetida com credencial legítima fornecida por canal seguro. Até lá, a entrega técnica pode ser revisada, mas não promovida a release estável.
## Gate de performance de pan/zoom

O caminho de navegação foi limitado a correções mensuráveis, sem alterar API ou
dados Anatel: câmera desejada acumulativa, debounce somente do IO, HTTP
cancelável por geração, fallback da grade anterior até cobertura completa,
decode de `Image` em `WorkerThreadPool`, cache de projeções/grupos de ERBs,
redraw progressivo coalescido e índice nacional latest-only (uma consulta em
voo + uma pendente substituível).

Os testes focados são:

- `tests/big_map_incremental_tile_test.gd`: cache/reuso, LRU, falha parcial,
  fallback, cancelamento HTTP, ausência de textura órfã e um flush por frame;
- `tests/big_map_tracking_controller_test.gd`: rajada de 11 pedidos nacionais,
  no máximo duas consultas efetivas e somente a última viewport aplicada;
- `tests/big_map_pan_zoom_performance_test.gd`: gesto→IO integrado nos cenários
  distante/médio/próximo, três zooms rápidos no cenário próximo, dois pans por
  cenário, uma rodada efetiva de downloads e métricas de frame p50/p95/max,
  first-paint, carga, decode, memória, source bytes, cache, evicção e cancelamento.

Este bloco não autoriza PCK, commit, tag, push ou API autenticada. Os resultados
numéricos devem ser coletados somente após `ZERO_PROCESSOS_GODOT` e congelamento
da escrita.

Resultados atuais após declutter sem clusters de ERB:

- headless z10→11: p95 7,066 ms; máximo 13,068 ms;
- headless z12→13: p95 7,237 ms; máximo 11,057 ms;
- headless z13→16: p95 6,980 ms; máximo 8,800 ms;
- renderer real z10→11: p95 17,772 ms; máximo 18,637 ms;
- renderer real z12→13: p95 19,176 ms; máximo 26,663 ms;
- renderer real z13→16: p95 17,412 ms; máximo 18,037 ms;
- todas as execuções: zero download extra da viewport obsoleta, vencedor com
  15 tiles, cache/fallback/latest-only preservados;
- rebuild atual: 42/42 tiles, repetição com zero downloads e 42 reusos, zero
  veículos e 365 ERBs oficiais na fonte.

### Gate visual autoencerrável

Capturas com renderer OpenGL real foram geradas sequencialmente em
`tmp/big_map_visual_gate/`, diretório excluído do export, nos zooms z10, z13 e
z16 e nas resoluções 1366×768 e 1920×1080. Cada processo encerrou antes do
seguinte. A inspeção confirmou métricas zero, ausência de pins de veículos,
OpenStreetMap/Imperatriz, ERBs v3 individuais sem bolhas/contadores, legenda
TIM/Claro/Vivo/Outras/N/D, ressalva de licenciamento e atribuição OSM. A linha
de sobreposição da legenda foi explicitada como exclusiva de veículos.

As rotinas históricas `_draw_index_station_cluster`, `_draw_station_cluster` e
detalhes de cluster permanecem como código morto, sem chamadas no fluxo final;
sua remoção fica registrada como dívida de manutenção separada.

O gate visual residual reforçou o declutter de z10–z15 com distância mínima
entre ERBs reais e manteve desenho/hit-test no mesmo conjunto. Em z16, labels
tentam posições acima/abaixo/laterais dentro de safe rect; labels não
selecionados que colidiriam são omitidos, e marcadores não selecionados que não
cabem inteiros são ocultados até o pan. As seis capturas foram regeneradas.

O teste conectado com placa/série real permanece **BLOQUEADO**: a conta ativa
exposta na documentação pública ainda não teve rotação/desativação confirmada,
e não foi fornecida credencial legítima por canal seguro. Nenhum login, portal
autenticado ou API de negócio foi acessado. Após correção administrativa e
aceite do administrador, o teste deve validar identidade exata, posição e
horário sem registrar dados sensíveis, além de consulta inexistente sem
fallback para o primeiro veículo.
