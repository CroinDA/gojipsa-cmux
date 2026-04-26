import Foundation

/// cmux가 관리하는 surface 한 개를 나타냅니다.
///
/// GOJIPSA는 terminal surface의 화면 텍스트만 Gemini에 전달합니다. browser나
/// 기타 surface는 터미널 컨텍스트가 아니므로 선택 단계에서 제외됩니다.
public struct CmuxSurface: Sendable, Equatable {
    /// CLI에서 바로 사용할 수 있는 짧은 참조입니다. 예: `surface:1`.
    public let ref: String

    /// cmux 내부 UUID입니다. RPC 응답에서만 제공될 수 있습니다.
    public let id: String?

    /// surface 타입입니다. 보통 `terminal` 또는 `browser`입니다.
    public let type: String?

    /// 현재 focus된 surface인지 여부입니다.
    public let focused: Bool

    /// pane 안에서 선택된 surface인지 여부입니다.
    public let selectedInPane: Bool

    /// 사용자가 보는 surface 제목입니다.
    public let title: String?

    public init(
        ref: String,
        id: String? = nil,
        type: String? = nil,
        focused: Bool = false,
        selectedInPane: Bool = false,
        title: String? = nil
    ) {
        self.ref = ref
        self.id = id
        self.type = type
        self.focused = focused
        self.selectedInPane = selectedInPane
        self.title = title
    }

    /// terminal로 읽을 수 있는 surface인지 판단합니다.
    public var isTerminal: Bool {
        guard let type, !type.isEmpty else { return true }
        return type.lowercased() == "terminal"
    }

    /// `CMUX_SURFACE_ID` 또는 cmux ref/UUID와 같은 surface인지 비교합니다.
    public func matches(_ identifier: String) -> Bool {
        let needle = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }

        if ref.lowercased() == needle { return true }
        if id?.lowercased() == needle { return true }
        return false
    }
}

/// cmux가 알려준 caller/focused surface 정보입니다.
public struct CmuxIdentity: Sendable, Equatable {
    public let caller: CmuxSurface?
    public let focused: CmuxSurface?

    public init(caller: CmuxSurface?, focused: CmuxSurface?) {
        self.caller = caller
        self.focused = focused
    }
}

/// cmux tree 텍스트 출력에서 surface ref를 추출하는 fallback parser입니다.
///
/// 새 cmux는 RPC JSON을 제공하지만, 구버전이나 일시적 RPC 실패에 대비해
/// `tree` 출력도 읽을 수 있게 둡니다.
public enum CmuxTreeParser {
    public static func parseSurfaces(from tree: String) -> [CmuxSurface] {
        let pattern = #"surface:[A-Za-z0-9_-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var seen = Set<String>()
        var surfaces: [CmuxSurface] = []

        for line in tree.components(separatedBy: .newlines) where line.contains("surface") {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, options: [], range: range)
            for match in matches {
                guard let swiftRange = Range(match.range, in: line) else { continue }
                let ref = String(line[swiftRange])
                guard seen.insert(ref).inserted else { continue }

                let lower = line.lowercased()
                let type: String?
                if lower.contains("[browser]") {
                    type = "browser"
                } else if lower.contains("[terminal]") {
                    type = "terminal"
                } else {
                    type = nil
                }

                surfaces.append(CmuxSurface(
                    ref: ref,
                    type: type,
                    focused: lower.contains("[focused]") || line.contains("◀ active"),
                    selectedInPane: lower.contains("[selected]"),
                    title: nil
                ))
            }
        }

        return surfaces
    }
}

/// 여러 cmux surface 중 GOJIPSA가 읽을 terminal surface를 고릅니다.
public enum CmuxSurfaceSelector {
    /// terminal surface를 focus/선택 상태 우선으로 정렬하고, GOJIPSA 자신의
    /// surface는 가능하면 제외합니다.
    ///
    /// 제외 후 후보가 하나도 남지 않으면 빈 화면 대신 유일한 surface라도 읽도록
    /// 원래 terminal 목록으로 되돌아갑니다. 이 동작은 1-pane 데모와 PID-ancestry
    /// 실행을 모두 살리기 위한 fallback입니다.
    public static func readableTerminalSurfaces(
        from surfaces: [CmuxSurface],
        excluding ownSurfaceID: String,
        limit: Int = 3
    ) -> [CmuxSurface] {
        guard limit > 0 else { return [] }

        let ordered = surfaces
            .filter(\.isTerminal)
            .sorted { lhs, rhs in
                if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
                if lhs.selectedInPane != rhs.selectedInPane { return lhs.selectedInPane && !rhs.selectedInPane }
                return lhs.ref.localizedStandardCompare(rhs.ref) == .orderedAscending
            }

        let withoutSelf = ordered.filter { !$0.matches(ownSurfaceID) }
        let candidates = withoutSelf.isEmpty ? ordered : withoutSelf
        return Array(candidates.prefix(limit))
    }
}
