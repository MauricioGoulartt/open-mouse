# Validação do Open Mouse

Registro de 01/11/2026. Referência funcional: Mac Mouse Fix 3.1.0.
Os resultados abaixo delimitam o que foi executado; não constituem prova de
equivalência em todo mouse, aplicativo ou versão do macOS.

## Origem e análise da referência

O [run REA 41294912960](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41294912960)
baixou o arquivo oficial 3.1.0, verificou o bundle e analisou os dois executáveis
Mach-O com REA 6.8.0 e Node 24.22.1, sem executá-los. Metadados reproduzíveis
estão em `artifacts/analysis/rea-3.1.0/`.

| Entrada | SHA-256 |
|---|---|
| ZIP oficial 3.1.0 | `afee98a91e86b287cc28c652fddefeeb02e17573af0e666d1ffa542f1025308f` |
| Executável principal universal | `4dc9fe0466965531cf0c85c8abf80ebd5d4f1644bf4ef6acaf666864ba6109f5` |
| Helper universal | `0b06b2cb94c297f3e1f18dfe6fd99d024543f6bb3b83fd0838be1eacd1d156b7` |
| Slice x86-64 do Helper | `f35a1f8f2801391839bdde872d524318b8fe10bbfcca7477d88da4a04808c35c` |

Os [runs 41296076008](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41296076008)
e [41296650773](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41296650773)
usaram REA e Ghidra 12.1.4 no slice x86-64 para identificar procedimentos e fatos
do protocolo de eventos. O binário de referência permaneceu imutável e os
projetos temporários foram removidos pelos workflows. Código descompilado e
arquivos proprietários da referência não são distribuídos neste repositório.
Os protocolos implementados e as fontes permissivas estão em
[macos-native-gesture-protocol.md](research/macos-native-gesture-protocol.md)
e [dock-packet-check.md](research/dock-packet-check.md).

## Execução automatizada

### Candidato instalado

[Run 41302325635](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41302325635),
SHA `f54475af13841ca3e6ea35e59ae93eed13de3616`, compilação **22**,
macOS **26.6.2 (25G83)**, binário **arm64**. Workflow completo aprovado:

| Verificação | Resultado |
|---|---|
| Núcleo e regressões | 26 testes aprovados |
| Representação nativa de eventos, sem postá-los | 5 verificações aprovadas |
| Entrada real por event tap e responder nativo | 8 verificações aprovadas |
| Mission Control por arrasto | Transição AX `mc` observada |
| Pinça para Aplicativos | Superfície Spotlight visível e grade `com.apple.spotlight.zkw.alphabetic` observadas |
| Pinça para Mesa | Hit test no Finder/desktop no lugar da janela de teste |
| Controles positivos Apple | Mission Control e Mostrar Mesa observados |
| Pacote | Assinatura ad hoc verificada; licenças distribuídas |

SHA-256 do ZIP:
`a03b7bbc7c8a02bf7877e492f42d06bc7f6d874487b0b5c3a75e12cbb5e8840b`.
SHA-256 do executável instalado:
`99ade5540d2c5fc84a646f641b1349fb7c10f32f03db598fb8bf284923dcfdd0`.

O mesmo ZIP, com seu arquivo de checksum, foi publicado como
[prévia v0.1.0](https://github.com/MauricioGoulartt/open-mouse/releases/tag/v0.1.0).
A publicação não altera o status experimental nem amplia a matriz testada.

O workflow `.github/workflows/macos.yml` compila e executa em runners hospedados
do GitHub. Não utiliza os runners locais do usuário. Os testes que postam eventos
exigem simultaneamente `GITHUB_ACTIONS=true`, `OPEN_MOUSE_ISOLATED_TEST=1` e
Acessibilidade autorizada. Criam apenas uma janela própria em desktop efêmero.

Comandos canônicos:

```bash
swift test --jobs 2
swift build -c release --jobs 2
bash scripts/package-app.sh --skip-build
"dist/Open Mouse.app/Contents/MacOS/OpenMouse" --diagnose
"dist/Open Mouse.app/Contents/MacOS/OpenMouse" --check-native-events
OPEN_MOUSE_ISOLATED_TEST=1 "dist/Open Mouse.app/Contents/MacOS/OpenMouse" --integration-check
OPEN_MOUSE_ISOLATED_TEST=1 "dist/Open Mouse.app/Contents/MacOS/OpenMouse" --system-gesture-check
"dist/Open Mouse.app/Contents/MacOS/OpenMouse" --render-preview "$PWD/dist/previews"
```

Os comandos de integração acima continuam exigindo as demais guardas do CI.
`--diagnose` e `--check-native-events` não iniciam interceptação nem postam eventos.

### Evidência anterior reutilizável

O [run 41297536404](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41297536404),
SHA `794d74eca5aa6b6d012d5788066f22d6aef3b838`, passou 26 testes unitários,
cinco verificações de protocolo e sete verificações de entrada real. O núcleo
e sua suíte permaneceram inalterados durante os ajustes posteriores do Dock.

O [run 41300516472](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41300516472),
SHA `1823b67c71260cd6e1e146cad8c76bd7b0098d20`, em macOS 26.6.2 (25G83),
repetiu essas provas e observou Mission Control real após o gesto sintético.
O run terminou vermelho no observador da pinça: o observador consultava apenas
o Dock. A captura do run seguinte mostrou a tela de Aplicativos do Spotlight
aberta pelo gesto, que não altera `frontmostApplication` nem a árvore AX do Dock.

O [run 41301764612](https://github.com/MauricioGoulartt/open-mouse/actions/runs/41301764612),
SHA `f42b723dded2746dde6e86c8836264a563fb90a5`, passou o workflow completo:
26 testes unitários, cinco verificações de protocolo, sete de entrada real e
três transições do sistema — Mission Control, Aplicativos e Mesa. A fixture
usa o hit test de Acessibilidade para distinguir a Mesa e o painel de Aplicativos;
a lista de janelas ainda inclui a janela deslocada por Mostrar Mesa.

### Regressões encontradas

- O evento DockControl precisa de um evento Gesture companheiro no mesmo tap.
  Sem esse par, a fixture não observava Mission Control; com o par, observou.
  O checker de protocolo protege tipo, ordem e tap dos pares, e o teste do sistema
  exige a transição real, com controle positivo usando o aplicativo da Apple.
- A fase Began deve carregar a primeira direção não nula; não é enviada antes
  de existir movimento. Cancelamento usa Cancelled, sem concluir o gesto.
- Um pipeline com `tee` ocultou inicialmente o código de saída do checker.
  O workflow agora usa Bash com `pipefail` explícito e um preflight que falha
  se um subprocesso com exit 17 for mascarado. O run 41298032476 não é evidência
  de aprovação dos gestos do sistema, apesar da conclusão verde histórica.
- A perda de autorização não encerrava um tap já criado: `start()` retornava
  cedo porque o tap existia. `configure()` agora encerra o tap quando a autorização
  falta. A integração simula perda/retorno na fronteira de autorização do motor,
  confirma parada real da transformação e confirma novo clique remapeado após
  recriar o tap. Não altera a permissão TCC do sistema durante o teste.
- A grade de Aplicativos muda de layout durante a indexação. O checker exige
  tanto a superfície Spotlight no ponto da fixture quanto a grade alfabética
  acessível; não depende de haver um ícone exatamente no ponto central.
  Dois Escapes fecham a grade e o painel de busca antes do próximo caso.
  Cada caso começa exigindo que a janela da fixture esteja desobstruída.

## Instalação e interface no Mac pessoal

A aplicação foi instalada em `~/Applications/Open Mouse.app`. O usuário
autenticou diretamente no diálogo do macOS, e a interface de Acessibilidade
confirmou autorização. O Mac Mouse Fix foi desativado pela interface e o Open
Mouse ativado, com status **Ativo**. A autorização não foi alterada por banco TCC,
script ou senha armazenada.

No teste visual nativo foi criado um mapeamento temporário para o botão 32,
salvo e removido. Os seis mapeamentos padrão foram preservados, assim como
os ajustes do Mac Mouse Fix. O mouse presente é um Logitech MX Master 3S;
após a instalação final o usuário confirmou que a roda e os botões laterais
funcionam. Essa confirmação inicial não substitui a qualificação de cada gesto
em aplicativos externos e das combinações com trackpad.

A atualização final foi feita pela compilação 22 do candidato acima, após
encerrar a instância anterior normalmente pelo Monitor de Atividade. O pacote
anterior e os ajustes foram preservados como rollback local. A assinatura ad hoc
mudou a identidade da compilação: a entrada antiga de Acessibilidade foi removida
e a aplicação instalada adicionada novamente pela interface do macOS. A nova
instância mostrou **Permissão concedida**, **Ativo** e compilação **22**, com os
seis mapeamentos e o arquivo de ajustes idênticos ao backup anterior à atualização.
Também foram exercitados o controle de visibilidade do ícone (desligado e
restaurado) e o fechamento/reabertura dos ajustes, mantendo o estado Ativo.
A consulta de versões foi exercitada com a prévia publicada: o canal beta
identificou a versão instalada como a mais recente; a opção foi restaurada para
desativada. O diagnóstico da aplicação lançada pelo macOS confirmou build 22,
o SHA do candidato e Acessibilidade autorizada em macOS 26.6 (25G72).
Uma consulta somente leitura com `CGGetEventTapList` confirmou o tap do Open
Mouse habilitado e os taps do BetterMouse, que permanecia em segundo plano,
desabilitados. Nenhum ajuste do BetterMouse foi alterado; o Helper do Mac Mouse
Fix não estava em execução.

O Mac estava ocupado com CI compartilhado. Foram feitas leituras, edições e
interações pontuais de interface; builds, suítes e análise pesada ficaram nos
executores hospedados. Não foram instalados REA/Ghidra ou dependências locais.

## Limites para a próxima qualificação

- Mouse físico e trackpad usados simultaneamente, inclinação/roda livre e
  protocolos proprietários de botões.
- Safari, Preview, Fotos, Mapas, Finder, navegadores e editores: zoom, rotação,
  navegação, rubber band e inércia em cada aplicativo.
- Spaces horizontais, múltiplos monitores, telas cheias e preferências de gestos
  diferentes das da fixture.
- Login após encerrar uma sessão real, suspensão/retomada e todas as teclas
  especiais em hardware que as ofereça.
- Builds notarizadas, assinatura de distribuição e instalação automática de
  atualizações. A versão atual tem assinatura ad hoc e consulta de versões.
- macOS 13–15 e 27 precisam de qualificação própria; o mínimo declarado 13 não
  é uma alegação de teste de todas essas versões. macOS 10.15–12 não é suportado.

## Recursos e limpeza

Os workflows removem seus downloads e projetos temporários e os runners são
descartáveis. Nenhum container, volume ou rede Docker foi criado pelo Open Mouse.
O inventário local de Docker sofreu corrida de remoção de cache de outro CI e
timeout de `docker system df`; o cliente de auditoria da própria tarefa foi
encerrado após prova de ownership. Não houve prune nem alteração de recursos
compartilhados. As evidências úteis ficam em `artifacts/local/`, ignorado pelo Git.
