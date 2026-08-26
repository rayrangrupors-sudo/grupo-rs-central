# Localização de veículos

O controlador ativo da cena principal é
`../big_map/big_map_tracking_layout.gd`. A interface autocontida fica em
`../big_map/big_map_tracking_view.gd`; `location_layout.gd` permanece apenas
como implementação anterior para referência e compatibilidade.

O nome `big_map_tracking_layout.gd` é histórico: ele é o controller ativo e
herda o dashboard. A construção visual pertence a `big_map_tracking_view.gd`.

`vehicle_location_integration.gd` é a camada de coordenação entre a
identificação do veículo, a posição retornada, as ERBs próximas e a operadora
do chip. Ela não acessa rede nem cria marcadores; recebe dados dos módulos
especializados e produz o estado que o único canvas integrado exibe.

As responsabilidades reutilizáveis do Mapa Grande ficam em
`../big_map/`: canvas, projeção geográfica, tiles, regiões e classificação de
status. A localização não deve implementar novamente essas regras. A tela
integrada mantém as ERBs e todos os veículos válidos do filtro no mesmo canvas.

O campo público `query_input` pesquisa exclusivamente por placa ou número de
série. `normalize_location_query` remove máscara, espaços e diferença de caixa;
`describe_location_query` identifica o tipo; `find_exact_vehicle` só retorna
uma linha quando o campo correspondente é exatamente igual após normalização.
O fallback da seleção visual permanece separado e nunca é usado para decidir o
resultado de uma pesquisa. Assim, “não encontrado” mantém a seleção vazia.

O arquivo `src/location_layout.gd` foi mantido apenas como compatibilidade
para referências antigas; a cena principal carrega diretamente o novo módulo
do Mapa Grande.

## Limites observados da API de rastreamento (25/08/2026)

- busca `q` por placa retornou correspondência exata; item inexistente retornou
  zero linhas;
- série não foi indexada por `q`; o fallback paginado por veículos permanece
  necessário (amostra: 2 páginas, 54 linhas, 964 ms);
- o perfil testado recebeu `403` em equipamentos;
- a amostra de localização trouxe coordenadas/datas válidas, mas não expôs
  operadora, chip, APN ou cliente;
- o contrato auditado não garante busca por cliente; por isso o campo ativo não
  anuncia nem encaminha nomes de cliente;
- operadora só pode ser exibida quando houver ICCID/APN local e resolução por
  integração autorizada; quando ausente, não deve ser inferida;
- a especificação OpenAPI pública não documenta `q/skip/take` em localização,
  embora o servidor tenha aceitado `q` por placa na data da auditoria.

Há um incidente de segurança separado: um exemplo público da especificação
autenticou em dados reais. Nenhuma credencial é reproduzida aqui. O
administrador deve rotacionar/desabilitar a conta, remover valores reais dos
exemplos e auditar tokens/logs antes de considerar publicação.
