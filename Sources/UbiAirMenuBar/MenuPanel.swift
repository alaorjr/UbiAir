import AppKit
import SwiftUI
import ThinQCore

enum PanelLayout {
    static let width: CGFloat = 360
    static let height: CGFloat = 740
    static let contentHeight: CGFloat = 650
}

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var token = ""
    @State private var country = "BR"
    @State private var rememberToken = true
    @State private var panelID = UUID()
    @State private var sliderValue = 22.0
    @State private var isEditingTemperature = false

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if let problem = model.problem, model.state != nil || model.selectedProblem == nil { problemBanner(problem) }
                    if model.isConnected { connectedPanel } else { connectionPanel }
                }
                .padding(14)
            }
            .frame(maxHeight: PanelLayout.contentHeight)
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(width: PanelLayout.width)
        .background(.regularMaterial)
        .background(PanelVisibilityReader { visible in model.panelVisibilityChanged(id: panelID, visible: visible) })
        .onAppear { country = preferences.countryCode; preferences.refreshLaunchAtLogin() }
        .onDisappear { model.panelVisibilityChanged(id: panelID, visible: false) }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "snowflake").font(.system(size: 17, weight: .semibold)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("UbiAir").font(.system(size: 14, weight: .semibold))
                Text("Controle de ar-condicionado").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isConnected {
                Button { Task { await model.reloadDevices() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(model.isBusy || model.requiresReconnect).accessibilityLabel("Atualizar aparelhos")
            }
            Menu {
                Toggle("Abrir ao iniciar sessão", isOn: Binding(get: { preferences.launchAtLogin }, set: { preferences.setLaunchAtLogin($0) }))
                if let message = preferences.loginMessage { Text(message) }
                Divider()
                Button("Portal ThinQ", systemImage: "arrow.up.right.square") { openPortal() }
                if model.isConnected {
                    Button("Conectar com outro PAT", systemImage: "key") { model.showConnectionForm() }.disabled(model.isSending)
                    Button(model.isDemo ? "Sair da demonstração" : "Desconectar e remover token", systemImage: "rectangle.portrait.and.arrow.right") { model.disconnect() }
                        .disabled(model.isSending)
                }
                Divider()
                Button("Encerrar UbiAir", systemImage: "power") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "gearshape").font(.system(size: 16)) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Opções")
        }
    }

    private var connectedPanel: some View {
        VStack(spacing: 10) {
            if model.devices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "air.conditioner.horizontal").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Nenhum ar-condicionado").font(.callout.weight(.semibold))
                    Text("O UbiAir controla apenas ar-condicionados. Outros aparelhos da sua conta não aparecem aqui.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Confira o cadastro no app LG ThinQ e as permissões do PAT no portal.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Atualizar aparelhos") { Task { await model.reloadDevices() } }.disabled(model.isBusy || model.requiresReconnect)
                }
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(20)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
            } else {
                if model.devices.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(model.devices) { device in
                                Button { Task { await model.selectDevice(device.id) } } label: {
                                    HStack(spacing: 6) {
                                        Circle().fill(powerColor(for: device.id)).frame(width: 6, height: 6)
                                        Text(device.name).lineLimit(1)
                                    }
                                    .font(.caption.weight(model.selectedID == device.id ? .semibold : .regular))
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(model.selectedID == device.id ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(model.selectedID == device.id ? .isSelected : [])
                                .accessibilityValue(powerDescription(for: device.id))
                                .help(model.deviceProblem(for: device.id)?.message ?? powerDescription(for: device.id))
                            }
                        }
                    }
                    .disabled(model.isSending || model.isRefreshing || model.requiresReconnect)
                }
                if let device = model.selectedDevice {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.caption.weight(.medium)).lineLimit(1)
                            if let name = device.modelName { Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        if model.isRefreshing { ProgressView().controlSize(.small) }
                        else { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(model.isBusy || model.requiresReconnect).accessibilityLabel("Atualizar estado") }
                    }
                    .padding(.horizontal, 3)
                }
                if let state = model.state, let capabilities = model.capabilities {
                    statePanel(state, capabilities: capabilities)
                } else if model.isRefreshing {
                    HStack { Spacer(); ProgressView("Lendo aparelho…"); Spacer() }.padding(.vertical, 30)
                } else {
                    unavailablePanel(model.selectedProblem ?? AppProblem(title: "Estado indisponível", message: "Atualize para consultar o aparelho novamente."))
                }
            }
        }
    }

    private func unavailablePanel(_ problem: AppProblem) -> some View {
        VStack(spacing: 10) {
            Image(systemName: problem.kind == .offline ? "wifi.slash" : "exclamationmark.circle")
                .font(.title2).foregroundStyle(.orange)
            Text(problem.title).font(.callout.weight(.semibold))
            Text(problem.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            recoveryButton(problem)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
    }

    @ViewBuilder private func recoveryButton(_ problem: AppProblem) -> some View {
        if model.requiresReconnect || problem.requiresReconnect {
            Button("Conectar novamente") { model.showConnectionForm() }.disabled(model.isBusy)
        } else if model.isConnected {
            Button(problem.kind == .rateLimited ? "Tentar novamente após aguardar" : "Atualizar estado") {
                Task {
                    if model.problem == problem && model.selectedProblem != problem { await model.reloadDevices() }
                    else if model.selectedID != nil { await model.refresh() }
                    else { await model.reloadDevices() }
                }
            }.disabled(model.isBusy)
        }
    }

    private func statePanel(_ state: ACState, capabilities: ACCapabilities) -> some View {
        let enabled = state.isOn == true
        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.isOn.map { $0 ? "Ligado" : "Desligado" } ?? "Energia desconhecida")
                            .font(.system(size: 14, weight: .semibold))
                        Text(state.mode.map(optionName) ?? "Modo não informado")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await model.send(.power(!(state.isOn ?? false))) } } label: {
                        Image(systemName: "power").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(state.isOn == true ? Color.white : Color.primary)
                            .frame(width: 40, height: 40)
                            .background(state.isOn == true ? Color.accentColor : Color.primary.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canControl || !capabilities.canControlPower || state.isOn == nil)
                    .accessibilityLabel(state.isOn == true ? "Desligar aparelho" : "Ligar aparelho")
                }
                AirConditionerIllustration(isOn: enabled, target: temperature(state.targetTemperature, unit: state.temperatureUnit), reduceMotion: reduceMotion)
                    .frame(height: 112)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(temperature(state.targetTemperature, unit: state.temperatureUnit))
                        .font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                    Spacer()
                    Label(temperature(state.currentTemperature, unit: state.temperatureUnit), systemImage: "thermometer.medium")
                        .font(.caption).foregroundStyle(.secondary)
                }
                temperatureControl(state, range: capabilities.temperature)
                if let message = model.commandMessage {
                    HStack(spacing: 6) { if model.isSending { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark.circle") }; Text(message).font(.caption) }
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(13)

            if !capabilities.modes.isEmpty || !capabilities.fanSpeeds.isEmpty {
                HStack(spacing: 8) {
                    if !capabilities.modes.isEmpty { compactPicker("Modo", symbol: "snowflake", values: capabilities.modes, current: state.mode) { .mode($0) } }
                    if !capabilities.fanSpeeds.isEmpty { compactPicker("Ventilação", symbol: "fan", values: capabilities.fanSpeeds, current: state.fanSpeed) { .fanSpeed($0) } }
                }
                .disabled(!model.canControl || !enabled)
                .padding(.horizontal, 10).padding(.bottom, 10)
            }

            if capabilities.canControlVerticalSwing || capabilities.canControlHorizontalSwing {
                DisclosureGroup("Direção do ar") {
                    VStack(spacing: 4) {
                        if capabilities.canControlVerticalSwing {
                            Toggle("Oscilação vertical", isOn: Binding(get: { state.verticalSwing ?? false }, set: { value in Task { await model.send(.verticalSwing(value)) } }))
                                .disabled(state.verticalSwing == nil)
                        }
                        if capabilities.canControlHorizontalSwing {
                            Toggle("Oscilação horizontal", isOn: Binding(get: { state.horizontalSwing ?? false }, set: { value in Task { await model.send(.horizontalSwing(value)) } }))
                                .disabled(state.horizontalSwing == nil)
                        }
                    }
                }
                .font(.caption)
                .disabled(!model.canControl || !enabled)
                .padding(.horizontal, 13).padding(.vertical, 8)
            }
            Text("\(model.isDemo ? "Demonstração" : "Estado da nuvem") · \(state.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.bottom, 10)
        }
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    @ViewBuilder private func temperatureControl(_ state: ACState, range: TemperatureCapability?) -> some View {
        if let range, range.step > 0 {
            let allowed = allowedTemperatures(range)
            HStack(spacing: 8) {
                Button { changeTemperature(-range.step, state: state, range: range) } label: {
                    Image(systemName: "minus")
                        .frame(width: 29, height: 29)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .disabled(!model.canControl || state.isOn != true || Self.nextTemperature(-range.step, state: state, range: range) == nil)
                    .accessibilityLabel("Diminuir temperatura")
                if allowed.count > 1, let current = state.targetTemperature {
                    Slider(value: Binding(get: { isEditingTemperature ? sliderValue : sliderValueFor(current, allowed: allowed) }, set: { sliderValue = $0 }), in: 0...Double(allowed.count - 1), onEditingChanged: { editing in
                        isEditingTemperature = editing
                        guard !editing, model.canControl, state.isOn == true else { return }
                        let index = min(max(Int(sliderValue.rounded()), 0), allowed.count - 1)
                        if abs(allowed[index] - current) > 0.000_001 { Task { await model.send(.temperature(allowed[index])) } }
                    })
                    .onAppear { sliderValue = sliderValueFor(current, allowed: allowed) }
                    .onChange(of: current) { _, value in if !isEditingTemperature { sliderValue = sliderValueFor(value, allowed: allowed) } }
                    .disabled(!model.canControl || state.isOn != true)
                    .accessibilityLabel("Temperatura desejada")
                } else {
                    Spacer(minLength: 2)
                    Text("\(range.minimum.formatted(.number.precision(.fractionLength(0...1))))° — \(range.maximum.formatted(.number.precision(.fractionLength(0...1))))°")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                }
                Button { changeTemperature(range.step, state: state, range: range) } label: {
                    Image(systemName: "plus")
                        .frame(width: 29, height: 29)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .disabled(!model.canControl || state.isOn != true || Self.nextTemperature(range.step, state: state, range: range) == nil)
                    .accessibilityLabel("Aumentar temperatura")
            }
            .padding(.top, 1)
        } else {
            HStack { Text("Temperatura ambiente"); Spacer(); Text(temperature(state.currentTemperature, unit: state.temperatureUnit)) }
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func compactPicker(_ title: String, symbol: String, values: [String], current: String?, command: @escaping (String) -> ThinQCommand) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Picker(title, selection: Binding(get: { current ?? "" }, set: { value in Task { await model.send(command(value)) } })) {
                if current == nil { Text("Não informado").tag("") }
                else if let current, !values.contains(current) { Text(optionName(current)).tag(current) }
                ForEach(values, id: \.self) { Text(optionName($0)).tag($0) }
            }
            .labelsHidden().font(.caption.weight(.medium)).pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Conecte seus aparelhos").font(.title3.weight(.semibold))
            Text("Compatível com ar-condicionados LG ThinQ.").font(.caption).foregroundStyle(.secondary)
            Text("Entre no portal com sua conta LG ThinQ. Se ainda não tiver uma conta, crie-a no app LG ThinQ. Depois, crie seu Personal Access Token (PAT) no portal e cole-o abaixo.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Token pessoal ThinQ").font(.caption.weight(.medium))
                SecureField("Cole seu Personal Access Token", text: $token).textFieldStyle(.roundedBorder).onSubmit { connect() }.disabled(model.isConnecting)
            }
            HStack { Text("País da conta").font(.callout); Spacer(); TextField("BR", text: $country).frame(width: 54).textFieldStyle(.roundedBorder).onChange(of: country) { _, value in country = String(value.uppercased().prefix(2)) }.disabled(model.isConnecting) }
            Toggle("Salvar token no Chaves do macOS", isOn: $rememberToken).font(.callout).disabled(model.isConnecting)
            Button(action: connect) {
                HStack { if model.isConnecting { ProgressView().controlSize(.small) }; Text(model.isConnecting ? "Conectando…" : "Conectar").frame(maxWidth: .infinity) }
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isConnecting || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Obter token no portal LG", systemImage: "arrow.up.right.square") { openPortal() }.buttonStyle(.link).font(.caption)
            Divider()
            Button("Explorar demonstração", systemImage: "play.circle") { Task { await model.startDemo() } }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(model.isConnecting)
            Text("A demonstração usa aparelhos fictícios e não envia comandos à LG.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(15).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }

    private func allowedTemperatures(_ range: TemperatureCapability) -> [Double] {
        guard range.step > 0 else { return [] }
        let steps = ((range.maximum - range.minimum) / range.step).rounded(.down)
        guard steps.isFinite, steps >= 0, steps <= 1000 else { return [] }
        let count = Int(steps)
        return (0...count).map { range.minimum + Double($0) * range.step }.filter { range.accepts($0) }
    }

    private func sliderValueFor(_ value: Double, allowed: [Double]) -> Double {
        Double(allowed.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 0)
    }

    @discardableResult
    func changeTemperature(_ delta: Double, state: ACState, range: TemperatureCapability) -> Task<Void, Never>? {
        guard let desired = Self.nextTemperature(delta, state: state, range: range) else { return nil }
        return Task { await model.send(.temperature(desired)) }
    }

    static func nextTemperature(_ delta: Double, state: ACState, range: TemperatureCapability) -> Double? {
        guard let current = state.targetTemperature, range.step > 0 else { return nil }
        let position = (current - range.minimum) / range.step
        let direction: Double = delta > 0 ? 1 : -1
        var increment = direction > 0 ? floor(position + 0.000_001) + 1 : ceil(position - 0.000_001) - 1
        for _ in 0...range.except.count {
            let value = range.minimum + increment * range.step
            guard value >= range.minimum, value <= range.maximum else { return nil }
            if range.accepts(value) { return value }
            increment += direction
        }
        return nil
    }

    private func temperature(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + " °" + unit
    }

    private func optionName(_ value: String) -> String {
        let names = ["COOL":"Resfriar", "HEAT":"Aquecer", "DRY":"Desumidificar", "FAN":"Ventilar", "AUTO":"Automático", "AI":"Inteligente", "LOW":"Baixa", "MID":"Média", "MEDIUM":"Média", "HIGH":"Alta", "SLOW":"Silenciosa", "POWER":"Turbo", "NATURE":"Natural"]
        return names[value] ?? value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func problemBanner(_ problem: AppProblem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(problem.title).font(.caption.weight(.semibold))
                    Text(problem.message).font(.caption).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if !problem.blocksControls {
                    Button { model.problem = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel("Dispensar mensagem")
                }
            }
            if problem.blocksControls { recoveryButton(problem) }
        }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Text(model.isDemo ? "Demonstração · aparelhos fictícios" : "UbiAir · ThinQ Connect").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(AppIdentity.version).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func connect() {
        Task { await model.connect(token: token, country: country, remember: rememberToken); if model.isConnected { token = "" } }
    }
    private func powerColor(for id: String) -> Color {
        switch model.powerState(for: id) {
        case true: return .green
        case false: return .red
        case nil: return .secondary.opacity(0.45)
        }
    }
    private func powerDescription(for id: String) -> String {
        if let problem = model.deviceProblem(for: id) { return problem.title }
        switch model.powerState(for: id) {
        case true: return "Ligado"
        case false: return "Desligado"
        case nil: return "Energia desconhecida"
        }
    }
    private func openPortal() { if let url = URL(string: "https://connect-pat.lgthinq.com/login") { NSWorkspace.shared.open(url) } }
}
