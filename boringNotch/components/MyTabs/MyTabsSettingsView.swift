//
//  MyTabsSettingsView.swift
//  boringNotch
//
//  설정 > My Tabs: 가계부 탭, Claude 사용량 탭
//

import Defaults
import SwiftUI

struct MyTabsSettingsView: View {
    @Default(.enableGagyebuTab) var enableGagyebuTab
    @Default(.gagyebuBaseURL) var gagyebuBaseURL
    @Default(.enableClaudeUsageTab) var enableClaudeUsageTab

    @State private var gagyebuToken = MyTabsKeychain.get(MyTabsKeychain.gagyebuToken) ?? ""
    @State private var claudeSessionKey = MyTabsKeychain.get(MyTabsKeychain.claudeSessionKey) ?? ""
    @State private var gagyebuStatus: String?
    @State private var claudeStatus: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show budget tab (가계부)", isOn: $enableGagyebuTab)
                TextField("Web app URL", text: $gagyebuBaseURL)
                SecureField("APP_TOKEN", text: $gagyebuToken)
                HStack {
                    Button("Save & test") {
                        MyTabsKeychain.set(gagyebuToken, for: MyTabsKeychain.gagyebuToken)
                        gagyebuStatus = "확인 중…"
                        Task { @MainActor in
                            await GagyebuManager.shared.refresh()
                            let m = GagyebuManager.shared
                            gagyebuStatus = m.error ?? (m.summary != nil ? "연결됨 ✓" : "응답 없음")
                        }
                    }
                    if let gagyebuStatus {
                        Text(gagyebuStatus).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Budget (가계부)")
            } footer: {
                Text("gagyebu 웹앱의 APP_TOKEN. 토큰은 키체인에 저장돼요. 노치의 '입력' 버튼으로 바로 기록할 수 있어요.")
            }

            Section {
                Toggle("Show Claude usage tab", isOn: $enableClaudeUsageTab)
                SecureField("claude.ai sessionKey (sk-ant-sid01-…)", text: $claudeSessionKey)
                HStack {
                    Button("Save & test") {
                        MyTabsKeychain.set(claudeSessionKey, for: MyTabsKeychain.claudeSessionKey)
                        claudeStatus = "확인 중…"
                        Task { @MainActor in
                            let m = ClaudeUsageManager.shared
                            m.resetSession()
                            await m.refresh()
                            claudeStatus = m.error ?? (m.windows.isEmpty ? "응답 없음" : "연결됨 ✓")
                        }
                    }
                    if let claudeStatus {
                        Text(claudeStatus).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Claude usage")
            } footer: {
                Text("브라우저에서 claude.ai 로그인 → 개발자 도구 → Application(저장소) → Cookies → claude.ai의 sessionKey 값을 붙여넣으세요. 비밀번호와 같은 값이니 다른 곳에 공유하지 마세요. claude.ai 내부 API를 쓰기 때문에 바뀌면 동작하지 않을 수 있어요.")
            }
        }
        .navigationTitle("My Tabs")
    }
}
