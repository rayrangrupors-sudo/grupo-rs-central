# Auditoria sanitizada do Estoque remoto

Data: 2026-08-27.

Escopo: filas remotas e fluxos de Cadastro/Modificar da área Estoque. Mapa Grande, publicação, PCK, commit, tag e push ficam fora deste documento.

## Contrato atual do formulário do Estoque

Cadastro e Modificar no formulário do Estoque usam a API Grupo RS somente para
consulta e preenchimento dos campos. A gravação operacional desses dados tem
como destino o Store local/BancoLocalSQL. O fluxo principal não deve criar nem
modificar Cadastro/Modificar na API Grupo RS. Rotas antigas de gravação remota
podem permanecer no código apenas como compatibilidade isolada, sem serem
alcançadas pelo fluxo normativo e sem produzir sucesso operacional sem Store e
BancoLocalSQL confirmados.

Para ações gravadas pelo Estoque, inclusive Dar baixa/devolver ao estoque, o
feedback de sucesso só pode aparecer depois de:

1. gravação local preservada no Store;
2. sincronização enviada ao BancoLocalSQL;
3. leitura de confirmação do registro esperado;
4. atualização da tabela.

Se o BancoLocalSQL recusar ou ficar pendente, o Store local pode preservar o estado
para sincronização posterior, mas a UI deve informar pendência/erro e não pode
exibir sucesso falso.

## Barreira defensiva das filas remotas legadas

As filas remotas continuam mantidas por compatibilidade/defesa. Se algum job
legado ainda alcançar Cadastro/Modificar com escrita remota, ele precisa
respeitar uma única ordem:

1. confirmação da API ou leitura remota equivalente do Grupo RS;
2. atualização do Store local;
3. confirmação de leitura/gravação no BancoLocalSQL por `_ensure_local_database_modification_saved()`;
4. somente então finalização como sucesso na fila/tabela.

Se a API ficar ambígua ou pendente, o fluxo deve ficar pendente. Se o BancoLocalSQL não confirmar, o registro local pode ser preservado para sincronização, mas a operação não pode ser apresentada como sucesso.

## Filas mapeadas

- `src/remote_operation_queue_current.gd`: caminho operacional ativo, carregado por `src/inventory_dashboard.gd`.
- `src/remote_operation_queue.gd`: legado independente, mantido como compatibilidade defensiva.
- `src/remote_operation_queue_v2.gd`: artefato legado/inativo sem referência operacional literal encontrada; mantido recuperável e blindado com a mesma barreira.
- fallback interno `legacy_run_remote_operation_job` em `src/inventory_dashboard.gd`: defesa para falha de inicialização do controller atual.

## Fallbacks web do Estoque

Fallback web é permitido apenas como fallback explícito de leitura, depois da
tentativa da API Grupo RS. Fallback ambíguo, timeout, API indisponível, resposta
parcial ou confirmação pendente não pode virar sucesso de negócio.

Na tabela visual “Grupo RS online”, a ordem normativa é:

1. API de equipamentos;
2. API de veículos/enriquecimento;
3. portal/web somente como fallback explícito de leitura.

O status cadastral (“Cadastro”) vem dos campos cadastrais da API/linha remota
e é normalizado apenas para apresentação: `A`/ativo vira “Ativo”, `I`/inativo
vira “Inativo”, `R`/reserva vira “Reserva”, e valores desconhecidos permanecem
visíveis como o texto original retornado pela fonte. Campos ausentes de chip,
telefone, APN e operadora devem aparecer como “Não informado”, sem serem
tratados como erro de consulta.

O “Status atual” é status de localização/comunicação e deve distinguir “Não
consultado”, “Consultando”, “Indisponível” e status real. “Não consultado” não é
erro de BancoLocalSQL nem sinal de cadastro inativo, e a tabela deve exibir o rótulo
completo com tooltip contextual.

Chip, telefone, APN e operadora são uma exceção controlada: vêm das fontes de
APN Hinova e Link Solutions, consultadas em paralelo e aceitas somente quando a
identidade do chip é coerente. Esses dados podem preencher o formulário, mas não
autorizam fallback silencioso nem sucesso sem BancoLocalSQL.

Principais pontos mapeados em `src/inventory_dashboard.gd`:

- Cadastro de equipamento via portal: `_register_modern_equipment_via_web()`.
- Cadastro/vínculo de placa via portal: usa confirmação por `_verify_modern_vehicle_registration()`.
- Modificação de equipamento via portal: `_modify_modern_equipment_via_web()` com confirmação por `_verify_modern_equipment_modification()`.
- Integrações legadas `_legacy_grupo_rs_*`: tratadas como caminhos de consulta/manutenção/baixa e não como fonte para sucesso ambíguo em Cadastro sem confirmação.

## Harnesses live

Harnesses live de escrita exigem `GRS_ALLOW_LIVE_WRITE_HARNESS=YES`. Sem essa variável, falham fechado antes de autenticar ou executar operação. Identificadores, senhas, tokens e payloads não devem ser fixados nesses arquivos.

Harnesses read-only podem continuar disponíveis para validação sanitizada, desde que os alvos sejam fornecidos por variáveis de ambiente e o relatório não exponha identificadores.

## Logs internos do Estoque

Os wrappers centrais de log do Estoque sanitizam detalhes e metadados antes de
enviar o evento ao Store. A chave `sku` recebida pelo Store permanece como chave
operacional interna para indexação/histórico, mas `sku`, chaves técnicas, série,
placa, chip, telefone, payload, corpo de resposta e detalhes equivalentes são
sanitizados quando aparecem em campos expostos de detalhes/metadados. Histórico
antigo não deve ser apagado ou reescrito sem autorização específica.

## Testes de proteção

- `tests/remote_registration_local_database_persistence_test.gd` executa a bateria de Cadastro contra as três filas.
- `tests/stock_remote_safety_static_test.gd` prova contrato estático das filas, trava dos harnesses live e mapeamento mínimo dos fallbacks web.
- `tests/stock_api_first_edge_cases_test.gd` cobre envelopes/aliases da API, cache limpo/expirado/obsoleto, consulta automática sem duplicidade, 401 com uma reautenticação, timeout, rate limit, JSON inválido, resposta vazia, múltiplos matches, fallback web somente leitura, Store mais novo preservado e sanitização completa de logs expostos, separando `sku` operacional interno dos detalhes/metadados sanitizados.
- `tests/inventory_dashboard_stock_test.gd`, `tests/main_scene_stock_exit_smoke_test.gd` e `tests/local_database_sync_read_only_test.gd` cobrem regressões do Estoque, Sair e modo BancoLocalSQL read-only.
