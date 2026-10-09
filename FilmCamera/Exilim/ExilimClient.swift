import Foundation
import UIKit

/// カシオ EXILIM（EX-FR100 など）と Wi-Fi で直接話す。
/// カメラは自分の Wi-Fi（アクセスポイント）を出していて、iPhone がそれにつなぐと、カメラは 192.168.100.2 で
/// HTTP の命令（/camlink/…、中身は JSON）を受け付ける。命令の名前と手順は、カシオが公開している
/// EXILIM Plugin（Device Connect 用、MIT ライセンス）の Android 版と同じ。
///
/// カメラには「モード」があり、できることが分かれている：
/// - LIVEVIEW：リモート撮影（ライブビューを UDP で送ってくる、シャッター）
/// - WEBSERVER：カメラの中の写真の一覧・サムネイル・本体の取り出し
/// モードを変えたら、もう一度 connect する。つないでいる間は 1 秒ごとに heartBeat を送る（止めると切られる）
actor ExilimClient {
    struct Info: Equatable {
        /// 機種名（例：EX-FR100）
        let model: String
        let apiVersion: String
    }

    struct RemoteFile: Identifiable, Hashable {
        /// カメラの中のパス（例：/DCIM/100CASIO/CIMG0001.JPG）
        let path: String
        let isVideo: Bool
        let size: Int64
        /// カメラが返す更新日時（"2017-01-01 00:00:00" の形）
        let modified: String

        var id: String { path }
        var fileName: String { (path as NSString).lastPathComponent }
    }

    enum Mode: String {
        case liveView = "LIVEVIEW"
        case webServer = "WEBSERVER"
        case imagePush = "IMAGEPUSH"
        case request = "REQUEST"
        /// 何もしていない（つないだばかり）
        case free = "FREE"
    }

    /// カメラからの呼びかけを受ける iPhone 側のポート（connect のときに伝える）
    private var callbackPort: UInt16 = 8081

    func setCallbackPort(_ port: UInt16) {
        callbackPort = port
    }

    enum ExilimError: LocalizedError {
        case notConnected
        case modeChangeFailed
        case notReady
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .notConnected: return "カメラとつながっていません"
            case .modeChangeFailed: return "カメラのモードを切り替えられませんでした"
            case .notReady:
                return "カメラが撮影できません（メモリーカードがないと、内蔵メモリーは数枚でいっぱいになります。「カメラの写真」で受け取って消すと、また撮れます）"
            case .downloadFailed: return "カメラから写真を受け取れませんでした"
            }
        }
    }

    /// カメラのアドレス（ふつうは 192.168.100.2）
    private(set) var host = "192.168.100.2"
    /// カメラに名乗る名前
    private let clientName = "FilmCamera iPhone"
    /// ライブビューのコマ数の上限（カシオのプラグインと同じ）
    static let previewRate = 10

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        // カメラの Wi-Fi はインターネットにつながっていないので、モバイル通信に逃げないようにする
        config.allowsCellularAccess = false
        config.connectionProxyDictionary = [:]
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    // MARK: - さがす

    /// カメラを探す（いつもの 192.168.100.2 から、近くのアドレスも順に試す。quick なら 192.168.100.2 だけ）
    func find(quick: Bool = false) async -> Info? {
        let candidates = (quick ? [2] : [2, 1, 3, 4, 5, 10, 100, 254]).map { "192.168.100.\($0)" }
        for candidate in candidates {
            if Task.isCancelled { return nil }
            guard let json = await request("getApiVersion", host: candidate, timeout: quick ? 1 : 1.5),
                  let model = json["MDL"] as? String else { continue }
            host = candidate
            return Info(model: model, apiVersion: string(json["resp"]) ?? "")
        }
        return nil
    }

    // MARK: - モード

    func appMode() async -> Mode? {
        guard let json = await request("getAppMode", timeout: 2) else { return nil }
        return (json["app_mode"] as? String).flatMap(Mode.init(rawValue:))
    }

    /// モードを切り替えて、つなぎ直す（返り値：connect の答え。live / web / free）
    @discardableResult
    /// カシオのプラグインと同じ手順：
    /// - ライブビューにするとき：WEBSERVER なら changeAppMode、WEBSERVER・REQUEST なら続けて setAppMode（LIVEVIEW）。
    ///   LIVEVIEW になったら connect して、答えが live ならつながった（free ならもう一度 setAppMode から）
    /// - 写真を見るとき：changeAppMode（WEBSERVER）して、WEBSERVER になるまで待ってから connect（答えは web）
    /// 待つのは最大で約 15 秒（止まったままにしない）
    func switchMode(to target: Mode) async throws -> String {
        let deadline = Date().addingTimeInterval(15)
        var askedChange = false
        var missing = 0
        while Date() < deadline {
            try Task.checkCancellation()
            guard let current = await appMode() else {
                missing += 1
                if missing >= 3 { throw ExilimError.notConnected }
                continue
            }
            if current == target {
                guard let json = await request("connect", body: ["name": clientName, "port": Int(callbackPort)]),
                      int(json["resp"]) == 0, let mode = json["mode"] as? String else {
                    throw ExilimError.notConnected
                }
                let expected = target == .liveView ? "live" : "web"
                if mode == expected { return mode }
                // 思ったモードでつながらなかった：もう一度切り替えから
                if target == .liveView {
                    _ = await request("setAppMode", body: ["app_mode": Mode.liveView.rawValue])
                }
                try await Task.sleep(for: .milliseconds(200))
                continue
            }
            if target == .liveView {
                if current == .webServer, !askedChange {
                    _ = await request("changeAppMode", body: ["app_mode": Mode.liveView.rawValue])
                    askedChange = true
                }
                _ = await request("setAppMode", body: ["app_mode": Mode.liveView.rawValue])
                try await Task.sleep(for: .milliseconds(150))
            } else {
                // 写真を見るモードへは、ライブビューでつなぎきってから切り替える
                // （REQUEST・FREE のまま changeAppMode を送ると 403 で断られた。プラグインもライブビューから切り替えている）
                if current == .request || current == .free || current == .imagePush {
                    _ = try await switchMode(to: .liveView)
                    await endLive()
                    try await Task.sleep(for: .milliseconds(150))
                    continue
                }
                if current == .liveView, !askedChange {
                    await endLive()
                }
                if !askedChange {
                    _ = await request("changeAppMode", body: ["app_mode": target.rawValue])
                    askedChange = true
                }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        throw ExilimError.modeChangeFailed
    }

    /// 1 秒ごとに送る「まだいるよ」
    @discardableResult
    func heartBeat() async -> Bool {
        await request("heartBeat", body: ["rate": Self.previewRate], timeout: 2) != nil
    }

    func disconnect() async {
        _ = await request("endLive", body: [:], timeout: 1)
        _ = await request("disconnect", body: ["cause": 0], timeout: 1)
    }

    // MARK: - リモート撮影（LIVEVIEW）

    /// ライブビューの送り先（iPhone の UDP のポート）を伝えて、送ってもらう
    func startLive(port: UInt16) async -> Bool {
        guard let json = await request("startLive", body: ["rate": Self.previewRate, "port": Int(port)], timeout: 3) else {
            return false
        }
        return int(json["resp"]) == 0
    }

    func endLive() async {
        _ = await request("endLive", body: [:])
    }

    struct Status {
        var captureEnable = false
        var latestThumb = false
        var latestImage = false
    }

    func status() async -> Status? {
        guard let json = await request("camStatus", body: [:]) else { return nil }
        return Status(captureEnable: int(json["captureEnable"]) == 1,
                      latestThumb: int(json["latest-thumb"]) == 1,
                      latestImage: int(json["latest-image"]) == 1)
    }

    /// シャッターを切る（撮れる状態のときだけ）
    /// カシオのプラグインと同じく、先に camMode（0＝静止画）を送ってから、撮れる状態になるのを待って切る
    func shutter() async throws {
        _ = await request("camMode", body: ["mode": 0])
        for _ in 0..<15 {
            if let status = await status(), status.captureEnable {
                _ = await request("shutter", body: ["action": 1])
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        // 撮れない理由を調べるため、カメラの状態と写真の枚数を通信ログに残す
        _ = await request("getAppMode", timeout: 2)
        _ = await request("getTotal", timeout: 2)
        throw ExilimError.notReady
    }

    /// いま撮った写真ができるまで待って、小さい画像を受け取る
    func waitLatestThumbnail() async -> UIImage? {
        for _ in 0..<50 {
            if let status = await status(), status.latestThumb {
                return await thumbnail(of: "latest.jpg")
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    /// いま撮った写真の本体を受け取る（ライブビューを一度止めて受け取り、また始める）
    func latestImage(livePort: UInt16) async throws -> Data {
        for _ in 0..<75 {
            if let status = await status(), status.latestImage { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        await endLive()
        let data = try? await download("latest.jpg")
        _ = await startLive(port: livePort)
        guard let data else { throw ExilimError.downloadFailed }
        return data
    }

    // MARK: - カメラから消す（内蔵メモリーをあける）

    /// カメラの中の写真を 1 枚消す（WEBSERVER のとき）
    func delete(_ path: String) async -> Bool {
        guard let json = await request("deleteImage", body: ["file": path], timeout: 8) else { return false }
        return int(json["resp"]) == 0
    }

    /// いちばん新しい写真のパス（WEBSERVER のとき。カシオのプラグインの updateLatestFileName と同じ頼み方）
    private func latestPath(apiVersion: String) async -> String? {
        if Self.versionNumber(apiVersion) >= 100000 {
            _ = await request("setTarget", body: ["target": 0])
        }
        guard let json = await request("getList", query: "pos=0&num=1&sort=1", timeout: 10),
              let files = json["files"] as? [[String: Any]],
              let name = files.first?["name"] as? String else { return nil }
        return name
    }

    /// リモート撮影で撮った写真をカメラから消す（写真を見るモードに切り替えて消し、ライブビューに戻す）。
    /// メモリーカードがなくても、内蔵メモリーがいっぱいにならずに撮り続けられる
    func deleteLatestShot(apiVersion: String, livePort: UInt16) async -> Bool {
        await endLive()
        var deleted = false
        if (try? await switchMode(to: .webServer)) != nil, let path = await latestPath(apiVersion: apiVersion) {
            deleted = await delete(path)
        }
        if (try? await switchMode(to: .liveView)) != nil {
            _ = await startLive(port: livePort)
        }
        return deleted
    }

    /// "1.2.3" → 10203（プラグインと同じ数え方）
    static func versionNumber(_ text: String) -> Int {
        text.split(separator: ".").reduce(0) { $0 * 100 + (Int($1) ?? 0) }
    }

    // MARK: - カメラの中の写真（WEBSERVER）

    /// 写真と動画の一覧（フォルダの中までたどる。新しい順）
    func list() async throws -> [RemoteFile] {
        try await switchMode(to: .webServer)
        var files: [RemoteFile] = []
        var folders = ["/"]
        var visited = Set<String>()
        while let folder = folders.popLast(), visited.count < 40 {
            guard visited.insert(folder).inserted else { continue }
            let query = "dir=\(Self.escape(folder))&pos=0&num=0&sort=0"
            guard let json = await request("getList", query: query, timeout: 10),
                  let entries = json["files"] as? [[String: Any]] else { continue }
            for entry in entries {
                guard var name = entry["name"] as? String else { continue }
                if !name.hasPrefix("/") {
                    name = (folder as NSString).appendingPathComponent(name)
                }
                switch int(entry["type"]) {
                case 0:
                    folders.append(name)
                case 1, 2:
                    files.append(RemoteFile(path: name, isVideo: int(entry["type"]) == 2,
                                            size: Int64(int(entry["size"]) ?? 0),
                                            modified: string(entry["mtime"]) ?? ""))
                default:
                    continue
                }
            }
        }
        return files.sorted { ($0.modified, $0.path) > ($1.modified, $1.path) }
    }

    func thumbnail(of path: String) async -> UIImage? {
        guard let data = await requestData("getThumbnail", query: "file=\(Self.escape(path))", timeout: 8) else {
            return nil
        }
        return UIImage(data: data)
    }

    /// 写真の本体を受け取る（大きいので、受け取っている間も heartBeat を送り続ける）
    func download(_ path: String) async throws -> Data {
        let beating = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self.heartBeat()
            }
        }
        defer { beating.cancel() }
        guard let data = await requestData("getImage", query: "file=\(Self.escape(path))", timeout: 90),
              !data.isEmpty else {
            throw ExilimError.downloadFailed
        }
        return data
    }

    // MARK: - 通信

    /// 命令を送り、JSON の答えを受け取る（body があれば POST、なければ GET）
    private func request(_ command: String, body: [String: Any]? = nil, query: String? = nil,
                         host: String? = nil, timeout: TimeInterval = 5) async -> [String: Any]? {
        guard let data = await requestData(command, body: body, query: query, host: host, timeout: timeout) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func requestData(_ command: String, body: [String: Any]? = nil, query: String? = nil,
                             host: String? = nil, timeout: TimeInterval = 5) async -> Data? {
        var text = "http://\(host ?? self.host)/camlink/\(command)"
        if let query { text += "?" + query }
        guard let url = URL(string: text) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        // 通信ログ（1 秒ごとの heartBeat は、うまくいかなかったときだけ書く）
        let quiet = command == "heartBeat"
        let isBinary = command == "getThumbnail" || command == "getImage"
        let sent = (body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }).flatMap { String(data: $0, encoding: .utf8) }
        let line = "\(body == nil ? "GET" : "POST") \(command)\(query.map { "?" + $0 } ?? "") \(sent ?? "")"
        if !quiet { await log("→ " + line) }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !quiet || status != 200 {
                let reply = isBinary ? "\(data.count) バイト" : String(String(decoding: data, as: UTF8.self).prefix(300))
                await log("← \(command) \(status) \(reply)")
            }
            return status == 200 ? data : nil
        } catch {
            // 受け取りが終わって heartBeat を止めたときの「キャンセル」は、ふつうのことなので書かない
            if !(quiet && (error as? URLError)?.code == .cancelled) {
                await log("× \(command) \((error as NSError).localizedDescription)")
            }
            return nil
        }
    }

    private func log(_ text: String) async {
        await MainActor.run { ExilimLog.shared.add(text) }
    }

    /// パスの「/」はそのままにして、ほかの記号だけ % で包む
    private static func escape(_ path: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    /// カメラは数字を文字列で返すことがあるので、どちらでも読めるように
    private func int(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

/// カメラとのやりとりの記録（画面の「通信ログ」で見られる。うまくいかないときに、どこで止まったかを調べるため）
@MainActor
final class ExilimLog: ObservableObject {
    static let shared = ExilimLog()
    @Published private(set) var lines: [String] = []

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func add(_ text: String) {
        lines.append(formatter.string(from: Date()) + " " + text)
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
    }

    func clear() { lines.removeAll() }
}
