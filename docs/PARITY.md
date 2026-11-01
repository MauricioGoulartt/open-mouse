# Paridade e evidência

Referência: Mac Mouse Fix 3.1.0. Este documento acompanha a diferença entre
código escrito, testes automatizados e comportamento real. Não declara paridade
integral antes da validação com hardware e aplicativos externos.

| Comportamento | Código | Prova necessária |
|---|---|---|
| Rolagem suave, velocidade, inversão e aceleração | Implementado | Testes de conservação/reversão/rajada + roda real |
| Trackpad preservado | Eventos contínuos passam intactos | Testar trackpad e roda simultaneamente |
| Clique, clique duplo/triplo, segurar, arrastar, rolar | Implementado | Testes do reconhecedor + mouse real |
| Modificadores, combinações e precedência | Implementado | Testes do reconhecedor + gravação na interface |
| Atalhos e cliques sintéticos | Implementado | Acessibilidade + apps externos |
| Mídia, brilho e ações do sistema | Implementado | Hardware/atalhos reais, inclusive atalhos desativados |
| Voltar/avançar | Atalhos por contexto | Navegadores, Finder, Preview, VS Code e Ajustes |
| Scroll & Navigate | Rolagem bidimensional com fases | Navegação, rubber band e inércia após soltar |
| Zoom, rotação, Smart Zoom | Experimental | Eventos privados aceitos por Safari, Preview, Fotos e Mapas |
| Spaces/Mission Control por arrasto | DockSwipe experimental | Continuidade, reversão, cancelamento e múltiplos monitores |
| Mesa/Launchpad por pinça de quatro dedos | Pendente | Protocolo, implementação e execução real |
| Persistência/importação/exportação | Implementado | Round trip, arquivo inválido preservado e reinício |
| Barra de menus/segundo plano/início de sessão | Implementado | Fechar janela, sair, reiniciar sessão |
| Atualização automática e pré-lançamentos | Pendente | Implementação e release assinada |
| Português brasileiro | Implementado na interface | Inspeção visual das telas |
| Outras traduções e macOS 10.15–12 | Pendente | Tradução/compatibilidade por plataforma |

## Estado da validação

01/11/2026: projeto inicial em implementação. A compilação, testes e análise REA
serão registrados com SHA, executor, comandos e resultados em
`docs/VALIDATION.md`. O Mac tem CI Journey ativo; não foram iniciadas suítes,
builds ou capturas de entrada locais durante essa ocupação.
