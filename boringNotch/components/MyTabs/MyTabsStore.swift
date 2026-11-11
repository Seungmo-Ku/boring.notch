//
//  MyTabsStore.swift
//  boringNotch
//
//  개인 탭(가계부, Claude 사용량) 설정값과 비밀값 저장소
//

import Defaults
import Foundation
import Security

extension Defaults.Keys {
    // 가계부 탭
    static let enableGagyebuTab = Key<Bool>("enableGagyebuTab", default: false)
    static let gagyebuBaseURL = Key<String>("gagyebuBaseURL", default: "https://gagyebu-sage.vercel.app")
    static let showGagyebuPaypal = Key<Bool>("showGagyebuPaypal", default: true)
    // Claude 사용량 탭
    static let enableClaudeUsageTab = Key<Bool>("enableClaudeUsageTab", default: false)
}

/// 토큰처럼 민감한 값은 UserDefaults 대신 키체인에 저장
enum MyTabsKeychain {
    private static let service = "boringNotch.myTabs"

    static let gagyebuToken = "gagyebuToken"
    static let claudeSessionKey = "claudeSessionKey"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum MyTabsFormat {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    static func won(_ n: Int) -> String {
        (formatter.string(from: NSNumber(value: n)) ?? "\(n)") + "원"
    }

    static func number(_ n: Int) -> String {
        formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// "$1,234.50" (음수면 "-$12.00")
    static func usd(_ n: Double) -> String {
        let s = usdFormatter.string(from: NSNumber(value: abs(n))) ?? String(format: "%.2f", abs(n))
        return (n < 0 ? "-$" : "$") + s
    }

    /// "2시간 13분 후", "3일 4시간 후"
    static func until(_ date: Date?) -> String {
        guard let date else { return "" }
        let secs = Int(date.timeIntervalSinceNow)
        if secs <= 0 { return "곧 리셋" }
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)일 \(h)시간 후 리셋" }
        if h > 0 { return "\(h)시간 \(m)분 후 리셋" }
        return "\(m)분 후 리셋"
    }

    static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
