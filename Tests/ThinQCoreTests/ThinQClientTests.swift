import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ThinQCore

final class ThinQClientTests: XCTestCase {
    func testCountryAndTokenValidation() throws {
        XCTAssertThrowsError(try ThinQClient(token: " ", countryCode: "BR", clientID: "stable")) { error in
            XCTAssertEqual(error as? ThinQError, .invalidToken)
        }
        XCTAssertThrowsError(try ThinQClient(token: "token", countryCode: "ZZ", clientID: "stable")) { error in
            XCTAssertEqual(error as? ThinQError, .unsupportedCountry("ZZ"))
        }
        XCTAssertThrowsError(try ThinQClient(token: "token", countryCode: "BR", clientID: " ")) { error in
            XCTAssertEqual(error as? ThinQError, .invalidClientID)
        }
    }

    func testHeadersRegionalHostAndAirConditionerFiltering() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.append(request)
            return (200, jsonData("""
            {"response":[
              {"deviceId":"ac-1","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER","alias":"Sala","modelName":"MODEL-1"}},
              {"deviceId":"washer-1","deviceInfo":{"deviceType":"DEVICE_WASHER","alias":"Lavadora","modelName":"MODEL-2"}}
            ]}
            """))
        }
        let client = try ThinQClient(token: "pat-example", countryCode: "br", clientID: "stable-client", session: session)

        let devices = try await client.devices()

        XCTAssertEqual(devices, [ThinQDevice(id: "ac-1", name: "Sala", modelName: "MODEL-1")])
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.host, "api-aic.lgthinq.com")
        XCTAssertEqual(request.url?.path, "/devices")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pat-example")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-country"), "BR")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-client-id"), "stable-client")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-service-phase"), "OP")
        let messageID = try XCTUnwrap(request.value(forHTTPHeaderField: "x-message-id"))
        XCTAssertEqual(messageID.count, 22)
        XCTAssertTrue(messageID.range(of: #"^[A-Za-z0-9_-]{22}$"#, options: .regularExpression) != nil)
    }

    func testAPIErrorEnvelopeIsTypedAndLocalized() async throws {
        let session = makeSession { _ in
            (401, jsonData("""
            {"error":{"code":"1103","message":"Invalid token"}}
            """))
        }
        let client = try ThinQClient(token: "invalid-pat", countryCode: "BR", clientID: "stable", session: session)

        do {
            _ = try await client.devices()
            XCTFail("Esperava erro da API")
        } catch let error as ThinQError {
            XCTAssertEqual(error, .api(code: "1103", message: "Invalid token"))
            XCTAssertTrue(error.localizedDescription.contains("Token da LG ThinQ"))
            XCTAssertFalse(error.localizedDescription.contains("invalid-pat"))
        }
    }

    func testCapabilitiesHonorWritableModesAndTemperatureUnitArray() async throws {
        let session = makeSession { _ in
            (200, jsonData("""
            {"response":{"property":{
              "operation":{"airConOperationMode":{"type":"enum","mode":["r"],"value":{"r":["POWER_ON","POWER_OFF"]}}},
              "airConJobMode":{"currentJobMode":{"type":"enum","mode":["r","w"],"value":{"r":["COOL","DRY"],"w":["COOL","DRY"]}}},
              "airFlow":{"windStrength":{"type":"enum","mode":["r"],"value":{"r":["LOW","HIGH"]}}},
              "temperatureInUnits":[
                {"unit":"F","targetTemperature":{"type":"range","mode":["r","w"],"value":{"r":{"min":60,"max":86,"step":2},"w":{"min":60,"max":86,"step":2}}}},
                {"unit":"C","targetTemperature":{"type":"range","mode":["r","w"],"value":{"r":{"min":16,"max":30,"step":1,"except":[20]},"w":{"min":16,"max":30,"step":1,"except":[20]}}}}
              ],
              "windDirection":{"rotateUpDown":{"type":"boolean","mode":["r","w"]},"rotateLeftRight":{"type":"boolean","mode":["r"]}}
            }}}
            """))
        }
        let client = try ThinQClient(token: "pat", countryCode: "BR", clientID: "stable", session: session)

        let capabilities = try await client.capabilities(for: "ac-1")

        XCTAssertFalse(capabilities.canControlPower)
        XCTAssertEqual(capabilities.modes, ["COOL", "DRY"])
        XCTAssertTrue(capabilities.fanSpeeds.isEmpty)
        XCTAssertTrue(capabilities.canControlVerticalSwing)
        XCTAssertFalse(capabilities.canControlHorizontalSwing)
        XCTAssertEqual(capabilities.temperature?.unit, "C")
        XCTAssertEqual(capabilities.temperature?.minimum, 16)
        XCTAssertEqual(capabilities.temperature?.maximum, 30)
        XCTAssertEqual(capabilities.temperature?.step, 1)
        XCTAssertEqual(capabilities.temperature?.except, [20])
    }

    func testTemperatureValidationPayloadAndStateParsing() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.append(request)
            switch request.url?.path {
            case "/devices/ac-1/profile":
                return (200, jsonData("""
                {"response":{"property":{
                  "operation":{"airConOperationMode":{"type":"enum","mode":["r","w"],"value":{"r":["POWER_ON","POWER_OFF"],"w":["POWER_ON","POWER_OFF"]}}},
                  "airConJobMode":{"currentJobMode":{"type":"enum","mode":["r","w"],"value":{"r":["COOL","HEAT"],"w":["COOL","HEAT"]}}},
                  "airFlow":{"windStrengthDetail":{"type":"enum","mode":["r","w"],"value":{"r":["LOW","HIGH"],"w":["LOW","HIGH"]}}},
                  "temperatureInUnits":[
                    {"unit":"C","targetTemperature":{"type":"range","mode":["r","w"],"value":{"r":{"min":16,"max":30,"step":1,"except":[20]},"w":{"min":16,"max":30,"step":1,"except":[20]}}}},
                    {"unit":"F","targetTemperature":{"type":"range","mode":["r","w"],"value":{"r":{"min":60,"max":86,"step":2},"w":{"min":60,"max":86,"step":2}}}}
                  ],
                  "windDirection":{"rotateUpDown":{"type":"boolean","mode":["r","w"]},"rotateLeftRight":{"type":"boolean","mode":["r","w"]}}
                }}}
                """))
            case "/devices/ac-1/control":
                return (200, jsonData(#"{"response":{}}"#))
            case "/devices/ac-1/state":
                return (200, jsonData("""
                {"response":{"operation":{"airConOperationMode":"POWER_ON"},"airConJobMode":{"currentJobMode":"COOL"},"temperatureInUnits":[{"unit":"C","currentTemperature":25,"targetTemperature":24},{"unit":"F","currentTemperature":77,"targetTemperature":75}],"airFlow":{"windStrengthDetail":"HIGH"},"windDirection":{"rotateUpDown":true,"rotateLeftRight":false}}}
                """))
            default:
                return (404, jsonData(#"{"error":{"code":"404","message":"not found"}}"#))
            }
        }
        let client = try ThinQClient(token: "pat", countryCode: "BR", clientID: "stable", session: session)
        let capabilities = try await client.capabilities(for: "ac-1")

        try await client.send(.temperature(24), to: "ac-1", capabilities: capabilities)
        let post = try XCTUnwrap(recorder.requests.first(where: { $0.httpMethod == "POST" }))
        XCTAssertEqual(post.value(forHTTPHeaderField: "x-conditional-control"), "true")
        let postedJSON = try XCTUnwrap(post.httpBody).withJSONValue()
        XCTAssertEqual(postedJSON["temperatureInUnits"]?["targetTemperature"]?.numberValue, 24)
        XCTAssertEqual(postedJSON["temperatureInUnits"]?["unit"]?.stringValue, "C")
        XCTAssertNil(postedJSON["temperatureInUnits"]?.arrayValue)

        do {
            try await client.send(.temperature(20), to: "ac-1", capabilities: capabilities)
            XCTFail("A exceção do perfil deve bloquear o comando")
        } catch let error as ThinQError {
            XCTAssertEqual(error, .unsupportedCommand("temperatura fora dos limites ou da escala aceita"))
        }
        do {
            try await client.send(.temperature(24.5), to: "ac-1", capabilities: capabilities)
            XCTFail("A etapa do perfil deve ser respeitada")
        } catch let error as ThinQError {
            XCTAssertEqual(error, .unsupportedCommand("temperatura fora dos limites ou da escala aceita"))
        }
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 1)

        let state = try await client.state(for: "ac-1")
        XCTAssertEqual(state.isOn, true)
        XCTAssertEqual(state.currentTemperature, 25)
        XCTAssertEqual(state.targetTemperature, 24)
        XCTAssertEqual(state.temperatureUnit, "C")
        XCTAssertEqual(state.mode, "COOL")
        XCTAssertEqual(state.fanSpeed, "HIGH")
        XCTAssertEqual(state.verticalSwing, true)
        XCTAssertEqual(state.horizontalSwing, false)
        XCTAssertTrue(ThinQCommand.temperature(24).isConfirmed(by: state))
        XCTAssertTrue(ThinQCommand.power(true).isConfirmed(by: state))
        XCTAssertFalse(ThinQCommand.mode("HEAT").isConfirmed(by: state))
    }

    func testControlPayloadUsesProfilePathsAndRejectsUnknownEnums() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.append(request)
            if request.url?.path == "/devices/ac-1/profile" {
                return (200, jsonData("""
                {"response":{"property":{
                  "operation":{"airConOperationMode":{"type":"enum","mode":["r","w"],"value":{"r":["POWER_ON","POWER_OFF"],"w":["POWER_ON","POWER_OFF"]}}},
                  "airConJobMode":{"currentJobMode":{"type":"enum","mode":["r","w"],"value":{"r":["COOL","HEAT"],"w":["COOL","HEAT"]}}},
                  "airFlow":{"windStrength":{"type":"enum","mode":["r","w"],"value":{"r":["LOW","HIGH"],"w":["LOW","HIGH"]}}},
                  "temperatureInUnits":[{"unit":"C","targetTemperature":{"type":"range","mode":["r","w"],"value":{"w":{"min":16,"max":30,"step":1}}}}],
                  "windDirection":{"rotateUpDown":{"type":"boolean","mode":["w"]},"rotateLeftRight":{"type":"boolean","mode":["w"]}}
                }}}
                """))
            }
            return (200, jsonData(#"{"response":{}}"#))
        }
        let client = try ThinQClient(token: "pat", countryCode: "BR", clientID: "stable", session: session)
        let capabilities = try await client.capabilities(for: "ac-1")

        try await client.send(.power(true), to: "ac-1", capabilities: capabilities)
        try await client.send(.mode("HEAT"), to: "ac-1", capabilities: capabilities)
        try await client.send(.fanSpeed("HIGH"), to: "ac-1", capabilities: capabilities)
        try await client.send(.verticalSwing(true), to: "ac-1", capabilities: capabilities)
        try await client.send(.horizontalSwing(false), to: "ac-1", capabilities: capabilities)
        do {
            try await client.send(.mode("AUTO"), to: "ac-1", capabilities: capabilities)
            XCTFail("Enum ausente no perfil deve ser rejeitado")
        } catch let error as ThinQError {
            XCTAssertEqual(error, .unsupportedCommand("modo não disponível para este aparelho"))
        }

        let controls = recorder.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(controls.count, 5)
        let bodies = try controls.map { try XCTUnwrap($0.httpBody).withJSONValue() }
        XCTAssertEqual(bodies[0]["operation"]?["airConOperationMode"]?.stringValue, "POWER_ON")
        XCTAssertEqual(bodies[1]["airConJobMode"]?["currentJobMode"]?.stringValue, "HEAT")
        XCTAssertEqual(bodies[2]["airFlow"]?["windStrength"]?.stringValue, "HIGH")
        XCTAssertEqual(bodies[3]["windDirection"]?["rotateUpDown"]?.boolValue, true)
        XCTAssertEqual(bodies[4]["windDirection"]?["rotateLeftRight"]?.boolValue, false)
        let messageIDs = try controls.map { try XCTUnwrap($0.value(forHTTPHeaderField: "x-message-id")) }
        XCTAssertEqual(Set(messageIDs).count, messageIDs.count)
    }

    func testSingleObjectTemperatureProfileAndStateAreAccepted() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.append(request)
            switch request.url?.path {
            case "/devices/ac-legacy/profile":
                return (200, jsonData("""
                {"response":{"property":{"temperature":{"unit":"C","targetTemperature":{"type":"range","mode":["r","w"],"value":{"w":{"min":17,"max":29,"step":0.5}}}}}}}
                """))
            case "/devices/ac-legacy/state":
                return (200, jsonData(#"{"response":{"temperature":{"unit":"C","currentTemperature":23.5,"targetTemperature":24}}}"#))
            default:
                return (200, jsonData(#"{"response":{}}"#))
            }
        }
        let client = try ThinQClient(token: "pat", countryCode: "BR", clientID: "stable", session: session)
        let capabilities = try await client.capabilities(for: "ac-legacy")

        XCTAssertEqual(capabilities.temperature?.minimum, 17)
        XCTAssertEqual(capabilities.temperature?.step, 0.5)
        try await client.send(.temperature(24.5), to: "ac-legacy", capabilities: capabilities)
        let post = try XCTUnwrap(recorder.requests.first(where: { $0.httpMethod == "POST" }))
        let body = try XCTUnwrap(post.httpBody).withJSONValue()
        XCTAssertEqual(body["temperature"]?["targetTemperature"]?.numberValue, 24.5)
        XCTAssertEqual(body["temperature"]?["unit"]?.stringValue, "C")

        let state = try await client.state(for: "ac-legacy")
        XCTAssertEqual(state.currentTemperature, 23.5)
        XCTAssertEqual(state.targetTemperature, 24)
    }

    func testWritableFahrenheitCapabilityKeepsStatusValuesInFahrenheit() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.append(request)
            switch request.url?.path {
            case "/devices/ac-fahrenheit/profile":
                return (200, jsonData("""
                {"response":{"property":{"temperatureInUnits":[
                  {"unit":"C","targetTemperature":{"type":"range","mode":["r"],"value":{"r":{"min":16,"max":30,"step":1}}}},
                  {"unit":"F","targetTemperature":{"type":"range","mode":"rw","value":{"w":{"min":60,"max":86,"step":2}}}}
                ]}}}
                """))
            case "/devices/ac-fahrenheit/state":
                return (200, jsonData("""
                {"response":{"temperatureInUnits":[{"unit":"C","currentTemperature":25,"targetTemperature":24},{"unit":"F","currentTemperature":77,"targetTemperature":75}]}}
                """))
            default:
                return (200, jsonData(#"{"response":{}}"#))
            }
        }
        let client = try ThinQClient(token: "pat", countryCode: "BR", clientID: "stable", session: session)
        let capabilities = try await client.capabilities(for: "ac-fahrenheit")

        XCTAssertEqual(capabilities.temperature?.unit, "F")
        try await client.send(.temperature(76), to: "ac-fahrenheit", capabilities: capabilities)
        let post = try XCTUnwrap(recorder.requests.first(where: { $0.httpMethod == "POST" }))
        let body = try XCTUnwrap(post.httpBody).withJSONValue()
        XCTAssertEqual(body["temperatureInUnits"]?["targetTemperature"]?.numberValue, 76)
        XCTAssertEqual(body["temperatureInUnits"]?["unit"]?.stringValue, "F")

        let state = try await client.state(for: "ac-fahrenheit")
        XCTAssertEqual(state.temperatureUnit, "F")
        XCTAssertEqual(state.currentTemperature, 77)
        XCTAssertEqual(state.targetTemperature, 75)
    }

    func testDemoServiceMutatesOnlyItsFictionalInMemoryState() async throws {
        let demo = DemoThinQService()
        let devices = try await demo.devices()
        XCTAssertEqual(devices.count, 2)
        XCTAssertTrue(devices.allSatisfy { $0.name.contains("demonstração") })
        let id = try XCTUnwrap(devices.first?.id)
        let capabilities = try await demo.capabilities(for: id)
        try await demo.send(.temperature(27), to: id, capabilities: capabilities)
        let state = try await demo.state(for: id)
        XCTAssertEqual(state.targetTemperature, 27)
        XCTAssertTrue(ThinQCommand.temperature(27).isConfirmed(by: state))
    }

    private func makeSession(handler: @escaping @Sendable (URLRequest) -> (Int, Data)) -> URLSession {
        StubURLProtocol.install(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

}

private func jsonData(_ text: String) -> Data {
    Data(text.utf8)
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func append(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = Self.read(stream)
        }
        stored.append(recorded)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    static func install(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        self.handler = handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: ThinQError.invalidResponse)
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Data {
    func withJSONValue() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: self)
    }
}
