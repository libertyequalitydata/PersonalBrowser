import SwiftUI

struct AppLinkPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var preferences: ExternalAppLinkPreferences

    var body: some View {
        NavigationStack {
            AppLinkPreferencesContentView(preferences: preferences)
            .navigationTitle("App Promos")
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

struct AppLinkPreferencesContentView: View {
    @ObservedObject var preferences: ExternalAppLinkPreferences

    var body: some View {
        List {
            if preferences.records.isEmpty {
                ContentUnavailableView(
                    "No App Link Choices",
                    systemImage: "arrow.up.forward.app",
                    description: Text("When a service first tries to open an installed app, Browser will ask whether to stay on the web or open the app.")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(preferences.records) { record in
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(Color.browserControl)
                                .frame(width: 24)

                            Text(record.serviceName)
                                .foregroundStyle(Color.browserInk)

                            Spacer()

                            Menu {
                                ForEach(ExternalAppLinkChoice.allCases) { choice in
                                    Button {
                                        preferences.setChoice(choice, for: record.serviceKey)
                                    } label: {
                                        if choice == record.choice {
                                            Label(choice.title, systemImage: "checkmark")
                                        } else {
                                            Text(choice.title)
                                        }
                                    }
                                }

                                Divider()

                                Button("Ask Next Time") {
                                    preferences.removeChoice(for: record.serviceKey)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(record.choice.title)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2.weight(.semibold))
                                }
                                .font(.subheadline)
                                .foregroundStyle(Color.browserAccent)
                            }
                        }
                        .frame(minHeight: 48)
                    }
                } header: {
                    Text("Remembered Choices")
                } footer: {
                    Text("Each service has its own permanent choice. Choose Ask Next Time to receive the prompt again for that service.")
                }

                Section {
                    Button("Ask Again for All Services", role: .destructive) {
                        preferences.resetAll()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.browserCanvas)
        .navigationTitle("App Promos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
