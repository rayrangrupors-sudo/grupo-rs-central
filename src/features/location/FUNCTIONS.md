# Índice de funções da Localização

## `vehicle_location_integration.gd`

- `begin_request`: cria uma geração de consulta offline.
- `is_current`: rejeita resposta de geração antiga.
- `select_vehicle`: seleção visual tolerante com fallback; não é busca exata.
- `normalize_location_query`: remove máscara/caixa de placa ou série.
- `describe_location_query`: identifica automaticamente placa ou série.
- `row_matches_exact_query`: compara igualdade exata nos grupos placa e série;
  a heurística de formato nunca bloqueia uma série parecida com placa.
- `find_exact_vehicle_result`: retorna resultado único ou ambiguidade explícita.
- `find_exact_vehicle`: retorna a correspondência exata ou dicionário vazio.
- `_plate_fields`: lista aliases aceitos para placa.
- `_serial_fields`: lista aliases aceitos para série/equipamento.
- `_row_matches_normalized_fields`: compara um grupo de campos normalizados.
- `_stable_row_key`: deduplica a mesma linha encontrada nos dois grupos.
- `_looks_like_brazilian_plate`: reconhece padrões antigo e Mercosul.
- `map_device`: converte localização válida para o contrato do mapa.
- `compose_map_state`: associa contexto de ERBs sem inferir sinal.
- `valid_coordinates`: rejeita limites inválidos e a coordenada 0,0.
- `_number`: converte número textual de forma defensiva.

`query_input` é o campo público da view ativa e aceita somente pesquisa por
placa ou número de série. A normalização permite placa formatada/compacta; a
busca exata nunca usa o fallback de `select_vehicle`; uma consulta inexistente
não seleciona a primeira linha e uma colisão entre veículos retorna ambiguidade.

## Controller legado de localização

- `_setup_st310_location_poll_timer`: configura o ciclo de atualização.
- `_show_vehicle_location_monitor`: abre a funcionalidade sem reiniciar o app.
- `_build_vehicle_location_view`: monta filtros, mapa, detalhes e lista.
- `_make_location_metric_card`: cria um indicador resumido.
- `_refresh_vehicle_location_view`: coordena consulta e preserva posição válida.
- `_clone_location_rows`: duplica resultados sem compartilhar estado mutável.
- `_location_row_key`: cria a identidade estável de uma linha.
- `_merge_last_valid_positions`: mantém a última coordenada com aviso de atraso.
- `_location_coordinates_valid`: valida a presença de latitude/longitude.
- `_has_valid_location_row`: detecta ao menos uma posição utilizável.
- `_update_location_runtime_banner`: atualiza fonte, latência e resumo.
- `_location_age_text`: converte a data em idade legível.
- `_location_device_status`: classifica o estado básico do equipamento.
- `_location_monitoring_status`: delega a regra oficial de comunicação.
- `_set_location_communication_state`: grava texto e cor no mesmo resultado.
- `_update_vehicle_location_summary`: recalcula os indicadores da tela.
- `_make_vehicle_location_row`: monta uma linha selecionável.
- `_make_location_row_label`: padroniza células da lista.
- `_render_vehicle_location_details`: apresenta os dados do selecionado.
- `_center_vehicle_location_selected`: centraliza a câmera no veículo.
- `_make_location_detail_line`: padroniza campos do painel de detalhes.
