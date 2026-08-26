# Mapa Grande

Esta pasta concentra o código do mapa e evita que manutenção de localização
altere estoque, autenticação, Firebase ou o botão **Sair**.

## Arquitetura ativa e responsabilidades

- `big_map_canvas.gd`: desenho e interação visual; não acessa rede.
- `big_map_tracking_view.gd`: composição visual autocontida e testável.
- `big_map_tracking_layout.gd`: apesar do sufixo histórico `layout`, é o
  **controller ativo** da cena principal. Liga a view às integrações
  autenticadas herdadas do dashboard, aplica filtros,
  coordena seleção e solicita tiles/ERBs. Construção visual nova deve ficar na
  view, não neste arquivo.
- `big_map_config.gd`: cidade inicial, zoom, regiões e provedor de tiles.
- `map_projection.gd`: matemática geográfica Web Mercator e distâncias.
- `map_tile_provider.gd`: URL, chave de cache, atribuição e decodificação dos
  tiles OpenStreetMap.
- `map_region_service.gd`: identificação e contagem de regiões/ERBs.
- `vehicle_status_resolver.gd`: estado Ligado, Desligado ou Desatualizado.

## Fluxo de manutenção

1. A pesquisa normaliza placa/série, exige correspondência exata e só então a
   integração autorizada devolve a localização do veículo.
2. `vehicle_status_resolver.gd` classifica a comunicação.
3. O índice nacional particionado derivado da base oficial SMP da Anatel
   fornece ERBs licenciadas 2G/3G/4G/5G sem inferir campos ausentes.
4. `map_tile_provider.gd` fornece exclusivamente o mapa-base OpenStreetMap.
5. `big_map_canvas.gd` apenas desenha as camadas recebidas.

## Fonte exclusiva de veículos

No Mapa Grande, placa, série, cliente explícito (`cliente:`), coordenadas,
status e última comunicação vêm exclusivamente da API Grupo RS. A consulta
permanece pendente fora da fila; somente uma resposta exata confirmada pela
API cria uma entrada. Resposta vazia, erro, timeout ou identidade divergente
não cria veículo e nunca seleciona a primeira linha como fallback.

O controller não consulta Store, fixtures, portal web, cache local de posição,
Arya ou Linksolutions para completar veículos. Campo ausente na API é exibido
como N/D. Uma posição ausente ou inválida não reutiliza coordenada anterior.
O endpoint de registros recentes pode recuperar a última posição porque faz
parte da mesma API Grupo RS; essa origem continua marcada como `API Grupo RS`.
Fixtures e dados sintéticos existem somente em `tests/`.

Atualizações comuns trocam somente o estado dos veículos. A cena, o canvas,
os filtros, os tiles e a camada Anatel permanecem montados. Em pan/zoom, a
grade nova reaproveita texturas já visíveis e o cache LRU de bytes/texturas;
somente chaves OSM ausentes são solicitadas na rede. A câmera desejada é
atualizada no mesmo gesto, enquanto a grade anterior continua desenhada e é
transformada como fallback até a nova cobertura ficar completa. Uma janela
curta de debounce coalesce somente o IO; ela não bloqueia o preview.

PNG/JPEG é decodificado como `Image` no `WorkerThreadPool`; apenas a criação de
`ImageTexture` ocorre na thread principal. Requisições HTTP de gerações antigas
são canceladas e resultados obsoletos não alteram o viewport. Projeções e
grupos de ERBs são memorizados por revisão de dados/viewport/zoom, aplicando o
`drag_offset` sem reprojetar a camada a cada movimento do mouse. O índice
nacional usa política latest-only: uma consulta em voo e uma pendente
substituível, sempre consumindo a task antes de iniciar a próxima.

Uma mudança em um desses passos deve permanecer no script responsável. Na rota
ativa, o controller do Mapa Grande coordena o fluxo usando contratos herdados;
o dashboard não deve voltar a concentrar regras novas do mapa.

## Dependência herdada e rotas substituídas

A cena `estoque_profissional.tscn` instancia `big_map_tracking_layout.gd`, que
herda `inventory_dashboard.gd`. A independência ainda não é completa. O
controller novo usa como contrato herdado:

- consulta autenticada e normalização inicial de localização;
- estado pendente/fila confirmada de placas/séries e timers existentes;
- cache HTTP e carregador assíncrono de tiles;
- instância de `AnatelCoverage` e estado de mapa já existentes;
- helpers visuais comuns e navegação da aplicação.

Ele substitui, para a rota “Mapa Grande”, a montagem antiga da tela, os filtros
de monitoramento, a seleção, os detalhes e a atualização do canvas. A rota
legada permanece no dashboard por compatibilidade e não deve ser chamada pela
cena ativa. Uma futura extração para um controller sem herança é dívida técnica
deliberada; não faz parte desta correção para evitar regressão em Estoque,
autenticação e Sair.

`big_map_canvas.gd` continua concentrando renderização, entrada, declutter
visual de ERBs, agrupamento exclusivo de veículos,
animação e seleção. Ele não acessa rede nem API. Separar esses blocos é outra
dívida técnica segura para uma revisão posterior.

## Dados oficiais de ERBs

O runtime ativo lê primeiro
`res://data/anatel_smp_national_index/manifest.json`. O sidecar
`manifest.sha256` é obrigatório; o serviço também valida hash e tamanho de
cada partição antes da primeira leitura. O fluxo operacional está limitado a
z10–z18 e abre ERBs individuais nas células z10 visíveis/vizinhas. Os resumos
z4/z6/z8 não são expostos como torres ou bolhas: uma visão abaixo de z10 só
será liberada após gerar uma redução auditável composta por ERBs reais.
O cache LRU limita células, registros e bytes de JSON de origem. Atualizações
de veículos não reabrem partições nem remontam a camada oficial.

`res://data/anatel_smp_regional.json` permanece como fallback regional
declarado, ativado apenas se o manifesto nacional falhar. Ele nunca é exibido
como catálogo nacional. `anatel_smp_2g4g_regional.json` é legado de migração.

Detalhes da auditoria, campos e atualização estão em
[`docs/anatel_smp_data_source.md`](../../../docs/anatel_smp_data_source.md).
O formato, as contagens e os limites do índice nacional estão em
[`docs/anatel_smp_national_index.md`](../../../docs/anatel_smp_national_index.md).
Quando a fonte não informa um campo, a UI mostra “Não informado pela fonte”.
Presença/licenciamento de ERB não equivale a intensidade de sinal em tempo real.

## Agulhas de veículos

Os SVGs autorizados ficam em `assets/maps/agulha_localizacao_*.svg` e são usados
sem recoloração dinâmica: verde = ligado, vermelha = desligado e amarela =
desatualizado. Os arquivos `.import` do Godot permanecem junto aos assets. A
ponta inferior da agulha coincide com a coordenada recebida; o tamanho normal é
30×38 px e cresce para 38×48 px durante a seleção.

## Marcadores de ERB

Somente os quatro PNGs compactos de
`assets/maps/erb_markers_v3/production/compact` são usados no runtime: Claro,
TIM, Vivo e neutro/outras. O canvas escala cada torre entre 34×34 e 56×56 px,
aumenta a seleção em 8 px e mantém hit-area mínima de 28 px. Um halo e
monograma na cor da prestadora permanecem visíveis em todo zoom; o nome
completo aparece no zoom 16+ ou após seleção. As legendas geral e de tracking
identificam TIM, Claro, Vivo, Outras e N/D e deixam explícito que licenciamento
não representa intensidade de sinal.

ERBs continuam separadas das agulhas e nunca viram bolhas/contadores. Em
z10–z15, sobreposições são reduzidas deterministicamente por célula visual e
prestadora, escolhendo uma ERB real sem alterar identidade ou coordenadas; a
selecionada permanece visível. Em z16+, todas as ERBs da viewport são mantidas.
Os conjuntos
v1/v2/v2r1 são históricos e não são referenciados pelo canvas. As variantes
v3 `selected/` e a prancha `review/` são apenas candidatas/evidência visual;
devem permanecer fora do inventário de runtime antes de qualquer PCK.
