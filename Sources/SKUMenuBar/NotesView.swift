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
    @State private var searchText: String = ""
    @State private var filterType: NoteType? = nil
    @State private var showingDone: Bool = false
    @State private var filterTag: String? = nil

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
            let matchesTag    = filterTag == nil || note.tags.contains { $0 == filterTag }
            return matchesType && matchesDone && matchesHide && matchesSearch && matchesTag
        }
        .sorted { $0.createdAt > $1.createdAt }
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
        HStack(spacing: 0) {
            // Left: list
            VStack(spacing: 0) {
                headerBar
                Divider().foregroundStyle(theme.cardBorder)
                filterBar
                Divider().foregroundStyle(theme.cardBorder)
                noteList
            }
            .frame(width: 260)
            .background(theme.windowBg)

            Rectangle().fill(theme.cardBorder).frame(width: 0.5)

            // Right: editor
            if let id = selectedId, let idx = state.notes.firstIndex(where: { $0.id == id }) {
                NoteEditorView(note: $state.notes[idx])
                    .id(id)
                    .environmentObject(state)
                    .environment(\.appTheme, theme)
            } else {
                emptyEditor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text(lockedType == .task ? "Aufgaben" : lockedType == .note ? "Notizen" : "Notizen & Aufgaben")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            if lockedType == nil || lockedType == .note {
                Button {
                    addNote(type: .note)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accentColor)
                        .frame(width: 28, height: 28)
                        .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accentColor.opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Neue Notiz")
            }
            if lockedType == nil || lockedType == .task {
                Button {
                    addNote(type: .task)
                } label: {
                    Image(systemName: "checkmark.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accentColor)
                        .frame(width: 28, height: 28)
                        .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accentColor.opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Neue Aufgabe")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 6) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
                TextField("Suchen…", text: $searchText)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.primaryText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
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
                                    .font(.system(size: 9))
                                Text(showingDone ? "Erledigte" : "Offen")
                                    .font(.system(size: 10, weight: showingDone ? .semibold : .regular))
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
                            .font(.system(size: 9))
                            .foregroundStyle(theme.tertiaryText)
                        if filterTag != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.12)) { filterTag = nil }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(allTagsInList, id: \.self) { tag in
                            let active = filterTag == tag
                            Button {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    filterTag = active ? nil : tag
                                }
                            } label: {
                                Text(tag)
                                    .font(.system(size: 10, weight: active ? .semibold : .regular))
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
                Image(systemName: icon).font(.system(size: 9))
                Text(label).font(.system(size: 10, weight: active ? .semibold : .regular))
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
                        .font(.system(size: 12)).foregroundStyle(theme.tertiaryText)
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
                            RoundedRectangle(cornerRadius: 5)
                                .fill(noteTypeColor(note.type).opacity(note.done ? 0.25 : 0.12))
                                .frame(width: 22, height: 22)
                            Image(systemName: noteTypeIcon(note))
                                .font(.system(size: 10))
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
                        Image(systemName: noteTypeIcon(note))
                            .font(.system(size: 10))
                            .foregroundStyle(noteTypeColor(note.type))
                    }
                    .padding(.top, 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle(note))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(note.done ? theme.tertiaryText : theme.primaryText)
                        .strikethrough(note.done && note.type == .task)
                        .lineLimit(1)
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
                                .font(.system(size: 9))
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
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    // Tags
                    if !note.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 3) {
                                ForEach(note.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 8))
                                        .foregroundStyle(filterTag == tag ? accentColor : theme.tertiaryText)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background((filterTag == tag ? accentColor : theme.cardBorder).opacity(0.25), in: Capsule())
                                }
                            }
                        }
                    }
                    Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText.opacity(0.7))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accentColor.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? accentColor.opacity(0.25) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
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
        selectedId = note.id
    }

    private func deleteNote(_ note: NoteItem) {
        if selectedId == note.id { selectedId = nil }
        state.notes.removeAll { $0.id == note.id }
    }

    private func toggleDone(_ note: NoteItem) {
        if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
            state.notes[idx].done.toggle()
        }
    }

    private func noteTypeColor(_ type: NoteType) -> Color {
        switch type {
        case .note:  return .blue
        case .task:  return .green
        }
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

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Type + title
            editorHeader

            Divider().foregroundStyle(theme.cardBorder)

            // Body: Checkliste für Tasks, Freitext für Notizen
            if note.type == .task {
                TaskLinesEditorView(lines: $note.taskLines, theme: theme, accent: accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .font(.system(size: 11))
                    Text(note.type.rawValue)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
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
    }

    // MARK: - Footer

    private var editorFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)

            // Tags as chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(note.tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text(tag)
                                .font(.system(size: 10))
                                .foregroundStyle(accentColor)
                            Button {
                                note.tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accentColor.opacity(0.10), in: Capsule())
                    }

                    // Inline tag input
                    TagInputView(tags: $note.tags, theme: theme, accent: accentColor)
                }
            }

            Spacer()

            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 9))
                .foregroundStyle(theme.tertiaryText.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func noteTypeColor(_ type: NoteType) -> Color {
        switch type {
        case .note:  return .blue
        case .task:  return .green
        }
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
    @FocusState private var focused: Bool

    var body: some View {
        TextField("+Tag", text: $input)
            .font(.system(size: 10))
            .foregroundStyle(theme.secondaryText)
            .textFieldStyle(.plain)
            .frame(width: focused ? 80 : 36)
            .focused($focused)
            .onSubmit {
                let tag = input.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tag.isEmpty && !tags.contains(tag) {
                    tags.append(tag)
                }
                input = ""
                focused = false
            }
            .animation(.easeInOut(duration: 0.12), value: focused)
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
                        Button {
                            var updated = lines
                            updated[idx].done.toggle()
                            lines = updated
                        } label: {
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
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)

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
