import SwiftUI

struct SiteSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var page: WebPage

    var body: some View {
        NavigationStack {
            SiteSettingsContentView(page: page)
            .navigationTitle("Site Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

struct SiteSettingsContentView: View {
    @ObservedObject var page: WebPage
    var onOpenAppLinkPreferences: (() -> Void)?

    init(page: WebPage, onOpenAppLinkPreferences: (() -> Void)? = nil) {
        self.page = page
        self.onOpenAppLinkPreferences = onOpenAppLinkPreferences
    }

    var body: some View {
        List {
            Section("Current Site") {
                Label(siteName, systemImage: "globe")
                    .foregroundStyle(Color.browserInk)
            }

            if let support = page.siteAccessibilitySupport,
               support.supportsBottomNavigation {
                Section {
                    Toggle(
                        "Bottom navigation",
                        isOn: Binding(
                            get: { page.usesSiteBottomNavigation },
                            set: { enabled in
                                Task {
                                    await page.setSiteBottomNavigationEnabled(enabled)
                                }
                            }
                        )
                    )
                    .tint(Color.browserAccent)
                } header: {
                    Text("Accessibility")
                } footer: {
                    Text("For \(support.displayName), this adds a compact one-thumb footer using the site's real navigation when available. The original page menu remains unchanged.")
                }
            } else {
                Section("Accessibility") {
                    Label("No adjustments available for this site", systemImage: "accessibility")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if page.url?.host != nil {
                    Toggle(
                        "Hide app-promotion prompts",
                        isOn: Binding(
                            get: { page.blocksAppPrompts },
                            set: { blocked in
                                Task {
                                    await page.setAppPromptBlocking(blocked)
                                }
                            }
                        )
                    )
                    .tint(Color.browserAccent)
                }

                appLinkPreferencesDestination
            } header: {
                Text("App Behavior")
            } footer: {
                Text("Choose whether this site may show prompts advertising its app. Remembered choices for opening installed apps are managed separately for each service.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.browserCanvas)
    }

    @ViewBuilder
    private var appLinkPreferencesDestination: some View {
        if let onOpenAppLinkPreferences {
            Button(action: onOpenAppLinkPreferences) {
                HStack {
                    Label("App Promos", systemImage: "arrow.up.forward.app")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(Color.browserInk)
        } else {
            NavigationLink {
                AppLinkPreferencesContentView(
                    preferences: page.externalAppLinkPreferences
                )
            } label: {
                Label("App Promos", systemImage: "arrow.up.forward.app")
            }
        }
    }

    private var siteName: String {
        AppPromptPreferences.normalizedHost(from: page.url) ?? "Current Site"
    }
}
