//
//  ClaudeUsageView.swift
//  boringNotch
//
//  노치 안 Claude 사용량 탭
//

import AppKit
import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject var manager = ClaudeUsageManager.shared

    var body: some View {
        Group {
            if manager.windows.isEmpty {
                MyTabsPlaceholder(
                    icon: "gauge.with.dots.needle.33percent",
                    message: manager.error ?? (manager.isLoading ? "불러오는 중…" : "Claude 사용량을 불러오는 중…")
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Claude 사용량").font(.caption).foregroundStyle(.gray)
                        Spacer()
                        if let err = manager.error {
                            Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                        } else if let last = manager.lastUpdated {
                            Text(last, style: .time).font(.caption2).foregroundStyle(.gray)
                        }
                        Button {
                            Task { await manager.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.gray)
                        Button {
                            if let url = URL(string: "https://claude.ai/settings/usage") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "arrow.up.right.square").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.gray)
                    }
                    ForEach(manager.windows.prefix(3)) { w in
                        row(w)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await manager.refreshIfStale() }
    }

    private func row(_ w: ClaudeUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(w.label).font(.callout).foregroundStyle(.white)
                Spacer()
                Text(MyTabsFormat.until(w.resetsAt)).font(.caption).foregroundStyle(.gray)
                Text("\(Int(w.percent.rounded()))%")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 44, alignment: .trailing)
            }
            MyTabsBar(ratio: w.percent / 100)
        }
    }
}
