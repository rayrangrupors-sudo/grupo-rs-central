# Relatório de erros e bugs da API Grupo RS

**Data:** 13/08/2026  
**Ambiente:** API REST do Grupo RS novo  
**Versão do sistema analisada:** 3.9.130

## Resumo executivo

A autenticação, as consultas e o cadastro/edição de equipamentos funcionam pela API. O principal problema encontrado está na rota de criação de veículos e associação de equipamentos: em teste real, a API retornou **HTTP 500**. O sistema confirmou que a transação não havia sido publicada e usou o portal web como fallback, concluindo o cadastro sem duplicar a associação.

## 1. Falha crítica — HTTP 500 ao criar veículo/associação

**Endpoint:** `POST /api_rest_app/endpoints/veiculos.php`  
**Severidade:** Crítica  
**Impacto:** impede o cadastro somente pela API de uma placa nova e da associação com o equipamento.

### Comportamento observado

1. O equipamento novo foi criado pela API.
2. O sistema enviou o cadastro da placa com o identificador do equipamento.
3. A API respondeu HTTP 500.
4. Uma consulta posterior não encontrou a associação criada, portanto o sistema não repetiu o POST.
5. O fallback web criou a placa e a associação.
6. A API passou a consultar a associação normalmente.
7. A alteração e a restauração da placa foram confirmadas pela API.

### Diagnóstico provável

O servidor da API possui erro interno na rotina de criação de veículos/associações. Como a resposta HTTP 500 é genérica, o motivo interno — validação, banco de dados, relacionamento ou regra de negócio — não foi exposto.

### Recomendação para o fornecedor da API

- Registrar o erro interno com correlação por requisição.
- Retornar JSON com `error`, `message` e código de validação útil.
- Validar previamente `placa`, `status` e `codEquipamento` e retornar 400/409 quando aplicável.
- Garantir transação atômica: ou veículo e associação são gravados, ou nada é gravado.
- Testar o mesmo payload no endpoint de homologação.

## 2. Inconsistência no trajeto diário

**Endpoint:** `GET /api_rest_app/endpoints/v1/veiculos/trajeto-dia.php`  
**Severidade:** Alta  
**Comportamento:** para um veículo retornado pelas consultas de veículos e localização, a API respondeu HTTP 403 com “Veiculo nao pertence ao cliente”.

Isso indica divergência entre a autorização usada pelas rotas de veículos/localização e a autorização usada pela rota de trajeto. O mesmo veículo é aceito em uma rota e rejeitado em outra.

## 3. Busca por campo inconsistente

**Severidade:** Média  

- A consulta de equipamento por número de série funcionou.
- A consulta de placa/cliente não retornou de forma consistente na rota de equipamentos.
- A rota de veículos indexou a placa e permitiu recuperar o equipamento associado.

O sistema passou a consultar primeiro equipamentos e, quando necessário, veículos, antes de usar o portal web.

## 4. Paginação operacionalmente extensa

**Severidade:** Alta para uso operacional  

A listagem completa de veículos/localizações pode exigir muitas páginas e ultrapassar o tempo aceitável da tela. Antes da correção, a consulta podia permanecer por vários minutos.

Foi implementado no sistema:

- limite de 15 segundos por requisição;
- limite de 45 segundos por varredura paginada;
- detecção de página repetida;
- fallback web quando a API não termina dentro do limite.

## 5. Limitações e respostas esperadas

As respostas abaixo foram consideradas comportamentos previstos, não bugs críticos:

- payload vazio: HTTP 400;
- equipamento ou veículo inexistente: HTTP 404;
- duplicidade de equipamento/placa: HTTP 409;
- exclusão pela API: HTTP 405, pois as rotas de DELETE estão bloqueadas.

## 6. Falhas de integração corrigidas no sistema local

Também havia um problema no cliente: cancelar `HTTPRequest` não garantia a emissão de `request_completed`, deixando o fluxo preso em `await`. O cliente agora usa prazo controlado por frames, cancela a requisição e encerra o fluxo com fallback seguro.

Além disso, o cadastro do equipamento passou a usar a API primeiro e o portal web somente quando a API falha antes de confirmar uma gravação.

## 7. Testes executados

- Login e consulta de usuário: aprovados.
- Consulta de veículos, equipamentos e localização: aprovadas quando consultadas por página/critério.
- Cadastro real de equipamento novo pela API: aprovado.
- Alteração e restauração de equipamento novo: aprovadas.
- Cadastro real de placa/associação: API retornou HTTP 500; fallback web aprovado.
- Consulta posterior da associação pela API: aprovada.
- Alteração e restauração da placa: aprovadas.
- Testes de contrato, idempotência, paginação e payloads: aprovados.

Nenhum equipamento ou veículo existente foi alterado. Foram usados identificadores exclusivos de teste.

## Conclusão

O sistema está protegido contra o HTTP 500 e funciona de ponta a ponta usando API como principal recurso e web como fallback. A correção local não elimina o erro interno da API; ela evita travamento, duplicidade e perda do cadastro. A correção definitiva do HTTP 500 depende do fornecedor da plataforma REST.

## Atualização após correção do desenvolvedor

O desenvolvedor informou ajustes em `veiculos.php` e `trajeto-dia.php`.

### Validação independente executada

Em 13/08/2026, foi repetida uma consulta somente leitura ao endpoint:

`GET /endpoints/v1/veiculos/trajeto-dia.php?veiculo=18593&data=2026-08-13&skip=0&take=10`

Resultado: **HTTP 200**, resposta JSON válida, perfil administrador identificado e pontos de trajeto retornados. A correção do erro HTTP 403 do trajeto foi confirmada.

### Pendência de validação

O teste API-only posterior identificou a causa exata do erro no ambiente inicialmente consultado: o cliente não enviava `codTipoVeiculo`, e o banco recusava `NULL` na coluna obrigatória `TB_Veiculo.CodTipoVeiculo`.

Correção aplicada no cliente: quando o tipo do veículo é `Carro`, o payload passa a incluir `codTipoVeiculo=1`; tipos desconhecidos continuam sem valor inventado.

Novo teste real após a correção:

- equipamento inédito criado pela API: HTTP 201;
- placa/associação inédita criada pela API: HTTP 201;
- nenhum fallback web utilizado;
- alteração de placa pela API: HTTP 200;
- restauração da placa pela API: HTTP 200;
- consulta final do equipamento e associação: confirmada.

Com isso, o HTTP 500 foi reproduzido, diagnosticado e eliminado no fluxo do sistema.

## Atualização — localização por status

Foi identificado um bloqueio adicional no cliente: aparelhos com status `Instalado` ou `Inativo` eram encaminhados diretamente para a plataforma web. Se essa fonte não retornasse a linha, o sistema informava que o aparelho não havia sido encontrado, mesmo existindo na API.

Correção aplicada: todos os status do Grupo RS novo agora consultam a API como fonte primária. O portal web continua disponível como fallback quando a API falhar ou não fornecer coordenadas.

Teste real somente leitura aprovado para a mesma associação real nos status `Instalado`, `Inativo`, `Manutencao`, `Reserva` e `Estoque`: todos retornaram localização válida pela API.
