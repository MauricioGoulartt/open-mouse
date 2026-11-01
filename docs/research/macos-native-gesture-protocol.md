# Gestos nativos no macOS: evidência e lacunas

Pesquisa de 1º de novembro de 2026 para implementação própria. Foram consultadas fontes Apple, WebKit e projetos independentes; a investigação também consultou a interface e constantes do Mac Mouse Fix. Nenhuma implementação do Mac Mouse Fix foi incorporada. Esta pesquisa não executou testes, instalações ou interações com a UI; as evidências de execução relatadas pela tarefa principal aparecem abaixo.

**Resultado:** as fontes localizadas descrevem suficientemente a semântica dos gestos recebidos pelos aplicativos e a criação pública de eventos de rolagem, e revelam campos privados usados pelo WebKit em testes para gestos; **não especificam um protocolo público completo nem comprovam injeção global em outros processos ou no Dock**. Os valores privados identificados estão abaixo; funcionamento global ainda requer validação. Criar rolagem sintética é demonstrado; isso não demonstra que seja equivalente a pinça ou gesto do Dock.

## Contratos documentados

| Entrada | Semântica evidenciada | Limite para emissão global |
|---|---|---|
| Magnify | `magnification` é variação relativa; somar 1 para obter fator da etapa. Entrega a `magnifyWithEvent:`. | Apple documenta recebimento, não um construtor público de CGEvent de pinça nesta pesquisa. |
| Rotate | `rotation` é incremento em graus no sentido anti-horário; entrega a `rotateWithEvent:`. | Campo privado identificado abaixo; emissão global não comprovada. |
| Swipe | `deltaX`: -1 direita, +1 esquerda; `deltaY`: -1 baixo, +1 cima. Apple descreve entrega a `swipeWithEvent:`. | Isso não estabelece protocolo para animação interativa de Spaces ou Mission Control no Dock. |
| Smart zoom | Existe `NSEventTypeSmartMagnify` e `smartMagnifyWithEvent:`. | Tipo AppKit é contrato de recebimento; criação e postagem global não comprovadas. |
| Rolagem | `CGEventCreateScrollWheelEvent` cria evento de até três eixos; unidades de linha ou pixel. Pixel é interpretado por muitos apps como rolagem suave. | O construtor e `CGEventPost` são públicos; o resultado varia conforme o aplicativo e não implica eventos de pinça. |

Fontes: [Apple: Handling Trackpad Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html), [tipos AppKit](https://developer.apple.com/documentation/appkit/nsevent/eventtypemask/rotate), [criação de rolagem](https://developer.apple.com/documentation/coregraphics/cgeventcreatescrollwheelevent), [unidades](https://developer.apple.com/documentation/coregraphics/cgscrolleventunit), [postagem](https://developer.apple.com/documentation/coregraphics/cgevent/post%28tap%3A%29?language=objc).

## Campos e fases

| Campo | Contrato verificado |
|---|---|
| `kCGScrollWheelEventDeltaAxis1/2` | Deslocamento vertical/horizontal, inteiro. |
| `kCGScrollWheelEventFixedPtDeltaAxis1/2` | Deslocamento em formato fixo assinado 16.16; getter double converte o valor. |
| `kCGScrollWheelEventPointDeltaAxis1/2` | Deslocamento em pixels, inteiro. |
| `kCGScrollWheelEventIsContinuous` | Não zero indica pixels; zero indica linhas. |
| `kCGScrollWheelEventScrollPhase`, `kCGScrollWheelEventMomentumPhase` | Campos nomeados no Core Graphics; WebKit usa constantes de fase próprias de scroll/momentum ao construir eventos para testes. A documentação pública encontrada não estabelece valores numéricos de todos os campos nem sua equivalência a campos privados de gestos. |
| `NSEventPhase` | None, Began, Stationary, Changed, Ended, Cancelled, MayBegin; são fases do contrato AppKit. Não presumir que os valores binários ou as sequências dos campos privados do Dock sejam idênticos. |

Fontes: [CGEventField](https://developer.apple.com/documentation/coregraphics/cgeventfield?changes=_3_1___9_2&language=objc), [NSEventPhase](https://developer.apple.com/documentation/appkit/nsevent/phase-swift.struct?language=objc), [WebKit EventSenderProxy](https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/mac/EventSenderProxy.mm).

A Apple distingue a fase de rolagem direta e a de momentum: durante momentum, `phase` é None e `momentumPhase` progride por Began, Changed e Ended; a janela alvo fica vinculada ao início do momentum. Eventos de mouse podem aparecer intercalados. [Fonte](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html).

## Campos privados identificados no WebKit

Correção da pesquisa anterior: o cabeçalho oficial de teste do WebKit declara valores numéricos privados. O [CoreGraphicsTestSPI.h fixado](https://github.com/WebKit/WebKit/blob/e20307a8c14f4f832a193739a19f02ba159100d4/Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h) e [IOKitSPIMac.h fixado](https://github.com/WebKit/WebKit/blob/e20307a8c14f4f832a193739a19f02ba159100d4/Source/WebCore/PAL/pal/spi/mac/IOKitSPIMac.h) são fontes primárias; `SPI` significa interface privada, sem garantia de compatibilidade pública.

| Significado no teste | Valor |
|---|---:|
| Campo tipo CGS / ID de janela | 55 / 51 |
| Campo tipo HID / preflight | 110 / 111 |
| Campo valor zoom / rotação / swipe | 113 / 114 / 115 |
| Campo início/fim de série | 117 |
| Campo movimento / progresso swipe | 123 / 124 |
| Campo posição X/Y e velocidade X/Y/Z swipe | 125 / 126 e 129 / 130 / 131 |
| Campo fase / máscara / máscara swipe | 132 / 133 / 134 |
| Campo flavor / zoom delta X/Y | 138 / 139 / 140 |
| Tipo CGS gesture / Dock control / fluid touch | 29 / 30 / 31 |
| Tipo HID zoom / navigation swipe / zoom toggle | 8 / 16 / 22 |
| Marcador HID início / fim de gesto | 61 / 62 |

O [SyntheticNSEvent do WebKit](https://github.com/WebKit/WebKit/blob/e20307a8c14f4f832a193739a19f02ba159100d4/Tools/TestRunnerShared/mac/SyntheticNSEvent.mm) constrói para o teste magnify com tipo CGS 29, tipo HID 8, fase e campo double 113; smart magnify usa CGS 29 e HID 22. O mesmo arquivo converte fases AppKit para fases CGS, sem estabelecer que valores AppKit e CGS sejam intercambiáveis. O serializador WebKit usa também o campo double 114 para rotação e campos de swipe para navigation swipe. [Serializador](https://github.com/WebKit/WebKit/blob/e20307a8c14f4f832a193739a19f02ba159100d4/Tools/TestRunnerShared/EventSerialization/mac/EventSerializerMac.mm).

Isto comprova a construção de eventos para testes em views do WebKit, não que `CGEventPost` com esses campos alcance aplicativos externos ou o Dock. Smart zoom também usa um wrapper `NSEvent` no teste. Os valores HID 61/62 são tipos de marcador, não fases; não extrapolar a sequência para Dock ou macOS atual. Verificar as condições de licença do WebKit antes de reutilizar código; esta tabela registra fatos e não incorpora código.

## O que os exemplos oficiais realmente provam

O teste WebKit cria eventos sintéticos de magnify com Began/Changed/Ended e smart magnify e invoca os respectivos métodos do `NSView` do próprio teste. Já a rolagem usa `CGEventCreateScrollWheelEvent`, campos de rolagem e conversão para `NSEvent`, também despachada ao view do teste. Não é prova de injeção sistêmica em outros aplicativos ou no Dock. [WebKit](https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/mac/EventSenderProxy.mm).

A distribuição oficial do código Apple descreve uma estrutura interna de evento HID de swipe com movimento, flavor e progresso fracionário (1.0 = 100%). Essa estrutura HID, isoladamente, não fornece o mapeamento dos campos CG nem a ordem de eventos, roteamento do Dock ou compatibilidade entre releases; o WebKit fornece alguns números acima. O arquivo tem sua própria licença APSL; esta nota apenas descreve os fatos, sem copiar código. [IOHIDEventData.h da Apple](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDEventData.h).

## Pinça do Dock: evidência adicional

O [cabeçalho IOHIDEventTypes de AXElements/mouse, commit 4a8e9f](https://github.com/AXElements/mouse/blob/4a8e9f69754ee5def99b5d9da59e33b3adb6768e/ext/mouse/IOHIDEventTypes.h) enumera movimentos none, horizontal, vertical e scale nessa ordem, correspondendo a 0, 1, 2 e **3**; [CGEventAdditions.h](https://github.com/AXElements/mouse/blob/4a8e9f69754ee5def99b5d9da59e33b3adb6768e/ext/mouse/CGEventAdditions.h) associa pinch a scale. A [interface TouchSimulator.h do Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix/blob/b25b734ddbba1ad958e9d1dc338276636298e339/Helper/Core/Touch/TouchSimulator.h) também declara o tipo de pinça Dock como 3 para Show Desktop e Launchpad. São evidências sobre nomenclatura e valor; não comprovam que uma sequência sintética funcione no Dock atual. A referência Apple válida para a estrutura é [IOHIDEventData.h](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDEventData.h); o suposto caminho Apple `IOHIDFamily/IOHIDEventTypes.h` retorna 404 e não deve ser usado como fonte.

## Evidência comunicada pela tarefa principal

Atualização de execução da tarefa principal: o
[run 41302325635](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41302325635),
SHA `f54475af13841ca3e6ea35e59ae93eed13de3616`, passou 26 testes unitários,
cinco verificações de protocolo, oito de entrada real e três transições do
sistema em macOS 26.6.2: Mission Control, Aplicativos e Mesa. A sequência
DockControl seguida de Gesture foi necessária no cenário que falhava.
A prova está delimitada à fixture e à versão testada; os próximos itens de
compatibilidade continuam relevantes. Detalhes e controles positivos em
[VALIDATION.md](../VALIDATION.md).

- REA 6.8.0 com Node 24.22.1: análise Mach-O e bundle concluída no run 41294912960; REA com Ghidra 12.1.4 no slice x86 thin, run 41296076008, encontrou seis procedimentos TouchSimulator. Análise estática não demonstra comportamento em execução.
- OpenMouse compilou e estava ativo em macOS 26.6 com Acessibilidade autorizada. No CI macOS 15.8.2, run 41296327186, passaram 23 testes unitários, cinco verificações de wire e sete de input; o pinch acionou três callbacks de `NSMagnificationGestureRecognizer`. Isto demonstra recepção AppKit no cenário testado, não qualifica Spaces, Mission Control ou pinça contínua do Dock.

Esses resultados foram comunicados pela tarefa principal; não foram executados nem inspecionados diretamente nesta pesquisa.

## Próximas evidências necessárias

1. Obter documentação primária ou medição independente e autorizada do fluxo real de eventos de trackpad para cada gesto, com fase, tipo, campos, unidades e ordenação, inclusive cancelamento e finalização. Não inferir IDs de campos a partir de nomes HID.
2. Verificar no macOS alvo a aceitação de emissão em outro processo e no Dock; testar Spaces, Mission Control, App Exposé, zoom e rotação em apps distintos, diferentes monitores, direção e alterações de configurações do sistema. Documentar versão, permissões e falhas.
3. Isolar qualquer protocolo privado atrás de uma interface com detecção de disponibilidade e testes por versão; não apresentar atalho discreto como gesto contínuo equivalente. Sem prova, manter a funcionalidade como não verificada.
4. Confirmar permissões e distribuição antes de prometer suporte: a Apple lista uso de APIs de acessibilidade por apps assistivos entre atividades proibidas no App Sandbox; isso por si só não descreve todas as restrições de CGEvent. [App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).

## Evidência independente para DockSwipe contínuo

O projeto [macos-trackpad-companion, commit 519edcd](https://github.com/scottlamb/macos-trackpad-companion/blob/519edcd56295d1b037afd0c1bef3a39482660866/src/output.rs), distribui seu código sob [MIT ou Apache-2.0](https://github.com/scottlamb/macos-trackpad-companion/blob/519edcd56295d1b037afd0c1bef3a39482660866/README.md). O autor atribui os nomes e índices ao cabeçalho SPI do WebKit e o conjunto de campos e a codificação de bits ao projeto FasterSwiper, licenciado Apache-2.0. As afirmações abaixo são dessa implementação independente, não garantias da Apple; não foram verificadas neste Mac.

| Campo/etapa | Afirmação da implementação |
|---|---|
| 55 / 110 | Tipo Dock control 30 / HID DockSwipe 23. |
| 132 | Began 1, Changed 2, Ended 4, Cancelled 8. |
| 123 | Movimento 1 horizontal, 2 vertical; valores observados empiricamente pelo projeto. |
| 124 | Double com deslocamento assinado acumulado desde o início; Changed sucessivos permitem acompanhar e reverter animação. |
| 135 | Campo inteiro recebe o padrão de bits do progresso convertido para Float32, com extensão de sinal; o projeto relata que setter double escreve em outro slot. |
| 129 / 130 | Velocidade double ao terminar/cancelar, usada pelo Dock na decisão de concluir ou reverter; coordenadas e sinal requerem aferição. |
| Despacho | Fonte de evento de sessão combinada, timestamp e postagem no `kCGSessionEventTap`; a implementação também relata pares de eventos por quadro. Sequência completa e efeitos devem ser conferidos no código de origem e observados. |

Uma sequência Began→Changed…→Ended permite representar acompanhamento contínuo, enquanto apenas Began→Ended não prova animação. O projeto [strafe](https://github.com/rileycx/strafe) afirma que macOS 27 exige payload IOHID associado e muda o sentido da codificação; essa afirmação independente ainda requer teste nas versões alvo. Fonte privada não constitui contrato estável, e a reprodução integral ou adaptação de código deve preservar os avisos e condições das respectivas licenças, incluindo atribuições de dependências.

A implementação [`newGesture` do Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/eventtap.lua) identifica dependência da biblioteca Touch licenciada GPL versão 2; a licença geral do projeto não basta para concluir que esse trecho possa ser incorporado diretamente a um projeto somente MIT. A API documenta criação de eventos, mas esta pesquisa não encontrou nela prova de paridade interativa do Dock. Consulte a procedência dos arquivos antes de reutilizá-los.
