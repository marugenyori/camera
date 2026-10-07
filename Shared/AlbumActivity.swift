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
        let me = try? await container.userRecordID().recordName
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
        do {
            var more = true
            while more {
                let result = try await db.recordZoneChanges(inZoneWith: zone, since: token,
                                                            desiredKeys: ["photo", "kind", "text"])
                for (_, outcome) in result.modificationResultsByID {
                    guard case .success(let modification) = outcome else { continue }
                    let record = modification.record
                    if record.recordType == reactionType {
                        reactions.append(record)
                    } else if record.recordType == photoType, isNew(record) {
                        photos.append(record)
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
        guard !freshReactions.isEmpty || !freshPhotos.isEmpty else { return [] }

        // 名前とアルバムの題名は、アルバムの共有（招待）から読む
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        let share = try? await db.record(for: shareID) as? CKShare
        let names = memberNames(of: share)
        let albumTitle = (share?[CKShare.SystemFieldKey.title] as? String) ?? "共有アルバム"
        func name(_ record: CKRecord) -> String {
            record.creatorUserRecordID.flatMap { names[$0.recordName] } ?? "メンバー"
        }

        var events: [Event] = []
        for record in freshReactions.sorted(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }) {
            let who = name(record)
            let kind = record["kind"] as? String ?? ""
            let text = record["text"] as? String ?? ""
            switch kind {
            case "comment":
                events.append(Event(title: "\(who)さんがコメントしました", body: text, album: albumTitle))
            case "like", "emoji":
                // いいね・絵文字は、自分の写真に付いたときだけ
                guard let photoName = record["photo"] as? String else { continue }
                let photoID = CKRecord.ID(recordName: photoName, zoneID: zone)
                guard let results = try? await db.records(for: [photoID], desiredKeys: []),
                      case .success(let photo)? = results[photoID],
                      isMine(photo.creatorUserRecordID?.recordName) else { continue }
                events.append(Event(title: kind == "like" ? "\(who)さんがあなたの写真にいいねしました"
                                                          : "\(who)さんが \(text) で反応しました",
                                    body: "写真を見てみましょう", album: albumTitle))
            default:
                continue
            }
        }
        // 写真は人ごとに 1 件にまとめる
        let byPerson = Dictionary(grouping: freshPhotos, by: name)
        for (who, list) in byPerson.sorted(by: { $0.key < $1.key }) {
            events.append(Event(title: "\(who)さんが写真を追加しました",
                                body: list.count == 1 ? "新しい写真が 1 枚あります" : "新しい写真が \(list.count) 枚あります",
                                album: albumTitle))
        }
        return events
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

    /// 1 件の通知にまとめる（2 件目からは「ほか N 件」）
    static func fill(_ content: UNMutableNotificationContent, with events: [Event]) {
        guard let first = events.first else { return }
        content.title = first.title
        content.subtitle = first.album
        content.body = events.count > 1 ? "\(first.body)\n（ほか \(events.count - 1) 件）" : first.body
        content.sound = .default
        content.threadIdentifier = "album"
        content.userInfo["album"] = true
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
