# Marcadores de ERB v3

Conjunto visual para ERBs licenciadas exibidas sobre OpenStreetMap. A cor
identifica somente a prestadora; não representa intensidade ou cobertura de
sinal em tempo real.

## Assets integrados pelo canvas

Os quatro PNGs em `production/compact/` são RGBA 256 × 256:

- Claro — 6.421 bytes — SHA-256
  `7865CD2E7E8B4B0B7074E0E3921BF551742D6F8F1216BF21E09AAF12568AF784`;
- neutro/Outras — 6.419 bytes — SHA-256
  `54C8C574E9DE5AB52A1B781CDA3E024F5D022246665A082A839C4D780AADD777`;
- TIM — 6.423 bytes — SHA-256
  `E3E124E7F971A379BF7992121A99C9D8B1ED69710A0716F20B160D7A06E68BCA`;
- Vivo — 6.408 bytes — SHA-256
  `AC738939A76BCE1D87BF34A796DF58D805A99D032B18774689FB10241C3B9FA9`.

## Assets não integrados

`production/selected/` contém candidatos visuais de seleção. O canvas usa o
compacto mais um rótulo vetorial desenhado em tempo real, que mantém a sigla
legível no tamanho operacional. `review/` contém apenas a prancha comparativa
40/48/56 px e não deve ser referenciado nem empacotado como recurso de runtime.
