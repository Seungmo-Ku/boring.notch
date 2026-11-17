//
//  DeadlineManager.swift
//  boringNotch
//
//  Notion 「과제/할 일」 DB에서 상태≠완료, 날짜≥오늘(한국 시간)인 항목을 마감 가까운 순으로 가져옴.
//  홈 화면의 캘린더 자리에 D-day로 보여줄 때 씀. Seoul Now와 같은 Notion 통합 토큰(키체인)을 쓰고,
//  읽기만 하고 DB는 수정하지 않음.
//

import Defaults
import Foundation

struct DeadlineItem: Identifiable, Equatable {
    let id: String
    let name: String
    let subject: String? // 과목/분류
    let dateString: String // "2026-11-27" 또는 "2026-11-27T23:59:00.000+09:00"
    let url: URL?

    /// 한국 시간 기준 마감 날짜 ("2026-11-27")
    var kstDay: String {
        guard dateString.count > 10, let d = MyTabsFormat.parseISO(dateString) else {
            return String(dateString.prefix(10))
        }
        return DeadlineManager.dayString(d)
    }

    /// 시간까지 적힌 마감이면 "23:59", 날짜만이면 nil
    var timeText: String? {
        guard dateString.count > 10, let d = MyTabsFormat.parseISO(dateString) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = DeadlineManager.kst
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// 오늘(한국 시간)부터 남은 일수. 0 = 오늘
    func daysLeft(from now: Date = Date()) -> Int? {
        DeadlineManager.daysBetween(DeadlineManager.dayString(now), kstDay)
    }

    /// "D-DAY", "D-6", 지났으면 "D+1"
    func dDayText(from now: Date = Date()) -> String {
        guard let n = daysLeft(from: now) else { return "D-?" }
        if n == 0 { return "D-DAY" }
        return n > 0 ? "D-\(n)" : "D+\(-n)"
    }

    /// "11/27"
    var shortDate: String {
        let parts = kstDay.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return kstDay }
        return "\(m)/\(d)"
    }
}

@MainActor
final class DeadlineManager: ObservableObject {
    static let shared = DeadlineManager()

    // Notion DB 속성 이름 (과제/할 일 DB와 같아야 함)
    nonisolated static let titleProperty = "이름"
    nonisolated static let dateProperty = "날짜"
    nonisolated static let statusProperty = "상태" // select
    nonisolated static let subjectProperty = "과목/분류" // select
    nonisolated static let doneStatus = "완료"

    /// 노치에 보여줄 개수
    nonisolated static let displayCount = 3

    nonisolated static let kst = TimeZone(identifier: "Asia/Seoul") ?? .current

    @Published private(set) var items: [DeadlineItem] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?

    private init() {
        // 10분마다 갱신 (기능이 꺼져 있으면 refresh가 바로 리턴)
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    /// 노치에 보여줄 항목 (날짜가 이미 지난 시간 지정 마감은 제외)
    var upcoming: [DeadlineItem] {
        let now = Date()
        return items.filter { item in
            if item.dateString.count > 10, let d = MyTabsFormat.parseISO(item.dateString) { return d >= now }
            return (item.daysLeft(from: now) ?? 0) >= 0
        }
        .prefix(Self.displayCount)
        .map { $0 }
    }

    nonisolated static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = kst
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// "yyyy-MM-dd" 두 개 사이의 일수 (to - from)
    nonisolated static func daysBetween(_ from: String, _ to: String) -> Int? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let a = f.date(from: from), let b = f.date(from: to) else { return nil }
        return Int((b.timeIntervalSince(a) / 86400).rounded())
    }

    func refreshIfStale() async {
        if let last = lastUpdated, Date().timeIntervalSince(last) < 60 { return }
        await refresh()
    }

    func refresh() async {
        guard Defaults[.showDeadlinesInsteadOfCalendar] else { return }
        guard let token = MyTabsKeychain.get(MyTabsKeychain.seoulNowNotionToken) else {
            error = "설정 > My Tabs에서 Notion 토큰을 넣어주세요"
            return
        }
        guard let dbID = SeoulNowManager.normalizedDatabaseID(Defaults[.deadlineDatabaseID]),
              let url = URL(string: "https://api.notion.com/v1/databases/\(dbID)/query")
        else {
            error = "설정에서 과제/할 일 DB ID를 확인해주세요"
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "page_size": 20,
            "filter": [
                "and": [
                    ["property": Self.dateProperty, "date": ["on_or_after": Self.dayString(Date())]],
                    ["property": Self.statusProperty, "select": ["does_not_equal": Self.doneStatus]],
                ],
            ],
            "sorts": [["property": Self.dateProperty, "direction": "ascending"]],
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
                error = "과제 DB를 못 찾았어요 (DB를 통합에 연결했는지 확인)"
                return
            }
            if code == 400 {
                error = "DB 속성이 달라요 (이름·날짜·상태 확인)"
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

    nonisolated static func parse(_ data: Data) -> [DeadlineItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { page in
            guard let id = page["id"] as? String else { return nil }
            let props = page["properties"] as? [String: Any] ?? [:]

            let titleParts = (props[titleProperty] as? [String: Any])?["title"] as? [[String: Any]] ?? []
            let name = titleParts.compactMap { $0["plain_text"] as? String }.joined()
            guard let date = ((props[dateProperty] as? [String: Any])?["date"] as? [String: Any])?["start"] as? String
            else { return nil }
            let subject = ((props[subjectProperty] as? [String: Any])?["select"] as? [String: Any])?["name"] as? String
            let url = (page["url"] as? String).flatMap(URL.init(string:))

            return DeadlineItem(
                id: id,
                name: name.isEmpty ? "(제목 없음)" : name,
                subject: subject,
                dateString: date,
                url: url
            )
        }
    }

    /// 과제/할 일 DB 자체를 엶
    static func openDatabase() {
        guard let id = SeoulNowManager.normalizedDatabaseID(Defaults[.deadlineDatabaseID]),
              let url = URL(string: "https://www.notion.so/\(id)")
        else { return }
        SeoulNowManager.open(url)
    }
}
