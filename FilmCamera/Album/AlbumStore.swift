import CloudKit
import ImageIO
import SwiftUI
import UIKit

/// 共有アルバムの 1 枚
struct AlbumPhoto: Identifiable {
    let id: CKRecord.ID
    let takenAt: Date
    let mode: String
    let thumbnail: UIImage?
}

/// 見られるアルバム（自分のアルバム、または招待された友だちのアルバム）
struct AlbumRef: Identifiable, Hashable {
    let zoneID: CKRecordZone.ID
    let isOwner: Bool
    let title: String
    var id: String { zoneID.ownerName + "/" + zoneID.zoneName }
}

/// iCloud（CloudKit）を使った共有アルバム。
/// 自分のアルバムは非公開データベースの専用ゾーン（"SharedAlbum"）に置き、ゾーンごと CKShare で友だちと共有する。
/// 招待を受けた友だちのアルバムは共有データベースに現れる。写真は「AlbumPhoto」レコードとして保存する
/// （フル解像度の image、一覧用の thumbnail、撮影日時 takenAt、モード名 mode）。
/// 一覧は検索（インデックスが要る）ではなく、ゾーンの変更の取得で読む
@MainActor
final class AlbumStore: ObservableObject {
    static let shared = AlbumStore()

    nonisolated static let container = CKContainer.default()
    nonisolated static let recordType = "AlbumPhoto"
    nonisolated static let ownZoneID = CKRecordZone.ID(zoneName: "SharedAlbum", ownerName: CKCurrentUserDefaultName)

    @Published private(set) var albums: [AlbumRef] = []
    @Published var selectedID: String? {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "albumSelected")
            if oldValue != selectedID { Task { await loadPhotos() } }
        }
    }
    @Published private(set) var photos: [AlbumPhoto] = []
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
            var list = [AlbumRef(zoneID: Self.ownZoneID, isOwner: true, title: "自分のアルバム")]
            let shared = Self.container.sharedCloudDatabase
            for (index, zone) in try await shared.allRecordZones().enumerated() {
                let name = await Self.ownerName(of: zone.zoneID, in: shared)
                list.append(AlbumRef(zoneID: zone.zoneID, isOwner: false,
                                     title: name.map { "\($0) のアルバム" } ?? "友だちのアルバム \(index + 1)"))
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
            if album.isOwner { try await Self.ensureOwnZone() }
            var records: [CKRecord] = []
            var token: CKServerChangeToken?
            var more = true
            while more {
                let changes = try await db.recordZoneChanges(inZoneWith: album.zoneID, since: token,
                                                             desiredKeys: ["thumbnail", "takenAt", "mode"])
                for (_, result) in changes.modificationResultsByID {
                    if case .success(let modification) = result,
                       modification.record.recordType == Self.recordType {
                        records.append(modification.record)
                    }
                }
                token = changes.changeToken
                more = changes.moreComing
            }
            photos = records.map(Self.photo(from:)).sorted { $0.takenAt > $1.takenAt }
        } catch {
            photos = []
            status = Self.describe(error)
        }
    }

    /// 1 枚をフル解像度で読む（表示用に長い辺 2400px まで縮める）
    func fullImage(of photo: AlbumPhoto) async -> UIImage? {
        guard let album = selected else { return nil }
        let db = database(for: album)
        guard let results = try? await db.records(for: [photo.id], desiredKeys: ["image"]),
              case .success(let record)? = results[photo.id],
              let asset = record["image"] as? CKAsset, let url = asset.fileURL else { return nil }
        return Self.downsample(url, maxPixel: 2400)
    }

    // MARK: - 追加

    /// 撮った写真を自動で入れる設定なら、選んでいるアルバムに入れる
    func addIfAutomatic(data: Data, type: String, thumbnail: UIImage?, mode: String) {
        guard autoAdd else { return }
        add(data: data, type: type, thumbnail: thumbnail, mode: mode)
    }

    /// 写真を選んでいるアルバムに入れる
    func add(data: Data, type: String, thumbnail: UIImage?, mode: String) {
        Task {
            if albums.isEmpty { await refresh() }
            guard let album = selected else {
                status = status ?? "共有アルバムを準備できませんでした"
                return
            }
            uploading += 1
            defer { uploading -= 1 }
            do {
                if album.isOwner { try await Self.ensureOwnZone() }
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
                    photos.insert(AlbumPhoto(id: saved.recordID, takenAt: Date(), mode: mode, thumbnail: thumbnail),
                                  at: 0)
                }
                status = nil
            } catch {
                status = "共有アルバムに追加できませんでした：" + Self.describe(error)
            }
        }
    }

    // MARK: - 共有

    /// 自分のアルバムの共有（招待のリンク）を用意する。なければ作る。
    /// LINE などにリンクだけ送れるよう「リンクを知っている人は誰でも参加して追加できる」にする
    /// （宛先を指定する方式だと、メールアドレスや電話番号を求められる）
    nonisolated static func prepareShare() async throws -> CKShare {
        try await ensureOwnZone()
        let db = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: ownZoneID)
        if let existing = try? await db.record(for: shareID) as? CKShare {
            guard existing.publicPermission != .readWrite else { return existing }
            existing.publicPermission = .readWrite
            return try await db.save(existing) as? CKShare ?? existing
        }
        let share = CKShare(recordZoneID: ownZoneID)
        share[CKShare.SystemFieldKey.title] = "フィルムカメラの共有アルバム" as NSString
        share.publicPermission = .readWrite
        return try await db.save(share) as? CKShare ?? share
    }

    /// 招待を用意する（うまくいかなければ理由を status に出す）
    func makeShare() async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            share = try await Self.prepareShare()
            status = nil
        } catch {
            status = "招待を作れませんでした：" + Self.describe(error)
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

    nonisolated private static func ensureOwnZone() async throws {
        let db = container.privateCloudDatabase
        if (try? await db.recordZone(for: ownZoneID)) != nil { return }
        _ = try await db.save(CKRecordZone(zoneID: ownZoneID))
    }

    nonisolated private static func ownerName(of zoneID: CKRecordZone.ID, in db: CKDatabase) async -> String? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try? await db.record(for: shareID) as? CKShare,
              let components = share.owner.userIdentity.nameComponents else { return nil }
        let name = PersonNameComponentsFormatter().string(from: components)
        return name.isEmpty ? nil : name
    }

    nonisolated private static func photo(from record: CKRecord) -> AlbumPhoto {
        let thumbnail = (record["thumbnail"] as? CKAsset)?.fileURL.flatMap { downsample($0, maxPixel: 600) }
        return AlbumPhoto(id: record.recordID,
                          takenAt: record["takenAt"] as? Date ?? record.creationDate ?? .distantPast,
                          mode: record["mode"] as? String ?? "",
                          thumbnail: thumbnail)
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
