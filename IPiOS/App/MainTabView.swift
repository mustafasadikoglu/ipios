import SwiftUI

/// Ana sekme yapısı.
///
/// Sekmeler `CategoryKind` sırasını izler (Canlı → Film → Dizi), ardından
/// arama ve ayarlar gelir. Her sekme kendi `NavigationStack`'ini kurar;
/// böylece bir sekmede gezinmek diğerinin konumunu bozmaz.
struct MainTabView: View {

    @EnvironmentObject private var environment: AppEnvironment

    @State private var selection: Tab = .live

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case live, movies, series, search, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .live: return L.t("tab.live")
            case .movies: return L.t("tab.movies")
            case .series: return L.t("tab.series")
            case .search: return L.t("tab.search")
            case .settings: return L.t("tab.settings")
            }
        }

        var iconName: String {
            switch self {
            case .live: return "tv"
            case .movies: return "film"
            case .series: return "rectangle.stack"
            case .search: return "magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Tab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                        .navigationTitle(tab.title)
                        .navigationBarTitleDisplayMode(.large)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.iconName)
                }
                .tag(tab)
            }
        }
        .tint(Theme.accent)
    }

    /// ViewModel'ler ortam nesnesine ihtiyaç duyar; `@StateObject` ise
    /// `init` içinde kurulmalıdır. Bu yüzden ortam, görünümlere parametre
    /// olarak geçirilir.
    @ViewBuilder
    private func screen(for tab: Tab) -> some View {
        switch tab {
        case .live:     LiveView(environment: environment)
        case .movies:   MoviesView(environment: environment)
        case .series:   SeriesView(environment: environment)
        case .search:   SearchView(environment: environment)
        case .settings: SettingsView(environment: environment)
        }
    }
}
