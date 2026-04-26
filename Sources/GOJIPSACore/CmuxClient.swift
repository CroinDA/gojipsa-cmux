import Foundation

/// cmux 소켓 API에 접근하는 애플리케이션 포트입니다.
///
/// `CmuxClient`는 CLI/RPC 호출과 JSON 디코딩만 담당합니다. 어떤 surface를 읽을지,
/// 읽은 텍스트를 Gemini에 보낼지는 상위 계층에서 결정합니다.
public struct CmuxClient: Sendable {
    public let configuration: CmuxConfiguration
    private let runner: any CmuxCommandRunning

    public init(configuration: CmuxConfiguration = .current()) {
        self.configuration = configuration
        self.runner = CmuxProcessRunner(configuration: configuration)
    }

    public init(configuration: CmuxConfiguration, runner: any CmuxCommandRunning) {
        self.configuration = configuration
        self.runner = runner
    }

    /// cmux 실행 파일을 찾았는지 여부입니다.
    public var isConfigured: Bool {
        !configuration.executablePath.isEmpty
    }

    /// low-level 명령 실행이 필요한 상태 진단용 진입점입니다.
    public func run(args: [String], timeout: TimeInterval = 5.0) async -> CmuxCommandResult {
        await runner.run(args: args, timeout: timeout)
    }

    /// cmux 소켓 연결과 인증 상태를 확인합니다.
    public func ping(timeout: TimeInterval = 3.0) async -> CmuxCommandResult {
        await run(args: ["ping"], timeout: timeout)
    }

    /// 구조화된 identify 정보를 읽습니다.
    public func identify() async -> CmuxIdentity? {
        let result = await rpc(method: "system.identify", payload: EmptyRPCPayload())
        if let decoded = decode(IdentifyResponse.self, from: result) {
            return decoded.identity
        }

        let fallback = await run(args: ["identify"])
        return decode(IdentifyResponse.self, from: fallback)?.identity
    }

    /// 현재 workspace의 surface 목록을 읽습니다.
    ///
    /// RPC가 실패하면 `tree` 텍스트 파싱으로 fallback합니다.
    public func listSurfaces() async -> [CmuxSurface] {
        let result = await rpc(method: "surface.list", payload: EmptyRPCPayload())
        if let decoded = decode(SurfaceListResponse.self, from: result) {
            return decoded.surfaces.map(\.surface)
        }

        if let treeText = await tree() {
            return CmuxTreeParser.parseSurfaces(from: treeText)
        }
        return []
    }

    /// surface 텍스트를 읽습니다. 명령은 성공했지만 화면이 비어 있으면 빈 문자열을 반환합니다.
    public func readText(surface: CmuxSurface) async -> String? {
        let handle = surface.ref.isEmpty ? surface.id : surface.ref
        guard let handle, !handle.isEmpty else { return nil }

        let rpcResult = await rpc(method: "surface.read_text", payload: SurfaceReadRequest(surface: handle))
        if let decoded = decode(SurfaceReadResponse.self, from: rpcResult) {
            return decoded.text
        }

        let cliResult = await run(args: ["read-screen", "--surface", handle])
        return cliResult.exitCode == 0 ? cliResult.stdout : nil
    }

    /// caller/focus 기본값에 기대어 현재 화면을 읽는 fallback입니다.
    public func readDefaultScreen() async -> String? {
        let result = await run(args: ["read-screen"])
        return result.exitCode == 0 ? result.stdout : nil
    }

    private func tree() async -> String? {
        let result = await run(args: ["tree"])
        return result.exitCode == 0 ? result.stdout : nil
    }

    private func rpc<Payload: Encodable>(
        method: String,
        payload: Payload,
        timeout: TimeInterval = 5.0
    ) async -> CmuxCommandResult {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return CmuxCommandResult(
                exitCode: nil,
                stdout: "",
                stderr: "Failed to encode cmux RPC payload for \(method)",
                timedOut: false
            )
        }

        return await run(args: ["rpc", method, json], timeout: timeout)
    }

    private func decode<T: Decodable>(_ type: T.Type, from result: CmuxCommandResult) -> T? {
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private struct EmptyRPCPayload: Encodable {}

private struct SurfaceReadRequest: Encodable {
    let surface: String
}

private struct SurfaceReadResponse: Decodable {
    let text: String
}

private struct SurfaceListResponse: Decodable {
    let surfaces: [SurfaceDTO]
}

private struct SurfaceDTO: Decodable {
    let ref: String?
    let id: String?
    let type: String?
    let focused: Bool?
    let selectedInPane: Bool?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case ref
        case id
        case type
        case focused
        case selectedInPane = "selected_in_pane"
        case title
    }

    var surface: CmuxSurface {
        CmuxSurface(
            ref: ref ?? id ?? "",
            id: id,
            type: type,
            focused: focused ?? false,
            selectedInPane: selectedInPane ?? false,
            title: title
        )
    }
}

private struct IdentifyResponse: Decodable {
    let caller: IdentitySurfaceDTO?
    let focused: IdentitySurfaceDTO?

    var identity: CmuxIdentity {
        CmuxIdentity(
            caller: caller?.surface(isFocused: false),
            focused: focused?.surface(isFocused: true)
        )
    }
}

private struct IdentitySurfaceDTO: Decodable {
    let surfaceRef: String?
    let surfaceID: String?
    let surfaceType: String?

    enum CodingKeys: String, CodingKey {
        case surfaceRef = "surface_ref"
        case surfaceID = "surface_id"
        case surfaceType = "surface_type"
    }

    func surface(isFocused: Bool) -> CmuxSurface? {
        let ref = surfaceRef ?? surfaceID ?? ""
        guard !ref.isEmpty else { return nil }
        return CmuxSurface(
            ref: ref,
            id: surfaceID,
            type: surfaceType,
            focused: isFocused,
            selectedInPane: isFocused,
            title: nil
        )
    }
}
