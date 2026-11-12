//
//  SeoulNowView.swift
//  boringNotch
//
//  노치 안 Seoul Now 탭: 검수 대기 n건(오늘 m건) + 제목 목록, 클릭하면 Notion 페이지 열기
//

import SwiftUI

struct SeoulNowView: View {
    @ObservedObject var manager = SeoulNowManager.shared

    var body: some View {
        Group {
            if manager.lastUpdated == nil {
                MyTabsPlaceholder(
                    icon: "checklist",
                    message: manager.error ?? (manager.isLoading ? "불러오는 중…" : "검수함을 불러오는 중…")
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    if manager.items.isEmpty {
                        Text("검수 대기 글이 없어요 🎉")
                            .font(.callout)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 14)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(manager.items) { item in
                                    row(item)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await manager.refreshIfStale() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("검수 대기")
                .font(.caption)
                .foregroundStyle(.gray)
            Text("\(manager.items.count)건")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(manager.items.isEmpty ? Color.gray : Color.white)
            if manager.todayCount > 0 {
                Text("오늘 \(manager.todayCount)건")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.25)))
                    .foregroundStyle(.yellow)
            }
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
                SeoulNowManager.openDatabase()
            } label: {
                Image(systemName: "arrow.up.right.square").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.gray)
        }
    }

    private func row(_ item: SeoulNowItem) -> some View {
        Button {
            if let url = item.url { SeoulNowManager.open(url) }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(item.isToday ? Color.yellow : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
                Text(item.displayTitle)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let ch = item.channel {
                    Text(ch).font(.caption2).foregroundStyle(.gray)
                }
                if let d = item.date {
                    Text(shortDate(d)).font(.caption2).monospacedDigit().foregroundStyle(.gray)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    /// "2026-11-12" → "11/12"
    private func shortDate(_ s: String) -> String {
        let parts = s.prefix(10).split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return String(s.prefix(10)) }
        return "\(m)/\(d)"
    }
}
