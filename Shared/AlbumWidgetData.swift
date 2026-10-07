import Foundation
import ImageIO
import UIKit

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
    /// アルバムの写真の枚数（ロック画面の「写真の枚数」用。古いデータには無い）
    var totalCount: Int? = nil
    /// 新しい写真の撮った日時（今日・今週の枚数を数えるため。新しい順に最大 maxDates 件）
    var recentDates: [Date]? = nil

    static let maxEntries = 4
    static let maxDates = 500

    /// 今日撮った（入れた）枚数
    func count(since start: Date) -> Int {
        (recentDates ?? []).filter { $0 >= start }.count
    }

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

    /// 画像を、長い辺 maxPixel まで縮めて読む（ウィジェットは使えるメモリがとても少ないので、大きいまま開かない）
    static func image(_ file: String, maxPixel: CGFloat = 500) -> UIImage? {
        guard let url = imageURL(file),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
