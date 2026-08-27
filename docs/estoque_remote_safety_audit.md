# Auditoria sanitizada do Estoque remoto

Data: 2026-08-27.

Escopo: filas remotas e fluxos de Cadastro/Modificar da área Estoque. Mapa Grande, publicação, PCK, commit, tag e push ficam fora deste documento.

## Barreira obrigatória

Todo Cadastro/Modificar que dependa do Grupo RS precisa respeitar uma única ordem:

1. confirmação da API ou leitura remota equivalente do Grupo RS;
2. atualização do Store local;
3. confirmação de leitura/gravação no Firebase por `_ensure_firebase_modification_saved()`;
4. somente então finalização como sucesso na fila/tabela.

Se a API ficar ambígua ou pendente, o fluxo deve ficar pendente. Se o Firebase não confirmar, o registro local pode ser preservado para sincronização, mas a operação não pode ser apresentada como sucesso.

## Filas mapeadas

- `src/remote_operation_queue_current.gd`: caminho operacional ativo, carregado por `src/inventory_dashboard.gd`.
- `src/remote_operation_queue.gd`: legado independente, mantido como compatibilidade defensiva.
- `src/remote_operation_queue_v2.gd`: artefato legado/inativo sem referência operacional literal encontrada; mantido recuperável e blindado com a mesma barreira.
- fallback interno `legacy_run_remote_operation_job` em `src/inventory_dashboard.gd`: defesa para falha de inicialização do controller atual.

## Fallbacks web do Estoque

Fallback web é permitido apenas quando há confirmação posterior por leitura remota exata. Fallback ambíguo, timeout, API indisponível, resposta parcial ou confirmação pendente não pode virar sucesso.

Principais pontos mapeados em `src/inventory_dashboard.gd`:

- Cadastro de equipamento via portal: `_register_modern_equipment_via_web()`.
- Cadastro/vínculo de placa via portal: usa confirmação por `_verify_modern_vehicle_registration()`.
- Modificação de equipamento via portal: `_modify_modern_equipment_via_web()` com confirmação por `_verify_modern_equipment_modification()`.
- Integrações legadas `_legacy_grupo_rs_*`: tratadas como caminhos de consulta/manutenção/baixa e não como fonte para sucesso ambíguo em Cadastro sem confirmação.

## Harnesses live

Harnesses live de escrita exigem `GRS_ALLOW_LIVE_WRITE_HARNESS=YES`. Sem essa variável, falham fechado antes de autenticar ou executar operação. Identificadores, senhas, tokens e payloads não devem ser fixados nesses arquivos.

Harnesses read-only podem continuar disponíveis para validação sanitizada, desde que os alvos sejam fornecidos por variáveis de ambiente e o relatório não exponha identificadores.

## Testes de proteção

- `tests/remote_registration_firebase_persistence_test.gd` executa a bateria de Cadastro contra as três filas.
- `tests/stock_remote_safety_static_test.gd` prova contrato estático das filas, trava dos harnesses live e mapeamento mínimo dos fallbacks web.
- `tests/inventory_dashboard_stock_test.gd`, `tests/main_scene_stock_exit_smoke_test.gd` e `tests/firebase_sync_read_only_test.gd` cobrem regressões do Estoque, Sair e modo Firebase read-only.
