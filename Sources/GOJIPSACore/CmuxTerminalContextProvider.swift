import Foundation

/// Gemini에 전달할 cmux terminal context를 조립합니다.
///
/// 이 타입은 "어떤 terminal surface를 읽을지"만 결정합니다. 소켓 호출은
/// `CmuxClient`가, 위험 명령 감지와 Gemini 호출은 `ScreenWatcher`가 담당합니다.
public struct CmuxTerminalContextProvider: Sendable {
    private let client: CmuxClient
    private let ownSurfaceID: String

    public init(client: CmuxClient, ownSurfaceID: String) {
        self.client = client
        self.ownSurfaceID = ownSurfaceID
    }

    /// 읽기 가능한 terminal surface의 화면 텍스트를 합칩니다.
    ///
    /// 여러 surface가 있으면 focus/선택 상태를 우선하고 최대 `limit`개만 읽습니다.
    /// surface 목록을 못 얻으면 cmux의 기본 `read-screen`으로 한 번 더 fallback합니다.
    public func readContext(limit: Int = 3) async -> String {
        let surfaces = await candidateSurfaces()
        let selected = CmuxSurfaceSelector.readableTerminalSurfaces(
            from: surfaces,
            excluding: ownSurfaceID,
            limit: limit
        )

        if selected.isEmpty {
            return await client.readDefaultScreen() ?? ""
        }

        var chunks: [String] = []
        for surface in selected {
            guard let text = await client.readText(surface: surface) else { continue }
            let trimmedTail = String(text.suffix(2000))
            guard !trimmedTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            chunks.append("=== \(surface.ref) ===\n\(trimmedTail)")
        }

        if chunks.isEmpty {
            return await client.readDefaultScreen() ?? ""
        }
        return chunks.joined(separator: "\n\n")
    }

    /// 상태 진단용 probe입니다.
    ///
    /// 화면 텍스트가 실제로 비어 있어도 명령이 성공하면 `true`를 반환합니다. 따라서
    /// "터미널이 조용함"과 "surface 읽기 실패"를 구분할 수 있습니다.
    public func canReadAnyTerminalSurface(limit: Int = 3) async -> Bool {
        let surfaces = await candidateSurfaces()
        let selected = CmuxSurfaceSelector.readableTerminalSurfaces(
            from: surfaces,
            excluding: ownSurfaceID,
            limit: limit
        )

        if selected.isEmpty {
            return await client.readDefaultScreen() != nil
        }

        for surface in selected {
            if await client.readText(surface: surface) != nil {
                return true
            }
        }
        return await client.readDefaultScreen() != nil
    }

    private func candidateSurfaces() async -> [CmuxSurface] {
        let listed = await client.listSurfaces()
        if !listed.isEmpty { return listed }

        guard let identity = await client.identify() else { return [] }
        return [identity.focused, identity.caller].compactMap { $0 }
    }
}
