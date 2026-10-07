import CloudKit
import UIKit
import UserNotifications

/// 共有アルバムに友だちがコメントしたら通知する。
/// iCloud の「変更があったら知らせる」（CKDatabaseSubscription、自分のアルバム＝非公開 DB、友だちのアルバム＝共有 DB）を、
/// 目に見える通知（mutable-content 付き）で登録する。届いた通知は拡張（FilmCameraNotify）が iCloud から変更を読み、
/// 「〇〇さんがコメントしました：本文」に書き換えて出す（アプリが閉じていても届く）。
/// アプリを開いたときも同じ読み取り（AlbumActivity）で取りこぼしを確かめる。読んだ位置は App Group で共有するので、二重には出ない
final class AlbumNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlbumNotifier()

    private let container = AlbumActivity.container
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
        // 前の、音の出ないプッシュだけの見張りは消す（届かないことが多かった）
        for (db, id) in [(container.privateCloudDatabase, "album-private"), (container.sharedCloudDatabase, "album-shared")]
        where defaults.bool(forKey: "subscribed-" + id) {
            if (try? await db.deleteSubscription(withID: id)) != nil {
                defaults.set(false, forKey: "subscribed-" + id)
            }
        }
        // 見張りの登録（一度だけ）：目に見える通知で届け、表示の前に拡張が文を書き換える
        for (db, id) in [(container.privateCloudDatabase, "album-private-alert"),
                         (container.sharedCloudDatabase, "album-shared-alert")]
        where !defaults.bool(forKey: "subscribed-" + id) {
            let subscription = CKDatabaseSubscription(subscriptionID: id)
            let info = CKSubscription.NotificationInfo()
            info.title = "共有アルバム"
            info.alertBody = "新しいコメントや写真があります"
            info.soundName = "default"
            info.shouldSendMutableContent = true
            subscription.notificationInfo = info
            if (try? await db.save(subscription)) != nil {
                defaults.set(true, forKey: "subscribed-" + id)
            }
        }
        // 今の位置を覚える（通知はしない）
        await catchUp(notify: false)
    }

    // MARK: - 変更を読む

    /// 前回からの変更を読み、友だちの動きがあれば通知する（拡張が先に読んでいれば、もう何も出ない）
    func catchUp(notify: Bool) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let events = await AlbumActivity.fetch(notify: notify)
        guard notify, !events.isEmpty else { return }
        await post(events)
    }

    private typealias Event = AlbumActivity.Event

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

    // MARK: - 通知の表示とタップ

    /// アプリを開いているときも、上に通知を出す
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        // iCloud からの通知なら、開いているアルバムも読み直す
        if content.userInfo["ck"] != nil {
            Task { @MainActor in await AlbumStore.shared.refresh() }
        }
        // 拡張が「友だちの動きなし」として文を空にしたものは出さない
        if content.title.isEmpty && content.body.isEmpty {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }

    /// 通知をタップしたら、共有アルバムを開く
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if info["album"] != nil || info["ck"] != nil {
            Task { @MainActor in
                AlbumStore.shared.showAlbum = true
                await AlbumStore.shared.refresh()
            }
        }
        completionHandler()
    }
}
