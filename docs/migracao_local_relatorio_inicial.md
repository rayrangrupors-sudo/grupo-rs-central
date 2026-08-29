# Relatório inicial — migração para banco local

Data da análise: 2026-08-29
Projeto analisado: `C:\Users\lugan\OneDrive\Documentos\grupo rs central - sinderacode\02-PROJETO_ORIGEM`

## Situação desta etapa

Esta é uma análise inicial, sem migração de dados, sem restauração, sem exclusão e sem alteração das regras ou dos dados do BancoLocalSQL.

Foi criada uma cópia pré-migração em:

`C:\Users\lugan\OneDrive\Documentos\grupo rs central - sinderacode\_BACKUP_PRE_MIGRACAO_20260829_02`

Também foi iniciado um segundo procedimento de cópia em `_BACKUP_PRE_MIGRACAO_20260829_03` para preservar a estrutura de links do projeto. A contagem de arquivos não pode ser considerada equivalente ainda, porque o projeto possui links/artefatos gerenciados pelo OneDrive e diretórios gerados pelo Godot. A pasta `_BACKUP_PRE_MIGRACAO_20260829_01` é somente o diretório vazio da tentativa inicial e não foi usada.

## Projeto e runtime

- Nome: `GRUPO RS CENTRAL`.
- Versão declarada no `project.godot`: `4.2.1`.
- Executável disponível: `godot\Godot_v4.7.1-stable_win64_console.exe`.
- Cena principal: `scenes/estoque_profissional.tscn`.
- Autoloads relevantes: `SecretVault` e `LocalDataService`.

## Arquitetura atual encontrada

- `src/local_data_service.gd`: serviço do banco SQLite local, sem autenticação externa.
- `src/inventory_store.gd`: armazenamento operacional ainda modelado para a base remota, com estrutura de produtos, movimentações, manutenções e logs.
- `src/inventory_dashboard.gd`: interface principal e fluxo de operações.
- `src/remote_operation_queue*.gd`: fila de operações remotas.
- `src/security/secret_vault.gd`: cofre local de configuração/credenciais.
- Não foi encontrado uso de SQLite; as referências encontradas são de banco SQLite local/BancoLocalSQL Auth.
- O projeto já usa SQLite em ferramentas Python para índices da Anatel, mas não possui ainda um banco SQLite operacional integrado ao runtime Godot.

## Busca de dependências

A busca foi feita por BancoLocalSQL, SQLite, banco SQLite local, autenticação, cloud, sync, save, delete, put, patch, inventory_db, rastreadores, backup e restore.

- BancoLocalSQL: referências em 38 arquivos.
- SQLite: nenhuma referência encontrada.
- banco SQLite local: referências encontradas.
- `local_data_service.gd`: serviço operacional registrado no autoload do projeto.
- Backups/restauração: existem rotinas e documentação, mas não um mecanismo SQLite local completo.

As chamadas `put`/HTTP precisam ser separadas por finalidade antes da remoção: chamadas para Grupo RS, Arya, LinkSolutions e outras APIs de rastreadores devem permanecer; somente as chamadas do BancoLocalSQL devem sair do fluxo operacional.

## Dados locais encontrados

Na árvore principal não foram localizados arquivos operacionais com os nomes `inventory_db*.json`, `rastreadores.json`, `.sqlite`, `.db`, `.xlsx` ou `.csv`. Foram encontrados arquivos de dados e índices da Anatel, que não devem ser confundidos com o estoque ou o histórico de rastreamento.

O diretório de dados do usuário Godot existente é:

`C:\Users\lugan\AppData\Roaming\Godot\app_userdata\grupo rs central`

Ele contém configurações locais do aplicativo. Nenhum segredo, token ou senha é reproduzido neste relatório.

Conclusão preliminar: os registros operacionais podem estar apenas no BancoLocalSQL. Se isso for confirmado, a migração dependerá de uma exportação controlada do BancoLocalSQL; dados ausentes localmente não podem ser inventados.

## Separação por filiais

O modelo atual usa filiais nomeadas `imperatriz`, `araguaina`, `acailandia` e `maraba`. A nova base deverá manter `branch_id` obrigatório em todas as tabelas operacionais, com índices e consultas sempre filtrados pela filial. Nenhuma importação poderá combinar registros de filiais diferentes.

## Modelo local proposto

SQLite em arquivo local, com WAL/transações e migrações versionadas. Tabelas mínimas:

`devices`, `telemetry_raw`, `locations`, `communications`, `ignition_events`, `maintenance`, `alerts`, `movements`, `audit_log` e `schema_migrations`.

Também serão necessários metadados de filiais, operadores, importações, backups e estado de sincronização do backup. IMEI/ICCID terão restrições de unicidade apropriadas, considerando a filial quando necessário.

## Riscos e pendências antes da implementação

1. A origem real dos registros de estoque e rastreamento precisa ser confirmada: arquivos locais ou BancoLocalSQL.
2. A cópia integral precisa ser validada considerando os links/artefatos do OneDrive; não é seguro tratar a contagem simples de arquivos como prova suficiente.
3. É necessário definir o diretório real do Google Drive Desktop neste computador.
4. É necessário escolher se o Agendador de Tarefas será criado pelo instalador/usuário, pois isso exige configuração do Windows fora do código.
5. A migração e a restauração exigirão confirmação explícita e gerarão auditoria.
6. O BancoLocalSQL será preservado como fonte histórica até a validação do banco local e do backup restaurável.

## Próxima etapa segura

Após validar a cópia pré-migração e confirmar a origem dos dados, implementar o esquema SQLite e os testes isolados. Em seguida, importar os dados sem apagar originais, gerar relatório de conflitos e criar um backup restaurável em área separada. Somente depois desses testes o fluxo normal poderá deixar de consultar o BancoLocalSQL.
