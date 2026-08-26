# Bloqueio crítico de segurança — OpenAPI

## PROBLEMA ENCONTRADO

**Arquivo/Origem:** documentação OpenAPI pública da API
**Problema:** exemplo de login contém credencial ativa e permite emissão de JWT
**Impacto:** acesso indevido ao escopo real de veículos/localizações
**Ação recomendada:** rotação/desativação, auditoria de logs/tokens, exemplo inerte e revisão de acesso

Nenhuma credencial, token, identidade ou dado operacional é reproduzido neste
registro. A auditoria foi interrompida após comprovar o risco. Não realizar
novas autenticações até o administrador da API:

1. desabilitar ou rotacionar imediatamente a conta exposta;
2. revogar/auditar tokens emitidos e revisar logs de acesso;
3. substituir o exemplo por valores inertes ou dados sintéticos;
4. restringir a documentação quando apropriado;
5. revisar permissões dos endpoints de login, perfil, veículos e localizações;
6. autorizar uma nova validação controlada após a correção.

O Mapa Grande e qualquer release relacionado permanecem **NÃO APROVADOS** até
aceite explícito do administrador da API. Enquanto isso, somente testes
offline/locais que não autenticam podem ser executados.
