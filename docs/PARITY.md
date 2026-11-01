# Paridade e evidência

Referência: Mac Mouse Fix 3.1.0. Este documento acompanha a diferença entre
código escrito, testes automatizados e comportamento real. Não declara paridade
integral antes da validação com hardware e aplicativos externos.

| Comportamento | Código | Prova necessária |
|---|---|---|
| Rolagem suave, velocidade, inversão e aceleração | Implementado e testado no núcleo; rolagem e inversão chegam ao responder real | Roda física, giro livre e apps externos |
| Trackpad preservado | Identificação IOHID; contínuos desconhecidos passam intactos, com teste real dessa passagem | Trackpad e roda física simultâneos |
| Clique, clique duplo/triplo, segurar, arrastar, rolar | Reconhecedor testado; clique, duplo e hold passam pelo event tap até um responder real | Botões físicos do mouse |
| Modificadores, combinações e precedência | Testes de reconhecimento e proteção contra cliques extras de combinações/arrasto | Gravação e uso com hardware real |
| Atalhos e cliques sintéticos | Emissão implementada; teclas verificadas no responder nativo | Atalhos globais e apps externos |
| Mídia, brilho e ações do sistema | Implementado | Hardware/atalhos reais, inclusive atalhos desativados |
| Voltar/avançar | Atalhos por contexto | Navegadores, Finder, Preview, VS Code e Ajustes |
| Scroll & Navigate | Rolagem bidimensional e inércia após soltar; física testada em taxas de quadros distintas | Navegação e rubber band por aplicativo |
| Zoom, rotação, Smart Zoom | Protocolo experimental; Smart Zoom e pinça chegam ao view real, incluindo recognizer de magnificação | Safari, Preview, Fotos e Mapas; rotação real |
| Spaces/Mission Control por arrasto | DockSwipe experimental; Mission Control observado no Dock real em CI | Spaces horizontais, App Exposé, continuidade/reversão e múltiplos monitores |
| Mesa/Launchpad por pinça de quatro dedos | Implementado; Mesa e Aplicativos abertos e observados no macOS 26 | Outras versões e configurações do sistema |
| Persistência/importação/exportação | JSON e validação testados; arquivo inválido é preservado; cópia antes de importar/restaurar | Diálogos completos de importação/exportação e reinício |
| Barra de menus/segundo plano/início de sessão | Implementado, com ícone opcional e entrada via Service Management | Login após encerrar uma sessão real |
| Atualização e pré-lançamentos | Consulta GitHub manual/ao abrir ajustes e seleção de canal implementadas; comparador de versões testado | Instalação automática e distribuição assinada/notarizada |
| Português brasileiro | Interface implementada e inspecionada; adição/remoção de mapeamento exercitada | Revisão de todas as mensagens |
| Outras traduções e macOS 10.15–12 | Pendente | Tradução/compatibilidade por plataforma |

## Estado da validação

01/11/2026: 26 testes unitários, cinco verificações de protocolo, oito de entrada
real e três transições do sistema passaram nos runners hospedados. Os gestos
têm um gate próprio e controles positivos; os resultados e SHAs estão em
[VALIDATION.md](VALIDATION.md). O Open Mouse foi instalado e ativado no Mac com
Acessibilidade, com Mac Mouse Fix desativado pela interface. Os testes sintéticos
no CI não equivalem a uma bateria com os botões físicos do MX Master 3S; após a
instalação final, o usuário confirmou o funcionamento da roda e dos botões laterais.
