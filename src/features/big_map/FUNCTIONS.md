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
- `set_coverage_profile`: recebe ERBs e metadados de cobertura.
- `select_station_by_id`: seleciona uma ERB pelo identificador.
- `select_tracking_by_key`: seleciona um veículo por série ou placa.
- `set_city_label`: atualiza o nome da área exibida.
- `set_station_visibility`: liga ou desliga somente a camada de ERBs.

### Tiles e carregamento

- `set_map_texture`: aplica uma imagem de mapa completa, por compatibilidade.
- `set_map_view`: inicia uma grade de tiles preservando câmera e contadores.
- `set_map_tile`: insere um tile recebido de forma assíncrona.
- `finish_map_tile_load`: encerra o carregamento da grade atual.
- `set_map_tile_progress`: atualiza contagem e texto de progresso.
- `begin_map_load`: cria uma geração para rejeitar respostas antigas.
- `set_loading_stage`: troca apenas o estado visual de carregamento.
- `is_load_current`: valida se uma resposta pertence à geração ativa.
- `set_map_error`: exibe erro quando não há mapa utilizável.
- `cancel_navigation_load`: cancela uma navegação sem desmontar o mapa anterior.

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
- `_draw_tracking_marker`: desenha um veículo individual.
- `_draw_tracking_cluster_marker`: desenha veículos sobrepostos.
- `_tracking_plate_label`: escolhe placa, série ou nome de fallback.
- `_draw_tracking_pin`: desenha agulha, rótulo e quantidade agrupada.
- `_tracking_marker_color`: resolve a cor do estado de comunicação.
- `_draw_tracking_legend`: desenha a legenda dos veículos.
- `_station_visual_groups`: prepara agrupamentos opcionais de ERBs.
- `_draw_station_cluster`: desenha um agrupamento de ERBs.
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

- `big_map_config.gd`: `default_center` e `default_view` centralizam Imperatriz.
- `map_projection.gd`: `lat_lng_to_tile`, `lat_lng_to_world_pixel`,
  `world_pixel_to_lat_lng` e `distance_km` cuidam somente da matemática.
- `map_tile_provider.gd`: `cache_key`, `tile_url`, `attribution` e
  `texture_from_png` isolam o provedor de mapa.
- `map_region_service.gd`: `definition`, `region_id_for_coordinates`,
  `region_id_for_device` e `counts_for_devices` cuidam das regiões.
- `vehicle_status_resolver.gd`: `resolve`, `apply_state` e `color_for_state`
  mantêm texto e cor do veículo consistentes.
