# Relatorio da migracao local SQLite

## Resultado

O fluxo operacional do aplicativo usa exclusivamente o banco local `C:\GRUPO RS CENTRAL\database\grupo_rs_central.sqlite`. O serviço registrado no autoload é `LocalDataService`; não há cliente de banco externo, autenticação externa nem arquivo de regras remotas na cópia operacional.

Projeto operacional: `C:\GRUPO RS CENTRAL\app`
Executavel: `C:\GRUPO RS CENTRAL\app\dist\GRUPO RS CENTRAL\GRUPO RS CENTRAL.exe`

## Estrutura SQLite

Tabelas: `branches`, `devices`, `telemetry_raw`, `locations`, `communications`, `ignition_events`, `maintenance`, `alerts`, `movements`, `audit_log`, `runtime_state` e `schema_migrations`.

Existem indices por filial, IMEI, ICCID, placa, status, operador e data. IMEI e ICCID sao unicos dentro da filial. As gravacoes do snapshot do estoque ocorrem em transacao; o banco usa WAL, chaves estrangeiras e `synchronous=FULL`.

## Teste real solicitado

Filial: Imperatriz.

- Tres aparelhos sinteticos foram cadastrados: `TESTE-SQLITE-001`, `TESTE-SQLITE-002` e `TESTE-SQLITE-003`.
- O aparelho 001 recebeu baixa e ficou com status Instalado, estoque zero e placa `TST-BAIXA`.
- O aparelho 002 foi excluido.
- O aparelho 003 permaneceu no estoque.
- Resultado final: 2 aparelhos, 1 movimentacao e 5 eventos de auditoria antes do teste de restauracao.
- Um novo processo Godot releu o SQLite e confirmou os mesmos dados apos reinicio.

## Backup

Pasta local automatica: `C:\GRUPO RS CENTRAL\app\backups\automaticos`.

Pasta sincronizada: `G:\Meu Drive\Grupo RS Central\Backups`.

Cada backup possui nome versionado, arquivo SQLite, manifesto JSON, tamanho, versao, contagens, SHA-256 e estado do Drive. Bancos vazios sao recusados. Backups antigos nao sao sobrescritos nem apagados automaticamente.

Tarefa do Windows: `Grupo RS Central - Backup SQLite Diario`.

- Horario: diariamente as 02:00.
- `StartWhenAvailable`: ativado.
- Funciona com o aplicativo fechado.
- Execucao manual validada com resultado `0`.
- Se o Drive estiver indisponivel, o backup local permanece com estado pendente.

## Restauracao validada

O backup `backup_2026-08-29_091848.sqlite` foi restaurado somente na copia separada `C:\GRUPO RS CENTRAL\restore_test\test.sqlite`.

Antes da restauracao foi criado outro backup em `restore_test\pre_restore`. A copia temporaria passou na verificacao de integridade antes da substituicao. Depois da restauracao, o banco permaneceu integro, com 2 aparelhos, 1 movimentacao e 6 eventos de auditoria, incluindo `RESTORE`.

## Testes executados

- Compilacao Python: passou.
- Compilacao Godot 4.7.1: passou.
- Inicializacao do projeto: passou.
- Inicializacao do executavel exportado: passou.
- Cadastro, baixa e exclusao: passou.
- Persistencia apos reinicio: passou.
- IMEI duplicado: bloqueado.
- ICCID duplicado: bloqueado.
- Banco corrompido: rejeitado.
- Banco vazio: backup recusado.
- Backup com conexao SQLite aberta: passou.
- Backup com aplicativo fechado pelo Agendador: passou.
- Copia para a pasta sincronizada do Drive e verificacao de hash: passou.
- Restauracao em copia separada: passou.

## Arquivos principais alterados

- `project.godot`
- `export_presets.cfg`
- `src/inventory_store.gd`
- `src/inventory_dashboard.gd`
- `src/local_data_service.gd`
- `src/local_sqlite_bridge.gd`
- `tools/local_sqlite_service.py`
- `tools/run_daily_backup.py`
- testes locais SQLite em `tests/`

## Observacoes

As APIs externas de rastreadores foram preservadas. Alguns nomes internos antigos de funcoes da interface ainda contem a palavra `local_database` por compatibilidade com o arquivo grande do dashboard, mas apontam para `LocalDataService` e nao executam requisicoes ao BancoLocalSQL. O cliente de rede, as URLs e o autoload BancoLocalSQL nao fazem parte do fluxo operacional.
