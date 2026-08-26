# Contrato de dados do Estoque por filial

- O Firebase é a fonte do Estoque de Imperatriz, Araguaína, Açailândia e Marabá.
- Ao abrir ou trocar de filial, o aplicativo vincula (`bind_store`) o armazenamento
  da filial selecionada, executa `refresh_remote` e só então recompõe tabela e
  indicadores. Respostas de uma seleção anterior são descartadas.
- Somente Imperatriz pode iniciar APIs operacionais de telemetria, localização,
  SGA, Arya, Linksolutions e sincronização de placas.
- Araguaína, Açailândia e Marabá são Firebase-only: não criam polling ST310 nem
  ciclos de telemetria/status.
- Registros de comunicação são ordenados por DataServidor válida e, em empate ou
  ausência bilateral, por DataGPS. Uma amostra histórica ou sem timestamp válido
  nunca substitui uma amostra válida mais recente.

Cobertura offline: `inventory_branch_firebase_refresh_test.gd`,
`inventory_dashboard_stock_test.gd`, `inventory_communication_status_test.gd` e
`main_scene_stock_exit_smoke_test.gd`.
