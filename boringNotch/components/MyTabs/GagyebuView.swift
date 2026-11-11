//
//  GagyebuView.swift
//  boringNotch
//
//  노치 안 가계부 탭: 생활비 진행률, 하루 사용 가능 금액, 잔고, 최근 내역
//

import AppKit
import Defaults
import SwiftUI

struct GagyebuView: View {
    @ObservedObject var manager = GagyebuManager.shared
    @Default(.showGagyebuPaypal) var showPaypal

    var body: some View {
        Group {
            if let s = manager.summary {
                HStack(alignment: .top, spacing: 14) {
                    overview(s)
                        .frame(width: 250, alignment: .leading)
                    Divider().background(Color.white.opacity(0.1))
                    recent(s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                MyTabsPlaceholder(
                    icon: "wonsign.circle",
                    message: manager.error ?? (manager.isLoading ? "불러오는 중…" : "가계부를 불러오는 중…")
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await manager.refreshIfStale() }
    }

    @ViewBuilder
    private func overview(_ s: GagyebuSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("이번 달 지출").font(.caption).foregroundStyle(.gray)
                Spacer()
                if let err = manager.error {
                    Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Text(MyTabsFormat.won(s.expense))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            if let ig = s.integrated, ig.budget > 0 {
                let ratio = Double(ig.spent) / Double(ig.budget)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(ig.name).font(.caption).foregroundStyle(.gray)
                        Spacer()
                        Text("\(MyTabsFormat.number(ig.spent)) / \(MyTabsFormat.number(ig.budget)) · \(Int((ratio * 100).rounded()))%")
                            .font(.caption).monospacedDigit().foregroundStyle(.gray)
                    }
                    MyTabsBar(ratio: ratio)
                }
            }

            if let perDay = s.perDayLeft {
                Text("남은 \(s.daysLeft)일 · 하루 \(MyTabsFormat.won(perDay))")
                    .font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.85))
            }

            if let b = s.balance {
                HStack(spacing: 4) {
                    Image(systemName: "building.columns").font(.caption2)
                    Text("잔고 \(MyTabsFormat.won(b.balance))").font(.caption).monospacedDigit()
                }
                .foregroundStyle(.gray)
            }

            if showPaypal, let pp = s.paypal, pp.isUsable, let bal = pp.balance {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle").font(.caption2)
                    Text("페이팔 \(MyTabsFormat.usd(bal))").font(.caption).monospacedDigit()
                    if let flow = paypalMonthFlow(pp) {
                        Text("(이번 달 \(flow))").font(.caption2).monospacedDigit().lineLimit(1)
                    }
                }
                .foregroundStyle(.gray)
            }
        }
    }

    /// "+$12.00 −$3.50" 처럼 이번 달 입금·결제. 둘 다 0이면 nil
    private func paypalMonthFlow(_ pp: GagyebuSummary.Paypal) -> String? {
        var parts: [String] = []
        if let i = pp.monthIn, i > 0 { parts.append("+" + MyTabsFormat.usd(i)) }
        if let o = pp.monthOut, o > 0 { parts.append("−" + MyTabsFormat.usd(o)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    @ViewBuilder
    private func recent(_ s: GagyebuSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("최근 내역").font(.caption).foregroundStyle(.gray)
                Spacer()
                Button {
                    GagyebuQuickInput.show()
                } label: {
                    Label("입력", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Button {
                    openWebApp()
                } label: {
                    Image(systemName: "arrow.up.right.square").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
                .help("웹에서 열기")
            }

            if s.txs.isEmpty {
                Text("이번 달 내역이 없어요").font(.caption).foregroundStyle(.gray)
            } else {
                ForEach(s.txs.prefix(4)) { tx in
                    HStack(spacing: 6) {
                        Text(tx.title).font(.callout).lineLimit(1).foregroundStyle(.white)
                        Text(tx.category).font(.caption2).foregroundStyle(.gray).lineLimit(1)
                        Spacer(minLength: 4)
                        Text((tx.type == "수입" ? "+" : "-") + MyTabsFormat.number(tx.amount))
                            .font(.callout).monospacedDigit()
                            .foregroundStyle(tx.type == "수입" ? Color.green : Color.white)
                    }
                }
            }
        }
    }

    private func openWebApp() {
        if let url = URL(string: Defaults[.gagyebuBaseURL]) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 공용 작은 컴포넌트

struct MyTabsBar: View {
    let ratio: Double

    private var color: Color {
        ratio >= 1 ? .red : ratio >= 0.8 ? .orange : .green
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color).frame(width: geo.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

struct MyTabsPlaceholder: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.gray)
            Text(message).font(.callout).foregroundStyle(.gray).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
