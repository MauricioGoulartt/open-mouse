# Open Mouse

Utilitário independente de mouse para macOS. Swift, AppKit e SwiftUI. Licença MIT.

**Em desenvolvimento: a paridade completa com Mac Mouse Fix 3.1.0 ainda não foi
comprovada.** O Open Mouse não contém código ou recursos daquele aplicativo.

## Implementado no código

- Rolagem suave, inércia exponencial, aceleração, velocidade, inversão independente
  e modificadores para rolagem horizontal, precisa e zoom.
- Botões 3–32: clique simples/duplo/triplo, segurar, arrastar, rolar com botão,
  modificadores de teclado e combinações de botões.
- Atalhos gravados, navegação, cliques, ações do sistema, volume, mídia e brilho.
- Gestos nativos experimentais de pinça, rotação, zoom inteligente e DockSwipe.
- Ajustes locais validados, importação/exportação, cópias de segurança, barra de
  menus, execução em segundo plano e início de sessão via Service Management.

“Implementado” não significa validado no hardware: veja a
[matriz de paridade](docs/PARITY.md). A pinça de quatro dedos para Mesa/Launchpad,
a equivalência exata de gestos em todos os apps e a atualização automática ainda
estão pendentes. Eventos contínuos de trackpads e mouses de alta resolução passam
sem alteração nesta versão. O aplicativo inicia desativado.

## Compilar

macOS 13 ou posterior e Swift 5.9+ (Command Line Tools ou Xcode).

```bash
swift test --jobs 2
bash scripts/package-app.sh
open "dist/Open Mouse.app"
```

A assinatura de desenvolvimento é ad hoc, sem notarização. Para transformar
eventos, autorize **Open Mouse** em Ajustes do Sistema → Privacidade e Segurança →
Acessibilidade e ative-o na interface. Evite executar dois remapeadores ao mesmo
tempo. Fechar a janela mantém o processamento; “Encerrar Open Mouse” o interrompe.

`OpenMouse --diagnose` informa as permissões sem iniciar captura de eventos.

## Pesquisa e contribuição

As fontes primárias e os pontos não comprovados estão em `docs/research/`.
O workflow manual **REA reference analysis** analisa uma cópia oficial do Mac
Mouse Fix 3.1.0 com REA, sem executá-la nem modificar dados do usuário.
O workflow **macOS** executa os testes, compila e empacota em runner hospedado.

Atribuições e licença de código permissivo adaptado:
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
