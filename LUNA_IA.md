# Assistente Luna - GRUPO RS CENTRAL

## Visao geral

A Luna usa uma arquitetura hibrida:

- **Modo local:** intencoes, regras e resumos do proprio sistema. Funciona sem internet.
- **Modo online:** Google Gemini pela API REST oficial, somente quando habilitado e necessario.
- **AIManager:** decide o modo, aplica privacidade, limites, cache e logs.
- **AIContextProvider:** unica ponte autorizada entre a IA e o `InventoryStore`.
- **AISystemMonitor:** regras locais periodicas. Nunca chama o Gemini automaticamente.

O modo online e opcional. Nao existe contratacao, cobranca ou ativacao automatica de servico pago.

## Arquivos

```text
res://ai/
    ai_manager.gd
    ai_settings.gd
    ai_sanitizer.gd
    ai_cache.gd
    ai_context_provider.gd
    local_assistant.gd
    ai_system_monitor.gd
    gemini_client.gd
    luna_chat.gd
    luna_chat.tscn
    luna_settings_panel.gd
    luna_settings_panel.tscn
```

O `AIManager` e o unico novo Autoload. Os demais componentes sao criados e controlados por ele.

## Configurar o Gemini

1. Abra **Configuracoes > Luna**.
2. Mantenha **Ativar IA local** ligado.
3. Cole uma chave criada no Google AI Studio no campo secreto.
4. Ative **Gemini** e **Permitir analise online**.
5. Clique em **Salvar alteracoes**.
6. Clique em **Testar conexao**.

O resultado esperado e:

```text
Conexao realizada com sucesso.
```

A chave e salva fora do projeto:

```text
user://ai_config.json
```

No Windows, o caminho normalmente corresponde a:

```text
%APPDATA%\Godot\app_userdata\GRUPO RS CENTRAL\ai_config.json
```

Tambem e possivel definir `GEMINI_API_KEY` como variavel de ambiente. A variavel de ambiente tem prioridade e nao e copiada para o arquivo.

O projeto nao possui chave real. `.gitignore` bloqueia arquivos locais de credencial.

## Modelo e API

O modelo padrao fica centralizado em `AISettings.DEFAULT_MODEL`:

```gdscript
const DEFAULT_MODEL := "gemini-2.5-flash-lite"
```

O endpoint base fica somente em `GeminiClient.API_BASE_URL`. A integracao usa `HTTPRequest`, `generateContent`, cabecalho `x-goog-api-key` e JSON oficial, sem biblioteca externa.

O modelo pode ser alterado em **Configuracoes > Luna** quando a disponibilidade oficial mudar.

Documentacao oficial:

- https://ai.google.dev/gemini-api/docs/generate-content
- https://ai.google.dev/api/models
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/gemini-api/docs/rate-limits

## Privacidade

Antes de qualquer chamada online, `AISanitizer`:

- bloqueia mensagens com senha, token, chave ou cabecalho Bearer;
- remove e-mails e telefones;
- substitui nomes de cliente;
- converte placas em aliases como `Veiculo 01`;
- reduz ICCIDs e equipamentos ao final de quatro digitos;
- limita o tamanho do texto e do contexto;
- envia apenas resumos autorizados.

O Gemini recebe texto e contexto agregado. A resposta e tratada somente como texto. Codigo, SQL, URLs, nomes de metodos e instrucoes do modelo nunca sao executados.

## Limites e cache

- limite local padrao: 20 respostas online por dia;
- intervalo minimo padrao: 10 segundos;
- cache em memoria por 30 minutos;
- no maximo 20 mensagens no historico de contexto;
- no maximo 6.000 caracteres por prompt;
- uma requisicao online ativa por vez;
- nenhuma chamada automatica por atualizacao de tela;
- nenhuma chamada automatica feita pelo monitor.

Perguntas repetidas podem usar o cache sem consumir uma nova chamada.

## Logs seguros

O log tecnico fica em:

```text
user://luna_ai_logs.jsonl
```

Ele registra somente:

- data e hora;
- modo;
- duracao;
- sucesso ou erro;
- codigo do erro;
- quantidade aproximada de caracteres;
- uso do cache;
- filial.

Ele nao registra chave, pergunta completa, resposta completa, credenciais ou banco de dados.

Outros estados locais:

```text
user://luna_ai_usage.json
user://luna_monitor_state.json
user://luna_chat_history.json
```

O historico so existe quando **Salvar historico local** esta habilitado e, mesmo assim, e sanitizado.

## Exemplos locais

```text
Quantos aparelhos estao disponiveis?
Quantos estao em manutencao?
Existem ICCIDs duplicados?
Quais registros apresentam campos vazios?
Como faco para dar baixa em um aparelho?
Como cadastrar um rastreador?
O sistema esta sincronizado?
Mostre um resumo do estoque.
Explique a tela de monitoramento 4G.
Como usar esta tela?
```

## Adicionar uma intencao local

1. Abra `res://ai/local_assistant.gd`.
2. Adicione o identificador e suas frases em `_intents`.
3. Registre um `Callable` em `_handlers`.
4. Crie uma funcao pequena que consulte somente `AIContextProvider`.
5. Retorne um dicionario com `handled`, `intent`, `text` e, opcionalmente, acoes permitidas.
6. Adicione um teste em `res://src/__codex_luna_ai_check.gd`.

Exemplo:

```gdscript
_handlers["ajuda_relatorio"] = Callable(self, "_answer_report_help")
_intents.append({
    "id": "ajuda_relatorio",
    "phrases": ["como gerar relatorio", "exportar relatorio"],
})
```

Nao leia arquivos do banco dentro de `LocalAssistant`. Novas consultas devem entrar primeiro em `AIContextProvider`.

## Desativar o Gemini

Em **Configuracoes > Luna**:

1. Desative **Ativar Gemini**.
2. Desative **Permitir analise online**.
3. Opcionalmente clique em **Limpar chave**.

A Luna continuara no modo local. Para desativar tudo, desligue tambem **Ativar IA local** e **Ativar monitor local**.

## Monitor local

O monitor executa por `Timer`, sem `_process`, e verifica:

- estoque baixo;
- alteracao incomum na quantidade disponivel;
- manutencoes acima da proporcao esperada;
- ICCIDs duplicados;
- campos vazios e formatos diagnosticados pelo sistema;
- sincronizacao com falhas;
- banco remoto indisponivel;
- equipamentos parados, quando esse resumo e fornecido pelo monitor operacional;
- falhas consecutivas, quando informadas;
- backup com mais de sete dias, quando houver data registrada.

Alertas iguais nao sao repetidos continuamente. As acoes exibidas sao locais e controladas, como abrir Estoque, Manutencoes, Logs ou Configuracoes.

## Testes

Suite principal:

```powershell
.\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://src/__codex_luna_ai_check.gd
```

Ela usa transporte Gemini simulado e valida:

1. internet e chave valida;
2. falta de internet;
3. chave vazia;
4. chave invalida;
5. limite remoto;
6. resposta vazia;
7. JSON invalido;
8. resposta local;
9. encaminhamento online;
10. bloqueio de dados sensiveis;
11. fechamento durante requisicao;
12. mensagens simultaneas;
13. cache;
14. estoque baixo;
15. modo somente local.

O teste de uma chave real deve ser feito pelo botao **Testar conexao**, pois nenhuma credencial real e incluida na suite.

## Limitacoes atuais

- A IA offline e deterministica e leve; ela nao e um modelo de linguagem local.
- A qualidade do modo local depende das intencoes cadastradas e dos resumos disponiveis.
- Cotas e modelos gratuitos podem mudar conforme as regras oficiais do Google.
- O modo online nao executa alteracoes e nao recebe registros completos.
- Se o certificado raiz do Windows estiver indisponivel, o teste HTTPS apresentara uma mensagem de conexao; o modo local continua funcionando.
