# Cofre de credenciais

O acesso operacional agora usa o BancoLocalSQL Auth. A senha do operador não é
gravada pelo aplicativo: o BancoLocalSQL mantém o hash e devolve uma sessão
temporária após a autenticação. As credenciais das integrações são sincronizadas
em `credentials/{filial}` no BancoLocalSQL, sob as regras e custom claims descritas
em `docs/escopo_inicial_e_seguranca.md`.

O cofre local abaixo permanece como camada de compatibilidade para refresh
tokens e migração de instalações antigas. Ele não substitui a autorização do
BancoLocalSQL para abrir uma filial, consultar ou modificar o estoque.

As credenciais das integracoes nao ficam mais nos arquivos JSON comuns do
Godot. Elas sao gravadas com criptografia no arquivo:

```text
.secrets/integrations.vault
```

Na versao executavel, a copia usada pelo sistema fica em:

```text
dist/GRUPO RS CENTRAL/.secrets/integrations.vault
```

## Uso no sistema

- Abra `Configuracoes` e escolha uma integracao.
- Digite a senha administrativa do cofre.
- O acesso permanece liberado por ate 10 minutos.
- As senhas continuam mascaradas ate clicar em `Mostrar credenciais`.
- Use `Bloquear` ao terminar.

O monitor automatico e as rotinas de consulta conseguem usar as credenciais
sem exibi-las e sem solicitar a senha de visualizacao.

## Seguranca

- O arquivo usa a criptografia nativa do Godot vinculada a este computador e
  ao usuario do Windows.
- O cofre e excluido dos pacotes `.pck`, historicos de versao e exportacoes do
  projeto.
- Nao envie o arquivo do cofre isoladamente para outro computador. Ele nao foi
  feito para ser aberto fora da maquina autorizada.
- Os arquivos `app_settings.json`, `local_database_sync_config.json` e
  `ai_config.json` guardam somente preferencias nao sensiveis.

## Transferencia para outro computador

Para levar o programa para outro PC, copie o executavel, a pasta `updates`, o
`transferir_cofre.ps1` e o arquivo criptografado `secrets-transfer.enc` que
fica ao lado do executavel. Nao copie a pasta `.secrets` da maquina de origem.
Esse arquivo e um pacote de transferencia protegido por uma senha propria; ele
nao e o `integrations.vault` da maquina atual e nao depende do usuario do
Windows que fez a exportacao.

No computador de destino, coloque `transferir_cofre.ps1` na pasta publicada,
abra o PowerShell nessa pasta e execute:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\transferir_cofre.ps1 -Mode Import
```

O script pede a senha do pacote e uma nova senha local. A importacao cria um
novo cofre vinculado ao usuario do Windows de destino. Depois disso, o
executavel passa a usar `dist/GRUPO RS CENTRAL/.secrets/integrations.vault`
normalmente. Para gerar um pacote atualizado na maquina de origem, use
`-Mode Export` e informe as duas senhas solicitadas.

Regras praticas:

- envie o executavel, a pasta `updates`, `transferir_cofre.ps1` e
  `secrets-transfer.enc` juntos;
- transmita a senha do pacote por um canal separado;
- nunca copie o arquivo `.secrets/integrations.vault` de um PC para outro;
- apague o `secrets-transfer.enc` depois de confirmar a importacao;
- se a senha for exposta, gere outro pacote e troque as credenciais das
  integracoes que permitem rotacao.
