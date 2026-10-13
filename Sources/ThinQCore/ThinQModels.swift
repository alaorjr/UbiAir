import Foundation

public protocol ThinQService: Sendable {
    func devices() async throws -> [ThinQDevice]
    func capabilities(for id: String) async throws -> ACCapabilities
    func state(for id: String) async throws -> ACState
    func send(_ command: ThinQCommand, to id: String, capabilities: ACCapabilities) async throws
}

public struct ThinQDevice: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let modelName: String?

    public init(id: String, name: String, modelName: String? = nil) {
        self.id = id
        self.name = name
        self.modelName = modelName
    }
}

public struct ACState: Sendable, Equatable {
    public var isOn: Bool?
    public var currentTemperature: Double?
    public var targetTemperature: Double?
    public var temperatureUnit: String
    public var mode: String?
    public var fanSpeed: String?
    public var verticalSwing: Bool?
    public var horizontalSwing: Bool?
    public var updatedAt: Date

    public init(
        isOn: Bool? = nil,
        currentTemperature: Double? = nil,
        targetTemperature: Double? = nil,
        temperatureUnit: String = "C",
        mode: String? = nil,
        fanSpeed: String? = nil,
        verticalSwing: Bool? = nil,
        horizontalSwing: Bool? = nil,
        updatedAt: Date = .now
    ) {
        self.isOn = isOn
        self.currentTemperature = currentTemperature
        self.targetTemperature = targetTemperature
        self.temperatureUnit = temperatureUnit
        self.mode = mode
        self.fanSpeed = fanSpeed
        self.verticalSwing = verticalSwing
        self.horizontalSwing = horizontalSwing
        self.updatedAt = updatedAt
    }
}

public struct TemperatureCapability: Sendable, Equatable {
    public let minimum: Double
    public let maximum: Double
    public let step: Double
    public let unit: String
    public let except: [Double]

    // These wire names are profile-specific and stay internal to the networking layer.
    let resource: String
    let property: String
    let unitProperty: String?

    public init(
        minimum: Double,
        maximum: Double,
        step: Double,
        unit: String = "C",
        except: [Double] = []
    ) {
        self.init(
            minimum: minimum,
            maximum: maximum,
            step: step,
            unit: unit,
            except: except,
            resource: "temperatureInUnits",
            property: "targetTemperature",
            unitProperty: "unit"
        )
    }

    init(
        minimum: Double,
        maximum: Double,
        step: Double,
        unit: String,
        except: [Double],
        resource: String,
        property: String,
        unitProperty: String?
    ) {
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.unit = unit
        self.except = except
        self.resource = resource
        self.property = property
        self.unitProperty = unitProperty
    }

    public func accepts(_ value: Double) -> Bool {
        guard value.isFinite, step > 0, value >= minimum, value <= maximum else { return false }
        guard !except.contains(where: { abs($0 - value) < 0.000_001 }) else { return false }
        let increments = (value - minimum) / step
        return abs(increments - increments.rounded()) < 0.000_001
    }
}

public struct ACCapabilities: Sendable, Equatable {
    public let canControlPower: Bool
    public let modes: [String]
    public let fanSpeeds: [String]
    public let temperature: TemperatureCapability?
    public let canControlVerticalSwing: Bool
    public let canControlHorizontalSwing: Bool

    let powerPath: ThinQPropertyPath?
    let powerOnValue: String
    let powerOffValue: String
    let modePath: ThinQPropertyPath?
    let fanPath: ThinQPropertyPath?
    let verticalSwingPath: ThinQPropertyPath?
    let horizontalSwingPath: ThinQPropertyPath?

    public init(
        canControlPower: Bool = false,
        modes: [String] = [],
        fanSpeeds: [String] = [],
        temperature: TemperatureCapability? = nil,
        canControlVerticalSwing: Bool = false,
        canControlHorizontalSwing: Bool = false
    ) {
        self.init(
            canControlPower: canControlPower,
            modes: modes,
            fanSpeeds: fanSpeeds,
            temperature: temperature,
            canControlVerticalSwing: canControlVerticalSwing,
            canControlHorizontalSwing: canControlHorizontalSwing,
            powerPath: canControlPower ? .init(resource: "operation", property: "airConOperationMode") : nil,
            powerOnValue: "POWER_ON",
            powerOffValue: "POWER_OFF",
            modePath: modes.isEmpty ? nil : .init(resource: "airConJobMode", property: "currentJobMode"),
            fanPath: fanSpeeds.isEmpty ? nil : .init(resource: "airFlow", property: "windStrength"),
            verticalSwingPath: canControlVerticalSwing ? .init(resource: "windDirection", property: "rotateUpDown") : nil,
            horizontalSwingPath: canControlHorizontalSwing ? .init(resource: "windDirection", property: "rotateLeftRight") : nil
        )
    }

    init(
        canControlPower: Bool,
        modes: [String],
        fanSpeeds: [String],
        temperature: TemperatureCapability?,
        canControlVerticalSwing: Bool,
        canControlHorizontalSwing: Bool,
        powerPath: ThinQPropertyPath?,
        powerOnValue: String,
        powerOffValue: String,
        modePath: ThinQPropertyPath?,
        fanPath: ThinQPropertyPath?,
        verticalSwingPath: ThinQPropertyPath?,
        horizontalSwingPath: ThinQPropertyPath?
    ) {
        self.canControlPower = canControlPower
        self.modes = modes
        self.fanSpeeds = fanSpeeds
        self.temperature = temperature
        self.canControlVerticalSwing = canControlVerticalSwing
        self.canControlHorizontalSwing = canControlHorizontalSwing
        self.powerPath = powerPath
        self.powerOnValue = powerOnValue
        self.powerOffValue = powerOffValue
        self.modePath = modePath
        self.fanPath = fanPath
        self.verticalSwingPath = verticalSwingPath
        self.horizontalSwingPath = horizontalSwingPath
    }
}

public enum ThinQCommand: Sendable, Equatable {
    case power(Bool)
    case temperature(Double)
    case mode(String)
    case fanSpeed(String)
    case verticalSwing(Bool)
    case horizontalSwing(Bool)

    public func isConfirmed(by state: ACState) -> Bool {
        switch self {
        case .power(let expected): return state.isOn == expected
        case .temperature(let expected):
            guard let actual = state.targetTemperature else { return false }
            return abs(actual - expected) < 0.000_001
        case .mode(let expected): return state.mode == expected
        case .fanSpeed(let expected): return state.fanSpeed == expected
        case .verticalSwing(let expected): return state.verticalSwing == expected
        case .horizontalSwing(let expected): return state.horizontalSwing == expected
        }
    }
}

public enum ThinQError: Error, Sendable, LocalizedError, Equatable {
    case invalidToken
    case invalidClientID
    case unsupportedCountry(String)
    case invalidResponse
    case unsupportedCommand(String)
    case api(code: String, message: String)
    case httpStatus(Int)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidToken: return "Informe um Personal Access Token válido da LG ThinQ."
        case .invalidClientID: return "Informe um identificador estável para este cliente ThinQ."
        case .unsupportedCountry(let code): return "O país “\(code)” não é compatível com a API LG ThinQ Connect."
        case .invalidResponse: return "A resposta da LG ThinQ não está em um formato reconhecido."
        case .unsupportedCommand(let command): return "O aparelho não oferece suporte ao comando “\(command)”."
        case .api(let code, let message):
            switch code {
            case "1103", "1218": return "O Personal Access Token da LG ThinQ é inválido ou expirou. Conecte sua conta novamente."
            case "1222": return "O aparelho está desconectado da LG ThinQ no momento."
            case "1306": return "O limite de solicitações da LG ThinQ foi atingido. Aguarde antes de tentar novamente."
            case "1308": return "Esta conta não tem permissão para controlar o aparelho."
            default: return "A LG ThinQ recusou a solicitação (\(code)): \(message)"
            }
        case .httpStatus(let status): return "A LG ThinQ retornou um erro HTTP (\(status))."
        case .transport(_): return "Não foi possível conectar à LG ThinQ. Verifique a conexão e tente novamente."
        }
    }
}

struct ThinQPropertyPath: Sendable, Equatable {
    let resource: String
    let property: String
}
