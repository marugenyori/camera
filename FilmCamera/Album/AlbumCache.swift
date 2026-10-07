import CloudKit
import UIKit

/// 共有アルバムの端末内の控え（キャッシュ）。アルバムごとにフォルダを分けて、
/// 写真と反応の一覧（index.json）、一覧用の小さい画像（thumbs/）、大きく見た画像（full/）、
/// そして iCloud の「どこまで読んだか」（CKServerChangeToken）を置く。
/// 次に開いたときはまず控えをすぐ出し、iCloud からはその位置より後の変更（追加・削除）だけを取り込む。
/// 場所は Caches（端末の空きが少ないと OS が消すことがあるが、そのときは最初から読み直すだけ）
struct AlbumCache {
    struct Photo: Codable {
        let name: String
        let takenAt: Date
        let mode: String
        let creator: String?
        /// 撮った場所（記録されていれば）
        var latitude: Double? = nil
        var longitude: Double? = nil
        /// 落書きで上書きしてあるか
        var edited: Bool? = nil
    }

    struct Reaction: Codable {
        let name: String
        let photo: String
        let kind: String
        let text: String
        let creator: String?
        let createdAt: Date
    }

    struct State: Codable {
        var token: Data?
        var photos: [String: Photo] = [:]
        var reactions: [String: Reaction] = [:]

        var changeToken: CKServerChangeToken? {
            get {
                token.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
            }
            set {
                token = newValue.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            }
        }
    }

    /// アルバムの一覧（起動してすぐ出すため）
    struct Album: Codable {
        let zoneName: String
        let ownerName: String
        let isOwner: Bool
        let title: String
    }

    let folder: URL

    init(albumID: String) {
        let safe = albumID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        folder = Self.root.appendingPathComponent(String(safe), isDirectory: true)
    }

    static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlbumCache", isDirectory: true)
    }

    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    func load() -> State {
        guard let data = try? Data(contentsOf: indexURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    func save(_ state: State) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    /// 控えを全部消す（読んだ位置が古すぎて使えないときなど）
    func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: 画像

    func thumbnailURL(_ name: String) -> URL {
        folder.appendingPathComponent("thumbs", isDirectory: true).appendingPathComponent(name + ".jpg")
    }

    func fullURL(_ name: String) -> URL {
        folder.appendingPathComponent("full", isDirectory: true).appendingPathComponent(name + ".jpg")
    }

    func thumbnail(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: thumbnailURL(name).path)
    }

    func fullImage(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: fullURL(name).path)
    }

    func store(_ image: UIImage, at url: URL, quality: CGFloat) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = image.jpegData(compressionQuality: quality) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func removeImages(_ name: String) {
        try? FileManager.default.removeItem(at: thumbnailURL(name))
        try? FileManager.default.removeItem(at: fullURL(name))
    }

    // MARK: アルバムの一覧

    static func loadAlbums() -> [Album] {
        guard let data = UserDefaults.standard.data(forKey: "albumListCache"),
              let list = try? JSONDecoder().decode([Album].self, from: data) else { return [] }
        return list
    }

    static func saveAlbums(_ list: [Album]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "albumListCache")
        }
    }
}
