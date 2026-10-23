import SwiftUI

struct SavedBookmarkEditorView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss

    let bookmark: Bookmark

    @State private var note: String
    @State private var selectedRoleIDs: Set<UUID>
    @State private var selectedListIDs: Set<UUID>
    @State private var newListName = ""
    @State private var listToRename: SavedBookmarkList?
    @State private var renamedListName = ""
    @State private var validationMessage: String?

    init(bookmark: Bookmark) {
        self.bookmark = bookmark
        _note = State(initialValue: bookmark.note ?? "")
        _selectedRoleIDs = State(initialValue: Set(bookmark.roleIDs ?? []))
        _selectedListIDs = State(initialValue: Set(bookmark.savedListIDs ?? []))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Note") {
                    TextField(
                        "Add a short note",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                    .onChange(of: note) { _, value in
                        if value.count > 280 {
                            note = String(value.prefix(280))
                        }
                    }

                    Text("\(note.count)/280")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section("Saved Lists") {
                    if activeLists.isEmpty {
                        Label("No lists yet", systemImage: "folder")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeLists) { list in
                            savedListRow(list)
                        }
                    }

                    HStack(spacing: 12) {
                        TextField("New list", text: $newListName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(addList)

                        Button(action: addList) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Add saved list")
                    }

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                }

                if !archivedLists.isEmpty {
                    Section("Archived Lists") {
                        ForEach(archivedLists) { list in
                            HStack(spacing: 12) {
                                Image(systemName: "archivebox")
                                    .foregroundStyle(.secondary)
                                Text(list.name)
                                Spacer()
                                Button("Restore") {
                                    store.setSavedBookmarkListArchived(list.id, archived: false)
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }

                Section {
                    if store.activeRoles.isEmpty {
                        Label("No Roles available", systemImage: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.rolesByUsage(prioritizing: selectedRoleIDs)) { role in
                            selectionRow(
                                title: role.name,
                                systemImage: "person.crop.circle",
                                isSelected: selectedRoleIDs.contains(role.id)
                            ) {
                                toggle(role.id, in: &selectedRoleIDs)
                            }
                        }
                    }
                } header: {
                    Text("Roles")
                } footer: {
                    Text("Roles add optional context to this saved page. Selecting none leaves it unlabeled.")
                }

                Section {
                    ShareLink(item: bookmark.url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        store.removeBookmark(bookmark.id)
                        dismiss()
                    } label: {
                        Label("Unsave", systemImage: "bookmark.slash")
                    }
                }
            }
            .navigationTitle("Saved Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateBookmarkMetadata(
                            bookmark.id,
                            note: note,
                            roleIDs: Array(selectedRoleIDs),
                            savedListIDs: Array(selectedListIDs)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(bookmark.isIncognito ? .dark : .light)
        .alert("Rename List", isPresented: renameAlertPresented) {
            TextField("List name", text: $renamedListName)
            Button("Cancel", role: .cancel) {
                listToRename = nil
                renamedListName = ""
            }
            Button("Rename") { renameList() }
                .disabled(renamedListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The updated name appears for every saved page in this list.")
        }
    }

    private func savedListRow(_ list: SavedBookmarkList) -> some View {
        HStack(spacing: 8) {
            Button {
                toggle(list.id, in: &selectedListIDs)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundStyle(Color.browserAccent)
                    Text(list.name)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: selectedListIDs.contains(list.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedListIDs.contains(list.id) ? Color.browserAccent : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    listToRename = list
                    renamedListName = list.name
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    selectedListIDs.remove(list.id)
                    store.setSavedBookmarkListArchived(list.id, archived: true)
                } label: {
                    Label("Archive List", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .rotationEffect(.degrees(90))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Options for \(list.name)")
        }
    }

    private func selectionRow(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.browserAccent)
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.browserAccent : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { listToRename != nil },
            set: { if !$0 { listToRename = nil } }
        )
    }

    private var activeLists: [SavedBookmarkList] {
        store.savedBookmarkLists(incognitoOnly: bookmark.isIncognito)
    }

    private var archivedLists: [SavedBookmarkList] {
        store.savedBookmarkLists(incognitoOnly: bookmark.isIncognito, archived: true)
    }

    private func toggle(_ id: UUID, in selection: inout Set<UUID>) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func addList() {
        guard let list = store.addSavedBookmarkList(
            name: newListName,
            isIncognito: bookmark.isIncognito
        ) else {
            validationMessage = "Use a unique list name."
            return
        }
        selectedListIDs.insert(list.id)
        newListName = ""
        validationMessage = nil
    }

    private func renameList() {
        guard let listToRename else { return }
        validationMessage = store.renameSavedBookmarkList(listToRename.id, name: renamedListName)
            ? nil
            : "Use a unique list name."
        self.listToRename = nil
        renamedListName = ""
    }
}
