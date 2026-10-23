import SwiftUI

struct RoleManagerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RoleManagerContentView()
                .navigationTitle("Manage Roles")
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

struct RoleManagerContentView: View {
    @EnvironmentObject private var store: BrowserStore

    @State private var newRoleName = ""
    @State private var roleToRename: BrowserRole?
    @State private var renamedRoleName = ""
    @State private var validationMessage: String?

    var body: some View {
        List {
            Section {
                if store.activeRoles.isEmpty {
                    ContentUnavailableView(
                        "No Roles yet",
                        systemImage: "person.crop.rectangle.stack",
                        description: Text("Add only the Roles that are useful to you. A tab with no selected Role remains unlabeled.")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.rolesByUsage()) { role in
                        roleRow(role)
                    }
                }
            } header: {
                Text("Your Roles")
            } footer: {
                Text("Roles describe contexts of the same person. Archiving a Role removes it from open tabs and selectors without deleting the Role itself.")
            }

            Section("Add Role") {
                TextField("Role name", text: $newRoleName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addRole)

                Button(action: addRole) {
                    Label("Add Role", systemImage: "plus")
                }
                .disabled(newRoleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !store.archivedRoles.isEmpty {
                Section("Archived") {
                    ForEach(store.archivedRoles) { role in
                        HStack(spacing: 12) {
                            roleIcon
                                .foregroundStyle(.secondary)

                            Text(role.name)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Restore") {
                                store.setRoleArchived(role.id, archived: false)
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.browserCanvas)
        .alert("Rename Role", isPresented: renameAlertPresented) {
            TextField("Role name", text: $renamedRoleName)
            Button("Cancel", role: .cancel) {
                roleToRename = nil
                renamedRoleName = ""
            }
            Button("Rename") { renameRole() }
                .disabled(renamedRoleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The updated name appears everywhere this Role is used.")
        }
    }

    private func roleRow(_ role: BrowserRole) -> some View {
        HStack(spacing: 12) {
            roleIcon
                .foregroundStyle(Color.browserControl)

            Text(role.name)
                .foregroundStyle(Color.browserInk)

            Spacer()

            Menu {
                Button {
                    roleToRename = role
                    renamedRoleName = role.name
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.setRoleArchived(role.id, archived: true)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(role.name)")
        }
        .frame(minHeight: 52)
    }

    private var roleIcon: some View {
        Image("RolesIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { roleToRename != nil },
            set: { presented in
                if !presented {
                    roleToRename = nil
                    renamedRoleName = ""
                }
            }
        )
    }

    private func addRole() {
        guard store.addRole(name: newRoleName) != nil else {
            validationMessage = "Use a unique Role name."
            return
        }
        newRoleName = ""
        validationMessage = nil
    }

    private func renameRole() {
        guard let roleToRename else { return }
        if store.renameRole(roleToRename.id, name: renamedRoleName) {
            validationMessage = nil
        } else {
            validationMessage = "Use a unique Role name."
        }
        self.roleToRename = nil
        renamedRoleName = ""
    }
}
