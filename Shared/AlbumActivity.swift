import CloudKit
import Foundation
import UserNotifications

/// 共有アルバムの新しい動き（友だちのコメント・写真・いいね）を iCloud から読んで、通知の文にする。
/// アプリ本体と、通知を書き換える拡張（FilmCameraNotify）の両方で使う。
/// どこまで読んだか（CKServerChangeToken）は App Group に置いて、両方で同じ位置を使う（同じ通知を 2 回出さない）。
/// 初めて見るアルバムは位置を覚えるだけで、昔のコメントはまとめて通知しない
enum AlbumActivity {
    struct Event {
        let title: String
        let body: String
        let album: String
        /// 通知に添える写真（一覧用の小さい画像を一時ファイルに写したもの）
        var imageURL: URL? = nil
    }

    static let photoType = "AlbumPhoto"
    static let reactionType = "AlbumReaction"
    static let ownZoneName = "SharedAlbum"
    static let albumZonePrefix = "Album-"

    /// アプリの Bundle ID（拡張から呼ばれたときは .widget / .notify を外す）
    static var appBundleID: String {
        var id = Bundle.main.bundleIdentifier ?? ""
        for suffix in [".widget", ".notify"] where id.hasSuffix(suffix) {
            id.removeLast(suffix.count)
        }
        return id
    }

    /// アプリの iCloud コンテナ（拡張の CKContainer.default() は拡張の名前になってしまうので、名前で指定する）
    static var container: CKContainer {
        CKContainer(identifier: "iCloud." + appBundleID)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group." + appBundleID) ?? .standard
    }

    // MARK: - 読む

    /// 前回からの変更を読み、友だちの動きを返す（notify が false なら位置を進めるだけ）
    static func fetch(notify: Bool) async -> [Event] {
        let container = Self.container
        let me = await myRecordName(container)
        var events: [Event] = []
        for (db, scope) in [(container.privateCloudDatabase, "private"), (container.sharedCloudDatabase, "shared")] {
            events += await changes(in: db, scope: scope, me: me, notify: notify)
        }
        return notify ? events : []
    }

    private static func changes(in db: CKDatabase, scope: String, me: String?, notify: Bool) async -> [Event] {
        let dbKey = "notifier-db-" + scope
        var token = loadToken(dbKey)
        var zones: [CKRecordZone.ID] = []
        do {
            var more = true
            while more {
                let result = try await db.databaseChanges(since: token)
                zones += result.modifications.map(\.zoneID)
                token = result.changeToken
                more = result.moreComing
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            saveToken(nil, dbKey)
            return []
        } catch {
            return []
        }
        var events: [Event] = []
        for zone in Set(zones) where scope == "shared" || zone.zoneName == ownZoneName
            || zone.zoneName.hasPrefix(albumZonePrefix) {
            events += await zoneChanges(db, zone: zone, scope: scope, me: me, notify: notify)
        }
        saveToken(token, dbKey)
        return events
    }

    private static func zoneChanges(_ db: CKDatabase, zone: CKRecordZone.ID, scope: String, me: String?,
                                    notify: Bool) async -> [Event] {
        let key = "notifier-zone-\(scope)-\(zone.ownerName)-\(zone.zoneName)"
        let start = loadToken(key)
        let shouldNotify = notify && start != nil
        var token = start
        var reactions: [CKRecord] = []
        var photos: [CKRecord] = []
        var doodled: [CKRecord] = []
        do {
            var more = true
            while more {
                let result = try await db.recordZoneChanges(inZoneWith: zone, since: token,
                                                            desiredKeys: ["photo", "kind", "text", "edited"])
                for (_, outcome) in result.modificationResultsByID {
                    guard case .success(let modification) = outcome else { continue }
                    let record = modification.record
                    if record.recordType == reactionType {
                        reactions.append(record)
                    } else if record.recordType == photoType {
                        if isNew(record) {
                            photos.append(record)
                        } else if (record["edited"] as? Int64 ?? 0) != 0 {
                            doodled.append(record)
                        }
                    }
                }
                token = result.changeToken
                more = result.moreComing
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            saveToken(nil, key)
            return []
        } catch {
            return []
        }
        saveToken(token, key)
        guard shouldNotify else { return [] }

        func isMine(_ creator: String?) -> Bool {
            guard let creator else { return false }
            return creator == CKCurrentUserDefaultName || creator == me
        }
        let freshReactions = reactions.filter { !isMine($0.creatorUserRecordID?.recordName) }
        let freshPhotos = photos.filter { !isMine($0.creatorUserRecordID?.recordName) }
        let freshDoodles = doodled.filter { !isMine($0.lastModifiedUserRecordID?.recordName) }
        guard !freshReactions.isEmpty || !freshPhotos.isEmpty || !freshDoodles.isEmpty else { return [] }

        // 名前とアルバムの題名は、アルバムの共有（招待）から読む
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        let share = try? await db.record(for: shareID) as? CKShare
        let names = memberNames(of: share)
        let albumTitle = (share?[CKShare.SystemFieldKey.title] as? String) ?? "共有アルバム"
        func name(_ id: CKRecord.ID?) -> String {
            id.flatMap { names[$0.recordName] } ?? "メンバー"
        }

        // 反応が付いた写真を、小さい画像と入れた人つきでまとめて読む
        let photoNames = Set(freshReactions.compactMap { $0["photo"] as? String })
        let photoIDs = photoNames.map { CKRecord.ID(recordName: $0, zoneID: zone) }
        var target: [String: CKRecord] = [:]
        if !photoIDs.isEmpty, let results = try? await db.records(for: photoIDs, desiredKeys: ["thumbnail"]) {
            for (id, result) in results {
                if case .success(let record) = result { target[id.recordName] = record }
            }
        }
        /// 「あなたの写真」「〇〇さんの写真」
        func whose(_ photo: CKRecord?) -> String {
            guard let photo else { return "写真" }
            if isMine(photo.creatorUserRecordID?.recordName) { return "あなたの写真" }
            return "\(name(photo.creatorUserRecordID))さんの写真"
        }

        var events: [Event] = []
        for record in freshReactions.sorted(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }) {
            let who = name(record.creatorUserRecordID)
            let kind = record["kind"] as? String ?? ""
            let text = record["text"] as? String ?? ""
            let photo = (record["photo"] as? String).flatMap { target[$0] }
            let mine = isMine(photo?.creatorUserRecordID?.recordName)
            switch kind {
            case "comment":
                events.append(Event(title: "💬 \(who)さんが\(whose(photo))にコメント",
                                    body: "「\(text)」", album: albumTitle, imageURL: thumbnailFile(photo)))
            case "like" where mine:
                events.append(Event(title: "❤️ \(who)さんがあなたの写真にいいね",
                                    body: "タップして写真を見る", album: albumTitle, imageURL: thumbnailFile(photo)))
            case "emoji" where mine:
                events.append(Event(title: "\(who)さんがあなたの写真に \(text)",
                                    body: "タップして写真を見る", album: albumTitle, imageURL: thumbnailFile(photo)))
            default:
                // ほかの人の写真へのいいね・絵文字は通知しない（多くなりすぎるため）
                continue
            }
        }
        // 写真は人ごとに 1 件にまとめる（最初の 1 枚を添える）
        let byPerson = Dictionary(grouping: freshPhotos, by: { name($0.creatorUserRecordID) })
        for (who, list) in byPerson.sorted(by: { $0.key < $1.key }) {
            let first = list.max(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) })
            events.append(Event(title: "📷 \(who)さんが写真を \(list.count) 枚追加",
                                body: "タップしてアルバムを見る", album: albumTitle,
                                imageURL: await thumbnailFile(of: first?.recordID, in: db)))
        }
        for record in freshDoodles {
            let who = name(record.lastModifiedUserRecordID)
            let thumb = await thumbnailFile(of: record.recordID, in: db)
            let owner: String
            if isMine(record.creatorUserRecordID?.recordName) {
                owner = "あなたの写真"
            } else if record.creatorUserRecordID?.recordName == record.lastModifiedUserRecordID?.recordName {
                owner = "自分の写真"
            } else {
                owner = "\(name(record.creatorUserRecordID))さんの写真"
            }
            events.append(Event(title: "✏️ \(who)さんが\(owner)に落書き",
                                body: "タップして見る", album: albumTitle, imageURL: thumb))
        }
        return events
    }

    /// 写真のレコードの小さい画像を、通知に添えられる一時ファイルに写す
    private static func thumbnailFile(_ photo: CKRecord?) -> URL? {
        guard let source = (photo?["thumbnail"] as? CKAsset)?.fileURL else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        return (try? FileManager.default.copyItem(at: source, to: url)) != nil ? url : nil
    }

    private static func thumbnailFile(of id: CKRecord.ID?, in db: CKDatabase) async -> URL? {
        guard let id, let results = try? await db.records(for: [id], desiredKeys: ["thumbnail"]),
              case .success(let record)? = results[id] else { return nil }
        return thumbnailFile(record)
    }

    /// 自分の recordName（毎回 iCloud に聞くと通知が遅れるので、覚えておく）
    private static func myRecordName(_ container: CKContainer) async -> String? {
        if let saved = defaults.string(forKey: "myRecordName") { return saved }
        guard let name = try? await container.userRecordID().recordName else { return nil }
        defaults.set(name, forKey: "myRecordName")
        return name
    }

    /// 新しく入った写真か（落書きの上書きなど、あとからの書き換えは数えない）
    private static func isNew(_ record: CKRecord) -> Bool {
        guard let created = record.creationDate, let modified = record.modificationDate else { return true }
        return modified.timeIntervalSince(created) < 5
    }

    static func memberNames(of share: CKShare?) -> [String: String] {
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

    // MARK: - 通知の文

    /// 通知の中身にする（others が 1 以上なら「ほか N 件」を添える）
    static func fill(_ content: UNMutableNotificationContent, with event: Event, others: Int = 0) {
        content.title = event.title
        content.subtitle = event.album
        content.body = others > 0 ? "\(event.body)\n（ほか \(others) 件）" : event.body
        content.sound = .default
        content.threadIdentifier = "album"
        content.userInfo["album"] = true
        if let url = event.imageURL,
           let attachment = try? UNNotificationAttachment(identifier: "photo", url: url,
                                                          options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]) {
            content.attachments = [attachment]
        }
    }

    // MARK: - 読んだ位置

    private static func loadToken(_ key: String) -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func saveToken(_ token: CKServerChangeToken?, _ key: String) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
