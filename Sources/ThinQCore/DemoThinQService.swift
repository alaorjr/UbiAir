import Foundation

/// Offline-only sample service. The appliance names and states are entirely fictional.
public actor DemoThinQService: ThinQService {
    public static let livingRoomID = "demo-ac-living-room"
    public static let bedroomID = "demo-ac-bedroom"

    private let sampleDevices = [
        ThinQDevice(id: livingRoomID, name: "Sala (demonstração)", modelName: "DEMO-AC-01"),
        ThinQDevice(id: bedroomID, name: "Quarto (demonstração)", modelName: "DEMO-AC-02")
    ]
    private let sampleCapabilities = ACCapabilities(
        canControlPower: true,
        modes: ["COOL", "HEAT", "FAN", "DRY", "AUTO"],
        fanSpeeds: ["LOW", "MID", "HIGH", "AUTO"],
        temperature: TemperatureCapability(minimum: 16, maximum: 30, step: 1),
        canControlVerticalSwing: true,
        canControlHorizontalSwing: true
    )
    private var states: [String: ACState] = [
        livingRoomID: ACState(isOn: true, currentTemperature: 25, targetTemperature: 23, mode: "COOL", fanSpeed: "AUTO", verticalSwing: true, horizontalSwing: false),
        bedroomID: ACState(isOn: false, currentTemperature: 24, targetTemperature: 22, mode: "HEAT", fanSpeed: "LOW", verticalSwing: false, horizontalSwing: false)
    ]

    public init() {}

    public func devices() async throws -> [ThinQDevice] {
        sampleDevices
    }

    public func capabilities(for id: String) async throws -> ACCapabilities {
        try ensureDevice(id)
        return sampleCapabilities
    }

    public func state(for id: String) async throws -> ACState {
        try ensureDevice(id)
        guard let state = states[id] else { throw ThinQError.invalidResponse }
        return state
    }

    public func send(_ command: ThinQCommand, to id: String, capabilities: ACCapabilities) async throws {
        try ensureDevice(id)
        guard var current = states[id] else { throw ThinQError.invalidResponse }
        switch command {
        case .power(let enabled):
            guard capabilities.canControlPower else { throw ThinQError.unsupportedCommand("liga/desliga") }
            current.isOn = enabled
        case .temperature(let value):
            guard let capability = capabilities.temperature, capability.accepts(value) else {
                throw ThinQError.unsupportedCommand("temperatura fora dos limites ou da escala aceita")
            }
            current.targetTemperature = value
            current.temperatureUnit = capability.unit
        case .mode(let value):
            guard capabilities.modes.contains(value) else { throw ThinQError.unsupportedCommand("modo") }
            current.mode = value
        case .fanSpeed(let value):
            guard capabilities.fanSpeeds.contains(value) else { throw ThinQError.unsupportedCommand("ventilador") }
            current.fanSpeed = value
        case .verticalSwing(let enabled):
            guard capabilities.canControlVerticalSwing else { throw ThinQError.unsupportedCommand("oscilação vertical") }
            current.verticalSwing = enabled
        case .horizontalSwing(let enabled):
            guard capabilities.canControlHorizontalSwing else { throw ThinQError.unsupportedCommand("oscilação horizontal") }
            current.horizontalSwing = enabled
        }
        current.updatedAt = .now
        states[id] = current
    }

    private func ensureDevice(_ id: String) throws {
        guard states[id] != nil else { throw ThinQError.unsupportedCommand("aparelho não encontrado") }
    }
}
