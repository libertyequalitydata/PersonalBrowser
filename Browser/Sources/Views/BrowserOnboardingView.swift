import SwiftUI

struct BrowserOnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages = BrowserOnboardingPage.allCases

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.browserControl)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element) { index, item in
                    VStack(spacing: 24) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 54, weight: .medium))
                            .foregroundStyle(Color.browserAccent)
                            .frame(width: 112, height: 112)
                            .background(Color.browserAccent.opacity(0.1), in: Circle())

                        VStack(spacing: 12) {
                            Text(item.title)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.browserInk)

                            Text(item.message)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(action: advance) {
                Text(page == pages.count - 1 ? "Start browsing" : "Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.browserAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.browserCanvas.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private func advance() {
        if page == pages.count - 1 {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                page += 1
            }
        }
    }
}

private enum BrowserOnboardingPage: CaseIterable {
    case browse
    case roles
    case reading
    case privacy

    var title: String {
        switch self {
        case .browse: "Your browser, on your terms"
        case .roles: "Add context, not profiles"
        case .reading: "Read and keep what matters"
        case .privacy: "Stay in control"
        }
    }

    var message: String {
        switch self {
        case .browse:
            "Browse with tabs, saved pages, history, and downloads. No Browser account is required, and this beta keeps its Browser data on this iPhone."
        case .roles:
            "Roles are optional labels for the same person. Use one, several, or none to filter tabs, saved pages, history, and downloads."
        case .reading:
            "Reader removes page clutter when an article can be captured. Add articles and selected downloads to Library when you want to return later."
        case .privacy:
            "Choose whether supported links stay on the web, and adjust app promos and supported accessibility options in Site Settings. Incognito tabs and history are not restored."
        }
    }

    var systemImage: String {
        switch self {
        case .browse: "globe"
        case .roles: "person.crop.rectangle.stack"
        case .reading: "eyeglasses"
        case .privacy: "hand.raised"
        }
    }
}

struct BrowserSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let onManageRoles: () -> Void
    let onReplayOnboarding: () -> Void

    var body: some View {
        NavigationStack {
            BrowserSettingsContentView(
                onManageRoles: onManageRoles,
                onReplayOnboarding: {
                    dismiss()
                    DispatchQueue.main.async {
                        onReplayOnboarding()
                    }
                }
            )
            .navigationTitle("Browser Settings")
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

struct BrowserSettingsContentView: View {
    let onManageRoles: () -> Void
    let onReplayOnboarding: () -> Void

    @ObservedObject private var passkeySupport = BrowserPasskeySupport.shared

    var body: some View {
        List {
            Section("Organization") {
                Button(action: onManageRoles) {
                    HStack {
                        Label {
                            Text("Manage Roles")
                        } icon: {
                            Image("RolesIcon")
                                .renderingMode(.template)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section("Security") {
                if passkeySupport.authorizationStatus == .disabled {
                    HStack(alignment: .top) {
                        Label(BrowserCapabilityPresentation.passkeyTitle, systemImage: "key.fill")
                        Spacer()
                        Text(passkeySupport.statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    Text(BrowserCapabilityPresentation.passkeySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        if passkeySupport.authorizationStatus == .denied {
                            passkeySupport.openSettings()
                        } else {
                            passkeySupport.requestAuthorization()
                        }
                    } label: {
                        HStack {
                            Label(BrowserCapabilityPresentation.passkeyTitle, systemImage: "key.fill")
                            Spacer()
                            Text(passkeySupport.statusDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .disabled(passkeySupport.authorizationStatus == .authorized)
                }
            }

            Section("Help") {
                Button(action: onReplayOnboarding) {
                    Label("Replay Onboarding", systemImage: "rectangle.stack.badge.play")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.browserCanvas)
        .onAppear {
            passkeySupport.refreshAuthorizationStatus()
        }
    }
}
