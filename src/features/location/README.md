# Localização de veículos

`location_layout.gd` é a camada ativa da tela de localização. Ela organiza a
interface e coordena as funções de consulta existentes no dashboard.

`vehicle_location_integration.gd` é a camada de coordenação entre a
identificação do veículo, a posição retornada, as ERBs próximas e a operadora
do chip. Ela não acessa rede nem cria marcadores; recebe dados dos módulos
especializados e produz o estado que o único canvas integrado exibe.

As responsabilidades reutilizáveis do Mapa Grande ficam em
`../big_map/`: canvas, projeção geográfica, tiles, regiões e classificação de
status. A localização não deve implementar novamente essas regras. A tela
integrada mantém as ERBs no mesmo canvas e envia somente o veículo selecionado
para a camada de rastreamento.

O arquivo `src/location_layout.gd` foi mantido apenas como compatibilidade
para referências antigas; a cena principal carrega diretamente este módulo.
