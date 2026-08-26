# Índice de funções do Mapa Grande

Este índice permite localizar rapidamente a responsabilidade que precisa ser
alterada. Funções internas começam com `_`; as demais formam a API do canvas.

## `big_map_canvas.gd`

### Ciclo de vida e dados

- `_init`: configura tamanho, mouse e processamento inicial.
- `_process`: atualiza animações e estado visual de carregamento.
- `set_devices`: recebe o recorte de aparelhos do monitor.
- `set_tracking_locations`: troca os veículos e prepara animação de movimento.
- `_tracking_location_key`: cria a identidade estável do veículo.
- `_tracking_target_geo`: extrai latitude e longitude do resultado.
- `_tracking_display_geo`: calcula a posição intermediária animada.
- `_tracking_animation_in_progress`: informa se ainda existe movimento.
- `_tracking_map_position`: converte a posição animada em ponto de tela.
- `set_tracking_mode`: alterna o comportamento de seleção de veículo/ERB.
- `current_map_view`: devolve centro e zoom atuais sem resetar a câmera.
- `set_basemap`: preserva o contrato público e fixa OpenStreetMap sem reload.
- `set_coverage_profile`: recebe ERBs e metadados de cobertura.
- `select_station_by_id`: seleciona uma ERB pelo identificador.
- `select_tracking_by_key`: seleciona um veículo por série ou placa.
- `clear_tracking_selection`: remove a seleção do veículo ao escolher uma ERB.
- `set_city_label`: atualiza o nome da área exibida.
- `set_station_visibility`: liga ou desliga somente a camada de ERBs.

### Tiles e carregamento

- `set_map_texture`: aplica uma imagem de mapa completa, por compatibilidade.
- `set_map_view`: aplica a grade e reutiliza texturas das chaves já visíveis.
- `set_map_tile`: insere um tile recebido de forma assíncrona.
- `finish_map_tile_load`: encerra o carregamento da grade atual.
- `set_map_tile_progress`: atualiza contagem e texto de progresso.
- `begin_map_load`: cria uma geração para rejeitar respostas antigas.
- `set_loading_stage`: troca apenas o estado visual de carregamento.
- `is_load_current`: valida se uma resposta pertence à geração ativa.
- `set_map_error`: exibe erro quando não há mapa utilizável.
- `cancel_navigation_load`: cancela uma navegação sem desmontar o mapa anterior.
- `_request_progressive_redraw`/`_flush_progressive_redraw`: coalescem callbacks
  de tile/progresso em um único redraw por frame.
- `_draw_fallback_tile_layer`: mantém a grade anterior transformada atrás da
  nova enquanto houver tiles faltantes.
- `_reset_navigation_target`, `_ensure_navigation_target`,
  `_display_map_zoom`, `_display_map_top_left` e
  `_commit_navigation_preview_change`: separam a câmera desejada da grade já
  carregada para acumular zoom/pan sem bloquear a interação.
- `_invalidate_station_visual_cache`: invalida projeções/grupos somente quando
  dados ou viewport realmente mudam.

### Interação e seleção

- `_gui_input`: trata clique, arraste, roda do mouse e controles do mapa.
- `_nearest_station_index`: encontra a ERB clicada.
- `_nearest_tracking_index`: encontra o veículo ou agrupamento clicado.
- `_tracking_visual_groups`: agrupa veículos visualmente sobrepostos.
- `_screen_to_world`: converte um ponto da tela em pixel global do mapa.
- `_request_pan_navigation`: solicita nova área após arraste.
- `_request_zoom`: calcula zoom mantendo o ponto sob o cursor.
- `_map_control_rect`: calcula o retângulo de um controle flutuante.
- `_map_control_action`: identifica o controle clicado.
- `_activate_map_control`: executa zoom, reset ou centralização.

### Desenho

- `_draw`: compõe tiles, ERBs, veículos, legenda, escala e controles.
- `_draw_loading_state`: desenha espera ou erro sem travar a interface.
- `_draw_station_marker`: desenha uma ERB individual.
- `_station_marker_texture`: escolhe o PNG Claro/TIM/Vivo/neutro de produção.
- `_station_marker_draw_size`: escala a torre entre 34 e 56 px pelo zoom.
- `_station_marker_hit_radius`: mantém área clicável maior que o desenho.
- `_draw_station_operator_label`: mostra o nome da prestadora no zoom próximo
  ou na seleção sem deslocar a âncora da ERB.
- `_station_operator_identity`: resolve cor, monograma e os fallbacks explícitos
  `OUTRAS`/`NÃO DETERMINADA` sem inferir dado ausente.
- `_draw_index_station_cluster`: compatibilidade histórica inalcançável no fluxo final.
- `_draw_tracking_marker`: desenha um veículo individual.
- `_draw_tracking_cluster_marker`: desenha veículos sobrepostos.
- `_tracking_plate_label`: escolhe placa, série ou nome de fallback.
- `_draw_tracking_pin`: desenha agulha, rótulo e quantidade agrupada.
- `_tracking_pin_texture`: escolhe um dos três SVGs de agulha conforme o estado.
- `_tracking_marker_color`: resolve a cor do estado de comunicação.
- `_draw_tracking_legend`: desenha a legenda dos veículos.
- `_draw_operator_legend_items`: mantém TIM/Claro/Vivo/Outras/N/D visíveis
  também no modo de rastreamento.
- `_operator_legend_labels`: expõe a lista determinística usada nas duas
  legendas para teste do contrato visual.
- `_station_visual_groups`: compatibilidade histórica; não participa do fluxo final.
- `_station_visual_positions`: memoriza projeções individuais e aplica arraste
  apenas durante pintura/hit-test.
- `_visible_station_indices`: compartilha entre desenho e hit-test a seleção
  determinística de ERBs reais por célula visual/prestadora em z10–z15.
- `station_render_metrics`: expõe fonte, renderizadas e ocultas por densidade.
- `_draw_station_cluster`: compatibilidade histórica inalcançável no fluxo final.
- `_should_cluster_stations`: retorna sempre falso; ERBs não viram bolhas.
- `_generation_color`: diferencia 2G/3G/4G/5G na legenda da camada oficial.
- `_draw_map_legend`: desenha tecnologia e operadoras das ERBs.
- `_draw_station_popup`: exibe dados cadastrais da ERB selecionada.
- `_map_position`: converte latitude/longitude em posição do canvas.
- `_operator_color`: converte operadora em cor visual.
- `_lat_lng_to_world_pixel`: delega projeção geográfica ao módulo matemático.
- `_world_pixel_to_lat_lng`: delega a conversão inversa.
- `_draw_map_controls`: desenha botões flutuantes de navegação.
- `_draw_navigation_loading`: mostra progresso sem esconder o mapa atual.
- `_draw_map_scale`: calcula e desenha a escala em quilômetros.

## Outros scripts

- `big_map_config.gd`: `default_center`, `default_view` e `basemap` centralizam
  Imperatriz e fixam OpenStreetMap, inclusive para estados legados.
- `map_projection.gd`: `lat_lng_to_tile`, `lat_lng_to_world_pixel`,
  `world_pixel_to_lat_lng` e `distance_km` cuidam somente da matemática.
- `map_tile_provider.gd`: `cache_key`, `tile_url`, `attribution` e
  `texture_from_bytes` isolam URL, cache, atribuição OSM e decodificação.
- `map_region_service.gd`: `definition`, `region_id_for_coordinates`,
  `region_id_for_device` e `counts_for_devices` cuidam das regiões.
- `vehicle_status_resolver.gd`: `resolve`, `apply_state` e `color_for_state`
  mantêm texto e cor do veículo consistentes.

## `anatel_national_index.gd` — todas as funções

- `load_manifest`: valida manifesto, sidecar SHA-256/tamanho, proveniência,
  células e arquivos de cluster sem carregar as ERBs.
- `query_viewport_threadsafe`/`query_viewport_threadsafe_to`: executam leitura e
  parse de shards fora da thread principal sob mutex e entregam o resultado a
  um estado consumido pelo controller.
- `query_viewport`: no contrato operacional z10+, lê células individuais e
  retorna somente ERBs reais dentro do recorte.
- `filter_entries`: aplica operadora, geração, município e situação a pontos
  e clusters sem varrer o catálogo nacional inteiro.
- `clear_cache`: descarta células LRU e zera contadores de registros/bytes.
- `cache_state`: expõe células, registros, `cache_bytes`, teto e estimativa de
  memória para benchmark e diagnóstico.
- `_clusters_for_zoom`: abre e memoriza o único resumo do nível solicitado.
- `_visible_cell_keys`: converte o viewport em células z10 visíveis/vizinhas.
- `_load_cell`: valida e lê uma partição, atualiza o LRU e aplica limites.
- `_load_index_file`: impede path traversal e valida SHA-256 antes do parse.
- `_touch_cache_key`: move uma célula acessada para o fim do LRU.
- `_enforce_cache_limits`: remove células antigas sem descartar
  silenciosamente uma única célula oficial superdimensionada.
- `_filtered_cluster`: recalcula contador por facetas do filtro ativo.
- `_station_matches`: compara os quatro filtros em uma ERB individual.
- `_value_matches`: trata igualdade sem caixa e o sentinela de campo ausente.
- `_array_matches`: aplica a mesma regra a listas de facetas.
- `_entry_count`: soma registros reais representados pelos clusters.
- `_normalized_bounds`: valida ordem e limites geográficos do viewport.
- `_bbox_intersects`: testa interseção de um cluster com o recorte.
- `_point_in_bounds`: impede ponto individual fora do viewport.
- `_cell_key`: cria chave estável `x:y` da partição.
- `_read_json_dictionary`: abre e valida um objeto JSON local.

## `big_map_tracking_view.gd` — todas as funções

- `_init`: configura o container e constrói as cinco áreas visuais.
- `set_metrics`: atualiza cartões e quantidade do botão da lista.
- `set_runtime`: atualiza mensagem, cor, metadados e horário operacional.
- `set_erb_source`: exibe fonte/estado e ressalva da camada oficial.
- `set_erb_filter_values`: preenche filtros com valores presentes no recorte.
- `selected_erb_filters`: devolve metadados selecionados sem regra de negócio.
- `set_details_title`: troca o título entre veículo e ERB.
- `set_list_expanded`: abre/recolhe a lista e atualiza seu botão.
- `set_query_state`: exibe apenas loading/found/not_found/error/idle, sem
  receber nem guardar o valor pesquisado.
- `_current_total`: lê o total atual para o texto do botão.
- `_build_toolbar`: cria busca, fila, monitoramento, câmera e ações.
- `_build_runtime_strip`: cria a faixa de estado da consulta de veículos.
- `_build_erb_filters`: cria fonte, ressalva, filtros e identificação OSM.
- `_build_metrics`: cria os seis cartões de contagem.
- `_metric_card`: cria um cartão com barra, rótulo e valor.
- `_build_map_workspace`: cria split, canvas, botão da lista e detalhes.
- `_build_vehicle_list`: cria cabeçalho e scroll da lista recolhível.
- `_button`: fabrica botão com tamanho e tema consistentes.
- `_style_input`: aplica tema ao campo de consulta.
- `_style_option`: aplica tema a um seletor.
- `_filter_select`: cria um seletor de filtro identificado.
- `_set_filter_items`: ordena opções, preserva seleção e representa ausentes.
- `_selected_filter_value`: lê o metadado da opção selecionada.
- `_apply_responsive_layout`: ajusta split e painel lateral conforme largura.
- `_style_check`: aplica tema ao controle de câmera.
- `_label`: fabrica rótulo temático.
- `_table_label`: fabrica célula de cabeçalho com largura/expansão.
- `_margin`: fabrica margens uniformes.
- `_panel_style`: fabrica estilo de painel com borda e raio.

Controles públicos: `query_input` (placa, número de série ou cliente explícito via API), `add_button`,
`monitor_select`, `camera_lock_check`, `erb_layer_check`, `refresh_button`,
`clear_queue_button`, `list_toggle`, `basemap_select`,
`erb_operator_select`, `erb_generation_select`, `erb_city_select` e
`erb_status_select`. A view não consulta API, não lê catálogo e não conhece
autenticação/Estoque.

## `big_map_tracking_layout.gd` — todas as funções do controller ativo

- `_setup_st310_location_poll_timer`: reutiliza o timer herdado e ajusta ciclo.
- `_show_vehicle_location_monitor`: abre a rota, contexto e view reconstruída.
- `_show_smart_4g_monitor`: redireciona a rota antiga compatível ao Mapa Grande.
- `_build_vehicle_location_view`: instancia a view, registra referências e sinais.
- `_on_vehicle_location_query_changed`: inicia estado visual sem expor a consulta.
- `_on_tracking_filter_selected`: aplica status e intervalo de atualização.
- `_on_tracking_camera_lock_toggled`: reenquadra veículos ao ativar a trava.
- `_on_tracking_erb_layer_toggled`: mostra/oculta somente a camada de ERBs.
- `_on_tracking_erb_filter_selected`: reaplica ERBs sem solicitar tiles.
- `_on_tracking_basemap_selected`: mantém compatibilidade do sinal sem reload;
  o único mapa-base é OpenStreetMap.
- `_initialize_tracking_erb_layer`: prioriza o manifesto nacional e usa o
  regional somente como fallback explícito.
- `_set_tracking_erb_source_error`: expõe erro sem criar pontos demonstrativos.
- `_update_tracking_erb_source_state`: apresenta data, escopo, URL e hash.
- `_refresh_tracking_erb_area`: recorta coordenadas oficiais ao viewport atual.
- `_drain_tracking_erb_queries`: mantém no máximo uma task nacional em voo e
  uma pendente substituível, consumindo toda task e descartando resultado velho.
- `_tracking_erb_query_state`: expõe requested/actual/coalesced/stale,
  in-flight/pending e latência da solicitação mais recente.
- `_populate_tracking_erb_filters`: extrai opções realmente presentes na área.
- `_tracking_append_entry_filter_values`: extrai facetas de clusters nacionais.
- `_tracking_append_unique`: acumula uma opção sem duplicidade.
- `_apply_tracking_erb_filters`: filtra o recorte e atualiza somente a camada.
- `_tracking_station_filter_matches`: compara valor exato ou campo ausente.
- `_update_tracking_poll_interval`: usa ciclo curto apenas em movimento.
- `_tracking_selected_filter`: lê o filtro operacional atual.
- `_refresh_vehicle_location_view`: consulta pelo contrato herdado e mede latência.
- `_tracking_query_signature`: estabiliza a identidade da fila/consulta.
- `_tracking_search_queries`: lista consultas válidas da fila ou do campo.
- `_tracking_row_matches_exact_queries`: aceita placa/série ou cliente explícito
  por igualdade exata, sempre sobre linhas retornadas pela API Grupo RS.
- `_tracking_coordinates_valid`: delega validação à integração de localização.
- `_tracking_number`: converte número textual com vírgula/ponto.
- `_location_monitoring_status`: classifica ligado/desligado/desatualizado.
- `_apply_vehicle_location_filters`: aplica busca/status e troca marcadores.
- `_tracking_row_matches_filter`: avalia um veículo no filtro selecionado.
- `_tracking_metrics`: calcula seis contagens do recorte de busca.
- `_render_tracking_list`: reconstrói somente as linhas ou estado vazio.
- `_sync_tracking_selection`: preserva seleção válida após atualização.
- `_focus_exact_tracking_result`: centraliza uma nova correspondência uma vez.
- `_update_tracking_query_state`: propaga loading/found/not_found/error/idle.
- `_vehicle_location_rows_for_map`: remove linhas sem posição do canvas.
- `_rows_with_tower_context`: integra veículo com contexto oficial já carregado.
- `_reload_vehicle_location_map`: carrega tiles/ERBs só quando necessário.
- `_vehicle_location_map_view`: calcula centro/zoom para todos os válidos.
- `_tracking_current_basemap`: devolve sempre o mapa-base OpenStreetMap.
- `_tracking_map_signature`: resume enquadramento para evitar recargas.
- `_ensure_vehicle_location_map_ready`: faz a carga inicial sem consulta de placa.
- `_on_vehicle_location_map_navigation`: solicita novo recorte após pan/zoom.
- `_on_vehicle_location_map_reset`: retorna ao enquadramento calculado.
- `_on_vehicle_location_map_selected`: seleciona veículo e limpa seleção de ERB.
- `_on_vehicle_location_station_selected`: seleciona ERB e limpa veículo.
- `_toggle_vehicle_location_list`: alterna a lista recolhível.
- `_sync_vehicle_location_map_list_toggle`: sincroniza estado visual do botão.
- `_make_vehicle_location_row`: cria uma linha clicável da lista.
- `_tracking_table_label`: cria célula de lista que ignora mouse.
- `_render_vehicle_location_details`: mostra dados operacionais do veículo.
- `_render_tracking_station_details`: mostra somente campos oficiais disponíveis.
- `_render_tracking_station_cluster_details`: mostra contagem/facetas do cluster
  e orienta ampliar o mapa para ERBs individuais.
- `_tracking_source_value`: traduz campo oficial vazio para texto explícito.
- `_tracking_source_array`: agrega lista oficial ou informa ausência.
- `_tracking_detail_line`: cria linha de legenda/valor no painel lateral.
- `_clear_control`: remove conteúdo anterior de lista/detalhes.
- `_center_vehicle_location_selected`: centraliza a câmera na posição válida.
- `_update_tracking_runtime_from_rows`: escolhe mensagem e cor do resumo.
- `_update_tracking_runtime`: combina fonte, mapa-base, ciclo e latência.

O controller ainda herda serviços de `inventory_dashboard.gd`; esta dependência
está documentada no README e deve ser reduzida em refatoração separada.

No contrato herdado de tiles, `_smart_4g_osm_tile_bytes` consulta somente
chaves ausentes, `_smart_4g_osm_tile_texture` reutiliza texturas decodificadas,
`_smart_4g_osm_tile_texture_async` decodifica `Image` em worker e cria a textura
somente no main thread, `_smart_4g_tile_http_bytes` cancela HTTP obsoleto,
`_smart_4g_touch_tile_cache_key` move hits de bytes/texturas para o fim da fila
LRU sem duplicar chaves e `_smart_4g_tile_cache_state` expõe requisições, hits,
decodes, tempo máximo de decode, cancelamentos, evicções, texturas órfãs,
first-paint, tempo total, entradas e bytes para os testes incrementais.
