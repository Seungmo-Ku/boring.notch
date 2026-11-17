//
//  DeadlineView.swift
//  boringNotch
//
//  홈 화면 캘린더 자리에 들어가는 마감 D-day 목록 (Notion 과제/할 일 DB에서 가까운 마감 3개).
//  항목을 누르면 Notion 페이지를 엶.
//

import SwiftUI

struct DeadlineView: View {
    @ObservedObject var manager = DeadlineManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            content
            Spacer(minLength: 0)
        }
        .frame(height: 120, alignment: .top)
        .task { await manager.refreshIfStale() }
        .onChange(of: vm.notchState) { _, state in
            if state == .open {
                Task { await manager.refreshIfStale() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("마감")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text(todayText)
                .font(.title3)
                .fontWeight(.light)
                .foregroundColor(Color(white: 0.65))
            Spacer()
            Button {
                Task { await manager.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.gray)
            Button {
                DeadlineManager.openDatabase()
            } label: {
                Image(systemName: "arrow.up.right.square").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.gray)
        }
    }

    @ViewBuilder
    private var content: some View {
        if manager.lastUpdated == nil {
            message(manager.error ?? "불러오는 중…", color: manager.error == nil ? .gray : .orange)
        } else if manager.upcoming.isEmpty {
            message("다가오는 마감이 없어요 🎉", color: .gray)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(manager.upcoming) { item in
                    row(item)
                }
            }
            if let err = manager.error {
                Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(1)
            }
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 14)
    }

    private func row(_ item: DeadlineItem) -> some View {
        let days = item.daysLeft() ?? 99
        return Button {
            if let url = item.url { SeoulNowManager.open(url) }
        } label: {
            HStack(spacing: 7) {
                Text(item.dDayText())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 44)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(badgeColor(days).opacity(0.22)))
                    .foregroundStyle(badgeColor(days))
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle(item))
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(item.subject.map { "[\($0)] " } ?? "")\(item.name) — \(item.kstDay)")
    }

    private func subtitle(_ item: DeadlineItem) -> String {
        var parts: [String] = []
        if let s = item.subject { parts.append(s) }
        parts.append(item.timeText.map { "\(item.shortDate) \($0)" } ?? item.shortDate)
        return parts.joined(separator: " · ")
    }

    private func badgeColor(_ days: Int) -> Color {
        switch days {
        case ..<2: return .red // 오늘·내일
        case 2...6: return .orange // 일주일 안
        case 7...13: return .yellow
        default: return .gray
        }
    }

    private var todayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = DeadlineManager.kst
        f.dateFormat = "M/d"
        return f.string(from: Date())
    }
}
