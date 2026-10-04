import CloudKit
import ImageIO
import Photos
import SwiftUI
import UIKit

/// 共有アルバムの 1 枚
struct AlbumPhoto: Identifiable, Equatable {
    let id: CKRecord.ID
    let takenAt: Date
    let mode: String
    let thumbnail: UIImage?
    /// 入れた人（CloudKit が自動で記録する作成者。自分が入れたものは "__defaultOwner__" のこともある）
    let creator: String?

    static func == (a: AlbumPhoto, b: AlbumPhoto) -> Bool { a.id == b.id }
}

/// 写真へのいいね・絵文字・コメント（レコード型 AlbumReaction。写真と同じゾーンに置くので、アルバムのメンバー全員に見える）
struct AlbumReaction: Identifiable, Equatable {
    enum Kind: String { case like, emoji, comment }
    let id: CKRecord.ID
    /// どの写真への反応か（写真のレコード名）
    let photo: String
    let kind: Kind
    /// 絵文字、またはコメントの文
    let text: String
    let creator: String?
    let createdAt: Date

    static func == (a: AlbumReaction, b: AlbumReaction) -> Bool { a.id == b.id }
}

/// 見られるアルバム（自分のアルバム、または招待された友だちのアルバム）
struct AlbumRef: Identifiable, Hashable {
    let zoneID: CKRecordZone.ID
    let isOwner: Bool
    let title: String
    var id: String { zoneID.ownerName + "/" + zoneID.zoneName }
}

/// iCloud（CloudKit）を使った共有アルバム。
/// 自分のアルバムは非公開データベースのゾーン 1 つずつ（最初の 1 つは "SharedAlbum"、追加分は "Album-…"）に置き、
/// ゾーンごと CKShare で共有する。友だちのグループごとにアルバムを分けて、それぞれ別の人を招待できる。
/// 招待を受けた友だちのアルバムは共有データベースに現れる。写真は「AlbumPhoto」レコードとして保存する
/// （フル解像度の image、一覧用の thumbnail、撮影日時 takenAt、モード名 mode）。
/// 一覧は検索（インデックスが要る）ではなく、ゾーンの変更の取得で読む
@MainActor
final class AlbumStore: ObservableObject {
    static let shared = AlbumStore()

    nonisolated static let container = CKContainer.default()
    nonisolated static let recordType = "AlbumPhoto"
    nonisolated static let reactionType = "AlbumReaction"
    nonisolated static let ownZoneID = CKRecordZone.ID(zoneName: "SharedAlbum", ownerName: CKCurrentUserDefaultName)
    /// 追加で作ったアルバムのゾーン名の頭
    nonisolated static let albumZonePrefix = "Album-"
    nonisolated static let defaultShareTitle = "フィルムカメラの共有アルバム"

    /// 自分で作ったアルバムの名前（ゾーン名 → 名前）。招待した後は共有の題名からも読める
    private var albumTitles: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "albumTitles") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "albumTitles") }
    }

    @Published private(set) var albums: [AlbumRef] = []
    @Published var selectedID: String? {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "albumSelected")
            if oldValue != selectedID {
                share = nil
                Task { await loadPhotos() }
            }
        }
    }
    @Published private(set) var photos: [AlbumPhoto] = []
    /// アルバムごとの表紙（いちばん新しい写真）と枚数。切り替えのカードに出す
    @Published private(set) var covers: [String: UIImage] = [:]
    @Published private(set) var counts: [String: Int] = [:]
    /// 選んでいるアルバムのメンバー（ユーザーの recordName → 名前）。写真を入れた人の表示に使う
    @Published private(set) var members: [String: String] = [:]
    /// 写真ごとの反応（写真のレコード名 → いいね・絵文字・コメント、古い順）
    @Published private(set) var reactions: [String: [AlbumReaction]] = [:]
    /// 撮影画面で使いたいモード（写真の「このフィルタで撮る」）。カメラの画面が受け取って切り替える
    @Published var requestedMode: String?
    /// 自分の recordName（自分が入れた写真を見分ける）
    private var myRecordName: String?
    /// 大きく見た写真をしばらく取っておく
    private var fullCache: [CKRecord.ID: UIImage] = [:]
    private var fullOrder: [CKRecord.ID] = []
    @Published private(set) var isLoading = false
    @Published private(set) var uploading = 0
    /// うまくいかなかったときの説明（iCloud に未サインインなど）
    @Published var status: String?
    /// 撮った写真を自動で共有アルバムにも入れるか
    @Published var autoAdd: Bool {
        didSet { UserDefaults.standard.set(autoAdd, forKey: "albumAutoAdd") }
    }
    /// 用意できた招待（自分のアルバムの共有）。これがあると「招待を送る」が出る
    @Published private(set) var share: CKShare?
    @Published private(set) var isPreparingShare = false
    /// このアルバムに参加している友だちの名前（作った人は除く）
    var participantNames: [String] {
        guard let share else { return [] }
        return share.participants
            .filter { $0.role != .owner && $0.acceptanceStatus == .accepted }
            .map { participant in
                participant.userIdentity.nameComponents
                    .map { PersonNameComponentsFormatter().string(from: $0) }
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "名前なしの参加者"
            }
    }

    /// 招待を受け取ったときなどに、アルバムの画面を開く
    @Published var showAlbum = false

    var selected: AlbumRef? { albums.first { $0.id == selectedID } ?? albums.first }

    private init() {
        autoAdd = UserDefaults.standard.bool(forKey: "albumAutoAdd")
        selectedID = UserDefaults.standard.string(forKey: "albumSelected")
    }

    private func database(for album: AlbumRef) -> CKDatabase {
        album.isOwner ? Self.container.privateCloudDatabase : Self.container.sharedCloudDatabase
    }

    // MARK: - 読み込み

    /// アルバムの一覧と、選んでいるアルバムの写真を読み直す
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard try await Self.container.accountStatus() == .available else {
                status = "iCloud にサインインすると使えます（設定 → 自分の名前 → iCloud）"
                return
            }
            // 自分のアルバム（最初の 1 つは必ず用意する）
            try await Self.ensureZone(Self.ownZoneID)
            let privateDB = Self.container.privateCloudDatabase
            let titles = albumTitles
            var own: [AlbumRef] = []
            for zone in try await privateDB.allRecordZones() {
                let name = zone.zoneID.zoneName
                guard name == Self.ownZoneID.zoneName || name.hasPrefix(Self.albumZonePrefix) else { continue }
                let info = await Self.shareInfo(of: zone.zoneID, in: privateDB)
                let title = titles[name] ?? info.title
                    ?? (name == Self.ownZoneID.zoneName ? "自分のアルバム" : "アルバム")
                own.append(AlbumRef(zoneID: zone.zoneID, isOwner: true, title: title))
            }
            own.sort { a, b in
                if a.zoneID.zoneName == Self.ownZoneID.zoneName { return true }
                if b.zoneID.zoneName == Self.ownZoneID.zoneName { return false }
                return a.title < b.title
            }
            // 友だちのアルバム（招待を受けたもの）
            var list = own
            let shared = Self.container.sharedCloudDatabase
            for (index, zone) in try await shared.allRecordZones().enumerated() {
                let info = await Self.shareInfo(of: zone.zoneID, in: shared)
                let title = info.title ?? "友だちのアルバム \(index + 1)"
                list.append(AlbumRef(zoneID: zone.zoneID, isOwner: false,
                                     title: info.owner.map { "\(title)（\($0)）" } ?? title))
            }
            albums = list
            status = nil
            await loadPhotos()
        } catch {
            status = Self.describe(error)
        }
    }

    /// 選んでいるアルバムの写真を読む（一覧用の小さい画像だけ受け取る）
    func loadPhotos() async {
        guard let album = selected else { return }
        let db = database(for: album)
        do {
            if album.isOwner { try await Self.ensureZone(album.zoneID) }
            if myRecordName == nil { myRecordName = try? await Self.container.userRecordID().recordName }
            // 招待があれば読んでおく（参加した人を表示し、すぐ招待を送れるように。写真を入れた人の名前にも使う）
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: album.zoneID)
            let existing = try? await db.record(for: shareID) as? CKShare
            if album.id == selected?.id {
                if album.isOwner { share = existing }
                members = Self.memberNames(of: existing)
            }
            var records: [CKRecord] = []
            var reactionRecords: [CKRecord] = []
            var token: CKServerChangeToken?
            var more = true
            while more {
                let changes = try await db.recordZoneChanges(inZoneWith: album.zoneID, since: token,
                                                             desiredKeys: ["thumbnail", "takenAt", "mode",
                                                                           "photo", "kind", "text", "createdAt"])
                for (_, result) in changes.modificationResultsByID {
                    guard case .success(let modification) = result else { continue }
                    switch modification.record.recordType {
                    case Self.recordType: records.append(modification.record)
                    case Self.reactionType: reactionRecords.append(modification.record)
                    default: break
                    }
                }
                token = changes.changeToken
                more = changes.moreComing
            }
            let loaded = records.map(Self.photo(from:)).sorted { $0.takenAt > $1.takenAt }
            counts[album.id] = loaded.count
            covers[album.id] = loaded.first?.thumbnail
            if album.id == selected?.id {
                photos = loaded
                reactions = Dictionary(grouping: reactionRecords.compactMap(Self.reaction(from:)), by: \.photo)
                    .mapValues { $0.sorted { $0.createdAt < $1.createdAt } }
            }
        } catch {
            photos = []
            status = Self.describe(error)
        }
    }

    /// 1 枚をフル解像度で読む（表示用に長い辺 2400px まで縮める）
    func fullImage(of photo: AlbumPhoto) async -> UIImage? {
        if let cached = fullCache[photo.id] { return cached }
        guard let url = await fullFile(of: photo), let image = Self.downsample(url, maxPixel: 2400) else { return nil }
        fullCache[photo.id] = image
        fullOrder.append(photo.id)
        if fullOrder.count > 12 { fullCache[fullOrder.removeFirst()] = nil }
        return image
    }

    /// 1 枚の元のファイル（CloudKit が一時的に置いた場所）
    private func fullFile(of photo: AlbumPhoto) async -> URL? {
        guard let album = selected else { return nil }
        guard let results = try? await database(for: album).records(for: [photo.id], desiredKeys: ["image"]),
              case .success(let record)? = results[photo.id],
              let asset = record["image"] as? CKAsset else { return nil }
        return asset.fileURL
    }

    // MARK: - 入れた人

    /// 写真を入れた人の名前（自分なら「自分」）
    func creatorName(of photo: AlbumPhoto) -> String {
        guard let creator = photo.creator else { return "だれか" }
        if isMine(photo) { return "自分" }
        return members[creator] ?? "メンバー"
    }

    func isMine(_ photo: AlbumPhoto) -> Bool { isMine(photo.creator) }

    func isMine(_ creator: String?) -> Bool {
        guard let creator else { return false }
        return creator == CKCurrentUserDefaultName || creator == myRecordName
    }

    /// 反応した人の名前（自分なら「自分」）
    func name(of creator: String?) -> String {
        guard let creator else { return "だれか" }
        if isMine(creator) { return "自分" }
        return members[creator] ?? "メンバー"
    }

    /// 消せる写真か（自分が入れたもの。自分のアルバムなら全部）
    func canDelete(_ photo: AlbumPhoto) -> Bool {
        selected?.isOwner == true || isMine(photo)
    }

    nonisolated private static func memberNames(of share: CKShare?) -> [String: String] {
        guard let share else { return [:] }
        var names: [String: String] = [:]
        for participant in share.participants {
            guard let id = participant.userIdentity.userRecordID?.recordName else { continue }
            let name = participant.userIdentity.nameComponents
                .map { PersonNameComponentsFormatter().string(from: $0) }
                .flatMap { $0.isEmpty ? nil : $0 }
            names[id] = name ?? (participant.role == .owner ? "アルバムの持ち主" : "名前なしの参加者")
        }
        return names
    }

    // MARK: - いいね・絵文字・コメント

    func likes(of photo: AlbumPhoto) -> [AlbumReaction] {
        (reactions[photo.id.recordName] ?? []).filter { $0.kind == .like }
    }

    func comments(of photo: AlbumPhoto) -> [AlbumReaction] {
        (reactions[photo.id.recordName] ?? []).filter { $0.kind == .comment }
    }

    /// 絵文字ごとの反応（よく使われた順）
    func emojis(of photo: AlbumPhoto) -> [(emoji: String, people: [AlbumReaction])] {
        let list = (reactions[photo.id.recordName] ?? []).filter { $0.kind == .emoji }
        return Dictionary(grouping: list, by: \.text)
            .map { (emoji: $0.key, people: $0.value) }
            .sorted { $0.people.count > $1.people.count || ($0.people.count == $1.people.count && $0.emoji < $1.emoji) }
    }

    func hasLiked(_ photo: AlbumPhoto) -> Bool { likes(of: photo).contains { isMine($0.creator) } }

    func hasReacted(_ photo: AlbumPhoto, with emoji: String) -> Bool {
        emojis(of: photo).first { $0.emoji == emoji }?.people.contains { isMine($0.creator) } ?? false
    }

    /// いいねを付ける・外す
    func toggleLike(_ photo: AlbumPhoto) async {
        if let mine = likes(of: photo).first(where: { isMine($0.creator) }) {
            await removeReaction(mine)
        } else {
            await addReaction(to: photo, kind: .like, text: "", key: "like")
        }
    }

    /// 絵文字の反応を付ける・外す
    func toggleEmoji(_ emoji: String, on photo: AlbumPhoto) async {
        let mine = (reactions[photo.id.recordName] ?? [])
            .first { $0.kind == .emoji && $0.text == emoji && isMine($0.creator) }
        if let mine {
            await removeReaction(mine)
        } else {
            let code = emoji.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
            await addReaction(to: photo, kind: .emoji, text: emoji, key: "emoji-" + code)
        }
    }

    func comment(on photo: AlbumPhoto, text: String) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        await addReaction(to: photo, kind: .comment, text: String(body.prefix(500)), key: nil)
    }

    /// 反応を保存する。いいねと絵文字は「写真＋人＋種類」で 1 つだけになるよう、決まった名前のレコードにする
    private func addReaction(to photo: AlbumPhoto, kind: AlbumReaction.Kind, text: String, key: String?) async {
        guard let album = selected else { return }
        let me = myRecordName ?? CKCurrentUserDefaultName
        let name = key.map { "\($0)-\(photo.id.recordName)-\(me)" } ?? UUID().uuidString
        let recordID = CKRecord.ID(recordName: name, zoneID: album.zoneID)
        let record = CKRecord(recordType: Self.reactionType, recordID: recordID)
        record["photo"] = photo.id.recordName as NSString
        record["kind"] = kind.rawValue as NSString
        record["text"] = text as NSString
        record["createdAt"] = Date() as NSDate
        // 先に画面に出しておく（失敗したら戻す）
        let pending = AlbumReaction(id: recordID, photo: photo.id.recordName, kind: kind, text: text,
                                    creator: CKCurrentUserDefaultName, createdAt: Date())
        reactions[photo.id.recordName, default: []].append(pending)
        do {
            _ = try await database(for: album).modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            status = nil
        } catch {
            reactions[photo.id.recordName]?.removeAll { $0.id == recordID }
            status = (kind == .comment ? "コメントできませんでした：" : "反応できませんでした：") + Self.describe(error)
        }
    }

    func removeReaction(_ reaction: AlbumReaction) async {
        guard let album = selected else { return }
        let backup = reactions[reaction.photo]
        reactions[reaction.photo]?.removeAll { $0.id == reaction.id }
        do {
            _ = try await database(for: album).deleteRecord(withID: reaction.id)
        } catch let error as CKError where error.code == .unknownItem {
            // もう消えている
        } catch {
            reactions[reaction.photo] = backup
            status = "取り消せませんでした：" + Self.describe(error)
        }
    }

    /// 消せる反応か（自分のもの。自分のアルバムなら全部）
    func canDelete(_ reaction: AlbumReaction) -> Bool {
        selected?.isOwner == true || isMine(reaction.creator)
    }

    nonisolated private static func reaction(from record: CKRecord) -> AlbumReaction? {
        guard let photo = record["photo"] as? String,
              let kind = (record["kind"] as? String).flatMap(AlbumReaction.Kind.init(rawValue:)) else { return nil }
        return AlbumReaction(id: record.recordID, photo: photo, kind: kind,
                             text: record["text"] as? String ?? "",
                             creator: record.creatorUserRecordID?.recordName,
                             createdAt: record["createdAt"] as? Date ?? record.creationDate ?? .distantPast)
    }

    // MARK: - ほかのアルバムへ

    /// 写真を元の画質のまま、ほかのアルバムにも入れる
    func copy(_ photo: AlbumPhoto, to target: AlbumRef) async -> Bool {
        guard let url = await fullFile(of: photo), let data = try? Data(contentsOf: url) else { return false }
        let type = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceGetType($0) as String? } ?? "public.jpeg"
        add(data: data, type: type, thumbnail: photo.thumbnail, mode: photo.mode, to: target)
        return true
    }

    // MARK: - 消す・保存する

    /// 写真を消す（消せないものは飛ばす）
    func delete(_ targets: [AlbumPhoto]) async {
        guard let album = selected else { return }
        let ids = targets.filter { canDelete($0) }.map(\.id)
        guard !ids.isEmpty else { return }
        // 写真についた反応も消す（自分のアルバムなら全部、そうでなければ自分の分）
        let reactionIDs = ids.flatMap { id in
            (reactions[id.recordName] ?? []).filter { album.isOwner || isMine($0.creator) }.map(\.id)
        }
        do {
            let result = try await database(for: album).modifyRecords(saving: [], deleting: ids + reactionIDs)
            var deleted: Set<CKRecord.ID> = []
            for (id, outcome) in result.deleteResults {
                if case .success = outcome { deleted.insert(id) }
            }
            photos.removeAll { deleted.contains($0.id) }
            for id in ids where deleted.contains(id) { reactions[id.recordName] = nil }
            counts[album.id] = photos.count
            covers[album.id] = photos.first?.thumbnail
            status = deleted.isSuperset(of: ids) ? nil : "消せなかった写真があります"
        } catch {
            status = "消せませんでした：" + Self.describe(error)
        }
    }

    /// 写真を元の画質で写真アプリに保存する。保存できた枚数を返す
    func saveToLibrary(_ targets: [AlbumPhoto]) async -> Int {
        let allowed = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard allowed == .authorized || allowed == .limited else {
            status = "写真への保存が許可されていません（設定 → フィルムカメラ → 写真）"
            return 0
        }
        var saved = 0
        for photo in targets {
            guard let url = await fullFile(of: photo), let data = try? Data(contentsOf: url) else { continue }
            let ok = (try? await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }) != nil
            if ok { saved += 1 }
        }
        return saved
    }

    /// 写真アプリから選んだ写真をアルバムに入れる
    func importPhotos(_ files: [Data]) {
        for data in files {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            let type = CGImageSourceGetType(source) as String? ?? "public.jpeg"
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
            ]
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
            add(data: data, type: type, thumbnail: thumbnail, mode: "写真から")
        }
    }

    // MARK: - 追加

    /// 撮った写真を自動で入れる設定なら、選んでいるアルバムに入れる
    func addIfAutomatic(data: Data, type: String, thumbnail: UIImage?, mode: String) {
        guard autoAdd else { return }
        add(data: data, type: type, thumbnail: thumbnail, mode: mode)
    }

    /// 写真をアルバムに入れる（target を省くと、選んでいるアルバム）
    func add(data: Data, type: String, thumbnail: UIImage?, mode: String, to target: AlbumRef? = nil) {
        Task {
            if albums.isEmpty { await refresh() }
            guard let album = target ?? selected else {
                status = status ?? "共有アルバムを準備できませんでした"
                return
            }
            uploading += 1
            defer { uploading -= 1 }
            do {
                if album.isOwner { try await Self.ensureZone(album.zoneID) }
                let folder = FileManager.default.temporaryDirectory
                let ext = type == "public.heic" ? "heic" : "jpg"
                let imageURL = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                try data.write(to: imageURL)
                defer { try? FileManager.default.removeItem(at: imageURL) }

                let record = CKRecord(recordType: Self.recordType,
                                      recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: album.zoneID))
                record["image"] = CKAsset(fileURL: imageURL)
                record["takenAt"] = Date() as NSDate
                record["mode"] = mode as NSString
                var thumbURL: URL?
                if let jpeg = thumbnail.flatMap(Self.thumbnailJPEG(_:)) {
                    let url = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                    try jpeg.write(to: url)
                    record["thumbnail"] = CKAsset(fileURL: url)
                    thumbURL = url
                }
                defer { if let thumbURL { try? FileManager.default.removeItem(at: thumbURL) } }

                let saved = try await database(for: album).save(record)
                if album.id == selected?.id {
                    photos.insert(AlbumPhoto(id: saved.recordID, takenAt: Date(), mode: mode, thumbnail: thumbnail,
                                             creator: CKCurrentUserDefaultName), at: 0)
                }
                counts[album.id, default: 0] += 1
                if let thumbnail { covers[album.id] = thumbnail }
                status = nil
            } catch {
                status = "共有アルバムに追加できませんでした：" + Self.describe(error)
            }
        }
    }

    // MARK: - 共有

    /// 自分のアルバムの共有（招待のリンク）を用意する。なければ作る。
    /// LINE などにリンクだけ送れるよう「リンクを知っている人は誰でも参加して追加できる」にする
    /// （宛先を指定する方式だと、メールアドレスや電話番号を求められる）。題名はアルバムの名前にする
    nonisolated static func prepareShare(zoneID: CKRecordZone.ID, title: String) async throws -> CKShare {
        try await ensureZone(zoneID)
        let db = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await db.record(for: shareID) as? CKShare {
            let currentTitle = existing[CKShare.SystemFieldKey.title] as? String
            guard existing.publicPermission != .readWrite || currentTitle != title else { return existing }
            existing.publicPermission = .readWrite
            existing[CKShare.SystemFieldKey.title] = title as NSString
            return try await db.save(existing) as? CKShare ?? existing
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title as NSString
        share.publicPermission = .readWrite
        return try await db.save(share) as? CKShare ?? share
    }

    /// 選んでいるアルバムの招待を用意する（うまくいかなければ理由を status に出す）
    func makeShare() async {
        guard let album = selected, album.isOwner else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let title = album.zoneID.zoneName == Self.ownZoneID.zoneName && album.title == "自分のアルバム"
                ? Self.defaultShareTitle : album.title
            share = try await Self.prepareShare(zoneID: album.zoneID, title: title)
            status = nil
        } catch {
            status = "招待を作れませんでした：" + Self.describe(error)
        }
    }

    // MARK: - アルバムを作る・消す

    /// 自分のアルバムの名前を変える（招待を作ってあれば、その題名も変える）
    func renameSelectedAlbum(to name: String) async {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let album = selected, album.isOwner, !title.isEmpty else { return }
        var titles = albumTitles
        titles[album.zoneID.zoneName] = title
        albumTitles = titles
        if share != nil {
            share = try? await Self.prepareShare(zoneID: album.zoneID, title: title)
        }
        await refresh()
    }

    /// 友だちのグループ用に、新しいアルバムを作って選ぶ
    func createAlbum(named name: String) async {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let zoneID = CKRecordZone.ID(zoneName: Self.albumZonePrefix + UUID().uuidString,
                                     ownerName: CKCurrentUserDefaultName)
        do {
            try await Self.ensureZone(zoneID)
            var titles = albumTitles
            titles[zoneID.zoneName] = title
            albumTitles = titles
            await refresh()
            if let album = albums.first(where: { $0.zoneID == zoneID }) { selectedID = album.id }
        } catch {
            status = "アルバムを作れませんでした：" + Self.describe(error)
        }
    }

    /// 選んでいるアルバムを消す（自分のアルバムなら写真ごと消え、招待した人も見られなくなる。
    /// 友だちのアルバムなら、そのアルバムから抜ける）。最初の「自分のアルバム」は消さない
    func removeSelectedAlbum() async {
        guard let album = selected, album.zoneID.zoneName != Self.ownZoneID.zoneName || !album.isOwner else { return }
        do {
            _ = try await database(for: album).deleteRecordZone(withID: album.zoneID)
            if album.isOwner {
                var titles = albumTitles
                titles[album.zoneID.zoneName] = nil
                albumTitles = titles
            }
            selectedID = nil
            await refresh()
        } catch {
            status = (album.isOwner ? "アルバムを消せませんでした：" : "アルバムから抜けられませんでした：")
                + Self.describe(error)
        }
    }

    /// 友だちからの招待を受ける（招待のリンクを開いたとき）
    func accept(_ metadata: CKShare.Metadata) {
        showAlbum = true
        Task {
            do {
                let container = CKContainer(identifier: metadata.containerIdentifier)
                _ = try await container.accept(metadata)
                let zoneID = metadata.share.recordID.zoneID
                await refresh()
                if let album = albums.first(where: { $0.zoneID == zoneID }) {
                    selectedID = album.id
                }
            } catch {
                status = "招待を受けられませんでした：" + Self.describe(error)
            }
        }
    }

    // MARK: - 下ごしらえ

    nonisolated private static func ensureZone(_ zoneID: CKRecordZone.ID) async throws {
        let db = container.privateCloudDatabase
        if (try? await db.recordZone(for: zoneID)) != nil { return }
        _ = try await db.save(CKRecordZone(zoneID: zoneID))
    }

    /// アルバムの共有の題名と、作った人の名前（共有していなければどちらも nil）
    nonisolated private static func shareInfo(of zoneID: CKRecordZone.ID,
                                              in db: CKDatabase) async -> (title: String?, owner: String?) {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try? await db.record(for: shareID) as? CKShare else { return (nil, nil) }
        var title = share[CKShare.SystemFieldKey.title] as? String
        if title == defaultShareTitle || title?.isEmpty == true { title = nil }
        let owner = share.owner.userIdentity.nameComponents
            .map { PersonNameComponentsFormatter().string(from: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }
        return (title, owner)
    }

    nonisolated private static func photo(from record: CKRecord) -> AlbumPhoto {
        let thumbnail = (record["thumbnail"] as? CKAsset)?.fileURL.flatMap { downsample($0, maxPixel: 600) }
        return AlbumPhoto(id: record.recordID,
                          takenAt: record["takenAt"] as? Date ?? record.creationDate ?? .distantPast,
                          mode: record["mode"] as? String ?? "",
                          thumbnail: thumbnail,
                          creator: record.creatorUserRecordID?.recordName)
    }

    nonisolated private static func thumbnailJPEG(_ image: UIImage) -> Data? {
        let long = max(image.size.width, image.size.height)
        let scale = min(1, 800 / max(long, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let small = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.8)
    }

    nonisolated static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    nonisolated private static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        // まとめて送ったうちの一部が失敗したときは、中身のエラーで説明する
        if ck.code == .partialFailure, let inner = ck.partialErrorsByItemID?.values.first {
            return describe(inner)
        }
        switch ck.code {
        case .notAuthenticated: return "iCloud にサインインしてください"
        case .networkUnavailable, .networkFailure: return "ネットにつながっていません"
        case .quotaExceeded: return "iCloud の空き容量が足りません"
        case .permissionFailure: return "このアルバムに追加する権限がありません"
        case .badContainer, .missingEntitlement: return "iCloud の設定が済んでいません（Apple Developer で iCloud コンテナの設定が必要）"
        case .serverRejectedRequest, .invalidArguments:
            return "iCloud の準備が済んでいません（CloudKit Console でスキーマの読み込みと公開が必要・コード \(ck.code.rawValue)）"
        default: return "\(ck.localizedDescription)（コード \(ck.code.rawValue)）"
        }
    }
}
