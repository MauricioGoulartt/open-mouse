import SwiftUI
import AppKit
import OpenMouseCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "Geral", scrolling = "Rolagem", buttons = "Botões", permissions = "Permissões", about = "Sobre"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: return "switch.2"; case .scrolling: return "arrow.up.and.down"
        case .buttons: return "computermouse"; case .permissions: return "hand.raised"; case .about: return "info.circle" }
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var section: SettingsSection? = .general
    @State private var editing: Mapping?
    @State private var showReset = false

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(165)
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: "computermouse.fill").font(.system(size: 32)).foregroundStyle(.tint)
                    Text("Open Mouse").font(.title3.weight(.semibold))
                    Text("Seu mouse, do seu jeito.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text((section ?? .general).rawValue).font(.title2.weight(.semibold))
                    Spacer()
                    Circle().fill(store.engine.isRunning ? Color.green : Color.secondary).frame(width: 7, height: 7)
                    Text(store.engine.isRunning ? "Ativo" : "Desativado").font(.callout).foregroundStyle(.secondary)
                }.padding(24)
                Divider()
                switch section ?? .general {
                case .general: general
                case .scrolling: scrolling
                case .buttons: buttons
                case .permissions: permissions
                case .about: about
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .sheet(item: $editing) { mapping in
            MappingEditor(mapping: mapping, store: store) { updated in
                store.update { config in
                    if let index = config.mappings.firstIndex(where: { $0.id == updated.id }) { config.mappings[index] = updated }
                    else { config.mappings.append(updated) }
                }
            }
        }
        .alert("Open Mouse", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("Restaurar os ajustes padrão? Uma cópia dos ajustes atuais será preservada.", isPresented: $showReset) {
            Button("Restaurar padrões", role: .destructive) { store.restoreDefaults() }
        }
    }

    private func binding<T>(_ key: WritableKeyPath<Configuration, T>) -> Binding<T> {
        Binding(get: { store.configuration[keyPath: key] }, set: { value in store.update { $0[keyPath: key] = value } })
    }
    private func scrollBinding<T>(_ key: WritableKeyPath<ScrollSettings, T>) -> Binding<T> {
        Binding(get: { store.configuration.scroll[keyPath: key] }, set: { value in store.update { $0.scroll[keyPath: key] = value } })
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Ativar Open Mouse", isOn: binding(\.enabled))
                Text(store.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if !store.accessibilityGranted {
                    Button("Autorizar Acessibilidade…") { store.openAccessibilitySettings() }
                }
            } footer: {
                Text("A janela pode ser fechada: o processamento continua na barra de menus. Encerre o outro utilitário de mouse antes de ativar este.")
            }
            Section("Recursos") {
                Toggle("Aprimorar rolagem", isOn: binding(\.scrollEnabled))
                Toggle("Remapear botões", isOn: binding(\.buttonsEnabled))
                Toggle("Iniciar ao entrar no macOS", isOn: Binding(get: { store.loginEnabled }, set: store.setLogin))
            }
            Section("Ajustes") {
                HStack {
                    Button("Importar…") { store.importSettings() }
                    Button("Exportar…") { store.exportSettings() }
                    Spacer()
                    Button("Restaurar padrões…") { showReset = true }
                }
            }
        }.formStyle(.grouped)
    }

    private var scrolling: some View {
        Form {
            Section("Movimento") {
                Picker("Suavização", selection: scrollBinding(\.smoothing)) {
                    ForEach(Smoothing.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                HStack {
                    Text("Velocidade")
                    Slider(value: scrollBinding(\.speed), in: 0.1...5, step: 0.05)
                    Text(String(format: "%.2f×", store.configuration.scroll.speed)).monospacedDigit().frame(width: 50)
                }
                HStack {
                    Text("Aceleração")
                    Slider(value: scrollBinding(\.acceleration), in: 0...2, step: 0.05)
                    Text(String(format: "%.2f", store.configuration.scroll.acceleration)).monospacedDigit().frame(width: 50)
                }
            }
            Section("Direção") {
                Toggle("Inverter rolagem vertical", isOn: scrollBinding(\.inverted))
                Toggle("Inverter rolagem horizontal", isOn: scrollBinding(\.horizontalInverted))
                Text("Os eventos contínuos de trackpads passam sem alteração. Mouses de alta resolução que emitem eventos contínuos também passam sem alteração nesta versão.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Combinações com a roda") {
                Toggle("⇧ Shift: rolagem horizontal", isOn: scrollBinding(\.shiftHorizontal))
                Toggle("⌥ Option: rolagem precisa", isOn: scrollBinding(\.optionPrecise))
                Toggle("⌃ Control: zoom contínuo experimental", isOn: scrollBinding(\.controlZoom))
            }
        }.formStyle(.grouped)
    }

    private var buttons: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Combine botões, modificadores e gestos.").foregroundStyle(.secondary)
                Spacer()
                Menu("Predefinições") {
                    Button("Mouse com cinco botões") { store.update { $0.mappings = Configuration.fiveButtonMappings() } }
                    Button("Mouse com três botões") { store.update { $0.mappings = Configuration.threeButtonMappings() } }
                    Button("Sem mapeamentos") { store.update { $0.mappings = [] } }
                }
                Button { editing = Mapping(button: 3, trigger: .click, action: MouseAction(.middleClick)) } label: {
                    Label("Adicionar", systemImage: "plus")
                }
            }.padding(18)
            List {
                ForEach(store.configuration.mappings) { mapping in
                    HStack(spacing: 12) {
                        Image(systemName: "computermouse").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mapping.title).fontWeight(.medium)
                            HStack(spacing: 4) {
                                Text(mapping.action.kind.title)
                                if mapping.action.kind == .keyboardShortcut {
                                    Text(mapping.action.modifiers.title + " " + (mapping.action.keyCode.map { "#\($0)" } ?? ""))
                                }
                                if mapping.action.kind == .desktopAndLaunchpad {
                                    Text("· pendente").foregroundStyle(.orange)
                                } else if [.smartZoom, .zoom, .rotate, .spacesAndMissionControl].contains(mapping.action.kind) {
                                    Text("· experimental").foregroundStyle(.orange)
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                            if !mapping.heldButtons.isEmpty {
                                Text("Com botões \(mapping.heldButtons.sorted().map(String.init).joined(separator: ", ")) pressionados")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Editar") { editing = mapping }.buttonStyle(.borderless)
                        Button { store.update { $0.mappings.removeAll { $0.id == mapping.id } } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Remover mapeamento")
                    }.padding(.vertical, 7)
                }
            }
            Text("Mesa/Launchpad por pinça de quatro dedos ainda não está implementado. Os demais gestos nativos são experimentais e exigem validação com o mouse real.")
                .font(.caption).foregroundStyle(.secondary).padding(18)
        }
    }

    private var permissions: some View {
        Form {
            Section("Acessibilidade") {
                Label(store.accessibilityGranted ? "Permissão concedida" : "Permissão necessária",
                      systemImage: store.accessibilityGranted ? "checkmark.circle.fill" : "lock")
                Text("O Open Mouse precisa desta permissão para transformar eventos do mouse. A concessão é feita por você nos Ajustes do Sistema.")
                Button("Abrir Ajustes de Acessibilidade…") { store.openAccessibilitySettings() }
            }
            Section("Privacidade") {
                Text("Os ajustes ficam neste Mac. O aplicativo não envia eventos, atalhos ou conteúdo das janelas para servidores.")
                Text("Não é necessário conceder Acesso Total ao Disco nem Gravação de Tela.")
            }
        }.formStyle(.grouped)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "computermouse.fill").font(.system(size: 54)).foregroundStyle(.tint)
            Text("Open Mouse").font(.largeTitle.bold())
            Text("0.1.0 · desenvolvimento").foregroundStyle(.secondary)
            Text("Um utilitário de mouse para macOS, independente e aberto. Licença MIT.")
            Text("Paridade completa com o Mac Mouse Fix ainda não foi comprovada. O projeto não incorpora seu código, marca ou arquivos.")
                .font(.callout).foregroundStyle(.secondary)
            Link("Código-fonte e progresso", destination: URL(string: "https://github.com/MauricioGoulartt/open-mouse")!)
            Text("Copyright © 2026 Open Mouse contributors").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(30)
    }
}

private struct MappingEditor: View {
    @State var mapping: Mapping
    @ObservedObject var store: SettingsStore
    var save: (Mapping) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recording = false
    @State private var monitor: Any?
    @State private var chord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mapeamento do mouse").font(.title2.bold())
            Form {
                HStack {
                    Picker("Botão", selection: $mapping.button) { ForEach(3...32, id: \.self) { Text("Botão \($0)").tag($0) } }
                    Button("Identificar…") {
                        if store.engine.isRunning { store.engine.captureNextButton = true }
                        else { store.error = "Ative o Open Mouse antes de identificar um botão, ou escolha seu número na lista." }
                    }
                }
                Picker("Entrada", selection: $mapping.trigger) { ForEach(Trigger.allCases) { Text($0.title).tag($0) } }
                HStack {
                    Text("Modificadores")
                    ForEach([Modifiers.control, .option, .shift, .command], id: \.rawValue) { modifier in
                        Toggle(modifier.title, isOn: Binding(get: { mapping.modifiers.contains(modifier) }, set: {
                            if $0 { mapping.modifiers.insert(modifier) } else { mapping.modifiers.remove(modifier) }
                        }))
                    }
                }
                TextField("Outros botões pressionados (ex.: 1, 4)", text: $chord)
                Picker("Ação", selection: $mapping.action.kind) {
                    ForEach(ActionKind.available(for: mapping.trigger)) { Text($0.title).tag($0) }
                }
                if mapping.action.kind == .keyboardShortcut {
                    HStack {
                        Text(mapping.action.modifiers.title + (mapping.action.keyCode.map { " Tecla #\($0)" } ?? "Nenhum atalho"))
                        Spacer()
                        Button(recording ? "Pressione o atalho… (Esc cancela)" : "Gravar atalho") { beginRecording() }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salvar") {
                    let parts = chord.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.allSatisfy({ Int($0).map { (1...32).contains($0) && $0 != mapping.button } ?? false }) else {
                        store.error = "Informe números de botões válidos, separados por vírgula."; return
                    }
                    mapping.heldButtons = Set(parts.compactMap(Int.init))
                    var candidate = store.configuration
                    candidate.mappings.removeAll { $0.id == mapping.id }; candidate.mappings.append(mapping)
                    do { _ = try candidate.validated(); save(mapping); dismiss() }
                    catch { store.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(recording || (mapping.action.kind == .keyboardShortcut && mapping.action.keyCode == nil))
            }
        }.padding(24).frame(width: 530)
        .onAppear { chord = mapping.heldButtons.sorted().map(String.init).joined(separator: ", ") }
        .onChange(of: mapping.trigger) { trigger in
            if !ActionKind.available(for: trigger).contains(mapping.action.kind) { mapping.action = MouseAction(ActionKind.available(for: trigger)[0]) }
        }
        .onChange(of: store.capturedButton) { button in if let button { mapping.button = button; store.capturedButton = nil } }
        .onDisappear { stopRecording(); store.engine.captureNextButton = false }
    }
    private func beginRecording() {
        stopRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode != 53 {
                mapping.action.keyCode = event.keyCode
                mapping.action.modifiers = Modifiers(rawValue: event.modifierFlags.rawValue).intersection(.supported)
            }
            stopRecording(); return nil
        }
    }
    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false
    }
}
