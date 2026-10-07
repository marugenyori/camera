import Foundation

/// アプリとウィジェットで共有する、共有アルバムの新しい写真の一覧。
/// アプリが App Group（group. + Bundle ID）の中の widget/ フォルダに entries.json と小さい画像を書き、
/// ウィジェットはそれを読むだけ（ウィジェットから iCloud には問い合わせない）
struct AlbumWidgetData: Codable {
    struct Entry: Codable, Hashable {
        /// 画像のファイル名（widget/ フォルダの中）
        let file: String
        let albumTitle: String
        /// 入れた人（自分なら「自分」）
        let who: String
        let takenAt: Date
    }

    var entries: [Entry] = []
    var updatedAt = Date()

    static let maxEntries = 4

    /// App Group の名前（アプリの Bundle ID の前に group. を付けたもの）
    static var groupID: String {
        var id = Bundle.main.bundleIdentifier ?? ""
        if id.hasSuffix(".widget") { id.removeLast(".widget".count) }
        return "group." + id
    }

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget", isDirectory: true)
    }

    static func load() -> AlbumWidgetData {
        guard let url = folder?.appendingPathComponent("entries.json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(AlbumWidgetData.self, from: data) else { return AlbumWidgetData() }
        return value
    }

    func save() {
        guard let folder = Self.folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: folder.appendingPathComponent("entries.json"), options: .atomic)
        }
    }

    static func imageURL(_ file: String) -> URL? {
        folder?.appendingPathComponent(file)
    }
}
