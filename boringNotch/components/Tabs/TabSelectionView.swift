//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: String { label }
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

// My Tabs: 설정에서 켠 개인 탭
let myTabs = [
    TabModel(label: "Budget", icon: "wonsign.circle.fill", view: .gagyebu),
    TabModel(label: "Claude", icon: "gauge.with.dots.needle.33percent", view: .claudeUsage)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) var boringShelf
    @Default(.enableGagyebuTab) var enableGagyebuTab
    @Default(.enableClaudeUsageTab) var enableClaudeUsageTab
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        var result = tabs.filter { $0.view != .shelf || boringShelf }
        result += myTabs.filter {
            ($0.view == .gagyebu && enableGagyebuTab) || ($0.view == .claudeUsage && enableClaudeUsageTab)
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
