import SwiftUI

enum BrowserAboutPresentation {
    static let productName = "Personal Browser"
    static let productSummary = "An independent, local-first iPhone browser source snapshot for everyday browsing, focused reading, organization, and site-by-site control."
    static let privacySummary = "Browser collections and Browsing Insights stay in this app's own sandbox. Incognito activity is excluded from normal restoration, History, and Insights."
    static let snapshotStatus = "MIT-licensed source snapshot • October 2026"
    static let snapshotSummary = "This edition is a separately identified periodic source snapshot. It may be modified, forked, or maintained independently, and it does not promise release continuity or compatibility with another edition."
    static let attributionSummary = "Original authors and community contributors are credited in the source distribution's license and provenance files."
    static let commercialProductName = "Browser by Prifina"
    static let commercialSummary = "For the continuously maintained end-user edition, current product information, and the public beta, visit the Browser website. The commercial edition may include separately approved Apple capabilities that are not part of this source build."
    static let commercialWebsiteURL = URL(string: "https://browser.prifina.com/")!
    static let commercialBetaURL = URL(string: "https://testflight.apple.com/join/VZZPdDXA")!
    static let appleBrowserCapabilitiesURL = URL(string: "https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser")!

    static func versionDescription(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}

struct BrowserAboutView: View {
    let onBack: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    privacySection
                    capabilitiesSection
                    sourceSection
                    maintainedAppSection

                    Text("Copyright © 2026 original authors and contributors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .background(Color.browserCanvas)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Color.browserInk)
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            Text(BrowserAboutPresentation.productName)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.browserInk)

            Text(BrowserAboutPresentation.versionDescription())
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(BrowserAboutPresentation.productSummary)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var privacySection: some View {
        aboutSection(title: "Local by default") {
            aboutInfoRow(
                title: "Your browser data",
                subtitle: BrowserAboutPresentation.privacySummary,
                systemImage: "iphone"
            )
        }
    }

    private var sourceSection: some View {
        aboutSection(title: "Open source") {
            aboutInfoRow(
                title: "Independent snapshot",
                subtitle: BrowserAboutPresentation.snapshotStatus,
                systemImage: "chevron.left.forwardslash.chevron.right"
            )

            Text(BrowserAboutPresentation.snapshotSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text(BrowserAboutPresentation.attributionSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var capabilitiesSection: some View {
        aboutSection(title: "Apple browser capabilities") {
            Text(BrowserCapabilityPresentation.sourceBuildSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            aboutInfoRow(
                title: BrowserCapabilityPresentation.defaultBrowserTitle,
                subtitle: BrowserCapabilityPresentation.defaultBrowserSummary,
                systemImage: "safari"
            )

            aboutInfoRow(
                title: BrowserCapabilityPresentation.passkeyTitle,
                subtitle: BrowserCapabilityPresentation.passkeySummary,
                systemImage: "key.fill"
            )

            aboutInfoRow(
                title: BrowserCapabilityPresentation.addToHomeScreenTitle,
                subtitle: BrowserCapabilityPresentation.addToHomeScreenSummary,
                systemImage: "square.and.arrow.down"
            )

            Link(destination: BrowserAboutPresentation.appleBrowserCapabilitiesURL) {
                Label("Learn about Apple's browser requirements", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.browserAccent)
                    .frame(minHeight: 44)
            }
        }
    }

    private var maintainedAppSection: some View {
        aboutSection(title: "Maintained commercial app") {
            aboutInfoRow(
                title: BrowserAboutPresentation.commercialProductName,
                subtitle: BrowserAboutPresentation.commercialSummary,
                systemImage: "globe"
            )

            Link(destination: BrowserAboutPresentation.commercialWebsiteURL) {
                Label("Open browser.prifina.com", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.browserAccent)
                    .frame(minHeight: 44)
            }

            Link(destination: BrowserAboutPresentation.commercialBetaURL) {
                Label("Try the maintained beta", systemImage: "iphone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.browserAccent)
                    .frame(minHeight: 44)
            }
        }
    }

    private func aboutSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.browserInk.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func aboutInfoRow(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.browserAccent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.browserInk)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
