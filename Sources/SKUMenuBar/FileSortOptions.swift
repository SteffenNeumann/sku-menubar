import SwiftUI

// MARK: - Sort / Group options (shared between FileExplorerView and ChatFilePanel)

enum FileSortOrder: String, CaseIterable {
    case nameAsc  = "name_asc"
    case nameDesc = "name_desc"
    case dateDesc = "date_desc"
    case dateAsc  = "date_asc"
    case sizeDesc = "size_desc"
    case kindAsc  = "kind_asc"

    var label: String {
        switch self {
        case .nameAsc:  return "Name A → Z"
        case .nameDesc: return "Name Z → A"
        case .dateDesc: return "Datum (Neueste)"
        case .dateAsc:  return "Datum (Älteste)"
        case .sizeDesc: return "Größe (Größte)"
        case .kindAsc:  return "Art/Erweiterung"
        }
    }
}

enum FileGroupBy: String, CaseIterable {
    case none         = "none"
    case foldersFirst = "folders_first"
    case kind         = "kind"

    var label: String {
        switch self {
        case .none:         return "Keine Gruppierung"
        case .foldersFirst: return "Ordner zuerst"
        case .kind:         return "Nach Art"
        }
    }
}

// MARK: - Environment keys

private struct FileSortOrderEnvKey: EnvironmentKey {
    static let defaultValue: FileSortOrder = .nameAsc
}
private struct FileGroupByEnvKey: EnvironmentKey {
    static let defaultValue: FileGroupBy = .foldersFirst
}
extension EnvironmentValues {
    var fileSortOrder: FileSortOrder {
        get { self[FileSortOrderEnvKey.self] }
        set { self[FileSortOrderEnvKey.self] = newValue }
    }
    var fileGroupBy: FileGroupBy {
        get { self[FileGroupByEnvKey.self] }
        set { self[FileGroupByEnvKey.self] = newValue }
    }
}

// MARK: - Sort/group helper

func applySortGroup(
    _ nodes: [ExplorerNode],
    sortOrder: FileSortOrder,
    groupBy: FileGroupBy
) -> [ExplorerNode] {
    func sorted(_ arr: [ExplorerNode]) -> [ExplorerNode] {
        arr.sorted { a, b in
            switch sortOrder {
            case .nameAsc:  return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .nameDesc: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .dateDesc: return (a.modifiedAt ?? .distantPast) > (b.modifiedAt ?? .distantPast)
            case .dateAsc:  return (a.modifiedAt ?? .distantPast) < (b.modifiedAt ?? .distantPast)
            case .sizeDesc: return a.fileSize > b.fileSize
            case .kindAsc:  return a.fileExtension.localizedCaseInsensitiveCompare(b.fileExtension) == .orderedAscending
            }
        }
    }
    switch groupBy {
    case .none:
        return sorted(nodes)
    case .foldersFirst:
        return sorted(nodes.filter(\.isDirectory)) + sorted(nodes.filter { !$0.isDirectory })
    case .kind:
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let extCmp = a.fileExtension.localizedCaseInsensitiveCompare(b.fileExtension)
            if extCmp != .orderedSame { return extCmp == .orderedAscending }
            switch sortOrder {
            case .nameAsc:  return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .nameDesc: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .dateDesc: return (a.modifiedAt ?? .distantPast) > (b.modifiedAt ?? .distantPast)
            case .dateAsc:  return (a.modifiedAt ?? .distantPast) < (b.modifiedAt ?? .distantPast)
            case .sizeDesc: return a.fileSize > b.fileSize
            case .kindAsc:  return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }
}
