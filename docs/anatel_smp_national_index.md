# Índice nacional Anatel SMP

## Proveniência

- Provedor: Agência Nacional de Telecomunicações — Anatel.
- Dataset: Estações do Serviço Móvel Pessoal (SMP).
- Fonte: `https://www.anatel.gov.br/dadosabertos/paineis_de_dados/outorga_e_licenciamento/estacoes_smp.zip`.
- Last-Modified oficial: `Tue, 25 Aug 2026 10:56:40 GMT`.
- ZIP: 91.381.047 bytes.
- SHA-256 do ZIP: `976C4BB3ABFC8F777D54D595DF1D944E12550FE653CB67EFB649ECABF8903051`.
- Linhas lidas: 3.292.893; malformadas: 0; coordenadas inválidas/fora do
  recorte documentado: 3; linhas selecionadas: 3.285.081.
- Regra: UF brasileira oficial, situação licenciada, gerações 2G/3G/4G/5G e
  coordenadas decimais válidas dentro dos limites nacionais declarados.

Campos vazios permanecem vazios no índice e a UI mostra “Não informado pela
fonte”. Coordenadas, operadoras, gerações e situação não são inferidas.

## Artefato final z10

- Versão: `anatel-smp-national-webmercator-z10-v2`.
- Manifesto SHA-256:
  `46023754CAB593816D7B1FB2724B4D080D3535ED0A9E7A6F05E6D9D5986B3FBA`.
- Conteúdo agregado SHA-256:
  `683B0101CBF2A95A05EB9C7FF8BF90DFACF33040F272209DDE70E9BCD3E655B9`.
- 3.366 células z10 e três arquivos de cluster z4/z6/z8.
- 3.369/3.369 arquivos validados por tamanho e SHA-256; zero divergências.
- 291.348 registros únicos estação/geração; 115.018 ERBs físicas; 27 UFs.
- Gerações: 2G 54.513; 3G 71.522; 4G 105.670; 5G 59.643.
- Operadoras: Claro 95.423; TIM 87.935; Vivo 99.085; outras 8.905.
- Índice: 153.414.196 bytes; diretório com manifesto/sidecar: 155.907.528 bytes.
- Maior célula: 12.591 registros e 6.704.209 bytes.

## Formato e consulta

O manifesto contém metadados, descritores de células e descritores dos
clusters. Cada descritor registra caminho relativo, tamanho, SHA-256, bbox e
facetas. O runtime:

1. carrega e valida somente o manifesto;
2. em zoom 4–6 usa clusters nacionais z4/z6;
3. em zoom 7–10 usa clusters regionais z8;
4. em zoom 11+ abre as células z10 visíveis e uma borda vizinha;
5. filtra os pontos pelo bbox exato antes de desenhá-los.

O fallback regional existe somente para indisponibilidade do índice nacional e
é identificado como `regional_fallback`; não representa o Brasil inteiro.

## Memória e desempenho

O gerador usa SQLite temporário fora de `res://`, `temp_store=FILE`, cache de
páginas configurado para 64 MiB e lotes de 5.000 linhas. Pico medido no build:
113.954.816 bytes.

O runtime mantém LRU de até 32 células, 20.000 registros e 16 MiB de JSON de
origem. `cache_state()` expõe `cache_bytes`, `max_cache_bytes`, registros,
células e estimativa de memória de Variants. Uma única célula acima do teto
nunca é descartada silenciosamente; o excesso fica explícito na métrica. No
artefato atual, o maior shard fica abaixo dos tetos de registros e bytes.

O benchmark Godot 4.7.1 headless do maior shard registrou 2.776 ms e delta/pico
de 86.473.148 bytes. Após a consulta densa, o LRU reteve duas células, 2.327
registros e 1.212.343 bytes de JSON de origem; a troca para célula distante
recuperou dados e exerceu a evicção. Limites de aceite do teste: 15.000 ms e
512 MiB de delta/pico. Esses números validam o runtime local, mas não removem
o gate de segurança da API de negócio nem aprovam release.

## Limite semântico

Uma ERB licenciada/presente no catálogo não prova intensidade, disponibilidade
ou qualidade de sinal em tempo real. O mapa exibe infraestrutura licenciada e
mantém essa ressalva na legenda e no painel de detalhes.
