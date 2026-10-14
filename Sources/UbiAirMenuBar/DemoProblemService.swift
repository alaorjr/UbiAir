import ThinQCore

/// Development-only scenarios. This service never connects to LG or reads a PAT.
enum DemoProblemScenario: String {
    case offline, internet, timeout, authentication, limit, service, empty
}

actor DemoProblemService: ThinQService {
    private let demo = DemoThinQService()
    private let scenario: DemoProblemScenario

    init(_ scenario: DemoProblemScenario) { self.scenario = scenario }

    func devices() async throws -> [ThinQDevice] {
        if scenario == .empty { return [] }
        return try await demo.devices()
    }

    func capabilities(for id: String) async throws -> ACCapabilities {
        try await demo.capabilities(for: id)
    }

    func state(for id: String) async throws -> ACState {
        if id == DemoThinQService.livingRoomID {
            switch scenario {
            case .offline: throw ThinQError.api(code: "1222", message: "")
            case .internet: throw ThinQError.noInternet
            case .timeout: throw ThinQError.timeout
            case .authentication: throw ThinQError.invalidToken
            case .limit: throw ThinQError.httpStatus(429)
            case .service: throw ThinQError.httpStatus(503)
            case .empty: break
            }
        }
        return try await demo.state(for: id)
    }

    func send(_ command: ThinQCommand, to id: String, capabilities: ACCapabilities) async throws {
        try await demo.send(command, to: id, capabilities: capabilities)
    }
}
