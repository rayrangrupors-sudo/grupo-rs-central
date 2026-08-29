# Assistente Luna

## Estado atual

A Luna desta versao opera somente em modo local. O modo legado online foi desativado e nao faz mais parte do fluxo ativo.

## Componentes ativos

```text
res://ai/
    ai_manager.gd
    ai_settings.gd
    ai_sanitizer.gd
    ai_cache.gd
    ai_context_provider.gd
    local_assistant.gd
    ai_system_monitor.gd
    luna_chat.gd
    luna_chat.tscn
    luna_settings_panel.gd
    luna_settings_panel.tscn
```

O `AIManager` continua como ponto central da Luna, mas agora somente para decisoes locais, sanitizacao, cache, historico e monitoramento interno.

## Escopo

- Intencoes e regras locais.
- Resumos autorizados do proprio sistema.
- Contexto controlado pelo `AIContextProvider`.
- Monitoramento local periodico.

## O que nao existe mais no fluxo ativo

- Modo legado online.
- Botao ou toggle de ativacao online.
- Teste de conexao online.
- Fallback automatizado para modo online dentro da Luna.

## Privacidade

- Nao registrar credenciais, tokens, chaves ou cabecalhos sensiveis no chat.
- Sanitizar qualquer contexto antes de persistir historico ou log.
- Limitar o conteudo aos dados autorizados pela interface e pelo contexto local.

## Historico

```text
user://luna_chat_history.json
user://luna_ai_logs.jsonl
user://luna_ai_usage.json
```

O historico continua opcional e sanitizado.

## Extensao futura

Para criar novas intencoes locais:

1. Abra `res://ai/local_assistant.gd`.
2. Adicione a nova intencao e os exemplos de frase.
3. Registre o `Callable` correspondente.
4. Consulte apenas `AIContextProvider`.
5. Crie ou ajuste testes locais.

## Verificacao

As verificacoes devem permanecer headless e locais. Esta versao nao depende de credencial online.
