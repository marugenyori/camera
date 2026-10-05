import CloudKit
import UIKit
import UserNotifications

/// 共有アルバムに友だちがコメントしたら通知する。
/// iCloud の「変更があったら知らせる」（CKDatabaseSubscription、自分のアルバム＝非公開 DB、友だちのアルバム＝共有 DB）から
/// 音の出ないプッシュでアプリを起こし、前回からの変更を読んで、友だちのコメント（と自分の写真へのいいね・絵文字）を
/// ローカル通知で出す。どこまで読んだかは CKServerChangeToken で覚える（最初の 1 回は読むだけで通知しない）
final class AlbumNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlbumNotifier()

    private let container = AlbumStore.container
    private let defaults = UserDefaults.standard
    private var running = false

    // MARK: - 準備

    /// アプリの起動時：許可済みならプッシュの登録と、iCloud の見張りの登録をしておく
    func start() {
        UNUserNotificationCenter.current().delegate = self
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            await register()
        }
    }

    /// アルバムを開いたとき：まだなら通知の許可をたずねる
    func requestPermission() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let now = await center.notificationSettings()
            guard now.authorizationStatus == .authorized || now.authorizationStatus == .provisional else { return }
            await register()
        }
    }

    private func register() async {
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        // 見張りの登録（一度だけ）
        for (db, id) in [(container.privateCloudDatabase, "album-private"), (container.sharedCloudDatabase, "album-shared")]
        where !defaults.bool(forKey: "subscribed-" + id) {
            let subscription = CKDatabaseSubscription(subscriptionID: id)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            if (try? await db.save(subscription)) != nil {
                defaults.set(true, forKey: "subscribed-" + id)
            }
        }
        // 今の位置を覚える（通知はしない）
        await catchUp(notify: false)
    }

    // MARK: - 変更を読む

    /// 前回からの変更を読み、友だちの反応があれば通知する
    func catchUp(notify: Bool) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let me = try? await container.userRecordID().recordName
        var events: [Event] = []
        for (db, scope) in [(container.privateCloudDatabase, "private"), (container.sharedCloudDatabase, "shared")] {
            events += await changes(in: db, scope: scope, me: me, notify: notify)
        }
        guard notify, !events.isEmpty else { return }
        await post(events)
    }

    private struct Event {
        let title: String
        let body: String
        let album: String
    }

    private func changes(in db: CKDatabase, scope: String, me: String?, notify: Bool) async -> [Event] {
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
        for zone in Set(zones) where scope == "shared" || zone.zoneName == AlbumStore.ownZoneID.zoneName
            || zone.zoneName.hasPrefix(AlbumStore.albumZonePrefix) {
            events += await zoneChanges(db, zone: zone, scope: scope, me: me, notify: notify)
        }
        saveToken(token, dbKey)
        return events
    }

    private func zoneChanges(_ db: CKDatabase, zone: CKRecordZone.ID, scope: String, me: String?,
                             notify: Bool) async -> [Event] {
        let key = "notifier-zone-\(scope)-\(zone.ownerName)-\(zone.zoneName)"
        let start = loadToken(key)
        // 初めて見るアルバムは、位置を覚えるだけ（昔のコメントをまとめて通知しない）
        let shouldNotify = notify && start != nil
        var token = start
        var reactions: [CKRecord] = []
        do {
            var more = true
            while more {
                let result = try await db.recordZoneChanges(inZoneWith: zone, since: token,
                                                            desiredKeys: ["photo", "kind", "text"])
                for (_, outcome) in result.modificationResultsByID {
                    if case .success(let modification) = outcome,
                       modification.record.recordType == AlbumStore.reactionType {
                        reactions.append(modification.record)
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
        let fresh = reactions.filter { !isMine($0.creatorUserRecordID?.recordName) }
        guard !fresh.isEmpty else { return [] }

        // 名前とアルバムの題名は、アルバムの共有（招待）から読む
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        let share = try? await db.record(for: shareID) as? CKShare
        let names = AlbumStore.memberNames(of: share)
        let albumTitle = (share?[CKShare.SystemFieldKey.title] as? String) ?? "共有アルバム"

        var events: [Event] = []
        for record in fresh {
            let who = record.creatorUserRecordID.flatMap { names[$0.recordName] } ?? "メンバー"
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
        return events
    }

    private func post(_ events: [Event]) async {
        let center = UNUserNotificationCenter.current()
        // たくさんあるときは 3 件まで出して、残りはまとめる
        for event in events.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.subtitle = event.album
            content.body = event.body
            content.sound = .default
            content.threadIdentifier = "album"
            content.userInfo = ["album": true]
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if events.count > 3 {
            let content = UNMutableNotificationContent()
            content.title = "共有アルバム"
            content.body = "ほかに \(events.count - 3) 件の反応があります"
            content.threadIdentifier = "album"
            content.userInfo = ["album": true]
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // MARK: - 読んだ位置

    private func loadToken(_ key: String) -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken?, _ key: String) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    // MARK: - 通知の表示とタップ

    /// アプリを開いているときも、上に通知を出す
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// 通知をタップしたら、共有アルバムを開く
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["album"] != nil {
            Task { @MainActor in
                AlbumStore.shared.showAlbum = true
                await AlbumStore.shared.refresh()
            }
        }
        completionHandler()
    }
}
