# Fonte oficial Anatel — Estações SMP

## Origem e artefato auditado

- Conjunto: Estações licenciadas do Serviço Móvel Pessoal (SMP).
- Endpoint oficial: `https://www.anatel.gov.br/dadosabertos/paineis_de_dados/outorga_e_licenciamento/estacoes_smp.zip`.
- Página institucional: `https://www.gov.br/anatel/pt-br/regulado/outorga/telefonia-movel/estacoes-radio-base`.
- ZIP auditado em 25/08/2026: 91.381.047 bytes.
- `Last-Modified`: `Tue, 25 Aug 2026 10:56:40 GMT`.
- SHA-256: `976C4BB3ABFC8F777D54D595DF1D944E12550FE653CB67EFB649ECABF8903051`.
- Entrada: `Estacoes_SMP.csv`, 984.082.927 bytes descompactados.
- O ZIP preservado durante a auditoria ficou em
  `%TEMP%\grupo-rs-anatel-audit-20260825\estacoes_smp.zip`.

O catálogo ativo é o índice particionado
`data/anatel_smp_national_index/manifest.json`, derivado dessa varredura
completa. Ele cobre o Brasil e mantém clusters z4/z6/z8 e células z10. O
catálogo `data/anatel_smp_regional.json` permanece somente como fallback
regional declarado; nunca representa o catálogo nacional. Ambos registram
URL, hash, data, escopo, regra, contagens e versão do schema em `metadata`.

Contagens, hashes, formato, partições e política de memória do índice ativo
estão em [`anatel_smp_national_index.md`](anatel_smp_national_index.md).

## Varredura completa e falhas explicadas

A leitura foi streaming, delimitada por ponto e vírgula e compatível com campos
entre aspas. Nenhuma execução carregou os 3.292.893 registros em memória.

1. A primeira tentativa com `TextFieldParser` puro foi interrompida após cerca
   de três minutos por baixo desempenho. O ZIP e o JSON anterior permaneceram
   intactos.
2. Uma tentativa C# falhou antes da primeira linha: `Add-Type
   -ReferencedAssemblies` substituiu referências padrão e deixou indisponíveis
   `Dictionary<>`, `List<>` e `ZipFile`. Resultado: 0 linhas processadas e
   nenhum artefato substituído.
3. A primeira execução do importador PowerShell encontrou nomes de coluna
   corrompidos pela leitura ANSI de literais UTF-8 sem BOM (`Número Estação`
   virou mojibake). Resultado: 0 linhas selecionadas. A correção normaliza os
   cabeçalhos Unicode para Form D e usa nomes ASCII estáveis.
4. A varredura auditável concluída leu 3.292.893 linhas, 0 linhas malformadas e
   0 coordenadas inválidas no recorte MA. Linhas regionais licenciadas por
   geração antes da deduplicação: 2G 2.139; 3G 2.052; 4G 2.877; 5G 561.
5. O importador repetiu a leitura completa e selecionou 7.629 linhas no recorte.
   Após deduplicação por estação/prestadora/geração/coordenada e agregação de
   frequências/tecnologias, o índice contém 667 ERBs: 112 2G, 170 3G, 247 4G e
   138 5G.

Durante a importação somente as ERBs deduplicadas do recorte ficam em memória;
linhas-fonte continuam sendo descartadas a cada iteração. A escrita usa arquivo
temporário e só substitui o destino depois de concluir.

## Regra regional de fallback e campos

Regra de seleção registrada no JSON:

- `UF = MA`;
- `Situacao = LICENCIADA`;
- geração em 2G, 3G, 4G ou 5G;
- latitude decimal entre -7,25 e -4,0;
- longitude decimal entre -49,0 e -46,5;
- coordenadas decimais válidas e diferentes de 0,0.

Mapeamento preservado:

| Uso no app | Campo oficial |
|---|---|
| Identificador | `Número Estação` |
| Coordenadas | `Latitude decimal`, `Longitude decimal` |
| Prestadora/entidade | `Empresa Estação`, `Entidade` |
| Tecnologia | `Geração`, `Tecnologia`, `Tipo de Tecnologia 5G` |
| Município/UF | `Município-UF`, `UF` |
| Situação | `Situacao` |
| Datas | `Data Primeiro Licenciamento`, `Data Licenciamento`, `Data Validade` |
| Frequências | `Frequência (MHz)`, inicial/final, TX/RX |
| Faixas | `Banda_MHZ`, `Faixa Estação`, `Subfaixa Estação` |
| Dados locais | endereço, número, complemento, bairro, classe de infraestrutura |

Campos que a fonte deixa vazios permanecem vazios no índice. A UI deve mostrar
exatamente “Não informado pela fonte”; município, operadora, tecnologia, status
e coordenadas nunca são completados por proximidade ou inferência. Colunas do
CSV não necessárias à visualização (Fistel, CNPJ/CPF, serviço, setor, ato,
emissão, CEP, caráter, código nacional/IBGE e nome expandido da UF) são
descartadas do índice, mas continuam no ZIP preservado.

## Atualização reproduzível

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\atualizar_base_anatel.ps1 `
  -ExistingZip "$env:TEMP\grupo-rs-anatel-audit-20260825\estacoes_smp.zip" `
  -Scope Regional
```

Sem `-ExistingZip`, o script baixa o endpoint oficial. O atualizador valida os
cabeçalhos esperados e falha sem substituir o catálogo se o schema mudar.

## Limite de interpretação

Uma ERB licenciada e presente no cadastro oficial não comprova intensidade,
disponibilidade ou qualidade de sinal em tempo real. O mapa mostra
infraestrutura licenciada separada dos veículos; não transforma o cadastro em
medição de cobertura.
