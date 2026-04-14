import SwiftUI

// MARK: - Notes & Tasks View

struct NotesView: View {
    let lockedType: NoteType?

    init(lockedType: NoteType? = nil) {
        self.lockedType = lockedType
    }

    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    @State private var selectedId: UUID?
    @State private var newlyAddedId: UUID? = nil
    @State private var searchText: String = ""
    @State private var filterType: NoteType? = nil
    @State private var showingDone: Bool = false
    @State private var filterTags: Set<String> = []
    @State private var tagFilterAnd: Bool = false   // false = ODER, true = UND
    @State private var showingTagManager = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var filtered: [NoteItem] {
        state.notes.filter { note in
            let matchesType   = lockedType != nil ? note.type == lockedType : (filterType == nil || note.type == filterType)
            let matchesDone   = showingDone ? note.done : true
            let matchesHide   = !showingDone ? (note.type != .task || !note.done) : true
            let matchesSearch = searchText.isEmpty ||
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.body.localizedCaseInsensitiveContains(searchText) ||
                note.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            let matchesTag: Bool
            if filterTags.isEmpty {
                matchesTag = true
            } else if tagFilterAnd {
                matchesTag = filterTags.allSatisfy { note.tags.contains($0) }
            } else {
                matchesTag = filterTags.contains { note.tags.contains($0) }
            }
            return matchesType && matchesDone && matchesHide && matchesSearch && matchesTag
        }
        .sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.createdAt > $1.createdAt
        }
    }

    /// Alle eindeutigen Tags aus der ungefilterten (ohne Tag-Filter) Liste
    private var allTagsInList: [String] {
        let base = state.notes.filter { note in
            let matchesType   = lockedType != nil ? note.type == lockedType : (filterType == nil || note.type == filterType)
            let matchesHide   = !showingDone ? (note.type != .task || !note.done) : true
            let matchesSearch = searchText.isEmpty ||
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.body.localizedCaseInsensitiveContains(searchText) ||
                note.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesType && matchesHide && matchesSearch
        }
        var seen = Set<String>()
        return base.flatMap { $0.tags }.filter { seen.insert($0).inserted }.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            HStack(spacing: 0) {
                // Left: list
                VStack(spacing: 0) {
                    filterBar
                    Divider().foregroundStyle(theme.cardBorder)
                    noteList
                }
                .frame(width: 260)
                .background(theme.windowBg)

                Rectangle().fill(theme.cardBorder).frame(width: 0.5)

                // Right: editor
                if let id = selectedId, let idx = state.notes.firstIndex(where: { $0.id == id }) {
                    NoteEditorView(note: $state.notes[idx], initialEditMode: newlyAddedId == id)
                        .id(id)
                        .environmentObject(state)
                        .environment(\.appTheme, theme)
                } else {
                    emptyEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                theme.cardBorder.opacity(0.5).frame(height: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingTagManager) {
            TagManagerSheet()
                .environmentObject(state)
                .environment(\.appTheme, theme)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                if let t = lockedType {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(noteTypeColor(t))
                        .frame(width: 4, height: 16)
                }
                Text(lockedType == .task ? "Aufgaben" : lockedType == .note ? "Notizen" : "Notizen & Aufgaben")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(lockedType != nil ? noteTypeColor(lockedType!) : theme.primaryText)
            }
            Spacer()
            if lockedType == nil || lockedType == .note {
                Button {
                    addNote(type: .note)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accentColor)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Neue Notiz")
            }
            if lockedType == nil || lockedType == .task {
                Button {
                    addNote(type: .task)
                } label: {
                    Image(systemName: "checkmark.square")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accentColor)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Neue Aufgabe")
            }
            Button {
                showingTagManager = true
            } label: {
                Image(systemName: "tag")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Tags verwalten")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
        .background(theme.windowBg)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 6) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                TextField("Suchen…", text: $searchText)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.primaryText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))

            // Chips: Type (nur mixed) + Erledigte-Toggle (immer außer .note)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if lockedType == nil {
                        typeChip(label: "Alle", icon: "tray.2", type: nil)
                        typeChip(label: "Notiz", icon: "note.text", type: .note)
                        typeChip(label: "Aufgabe", icon: "checkmark.square", type: .task)
                        Divider().frame(height: 14)
                    }
                    if lockedType != .note {
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) { showingDone.toggle() }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: showingDone ? "eye.slash" : "eye")
                                    .font(.system(size: 11))
                                Text(showingDone ? "Erledigte" : "Offen")
                                    .font(.system(size: 12, weight: showingDone ? .semibold : .regular))
                            }
                            .foregroundStyle(showingDone ? accentColor : theme.tertiaryText)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(showingDone ? accentColor.opacity(0.10) : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(showingDone ? accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Tag-Filter (nur wenn Tags vorhanden)
            if !allTagsInList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        Image(systemName: "tag")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                        if !filterTags.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.12)) { filterTags.removeAll() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                            if filterTags.count >= 2 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.12)) { tagFilterAnd.toggle() }
                                } label: {
                                    Text(tagFilterAnd ? "UND" : "ODER")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(accentColor)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(accentColor.opacity(0.15), in: Capsule())
                                        .overlay(Capsule().strokeBorder(accentColor.opacity(0.35), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                                .help(tagFilterAnd ? "Modus: Alle Tags müssen passen (klicken für ODER)" : "Modus: Mindestens ein Tag muss passen (klicken für UND)")
                            }
                        }
                        ForEach(allTagsInList, id: \.self) { tag in
                            let active = filterTags.contains(tag)
                            Button {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    if active { filterTags.remove(tag) } else { filterTags.insert(tag) }
                                }
                            } label: {
                                Text(tag)
                                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? accentColor : theme.secondaryText)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(active ? accentColor.opacity(0.10) : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(active ? accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func typeChip(label: String, icon: String, type: NoteType?) -> some View {
        let active = filterType == type
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { filterType = type }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? accentColor : theme.secondaryText)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(active ? accentColor.opacity(0.10) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note list

    private var noteList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                        .font(.system(size: 28)).foregroundStyle(theme.tertiaryText)
                    Text(searchText.isEmpty ? "Noch keine Einträge" : "Keine Treffer")
                        .font(.system(size: 14)).foregroundStyle(theme.tertiaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { note in
                            noteRow(note)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func displayTitle(_ note: NoteItem) -> String {
        if !note.title.isEmpty { return note.title }
        let firstLine = note.body
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return firstLine.isEmpty ? "Unbenannt" : firstLine
    }

    private func noteRow(_ note: NoteItem) -> some View {
        let isSelected = selectedId == note.id
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { selectedId = note.id }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                // type indicator — für Tasks direkt klickbar zum Erledigen
                if note.type == .task {
                    Button {
                        toggleDone(note)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(noteTypeColor(note.type).opacity(note.done ? 0.25 : 0.12))
                                .frame(width: 22, height: 22)
                            Circle()
                                .strokeBorder(noteTypeColor(note.type).opacity(0.4), lineWidth: 1)
                                .frame(width: 22, height: 22)
                            Image(systemName: noteTypeIcon(note))
                                .font(.system(size: 12))
                                .foregroundStyle(noteTypeColor(note.type))
                        }
                        .padding(.top, 1)
                    }
                    .buttonStyle(.plain)
                    .help(note.done ? "Als offen markieren" : "Als erledigt markieren")
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(noteTypeColor(note.type).opacity(0.15))
                            .frame(width: 22, height: 22)
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(noteTypeColor(note.type).opacity(0.3), lineWidth: 0.5)
                            .frame(width: 22, height: 22)
                        Image(systemName: noteTypeIcon(note))
                            .font(.system(size: 12))
                            .foregroundStyle(noteTypeColor(note.type))
                    }
                    .padding(.top, 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayTitle(note))
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(note.done ? theme.tertiaryText : theme.primaryText)
                            .strikethrough(note.done && note.type == .task)
                            .lineLimit(1)
                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(accentColor.opacity(0.7))
                        }
                    }
                    // Fortschritt bei Tasks mit Sub-Items
                    if note.type == .task && !note.taskLines.isEmpty {
                        let doneCount = note.taskLines.filter(\.done).count
                        let total = note.taskLines.count
                        HStack(spacing: 4) {
                            // Mini-Progress-Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(theme.cardBorder)
                                        .frame(height: 3)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(doneCount == total ? Color.green : accentColor)
                                        .frame(width: geo.size.width * (total > 0 ? CGFloat(doneCount) / CGFloat(total) : 0), height: 3)
                                }
                            }
                            .frame(height: 3)
                            Text("\(doneCount)/\(total)")
                                .font(.system(size: 11))
                                .foregroundStyle(doneCount == total ? .green : theme.tertiaryText)
                                .monospacedDigit()
                        }
                    } else if note.type == .note, !note.body.isEmpty {
                        let previewLine = note.body
                            .components(separatedBy: .newlines)
                            .dropFirst()
                            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                        if !previewLine.isEmpty {
                            Text(previewLine)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    // Tags
                    if !note.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 3) {
                                ForEach(note.tags, id: \.self) { tag in
                                    let highlighted = filterTags.contains(tag)
                                    Text(tag)
                                        .font(.system(size: 10))
                                        .foregroundStyle(highlighted ? accentColor : theme.tertiaryText)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background((highlighted ? accentColor : theme.cardBorder).opacity(0.25), in: Capsule())
                                }
                            }
                        }
                    }
                    Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText.opacity(0.7))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                        ? theme.primaryText.opacity(0.08)
                        : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? theme.primaryText.opacity(0.14) : noteTypeColor(note.type).opacity(0.12),
                        lineWidth: 0.5)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(noteTypeColor(note.type).opacity(note.done ? 0.25 : 0.65))
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.leading, 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { togglePin(note) } label: {
                Label(note.pinned ? "Nicht mehr anpinnen" : "Anpinnen",
                      systemImage: note.pinned ? "pin.slash" : "pin")
            }
            if note.type == .task {
                Button { toggleDone(note) } label: {
                    Label(note.done ? "Als offen markieren" : "Als erledigt markieren",
                          systemImage: note.done ? "arrow.uturn.left" : "checkmark")
                }
            }
            Divider()
            Button(role: .destructive) { deleteNote(note) } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty editor

    private var emptyEditor: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 36))
                .foregroundStyle(theme.tertiaryText)
            Text("Notiz auswählen oder neu anlegen")
                .font(.system(size: 13))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func addNote(type: NoteType) {
        var note = NoteItem(type: type, title: "", body: "")
        if type == .task { note.taskLines = [TaskLine()] }
        state.notes.insert(note, at: 0)
        newlyAddedId = note.id
        selectedId = note.id
    }

    private func deleteNote(_ note: NoteItem) {
        if selectedId == note.id { selectedId = nil }
        state.notes.removeAll { $0.id == note.id }
    }

    private func togglePin(_ note: NoteItem) {
        if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
            state.notes[idx].pinned.toggle()
        }
    }

    private func toggleDone(_ note: NoteItem) {
        if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
            state.notes[idx].done.toggle()
        }
    }

    private func noteTypeColor(_ type: NoteType) -> Color {
        return accentColor
    }

    private func noteTypeIcon(_ note: NoteItem) -> String {
        if note.type == .task { return note.done ? "checkmark.square.fill" : "square" }
        return "note.text"
    }
}

// MARK: - Note Editor

struct NoteEditorView: View {
    @Binding var note: NoteItem
    @Environment(\.appTheme) var theme
    @EnvironmentObject var state: AppState
    @FocusState private var bodyFocused: Bool
    @State private var showPreview: Bool

    init(note: Binding<NoteItem>, initialEditMode: Bool = false) {
        self._note = note
        // Neue Notiz → Edit-Modus; bestehende Notiz → Vorschau-Modus
        self._showPreview = State(initialValue: !initialEditMode)
    }

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Type + title
            editorHeader

            // Body: Checkliste für Tasks, Freitext/Preview für Notizen
            if note.type == .task {
                TaskLinesEditorView(lines: $note.taskLines, theme: theme, accent: accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showPreview {
                ScrollView(.vertical, showsIndicators: false) {
                    MarkdownTextView(text: note.body.isEmpty ? "*Keine Inhalte*" : note.body)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.clear)
            } else {
                TextEditor(text: $note.body)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.primaryText)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .tint(accentColor)
                    .padding(16)
                    .focused($bodyFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider().foregroundStyle(theme.cardBorder)

            // Footer: tags + done toggle
            editorFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { bodyFocused = note.title.isEmpty }
        .onChange(of: note.body) { _, newBody in
            guard note.type == .note else { return }
            let firstLine = newBody
                .components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
            note.title = firstLine
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 10) {
            // Type picker
            Menu {
                ForEach(NoteType.allCases, id: \.self) { t in
                    Button {
                        note.type = t
                    } label: {
                        Label(t.rawValue, systemImage: noteTypeMenuIcon(t))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: noteTypeMenuIcon(note.type))
                        .font(.system(size: 13))
                    Text(note.type.rawValue)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(noteTypeColor(note.type))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(noteTypeColor(note.type).opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)

            // Title
            TextField("Titel…", text: $note.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .textFieldStyle(.plain)

            // Preview toggle (nur für Notizen)
            if note.type == .note {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showPreview.toggle() }
                } label: {
                    Group {
                        if showPreview {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                        } else {
                            Image(systemName: "book.pages")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(theme.primaryText.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(theme.primaryText.opacity(0.08),
                                      lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help(showPreview ? "Bearbeiten" : "Vorschau (Markdown)")
            }

            // Task done toggle
            if note.type == .task {
                Button {
                    note.done.toggle()
                } label: {
                    Image(systemName: note.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(note.done ? .green : theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help(note.done ? "Als offen markieren" : "Als erledigt markieren")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(theme.cardBg.opacity(0.4))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.cardBorder).frame(height: 0.5)
        }
    }

    // MARK: - Footer

    private var editorFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)

            // Tags as chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(note.tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text(tag)
                                .font(.system(size: 12))
                                .foregroundStyle(accentColor)
                            Button {
                                note.tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accentColor.opacity(0.10), in: Capsule())
                    }

                    // Inline tag input
                    TagInputView(
                        tags: $note.tags,
                        theme: theme,
                        accent: accentColor
                    )
                }
            }

            Spacer()

            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func noteTypeColor(_ type: NoteType) -> Color {
        return accentColor
    }

    private func noteTypeMenuIcon(_ type: NoteType) -> String {
        switch type {
        case .note:  return "note.text"
        case .task:  return "checkmark.square"
        }
    }
}

// MARK: - Tag Input Helper

private struct TagInputView: View {
    @Binding var tags: [String]
    let theme: AppTheme
    let accent: Color
    @State private var input = ""

    var body: some View {
        TextField("+Tag", text: $input)
            .font(.system(size: 12))
            .foregroundStyle(theme.secondaryText)
            .textFieldStyle(.plain)
            .frame(width: 80)
            .onSubmit {
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !tags.contains(trimmed) {
                    tags.append(trimmed)
                }
                input = ""
            }
    }
}

// MARK: - Tag Manager Sheet

struct TagManagerSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @Environment(\.dismiss) var dismiss

    @State private var editingTag: String? = nil
    @State private var editText: String = ""

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var allTagsWithCount: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for note in state.notes {
            for tag in note.tags { counts[tag, default: 0] += 1 }
        }
        return counts.map { (tag: $0.key, count: $0.value) }.sorted { $0.tag < $1.tag }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tags verwalten")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().foregroundStyle(theme.cardBorder)

            if allTagsWithCount.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.tertiaryText)
                    Text("Keine Tags vorhanden")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(allTagsWithCount, id: \.tag) { item in
                            tagRow(item.tag, count: item.count)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 300, height: 360)
        .background(theme.windowBg)
    }

    @ViewBuilder
    private func tagRow(_ tag: String, count: Int) -> some View {
        HStack(spacing: 8) {
            if editingTag == tag {
                TextField("Tag-Name", text: $editText)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.primaryText)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename(from: tag) }

                Button { commitRename(from: tag) } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)

                Button { editingTag = nil } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "tag.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor.opacity(0.7))

                Text(tag)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.primaryText)

                Text("·  \(count)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)

                Spacer()

                Button {
                    editingTag = tag
                    editText = tag
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Umbenennen")

                Button { deleteTag(tag) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.65))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Tag löschen")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(editingTag == tag ? accentColor.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
    }

    private func commitRename(from oldTag: String) {
        let newTag = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTag.isEmpty, newTag != oldTag else { editingTag = nil; return }
        for i in state.notes.indices {
            if let idx = state.notes[i].tags.firstIndex(of: oldTag) {
                if !state.notes[i].tags.contains(newTag) {
                    state.notes[i].tags[idx] = newTag
                } else {
                    state.notes[i].tags.remove(at: idx)
                }
            }
        }
        editingTag = nil
    }

    private func deleteTag(_ tag: String) {
        for i in state.notes.indices {
            state.notes[i].tags.removeAll { $0 == tag }
        }
    }
}

// MARK: - Task Lines Editor

struct TaskLinesEditorView: View {
    @Binding var lines: [TaskLine]
    let theme: AppTheme
    let accent: Color
    @FocusState private var focusedId: UUID?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { idx in
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(lines[idx].done ? accent : Color.clear)
                                .frame(width: 18, height: 18)
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(
                                    lines[idx].done ? accent : theme.tertiaryText.opacity(0.5),
                                    lineWidth: 1.5
                                )
                                .frame(width: 18, height: 18)
                            if lines[idx].done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            var updated = lines
                            updated[idx].done.toggle()
                            lines = updated
                        }

                        TextField("Aufgabe…", text: $lines[idx].text)
                            .font(.system(size: 13))
                            .foregroundStyle(lines[idx].done ? theme.tertiaryText : theme.primaryText)
                            .strikethrough(lines[idx].done)
                            .textFieldStyle(.plain)
                            .focused($focusedId, equals: lines[idx].id)
                            .onSubmit { addLineAfter(lines[idx]) }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 10)
        }
        .onAppear {
            if let first = lines.first { focusedId = first.id }
        }
    }

    private func addLineAfter(_ line: TaskLine) {
        let newLine = TaskLine()
        if let idx = lines.firstIndex(where: { $0.id == line.id }) {
            lines.insert(newLine, at: idx + 1)
        } else {
            lines.append(newLine)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedId = newLine.id
        }
    }
}

// MARK: - SVG-style preview toggle icons

private struct NotesEyeIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let cx = w / 2, cy = h / 2
            // Lens outline
            var lens = Path()
            lens.move(to: CGPoint(x: 2, y: cy))
            lens.addCurve(
                to: CGPoint(x: w - 2, y: cy),
                control1: CGPoint(x: cx * 0.4, y: 1.5),
                control2: CGPoint(x: cx * 1.6, y: 1.5)
            )
            lens.addCurve(
                to: CGPoint(x: 2, y: cy),
                control1: CGPoint(x: cx * 1.6, y: h - 1.5),
                control2: CGPoint(x: cx * 0.4, y: h - 1.5)
            )
            ctx.stroke(lens, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            // Iris
            let r: CGFloat = h * 0.26
            let pupil = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.fill(pupil, with: .color(color))
        }
        .frame(width: 16, height: 10)
    }
}

private struct NotesPencilIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            // Shaft body
            var shaft = Path()
            shaft.move(to:    CGPoint(x: w * 0.14, y: h * 0.82))
            shaft.addLine(to: CGPoint(x: w * 0.76, y: h * 0.10))
            shaft.addLine(to: CGPoint(x: w * 0.92, y: h * 0.26))
            shaft.addLine(to: CGPoint(x: w * 0.30, y: h * 0.96))
            shaft.closeSubpath()
            ctx.stroke(shaft, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            // Tip
            var tip = Path()
            tip.move(to:    CGPoint(x: w * 0.02, y: h * 0.98))
            tip.addLine(to: CGPoint(x: w * 0.14, y: h * 0.82))
            tip.addLine(to: CGPoint(x: w * 0.30, y: h * 0.96))
            tip.closeSubpath()
            ctx.fill(tip, with: .color(color.opacity(0.6)))
            // Eraser divider
            var band = Path()
            band.move(to:    CGPoint(x: w * 0.70, y: h * 0.12))
            band.addLine(to: CGPoint(x: w * 0.86, y: h * 0.28))
            ctx.stroke(band, with: .color(color.opacity(0.45)), lineWidth: 1.6)
        }
        .frame(width: 13, height: 13)
    }
}
