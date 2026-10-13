import AppKit
import SwiftUI
import ThinQCore

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences
    @State private var token = ""
    @State private var country = "BR"
    @State private var rememberToken = true
    @State private var panelID = UUID()

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.isConnected { connectedPanel } else { connectionPanel }
                    if let error = model.errorMessage { errorBanner(error) }
                }
                .padding(20)
            }
            .frame(maxHeight: 570)
            Divider()
            footer.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 380)
        .background(.background)
        .background(PanelVisibilityReader { visible in model.panelVisibilityChanged(id: panelID, visible: visible) })
        .onAppear { country = preferences.countryCode; preferences.refreshLaunchAtLogin() }
        .onDisappear { model.panelVisibilityChanged(id: panelID, visible: false) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "snowflake").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("LGThinQ").font(.headline)
                Text(model.isDemo ? "Demonstração · aparelhos fictícios" : "Seu clima na barra de menus")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if model.isConnected {
                    Button("Atualizar aparelhos", systemImage: "arrow.clockwise") { Task { await model.reloadDevices() } }
                        .disabled(model.isBusy)
                }
                Toggle("Abrir ao iniciar sessão", isOn: Binding(get: { preferences.launchAtLogin }, set: { preferences.setLaunchAtLogin($0) }))
                if let message = preferences.loginMessage { Text(message) }
                Divider()
                Button("Portal ThinQ", systemImage: "arrow.up.right.square") { openPortal() }
                if model.isConnected {
                    Button(model.isDemo ? "Sair da demonstração" : "Desconectar e remover token", systemImage: "rectangle.portrait.and.arrow.right") { model.disconnect() }
                        .disabled(model.isSending)
                }
                Divider()
                Button("Encerrar LGThinQ", systemImage: "power") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Opções")
        }
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conecte seus aparelhos").font(.title3.weight(.semibold))
            Text("Use o token pessoal da sua conta LG ThinQ para encontrar os ar-condicionados já cadastrados.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Token pessoal ThinQ").font(.caption.weight(.medium))
                SecureField("Cole seu Personal Access Token", text: $token)
                    .textFieldStyle(.roundedBorder).onSubmit { connect() }
                    .disabled(model.isConnecting)
            }
            HStack {
                Text("País da conta").font(.callout)
                Spacer()
                TextField("BR", text: $country).frame(width: 54).textFieldStyle(.roundedBorder)
                    .onChange(of: country) { _, value in country = String(value.uppercased().prefix(2)) }
                    .accessibilityLabel("Código de duas letras do país da conta")
                    .disabled(model.isConnecting)
            }
            Toggle("Salvar token no Chaves do macOS", isOn: $rememberToken).font(.callout)
                .disabled(model.isConnecting)
            Button(action: connect) {
                HStack { if model.isConnecting { ProgressView().controlSize(.small) }; Text(model.isConnecting ? "Conectando…" : "Conectar").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(model.isConnecting || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Obter token no portal LG", systemImage: "arrow.up.right.square") { openPortal() }
                .buttonStyle(.link).font(.caption)
            Divider()
            Button("Explorar demonstração", systemImage: "play.circle") { Task { await model.startDemo() } }
                .buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(model.isConnecting)
            Text("A demonstração usa aparelhos fictícios e não envia comandos à LG.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var connectedPanel: some View {
        if model.devices.isEmpty {
            ContentUnavailableView("Nenhum ar-condicionado", systemImage: "air.conditioner.horizontal", description: Text("Cadastre os aparelhos no app LG ThinQ e confira as permissões do seu token."))
            Button("Atualizar aparelhos") { Task { await model.reloadDevices() } }.disabled(model.isBusy)
        } else {
            if model.devices.count > 1 {
                Picker("Aparelho", selection: Binding(get: { model.selectedID ?? "" }, set: { id in Task { await model.selectDevice(id) } })) {
                    ForEach(model.devices) { device in Text(device.name).tag(device.id) }
                }
                .disabled(model.isSending || model.isRefreshing)
            }
            if let device = model.selectedDevice {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.title3.weight(.semibold))
                        if let name = device.modelName { Text(name).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if model.isRefreshing { ProgressView().controlSize(.small) }
                    else { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).disabled(model.isBusy).accessibilityLabel("Atualizar estado") }
                }
            }
            if let state = model.state, let capabilities = model.capabilities {
                statePanel(state, capabilities: capabilities)
            } else if model.isRefreshing {
                HStack { Spacer(); ProgressView("Lendo aparelho…"); Spacer() }.padding(.vertical, 30)
            } else {
                Text("Estado indisponível. Atualize para tentar novamente.").font(.callout).foregroundStyle(.secondary)
                Button("Tentar novamente") { if let id = model.selectedID { Task { await model.selectDevice(id) } } }
                    .disabled(model.isBusy)
            }
        }
    }

    private func statePanel(_ state: ACState, capabilities: ACCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Temperatura ambiente").font(.caption).foregroundStyle(.secondary)
                    Text(temperature(state.currentTemperature, unit: state.temperatureUnit)).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(state.isOn.map { $0 ? "Ligado" : "Desligado" } ?? "Energia desconhecida").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.send(.power(!(state.isOn ?? false))) } } label: {
                    Image(systemName: "power").font(.title2).frame(width: 46, height: 46)
                }
                .buttonStyle(.bordered).tint(state.isOn == true ? .blue : .secondary)
                .disabled(!model.canControl || !capabilities.canControlPower || state.isOn == nil)
                .accessibilityLabel(state.isOn == true ? "Desligar aparelho" : "Ligar aparelho")
            }
            if let range = capabilities.temperature {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Temperatura desejada").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { changeTemperature(-range.step, state: state, range: range) } label: { Image(systemName: "minus").frame(width: 26, height: 26) }
                            .disabled(!model.canControl || state.isOn != true || nextTemperature(-range.step, state: state, range: range) == nil)
                            .accessibilityLabel("Diminuir temperatura")
                        Spacer()
                        Text(temperature(state.targetTemperature, unit: range.unit)).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                        Spacer()
                        Button { changeTemperature(range.step, state: state, range: range) } label: { Image(systemName: "plus").frame(width: 26, height: 26) }
                            .disabled(!model.canControl || state.isOn != true || nextTemperature(range.step, state: state, range: range) == nil)
                            .accessibilityLabel("Aumentar temperatura")
                    }.buttonStyle(.bordered)
                }
            }
            if !capabilities.modes.isEmpty || !capabilities.fanSpeeds.isEmpty {
                Divider()
                VStack(spacing: 12) {
                    if !capabilities.modes.isEmpty { optionPicker("Modo", values: capabilities.modes, current: state.mode) { .mode($0) } }
                    if !capabilities.fanSpeeds.isEmpty { optionPicker("Ventilação", values: capabilities.fanSpeeds, current: state.fanSpeed) { .fanSpeed($0) } }
                }.disabled(!model.canControl || state.isOn != true)
            }
            if capabilities.canControlVerticalSwing || capabilities.canControlHorizontalSwing {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Direção do ar").font(.caption).foregroundStyle(.secondary)
                    if capabilities.canControlVerticalSwing {
                        Toggle("Oscilação vertical", isOn: Binding(get: { state.verticalSwing ?? false }, set: { value in Task { await model.send(.verticalSwing(value)) } }))
                            .disabled(state.verticalSwing == nil)
                    }
                    if capabilities.canControlHorizontalSwing {
                        Toggle("Oscilação horizontal", isOn: Binding(get: { state.horizontalSwing ?? false }, set: { value in Task { await model.send(.horizontalSwing(value)) } }))
                            .disabled(state.horizontalSwing == nil)
                    }
                }.disabled(!model.canControl || state.isOn != true)
            }
            if let message = model.commandMessage {
                HStack(spacing: 8) { if model.isSending { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark.circle") }; Text(message).font(.caption) }
                    .foregroundStyle(.secondary).accessibilityElement(children: .combine)
            }
            Text("\(model.isDemo ? "Demonstração" : "Estado da nuvem") · \(state.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func optionPicker(_ title: String, values: [String], current: String?, command: @escaping (String) -> ThinQCommand) -> some View {
        Picker(title, selection: Binding(get: { current ?? "" }, set: { value in Task { await model.send(command(value)) } })) {
            if current == nil { Text("Não informado").tag("") }
            else if let current, !values.contains(current) { Text(optionName(current)).tag(current) }
            ForEach(values, id: \.self) { Text(optionName($0)).tag($0) }
        }
    }

    private func changeTemperature(_ delta: Double, state: ACState, range: TemperatureCapability) {
        guard let desired = nextTemperature(delta, state: state, range: range) else { return }
        Task { await model.send(.temperature(desired)) }
    }

    private func nextTemperature(_ delta: Double, state: ACState, range: TemperatureCapability) -> Double? {
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

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(message).font(.caption).textSelection(.enabled)
            Spacer(minLength: 0)
            Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("Dispensar mensagem")
        }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10)).accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack {
            Text(model.isDemo ? "Sem conexão com aparelhos reais" : "LG ThinQ Connect").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("0.1.0").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func connect() {
        Task { await model.connect(token: token, country: country, remember: rememberToken); if model.isConnected { token = "" } }
    }
    private func openPortal() { if let url = URL(string: "https://smartsolution.developer.lge.com") { NSWorkspace.shared.open(url) } }
}
