# Mapa Grande

Esta pasta concentra o código do mapa e evita que manutenção de localização
altere estoque, autenticação, Firebase ou o botão **Sair**.

## Responsabilidade de cada script

- `big_map_canvas.gd`: desenho e interação visual; não acessa rede.
- `big_map_config.gd`: cidade inicial, zoom, regiões e provedor de tiles.
- `map_projection.gd`: matemática geográfica Web Mercator e distâncias.
- `map_tile_provider.gd`: URL, cache, atribuição e decodificação dos tiles de
  satélite World Imagery.
- `map_region_service.gd`: identificação e contagem de regiões/ERBs.
- `vehicle_status_resolver.gd`: estado Ligado, Desligado ou Desatualizado.

## Fluxo de manutenção

1. Busca/API devolve a localização do veículo.
2. `vehicle_status_resolver.gd` classifica a comunicação.
3. O catálogo Anatel fornece as ERBs próximas.
4. `map_tile_provider.gd` fornece o mapa-base de satélite.
5. `big_map_canvas.gd` apenas desenha as camadas recebidas.

Uma mudança em um desses passos deve permanecer no script responsável. O
dashboard coordena o fluxo, mas não deve voltar a concentrar as regras.
