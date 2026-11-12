//
//  SeoulNowManager.swift
//  boringNotch
//
//  Seoul Now 「콘텐츠 검수함」(Notion DB)에서 상태=검수 대기 글을 가져옴.
//  Notion 공식 API(2022-06-28)를 쓰고, 통합(Integration) 토큰은 키체인에 저장.
//  읽기만 하고 검수함은 수정하지 않음.
//

import AppKit
import Defaults
import Foundation

struct SeoulNowItem: Identifiable {
    let id: String
    let title: String
    let date: String? // "2026-11-12"
    let channel: String? // X / note
    let categories: [String] // 음식 / 뷰티 / 여행
    let url: URL?

    /// 제목 앞의 "[2026-11-12] " 같은 날짜 접두어를 뗀 표시용 제목
    var displayTitle: String {
        guard title.hasPrefix("["), let close = title.firstIndex(of: "]") else { return title }
        let rest = title[title.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? title : rest
    }

    /// 한국 시간 기준 오늘 날짜 항목인지
    var isToday: Bool {
        guard let date else { return false }
        return date.hasPrefix(SeoulNowManager.todayString())
    }
}

@MainActor
final class SeoulNowManager: ObservableObject {
    static let shared = SeoulNowManager()

    /// 검수함 상태 이름 (Notion DB의 status 옵션과 같아야 함)
    static let waitingStatus = "검수 대기"

    @Published private(set) var items: [SeoulNowItem] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?

    private init() {
        // 5분마다 갱신 (탭이 꺼져 있으면 refresh가 바로 리턴)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    var todayCount: Int { items.filter(\.isToday).count }

    nonisolated static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// 설정값의 DB ID. URL을 통째로 붙여넣어도 32자리 ID만 뽑아 씀
    nonisolated static func normalizedDatabaseID(_ raw: String) -> String? {
        let hex = Set("0123456789abcdefABCDEF")
        let compact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "?").first?
            .replacingOccurrences(of: "-", with: "") ?? ""
        let chars = Array(compact)
        guard chars.count >= 32 else { return nil }
        // 끝에서부터 32자리 16진수 묶음을 찾음 (…/제목-<id> 형태 대응)
        var i = chars.count - 32
        while i >= 0 {
            let slice = chars[i..<(i + 32)]
            if slice.allSatisfy({ hex.contains($0) }) { return String(slice).lowercased() }
            i -= 1
        }
        return nil
    }

    func refreshIfStale() async {
        if let last = lastUpdated, Date().timeIntervalSince(last) < 30 { return }
        await refresh()
    }

    func refresh() async {
        guard Defaults[.enableSeoulNowTab] else { return }
        guard let token = MyTabsKeychain.get(MyTabsKeychain.seoulNowNotionToken) else {
            error = "설정에서 Notion 토큰을 넣어주세요"
            return
        }
        guard let dbID = Self.normalizedDatabaseID(Defaults[.seoulNowDatabaseID]),
              let url = URL(string: "https://api.notion.com/v1/databases/\(dbID)/query")
        else {
            error = "설정에서 검수함 DB ID를 확인해주세요"
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "page_size": 30,
            "filter": ["property": "상태", "status": ["equals": Self.waitingStatus]],
            "sorts": [["property": "날짜", "direction": "descending"]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true
        defer { isLoading = false }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                error = "토큰이 틀렸어요 (설정 확인)"
                return
            }
            if code == 404 {
                error = "검수함을 못 찾았어요 (DB를 통합에 연결했는지 확인)"
                return
            }
            guard (200..<300).contains(code) else {
                error = "불러오기 실패 (\(code))"
                return
            }
            items = Self.parse(data)
            error = nil
            lastUpdated = Date()
        } catch {
            self.error = "연결 실패"
        }
    }

    /// 속성 이름이 한국어라 Decodable 대신 직접 풂. 모양이 달라도 항목 단위로 건너뜀
    nonisolated static func parse(_ data: Data) -> [SeoulNowItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { page in
            guard let id = page["id"] as? String else { return nil }
            let props = page["properties"] as? [String: Any] ?? [:]

            let titleParts = (props["제목"] as? [String: Any])?["title"] as? [[String: Any]] ?? []
            let title = titleParts.compactMap { $0["plain_text"] as? String }.joined()

            let date = ((props["날짜"] as? [String: Any])?["date"] as? [String: Any])?["start"] as? String
            let channel = ((props["채널"] as? [String: Any])?["select"] as? [String: Any])?["name"] as? String
            let cats = ((props["카테고리"] as? [String: Any])?["multi_select"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
            let url = (page["url"] as? String).flatMap(URL.init(string:))

            return SeoulNowItem(
                id: id,
                title: title.isEmpty ? "(제목 없음)" : title,
                date: date,
                channel: channel,
                categories: cats,
                url: url
            )
        }
    }

    /// Notion 데스크톱 앱이 있으면 앱으로, 없으면 브라우저로 엶
    static func open(_ url: URL) {
        let ws = NSWorkspace.shared
        if let appURL = URL(string: "notion://"),
           ws.urlForApplication(toOpen: appURL) != nil,
           var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            comps.scheme = "notion"
            if let notionURL = comps.url, ws.open(notionURL) { return }
        }
        ws.open(url)
    }

    /// 검수함 DB 자체를 엶
    static func openDatabase() {
        guard let id = normalizedDatabaseID(Defaults[.seoulNowDatabaseID]),
              let url = URL(string: "https://www.notion.so/\(id)")
        else { return }
        open(url)
    }
}
