//
//  GagyebuQuickInput.swift
//  boringNotch
//
//  노치 창은 키보드 입력을 받지 않으므로(canBecomeKey = false),
//  입력은 작은 별도 창을 띄워서 받음
//

import AppKit
import SwiftUI

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
enum GagyebuQuickInput {
    private static var panel: NSPanel?

    static func show() {
        if panel == nil {
            let p = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            p.title = "가계부 입력"
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isReleasedWhenClosed = false
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.contentView = NSHostingView(rootView: GagyebuQuickInputView(onClose: { close() }))
            panel = p
        } else {
            // 다시 열 때 입력 상태 초기화
            panel?.contentView = NSHostingView(rootView: GagyebuQuickInputView(onClose: { close() }))
        }
        guard let panel else { return }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 40))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    static func close() {
        panel?.orderOut(nil)
    }
}

private struct GagyebuQuickInputView: View {
    let onClose: @MainActor () -> Void

    @State private var text = ""
    @State private var message: String?
    @State private var ok = true
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wonsign.circle.fill").foregroundStyle(.green)
                TextField("김밥천국 9000 · +50000 용돈 · 잔고 2350000", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .disabled(sending)
                    .onSubmit { submit() }
                if sending { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))

            Text(message ?? "Enter로 저장 · Esc로 닫기")
                .font(.callout)
                .foregroundStyle(message == nil ? Color.secondary : (ok ? Color.primary : Color.red))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .padding(.top, 10)
        .frame(width: 380)
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }

    private func submit() {
        let input = text
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty, !sending else { return }
        sending = true
        Task { @MainActor in
            let result = await GagyebuManager.shared.add(input)
            sending = false
            ok = result.ok
            message = result.message
            if result.ok {
                text = ""
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                onClose()
            } else {
                focused = true
            }
        }
    }
}
