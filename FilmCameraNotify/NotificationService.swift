import UserNotifications

/// iCloud から届いた「共有アルバムが変わった」というプッシュを、表示する前に書き換える拡張。
/// iCloud から変更を読んで、「〇〇さんがコメントしました：本文」のような通知にする。
/// 友だちの動きでなかったとき（自分の別の端末での変更など）は、文を空にして表示しない
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        self.content = content
        Task {
            let events = await AlbumActivity.fetch(notify: true)
            if events.isEmpty {
                content.title = ""
                content.subtitle = ""
                content.body = ""
                content.sound = nil
            } else {
                AlbumActivity.fill(content, with: events)
            }
            finish()
        }
    }

    /// 時間切れ（約 30 秒）のときは、届いたままの文で出す
    override func serviceExtensionTimeWillExpire() {
        finish()
    }

    private func finish() {
        guard let handler = contentHandler, let content else { return }
        contentHandler = nil
        handler(content)
    }
}
