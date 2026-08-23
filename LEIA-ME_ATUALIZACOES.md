# Atualizacoes do Grupo RS Central

## Estrutura

- `godot/Godot_v4.7.1-stable_win64.exe`: executavel principal do Godot usado pelos geradores.
- `godot/Godot_v4.7.1-stable_win64_console.exe`: inicializador de console usado pelos geradores.
- `dist/GRUPO RS CENTRAL/GRUPO RS CENTRAL.exe`: executavel-base fixo.
- `dist/GRUPO RS CENTRAL/updates/manifest.json`: descricao da versao publicada.
- `dist/GRUPO RS CENTRAL/updates/*.pck`: codigo e recursos da nova versao.
- `releases/<versao>/`: copia permanente e verificada de cada pacote e manifesto.
- `%APPDATA%/Godot/app_userdata/GRUPO RS CENTRAL/updates`: pacotes instalados e versao anterior.

Os geradores encontram o Godot pela pasta do proprio projeto, sem depender do nome do usuario ou do local em que a pasta foi copiada.
O publicador valida os arquivos essenciais, inicia o pacote em modo de teste e confere tamanho e SHA-256 nas tres copias. O manifesto e gravado somente depois dessas validacoes.

## Publicar uma nova versao

1. Termine as alteracoes e execute os testes.
2. Abra `GERAR_ATUALIZACAO.cmd`.
3. Informe uma versao maior, por exemplo `3.8.2`.
4. Escreva um resumo curto das mudancas.
5. Aguarde a mensagem `ATUALIZACAO PRONTA`.
6. Abra o sistema e entre em `Config. > Atualizacoes`.
7. Clique em `Verificar agora`, depois em `Baixar e instalar`.
8. Clique em `Reiniciar e aplicar`.

O monitor automatico termina a operacao atual antes do reinicio. Se a nova versao nao confirmar a inicializacao, o carregador volta para a versao anterior.
Cada numero de versao e imutavel. Se uma publicacao precisar ser refeita, use um numero maior.

## Copia permanente

Nunca apague a pasta `releases`. Ela fica dentro do projeto justamente para impedir que um manifesto sobreviva sem o pacote correspondente. Essa pasta e excluida do conteudo exportado, portanto uma atualizacao nao inclui os pacotes antigos dentro dela.

## Publicacao em outros computadores

Hospede o `manifest.json` e o arquivo `.pck` da pasta `updates` em um endereco HTTPS. Em cada sistema, informe o endereco completo do manifesto em `Config. > Atualizacoes > Origem das atualizacoes`.

O pacote somente sera instalado quando tamanho e SHA-256 forem iguais aos valores do manifesto.

## Quando gerar outro executavel

Um novo executavel-base so e necessario ao trocar:

- a versao principal do Godot;
- DLLs ou extensoes nativas;
- icone e metadados do executavel;
- o proprio carregador fixo de atualizacoes.

Para isso, execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\criar_executavel_fixo.ps1 -BaseVersion 3.8.0
```
