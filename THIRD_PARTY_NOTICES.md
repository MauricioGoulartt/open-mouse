# Componentes e referências

O Open Mouse é uma implementação própria. Não inclui código, recursos visuais,
configurações ou sistemas de licença do Mac Mouse Fix. Esse aplicativo foi usado
como referência de comportamento, conforme a pesquisa em `docs/research/`.

## macos-trackpad-companion — Scott Lamb

A construção dos eventos DockSwipe em `Sources/OpenMouse/ActionEmitter.swift`
foi adaptada do protocolo e implementação de `src/output.rs`, commit
`519edcd56295d1b037afd0c1bef3a39482660866`:
https://github.com/scottlamb/macos-trackpad-companion

O projeto oferece licença MIT ou Apache-2.0. Para esta adaptação, foi escolhida
a licença MIT, reproduzida integralmente em `LICENSES/ScottLamb-MIT.txt`.
O upstream atribui sua descoberta do formato dos eventos ao WebKit e ao
FasterSwiper; essas referências e os limites de validação estão registrados
em `docs/research/macos-native-gesture-protocol.md`.

## WebKit e cabeçalhos da Apple

Os identificadores e significados de campos privados de eventos foram
consultados em cabeçalhos de teste do WebKit e em cabeçalhos do SDK da Apple.
Nenhum arquivo desses projetos foi incorporado ao Open Mouse. Protocolos
privados podem mudar entre versões do macOS.
