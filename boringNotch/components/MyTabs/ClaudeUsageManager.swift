//
//  ClaudeUsageManager.swift
//  boringNotch
//
//  claude.ai 사용량(5시간 세션, 주간 한도)을 가져옴.
//  ⚠️ 공식 API가 아니라 claude.ai 설정 > 사용량 페이지가 쓰는 내부 엔드포인트라서
//  예고 없이 바뀌면 동작하지 않을 수 있음.
//

import Defaults
import Foundation

struct ClaudeUsageWindow: Identifiable {
    let id: String
    let label: String
    let percent: Double // 0...100
    let resetsAt: Date?
}

@MainActor
final class ClaudeUsageManager: ObservableObject {
    static let shared = ClaudeUsageManager()

    @Published private(set) var windows: [ClaudeUsageWindow] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?

    private var orgId: String?
    private var timer: Timer?

    private init() {
        // 3분마다 갱신
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    /// 세션 키를 바꾸면 조직 ID도 다시 찾도록 초기화
    func resetSession() {
        orgId = nil
        windows = []
        lastUpdated = nil
    }

    func refreshIfStale() async {
        if let last = lastUpdated, Date().timeIntervalSince(last) < 30 { return }
        await refresh()
    }

    private func get(_ path: String, sessionKey: String) async throws -> (Data, Int) {
        guard let url = URL(string: "https://claude.ai" + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.httpShouldHandleCookies = false
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func refresh() async {
        guard Defaults[.enableClaudeUsageTab] else { return }
        guard let key = MyTabsKeychain.get(MyTabsKeychain.claudeSessionKey) else {
            error = "설정에서 claude.ai 세션 키를 넣어주세요"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            if orgId == nil {
                let (data, code) = try await get("/api/organizations", sessionKey: key)
                if code == 401 || code == 403 {
                    error = "세션이 만료됐어요. 세션 키를 다시 넣어주세요"
                    return
                }
                guard (200..<300).contains(code),
                      let orgs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    error = "조직 정보를 못 불러왔어요 (\(code))"
                    return
                }
                // 개인 구독이 있는 조직을 우선 (capabilities에 "chat"이 있는 첫 조직), 없으면 첫 번째
                let preferred = orgs.first { ($0["capabilities"] as? [String])?.contains("chat") == true } ?? orgs.first
                orgId = preferred?["uuid"] as? String
                guard orgId != nil else {
                    error = "조직을 찾을 수 없어요"
                    return
                }
            }
            let (data, code) = try await get("/api/organizations/\(orgId!)/usage", sessionKey: key)
            if code == 401 || code == 403 {
                orgId = nil
                error = "세션이 만료됐어요. 세션 키를 다시 넣어주세요"
                return
            }
            guard (200..<300).contains(code),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                error = "사용량을 못 불러왔어요 (\(code))"
                return
            }
            windows = Self.parse(json)
            error = windows.isEmpty ? "사용량 데이터가 비어 있어요" : nil
            lastUpdated = Date()
        } catch {
            self.error = "연결 실패"
        }
    }

    private static func parse(_ json: [String: Any]) -> [ClaudeUsageWindow] {
        let spec: [(key: String, label: String)] = [
            ("five_hour", "세션 (5시간)"),
            ("seven_day", "주간 (전체)"),
            ("seven_day_sonnet", "주간 (Sonnet)"),
            ("seven_day_opus", "주간 (Opus)"),
        ]
        return spec.compactMap { item in
            guard let w = json[item.key] as? [String: Any],
                  let util = (w["utilization"] as? NSNumber)?.doubleValue
            else { return nil }
            return ClaudeUsageWindow(
                id: item.key,
                label: item.label,
                percent: min(max(util, 0), 100),
                resetsAt: MyTabsFormat.parseISO(w["resets_at"] as? String)
            )
        }
    }
}
