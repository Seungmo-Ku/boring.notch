//
//  GagyebuManager.swift
//  boringNotch
//
//  가계부 웹앱(gagyebu) API에서 이번 달 요약을 가져오고, 빠른 입력을 보냄
//

import Defaults
import Foundation

struct GagyebuSummary: Decodable {
    struct Balance: Decodable {
        let balance: Int
        let baseAmount: Int
        let baseDate: String
    }

    struct Integrated: Decodable {
        let name: String
        let budget: Int
        let spent: Int
    }

    struct Tx: Decodable, Identifiable {
        let id: String
        let title: String
        let amount: Int
        let type: String
        let category: String
        let date: String
    }

    let month: String
    let expense: Int
    let income: Int
    let totalBudget: Int
    let budgetedSpent: Int
    let perDayLeft: Int?
    let daysLeft: Int
    let net: Int?
    let balance: Balance?
    let integrated: Integrated?
    let txs: [Tx]
}

@MainActor
final class GagyebuManager: ObservableObject {
    static let shared = GagyebuManager()

    @Published private(set) var summary: GagyebuSummary?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?

    private init() {
        // 5분마다 갱신
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private var baseURL: URL? {
        var s = Defaults[.gagyebuBaseURL].trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    private func request(_ path: String) -> URLRequest? {
        guard Defaults[.enableGagyebuTab],
              let base = baseURL,
              let token = MyTabsKeychain.get(MyTabsKeychain.gagyebuToken),
              let url = URL(string: base.absoluteString + path)
        else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    /// 화면에 보일 때 호출. 최근 30초 안에 갱신했으면 건너뜀
    func refreshIfStale() async {
        if let last = lastUpdated, Date().timeIntervalSince(last) < 30 { return }
        await refresh()
    }

    func refresh() async {
        guard let req = request("/api/tx") else {
            error = Defaults[.enableGagyebuTab] ? "설정에서 토큰을 넣어주세요" : nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                error = "토큰이 틀렸어요 (설정 확인)"
                return
            }
            guard (200..<300).contains(code) else {
                error = "불러오기 실패 (\(code))"
                return
            }
            summary = try JSONDecoder().decode(GagyebuSummary.self, from: data)
            error = nil
            lastUpdated = Date()
        } catch {
            self.error = "연결 실패"
        }
    }

    /// 빠른 입력. 서버가 돌려주는 확인 문구를 그대로 반환
    func add(_ text: String) async -> (ok: Bool, message: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "입력이 비어 있어요") }
        guard var req = request("/api/tx?format=text&source=shortcut") else {
            return (false, "설정에서 가계부 토큰을 넣어주세요")
        }
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(trimmed.utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let message = String(data: data, encoding: .utf8) ?? ""
            let ok = (200..<300).contains(code)
            if ok { await refresh() }
            return (ok, message.isEmpty ? "오류 (\(code))" : message)
        } catch {
            return (false, "연결 실패")
        }
    }
}
