import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor ThinQClient: ThinQService {
    private static let apiKey = "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3"

    private let token: String
    private let countryCode: String
    private let clientID: String
    private let baseURL: URL
    private let session: URLSession
    private var capabilitiesCache: [String: ACCapabilities] = [:]

    public init(
        token: String,
        countryCode: String,
        clientID: String,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) throws {
        let cleanedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedToken.isEmpty else { throw ThinQError.invalidToken }

        let cleanedCountry = countryCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let region = Self.region(for: cleanedCountry) else {
            throw ThinQError.unsupportedCountry(cleanedCountry)
        }
        let cleanedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedClientID.isEmpty else {
            throw ThinQError.invalidClientID
        }

        self.token = cleanedToken
        self.countryCode = cleanedCountry
        self.clientID = cleanedClientID
        self.baseURL = URL(string: "https://api-\(region).lgthinq.com")!
        self.session = session
    }

    public func devices() async throws -> [ThinQDevice] {
        let payload = try await request(path: "devices", method: "GET")
        guard let rows = payload.arrayValue else { throw ThinQError.invalidResponse }

        return rows.compactMap { row in
            guard
                let id = row["deviceId"]?.stringValue,
                let info = row["deviceInfo"],
                info["deviceType"]?.stringValue == "DEVICE_AIR_CONDITIONER"
            else { return nil }
            return ThinQDevice(
                id: id,
                name: info["alias"]?.stringValue ?? id,
                modelName: info["modelName"]?.stringValue
            )
        }
    }

    public func capabilities(for id: String) async throws -> ACCapabilities {
        let payload = try await request(path: "devices/\(Self.pathComponent(id))/profile", method: "GET")
        guard let properties = payload["property"] else { throw ThinQError.invalidResponse }

        let operation = properties["operation"]
        let powerDescriptor = operation?["airConOperationMode"]
        let powerValues = Self.writableValues(powerDescriptor)
        let powerOnValue = powerValues.first(where: { ["POWER_ON", "ON"].contains($0) })
        let powerOffValue = powerValues.first(where: { ["POWER_OFF", "OFF"].contains($0) })
        let hasOn = powerOnValue != nil
        let hasOff = powerOffValue != nil
        let powerPath = hasOn && hasOff && Self.isWritable(powerDescriptor)
            ? ThinQPropertyPath(resource: "operation", property: "airConOperationMode")
            : nil

        let jobModeDescriptor = properties["airConJobMode"]?["currentJobMode"]
        let jobModes = Self.writableValues(jobModeDescriptor)
        var modes = jobModes
        var modePath: ThinQPropertyPath? = jobModes.isEmpty
            ? nil
            : ThinQPropertyPath(resource: "airConJobMode", property: "currentJobMode")

        if modes.isEmpty, Self.isWritable(powerDescriptor) {
            let nonPowerModes = powerValues.filter { !["POWER_ON", "POWER_OFF", "ON", "OFF"].contains($0) }
            modes = nonPowerModes
            if !nonPowerModes.isEmpty {
                modePath = ThinQPropertyPath(resource: "operation", property: "airConOperationMode")
            }
        }

        let airFlow = properties["airFlow"]
        let fanProperty = airFlow?["windStrengthDetail"] != nil ? "windStrengthDetail" : "windStrength"
        let fanDescriptor = airFlow?[fanProperty]
        let fanSpeeds = Self.writableValues(fanDescriptor)
        let fanPath = fanSpeeds.isEmpty
            ? nil
            : ThinQPropertyPath(resource: "airFlow", property: fanProperty)

        let temperature = Self.temperatureCapability(in: properties)
        let verticalDescriptor = properties["windDirection"]?["rotateUpDown"]
        let horizontalDescriptor = properties["windDirection"]?["rotateLeftRight"]
        let verticalPath = Self.isWritable(verticalDescriptor)
            ? ThinQPropertyPath(resource: "windDirection", property: "rotateUpDown")
            : nil
        let horizontalPath = Self.isWritable(horizontalDescriptor)
            ? ThinQPropertyPath(resource: "windDirection", property: "rotateLeftRight")
            : nil

        let capabilities = ACCapabilities(
            canControlPower: powerPath != nil,
            modes: modes,
            fanSpeeds: fanSpeeds,
            temperature: temperature,
            canControlVerticalSwing: verticalPath != nil,
            canControlHorizontalSwing: horizontalPath != nil,
            powerPath: powerPath,
            powerOnValue: powerOnValue ?? "POWER_ON",
            powerOffValue: powerOffValue ?? "POWER_OFF",
            modePath: modePath,
            fanPath: fanPath,
            verticalSwingPath: verticalPath,
            horizontalSwingPath: horizontalPath
        )
        capabilitiesCache[id] = capabilities
        return capabilities
    }

    public func state(for id: String) async throws -> ACState {
        let payload = try await request(path: "devices/\(Self.pathComponent(id))/state", method: "GET")
        guard payload.objectValue != nil else { throw ThinQError.invalidResponse }

        let operation = payload["operation"]
        let operationMode = operation?["airConOperationMode"]?.scalarString
        let jobMode = payload["airConJobMode"]?["currentJobMode"]?.scalarString
        let isOn: Bool?
        switch operationMode?.uppercased() {
        case "POWER_ON", "ON": isOn = true
        case "POWER_OFF", "OFF": isOn = false
        default: isOn = nil
        }

        let preferredUnit = capabilitiesCache[id]?.temperature?.unit ?? "C"
        let temperatureFields = Self.temperatureState(in: payload, preferredUnit: preferredUnit)
        let airFlow = payload["airFlow"]
        let fanSpeed = airFlow?["windStrengthDetail"]?.scalarString ?? airFlow?["windStrength"]?.scalarString
        let verticalSwing = payload["windDirection"]?["rotateUpDown"]?.boolValue
        let horizontalSwing = payload["windDirection"]?["rotateLeftRight"]?.boolValue

        // Use a populated profile field as a signal that the response shape is valid.
        return ACState(
            isOn: isOn,
            currentTemperature: temperatureFields.current,
            targetTemperature: temperatureFields.target,
            temperatureUnit: temperatureFields.unit,
            mode: jobMode ?? (isOn == nil ? operationMode : nil),
            fanSpeed: fanSpeed,
            verticalSwing: verticalSwing,
            horizontalSwing: horizontalSwing
        )
    }

    public func send(_ command: ThinQCommand, to id: String, capabilities: ACCapabilities) async throws {
        var body: [String: JSONValue] = [:]
        switch command {
        case .power(let enabled):
            guard capabilities.canControlPower, let path = capabilities.powerPath else {
                throw ThinQError.unsupportedCommand("liga/desliga")
            }
            body.set(.string(enabled ? capabilities.powerOnValue : capabilities.powerOffValue), at: path)
        case .temperature(let value):
            guard let capability = capabilities.temperature, capability.accepts(value) else {
                throw ThinQError.unsupportedCommand("temperatura fora dos limites ou da escala aceita")
            }
            body.set(.number(value), at: .init(resource: capability.resource, property: capability.property))
            if let unitProperty = capability.unitProperty {
                body.set(.string(capability.unit), at: .init(resource: capability.resource, property: unitProperty))
            }
        case .mode(let value):
            guard capabilities.modes.contains(value), let path = capabilities.modePath else {
                throw ThinQError.unsupportedCommand("modo não disponível para este aparelho")
            }
            body.set(.string(value), at: path)
        case .fanSpeed(let value):
            guard capabilities.fanSpeeds.contains(value), let path = capabilities.fanPath else {
                throw ThinQError.unsupportedCommand("velocidade do ventilador não disponível")
            }
            body.set(.string(value), at: path)
        case .verticalSwing(let enabled):
            guard capabilities.canControlVerticalSwing, let path = capabilities.verticalSwingPath else {
                throw ThinQError.unsupportedCommand("oscilação vertical não disponível")
            }
            body.set(.bool(enabled), at: path)
        case .horizontalSwing(let enabled):
            guard capabilities.canControlHorizontalSwing, let path = capabilities.horizontalSwingPath else {
                throw ThinQError.unsupportedCommand("oscilação horizontal não disponível")
            }
            body.set(.bool(enabled), at: path)
        }
        _ = try await request(
            path: "devices/\(Self.pathComponent(id))/control",
            method: "POST",
            body: .object(body),
            conditionalControl: true
        )
    }

    private func request(
        path: String,
        method: String,
        body: JSONValue? = nil,
        conditionalControl: Bool = false
    ) async throws -> JSONValue {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw ThinQError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(countryCode, forHTTPHeaderField: "x-country")
        request.setValue(Self.messageID(), forHTTPHeaderField: "x-message-id")
        request.setValue(clientID, forHTTPHeaderField: "x-client-id")
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("OP", forHTTPHeaderField: "x-service-phase")
        if conditionalControl {
            request.setValue("true", forHTTPHeaderField: "x-conditional-control")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ThinQError.timeout
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ThinQError.noInternet
        } catch {
            // Avoid returning the underlying URL error text, which may contain request details.
            throw ThinQError.transport(String(describing: type(of: error)))
        }
        guard let http = response as? HTTPURLResponse else { throw ThinQError.invalidResponse }
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            if !(200..<300).contains(http.statusCode) {
                throw ThinQError.httpStatus(http.statusCode)
            }
            throw ThinQError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if let error = root["error"] {
                let code = error["code"]?.scalarString ?? "HTTP_\(http.statusCode)"
                let message = error["message"]?.stringValue ?? "A solicitação não foi aceita."
                if Self.isKnownAPICode(code) {
                    throw ThinQError.api(code: code, message: message)
                }
            }
            throw ThinQError.httpStatus(http.statusCode)
        }
        guard let payload = root["response"] else { throw ThinQError.invalidResponse }
        return payload
    }

    private static func region(for country: String) -> String? {
        let kic: Set<String> = ["AU", "BD", "CN", "HK", "ID", "IN", "JP", "KH", "KR", "LA", "LK", "MM", "MY", "NP", "NZ", "PH", "SG", "TH", "TW", "VN"]
        let aic: Set<String> = ["AG", "AR", "AW", "BB", "BO", "BR", "BS", "BZ", "CA", "CL", "CO", "CR", "CU", "DM", "DO", "EC", "GD", "GT", "GY", "HN", "HT", "JM", "KN", "LC", "MX", "NI", "PA", "PE", "PR", "PY", "SR", "SV", "TT", "US", "UY", "VC", "VE"]
        let eic: Set<String> = ["AE", "AF", "AL", "AM", "AO", "AT", "AZ", "BA", "BE", "BF", "BG", "BH", "BJ", "BY", "CD", "CF", "CG", "CH", "CI", "CM", "CV", "CY", "CZ", "DE", "DJ", "DK", "DZ", "EE", "EG", "ES", "ET", "FI", "FR", "GA", "GB", "GE", "GH", "GM", "GN", "GQ", "GR", "HR", "HU", "IE", "IL", "IQ", "IR", "IS", "IT", "JO", "KE", "KG", "KW", "KZ", "LB", "LR", "LT", "LU", "LV", "LY", "MA", "MD", "ME", "MK", "ML", "MR", "MT", "MU", "MW", "NE", "NG", "NL", "NO", "OM", "PK", "PL", "PS", "PT", "QA", "RO", "RS", "RU", "RW", "SA", "SD", "SE", "SI", "SK", "SL", "SN", "SO", "ST", "SY", "TD", "TG", "TN", "TR", "TZ", "UA", "UG", "UZ", "XK", "YE", "ZA", "ZM"]
        if kic.contains(country) { return "kic" }
        if aic.contains(country) { return "aic" }
        if eic.contains(country) { return "eic" }
        return nil
    }

    private static func isKnownAPICode(_ code: String) -> Bool {
        ["1103", "1218", "1222", "1306", "1308", "2000", "2207", "2209", "2210", "2301", "2302", "2303", "2304", "2305"].contains(code)
    }

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func messageID() -> String {
        var uuid = UUID().uuid
        let bytes = withUnsafeBytes(of: &uuid) { Data($0) }
        return bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isWritable(_ descriptor: JSONValue?) -> Bool {
        guard let mode = descriptor?["mode"] else { return false }
        if mode.arrayValue?.contains(.string("w")) == true { return true }
        return mode.stringValue?.contains("w") == true
    }

    private static func writableValues(_ descriptor: JSONValue?) -> [String] {
        guard isWritable(descriptor), let values = descriptor?["value"]?["w"]?.arrayValue else { return [] }
        return values.compactMap(\.stringValue)
    }

    private static func temperatureCapability(in properties: JSONValue) -> TemperatureCapability? {
        let candidates: [(String, JSONValue)] = [
            ("temperatureInUnits", properties["temperatureInUnits"]),
            ("temperature", properties["temperature"])
        ].compactMap { entry -> (String, JSONValue)? in
            guard let value = entry.1 else { return nil }
            return (entry.0, value)
        }

        for (resource, value) in candidates {
            let entries: [JSONValue]
            if let array = value.arrayValue {
                entries = array
            } else {
                entries = [value]
            }
            let ordered = entries.sorted { lhs, rhs in
                (lhs["unit"]?.stringValue == "C") && (rhs["unit"]?.stringValue != "C")
            }
            for entry in ordered {
                let unit = entry["unit"]?.stringValue ?? "C"
                let propertiesToCheck: [(String, String)] = [
                    ("targetTemperature", "targetTemperature"),
                    ("targetTemperature\(unit)", "targetTemperature")
                ]
                for (profileKey, commandKey) in propertiesToCheck {
                    guard let descriptor = entry[profileKey], isWritable(descriptor) else { continue }
                    guard let range = temperatureRange(from: descriptor) else { continue }
                    let commandResource = resource == "temperature" ? "temperature" : resource
                    let property = commandKey
                    let unitProperty = entry["unit"] != nil ? "unit" : nil
                    return TemperatureCapability(
                        minimum: range.minimum,
                        maximum: range.maximum,
                        step: range.step,
                        unit: unit,
                        except: range.except,
                        resource: commandResource,
                        property: property,
                        unitProperty: unitProperty
                    )
                }
            }
        }
        return nil
    }

    private static func temperatureRange(from descriptor: JSONValue) -> (minimum: Double, maximum: Double, step: Double, except: [Double])? {
        let writeRange = descriptor["value"]?["w"]
        let min = writeRange?["min"]?.numberValue ?? descriptor["min"]?.numberValue
        let max = writeRange?["max"]?.numberValue ?? descriptor["max"]?.numberValue
        guard let min, let max, min.isFinite, max.isFinite, min <= max else { return nil }
        let step = writeRange?["step"]?.numberValue ?? descriptor["step"]?.numberValue ?? 1
        guard step > 0, step.isFinite else { return nil }
        let except = writeRange?["except"]?.arrayValue?.compactMap(\.numberValue)
            ?? descriptor["except"]?.arrayValue?.compactMap(\.numberValue)
            ?? []
        return (min, max, step, except)
    }

    private static func temperatureState(
        in payload: JSONValue,
        preferredUnit: String
    ) -> (current: Double?, target: Double?, unit: String) {
        for resource in ["temperatureInUnits", "temperature"] {
            guard let value = payload[resource] else { continue }
            let entries = value.arrayValue ?? [value]
            let chosen = entries.first(where: { $0["unit"]?.stringValue?.uppercased() == preferredUnit.uppercased() })
                ?? entries.first
            guard let chosen else { continue }
            let unit = chosen["unit"]?.stringValue ?? "C"
            let current = chosen["currentTemperature"]?.numberValue
                ?? chosen["currentTemperature\(unit)"]?.numberValue
            let target = chosen["targetTemperature"]?.numberValue
                ?? chosen["targetTemperature\(unit)"]?.numberValue
            if current != nil || target != nil {
                let normalizedCurrent = convertTemperature(current, from: unit, to: preferredUnit)
                let normalizedTarget = convertTemperature(target, from: unit, to: preferredUnit)
                return (normalizedCurrent, normalizedTarget, preferredUnit)
            }
        }
        return (nil, nil, preferredUnit)
    }

    private static func convertTemperature(_ value: Double?, from source: String, to target: String) -> Double? {
        guard let value, source.uppercased() != target.uppercased() else { return value }
        switch (source.uppercased(), target.uppercased()) {
        case ("C", "F"): return value * 9 / 5 + 32
        case ("F", "C"): return (value - 32) * 5 / 9
        default: return value
        }
    }
}

private extension JSONValue {
    var scalarString: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    mutating func set(_ value: JSONValue, at path: ThinQPropertyPath) {
        var resource = self[path.resource]?.objectValue ?? [:]
        resource[path.property] = value
        self[path.resource] = .object(resource)
    }
}
