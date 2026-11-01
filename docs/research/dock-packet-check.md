# DockSwipe: conferência da serialização

Pesquisa independente em 1º de novembro de 2026. Esta nota descreve código de terceiros, não um contrato público da Apple. Não houve execução, postagem de eventos ou teste de comportamento nesta investigação. A inclusão do payload é uma hipótese para a falha observada, não uma causa comprovada. Fontes fixadas: [serializador FasterSwiper](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/gesture-serialization.cc), [estruturas FasterSwiper](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/macos-private.h), [companion](https://github.com/scottlamb/macos-trackpad-companion/blob/519edcd56295d1b037afd0c1bef3a39482660866/src/output.rs).

## CGEventData versão 2

O FasterSwiper obtém os dados de um evento existente com `CGEventCreateData`, interpreta e preserva os demais campos, acrescenta ou substitui o campo **4205** com o blob HID, serializa e chama `CGEventCreateFromData`. Não é necessário presumir um sufixo fixo ou eliminar bytes existentes. [Fonte](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/gesture-serialization.cc#L200-L277), [inserção](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/gesture-serialization.cc#L449-L470).

| Elemento externo | Codificação observada |
|---|---|
| Prefixo | `int32` big-endian igual a 2. |
| Cada campo | `uint16` BE tamanho; `uint16` BE com tag nos 2 bits superiores e ID nos 14 inferiores; imediatamente seguido pelo valor, sem terminador na implementação. |
| Tag 0 | Tamanho 1 representa `int64` BE; tamanho >1 representa blob de exatamente esse número de bytes. |
| Tag 1 | Tamanho 1; `int32` BE. |
| Tag 3 | Tamanho 1 para `float32` BE, tamanho 2 para `float64` BE. Tag 2 é rejeitada pelo parser da fonte. |
| Blob 4205 | `4205 = 0x106d`, tag 0. Com filho fluid apenas, header `00 44 10 6d` (68 bytes); com velocity, `00 60 10 6d` (96 bytes). A ordem e a quantidade de outros campos podem variar; preserve-os. |

**Endianness misto:** os headers/valores do contêiner são BE, mas o blob é a cópia bruta das estruturas C packed, em ordem nativa do host. Nos Macs x86-64 e arm64 isso significa little-endian para os inteiros internos. [Fonte](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/gesture-serialization.cc#L286-L384).

## Blob IOHID: offsets e valores

Todos os offsets são relativos ao início de cada estrutura, sem padding. As estruturas e tamanhos abaixo são os do código fixado; não há garantia de ABI pública. [Fonte](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/macos-private.h#L108-L182).

| Estrutura | Offset e valor |
|---|---|
| Queue, 28 bytes | `0:u64 timestamp`, `8:u64 senderID=0`, `16:u32 options=0`, `20:u32 attributeLength=0`, `24:u32 eventCount=1 ou 2`. |
| Base, 16 bytes | `0:u32 size`, `4:u32 type`, `8:u32 options`, `12:u8 depth`, `13..15: zeros`. |
| Fluid, 40 bytes | Base: size 40, type 23, options `(phase & 0xff) << 24`, depth 0. Depois `16:i32 positionX`, `20:i32 positionY`, `24:i32 positionZ=0`, `28:u32 swipeMask`, `32:u16 motion`, `34:u16 flavor=3`, `36:i32 progress`. |
| Velocity, 28 bytes | Base: size 28, type 9, options 0, depth 1. Depois `16:i32 velocityX`, `20:i32 velocityY`, `24:i32 velocityZ=0`. |

Os valores de posição, progresso e velocidade são fixos assinados 16.16: truncar `double * 65536` para `int32`; se o resultado for zero para entrada diferente de zero, a fonte usa +1 ou -1 conforme o sinal. Ao converter, tratar valores não finitos ou fora do intervalo para não produzir overflow. O autor acrescenta velocity quando `vx != 0 || vy != 0 || phase == 4`, inclusive velocity zero em Ended; Cancelled sozinho não força velocity. A queue usa o timestamp do CGEvent e, quando zero, `mach_absolute_time()`. [Fonte](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/gesture-serialization.cc#L21-L28), [geração](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/gesture-serialization.cc#L386-L446).

| Campo do CGEvent usado para criar o blob | Valor/observação |
|---|---|
| 132 phase | Began 1, Changed 2, Ended 4, Cancelled 8; transferir para os bits altos das options da base fluid. |
| 123 motion | 1 horizontal, 2 vertical; a estrutura aceita `u16`, mas FasterSwiper enumera apenas 0, 1 e 2. Não extrapolar para pinch 3 como se esta fonte o validasse. |
| 124 progress | Double do evento copiado ao fixed 16.16 do blob. |
| 125, 126 | Posições X/Y, double, copiadas ao blob. |
| 129, 130 | Velocidades X/Y, double, copiadas ao filho velocity. |
| 115 | Máscara extraída pelo FasterSwiper: 0 desconhecido, up 1, down 2, left 4, right 8. **Cuidado:** WebKit também nomeia campo 134 como swipe mask; não inferir que IDs 115 e 134 sejam intercambiáveis. |

Os campos externos 55=30, 110=23, 132, 123 e 124 são estabelecidos também pelo [companion](https://github.com/scottlamb/macos-trackpad-companion/blob/519edcd56295d1b037afd0c1bef3a39482660866/src/output.rs#L1621-L1659). Essa fonte escreve em 135 o bit pattern de Float32 do progresso como inteiro assinado com extensão de sinal e escreve 129/130 no fim. Ela recomenda fonte combinada, timestamp e `kCGSessionEventTap`. Sua descrição de necessidade de campos e de efeito no Dock é relato do projeto, não verificação independente neste ambiente.

## Limites e pontos de diagnóstico

- A fixture usa deslocamento vertical `-200`; o emissor converte para progresso positivo. A fonte companion relata que progresso vertical positivo corresponde a dedos para cima e Mission Control; isso confirma a convenção escolhida, não o efeito no ambiente de teste. [Fonte](https://github.com/scottlamb/macos-trackpad-companion/blob/519edcd56295d1b037afd0c1bef3a39482660866/src/output.rs#L1451-L1457).
- Em outro caminho real, FasterSwiper inicia o gesto com progresso epsilon assinado diferente de zero e preenche velocidade somente no eixo ativo; o emissor inicial começava em zero e preenchia ambos os eixos; a versão posterior começa com o primeiro movimento não nulo. O companion preenche ambos, portanto diferenças são candidatos a comparação, não causas demonstradas. [Início](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/engine/space-switch-operation.cc#L181-L191), [velocidade](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/event.cc#L173-L213).
- O cabeçalho WebKit nomeia 134 como swipe mask, 136 como swipe gesture flag bits e 139 como zoom delta X, mas não estabelece que devam ser preenchidos para DockSwipe nem que 134 seja uma cópia da fase. FasterSwiper não os escreve em seu construtor citado acima. [Cabeçalho](https://github.com/WebKit/WebKit/blob/e20307a8c14f4f832a193739a19f02ba159100d4/Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h#L51-L65).
- O `post_dock_swipe` do companion no commit indicado **posta o CGEvent cru**, sem acrescentar o campo 4205. O [playback-gesture do FasterSwiper](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/src/tools/playback-gesture.cc#L20-L49) também posta campos crus. Portanto, a presença do serializador não comprova que o payload seja universalmente necessário; versões do SO, fonte, sequência, permissões e contexto podem importar. Tampouco os dois caminhos provam que o mesmo gesto funcione na máquina alvo.
- A fonte companion recomenda progresso **acumulado**, Began → Changed em tempo real → Ended/Cancelled e relata que sinal e velocidade na soltura influenciam o resultado; direção e limiar exigem observação. [Fonte](https://github.com/scottlamb/macos-trackpad-companion/blob/519edcd56295d1b037afd0c1bef3a39482660866/src/output.rs#L1437-L1457). O valor de 135, event source, timestamp e entrada do tap devem ser conferidos junto com o blob.
- O blob serializado é 68 bytes com um filho e 96 com dois: não confundir com o tamanho do campo externo, cabeçalho do campo ou número de filhos. O `eventCount`, cada `size`, depth e opções devem coincidir com os dados. A falta de ação com getters corretos não prova que o Dock aceitou nem consumiu o evento; validação de round-trip não substitui resultado visual ou observável no Dock.
- O README do FasterSwiper declara suporte ao macOS 26, mas diz que outras versões anteriores são não testadas; sua alegação não é evidência de sucesso em macOS 15. [Fonte](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/README.md#L30-L44).

## Proveniência

Atualização de execução da tarefa principal: a combinação de payload, movimento
inicial não nulo e evento Gesture companheiro passou os testes de Mission
Control e pinça para Aplicativos/Mesa no
[run 41302325635](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41302325635).
O comparativo anterior isolou o evento companheiro como correção para Mission
Control no cenário testado; ele não isola a necessidade do payload em todas as
versões. Os resultados completos estão em [VALIDATION.md](../VALIDATION.md).

O repositório FasterSwiper fornece [Apache-2.0](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/LICENSE). Uma adaptação deve distribuir a licença aplicável, manter avisos pertinentes e identificar alterações conforme seus termos. O cabeçalho `macos-private.h` remete explicitamente a [ATTRIBUTION.md](https://github.com/mgbowen/FasterSwiper/blob/3665350bbd05cb7245063ade5143f155d8228d27/ATTRIBUTION.md), que lista outras origens e licenças: verificar quais se aplicam ao material efetivamente adaptado, em vez de presumir que todo trecho tenha somente autoria FasterSwiper. Uma licença MIT para o projeto próprio não elimina as condições dos componentes Apache distribuídos. Nenhum código do Mac Mouse Fix foi consultado para esta nota.
