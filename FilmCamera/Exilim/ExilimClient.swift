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
    /// 最後の答えの HTTP の番号（0 は答えがなかった）
    private(set) var lastStatus = 0
    /// 最後に失敗した理由（つなぐ途中の探しは通信ログに書かないので、ときどきこれを書く）
    private(set) var lastError: String?
    /// カメラに名乗る名前
    private let clientName = "FilmCamera iPhone"
    /// ライブビューのコマ数の上限。プラグインの初期値は 10、上限は 30（大きさは 320×240 のまま。カメラ側で決まっている）
    static let previewRate = 30

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
    /// silent なら、見つからなかったときは通信ログに書かない（つなぐ途中は 0.3 秒おきに聞くので）
    func find(quick: Bool = false, timeout: TimeInterval? = nil, silent: Bool = false) async -> Info? {
        let candidates = (quick ? [2] : [2, 1, 3, 4, 5, 10, 100, 254]).map { "192.168.100.\($0)" }
        for candidate in candidates {
            if Task.isCancelled { return nil }
            guard let json = await request("getApiVersion", host: candidate, timeout: timeout ?? (quick ? 1 : 1.5),
                                           silent: silent),
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

    /// 画面を閉じるとき：ライブビューを止めるだけにする。
    /// disconnect を送ると、カメラが待ち受けをやめて次に開いたときに答えなくなった（実機のログ）ので送らない
    func disconnect() async {
        _ = await request("endLive", body: [:], timeout: 1)
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

    /// シャッターだけ切って、すぐ戻る（写真ができるのは待たない。受け取りは latestImage で別に）
    func shutterOnly() async throws {
        _ = await request("camMode", body: ["mode": 0])
        if let status = await status(), status.captureEnable {
            _ = await request("shutter", body: ["action": 1])
            return
        }
        try await shutter()
    }

    // MARK: - 動画・設定

    /// 動画を撮り始める（プラグインと同じく、先に camMode 1＝動画 を送る）
    func startMovie() async -> Bool {
        _ = await request("camMode", body: ["mode": 1])
        guard let json = await request("startRecMovie", body: [:]) else { return false }
        return (int(json["resp"]) ?? 0) == 0
    }

    func stopMovie() async -> Bool {
        guard let json = await request("endRecMovie", body: ["cause": 0]) else { return false }
        _ = await request("camMode", body: ["mode": 0])
        return (int(json["resp"]) ?? 0) == 0
    }

    /// カメラの設定の番号（プラグインの CameraParameter と同じ）
    enum Param: Int {
        /// 露出補正：1〜13（7 が ±0。-2.0, -1.7, -1.3, -1.0, -0.7, -0.3, 0, +0.3 … +2.0）
        case ev = 9
        /// ホワイトバランス：1 オート、2 太陽光、3 曇天、4 日陰、5 昼白色蛍光灯、6 昼光色蛍光灯、7 電球
        case whiteBalance = 14
        /// 電池：0〜5（0%, 30%, 50%, 60%, 99%, 100% のめやす）
        case battery = 16
        /// 左右反転：0 しない、1 する
        case mirror = 21
        /// あと何枚撮れるか
        case snapCapacity = 23
        /// セルフタイマー：0、5、10（秒）
        case selfTimer = 44
    }

    /// 設定の命令の送り方。プラグインは POST（JSON）だが、EX-FR100（API 4.0.0）はライブビューを止めても 405 で断った。
    /// 405 は「受け口はあるが、その送り方では受け付けない」なので、GET（?param_id=）も試し、通ったほうを使う。
    /// どちらも断られたら、このカメラはアプリからの設定変更に対応していないとみなす
    enum ParamStyle { case unknown, post, get, unsupported }
    private(set) var paramStyle = ParamStyle.unknown

    func setParam(_ param: Param, _ value: Int) async -> Bool {
        let json = await paramRequest("setParam", ["param_id": param.rawValue, "param_val": value])
        guard let json else { return false }
        return (int(json["resp"]) ?? 0) >= 0
    }

    /// 設定を読む（答えは {"9": 7} のように、番号が名前になっている）
    func getParam(_ param: Param) async -> Int? {
        guard let json = await paramRequest("getParam", ["param_id": param.rawValue]) else { return nil }
        return int(json[String(param.rawValue)]) ?? int(json["param_val"]) ?? int(json["value"])
    }

    private func paramRequest(_ command: String, _ values: [String: Int]) async -> [String: Any]? {
        let query = values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        switch paramStyle {
        case .unsupported:
            return nil
        case .post:
            return await request(command, body: values, timeout: 3)
        case .get:
            return await request(command, query: query, timeout: 3)
        case .unknown:
            if let json = await request(command, body: values, timeout: 3) {
                paramStyle = .post
                return json
            }
            guard lastStatus == 405 || lastStatus == 404 else { return nil }
            if let json = await request(command, query: query, timeout: 3) {
                paramStyle = .get
                return json
            }
            if lastStatus == 405 || lastStatus == 404 {
                paramStyle = .unsupported
                // カメラの設定の全体（プラグインが getParam の代わりに使う命令）を通信ログに残す
                _ = await request("camSetting", body: [:], timeout: 3)
            }
            return nil
        }
    }

    /// 電池の残りを、getParam 以外の答えからも探す（EX-FR100 は getParam を断った）。
    /// camStatus・camSetting・getConnectInfo の答えに "batt" を含む名前があれば、その値を返す（答えは通信ログにも残る）。
    /// 返す値：0〜5 ならプラグインと同じ段階、それより大きければ % とみなす
    func findBattery() async -> Int? {
        let answers = [await request("camStatus", body: [:], timeout: 3),
                       await request("camSetting", body: [:], timeout: 3),
                       await request("getConnectInfo", query: "id=0", timeout: 3)]
        for json in answers.compactMap({ $0 }) {
            for (key, value) in json where key.lowercased().contains("batt") {
                if let level = int(value) { return level }
            }
        }
        return nil
    }

    /// カメラの時計を iPhone に合わせる（TimeStamp は "2026:10:09 21:06:17"、TimeZone は世界標準時からの秒）
    func syncClock() async {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        _ = await request("setDateTime", body: ["TimeStamp": formatter.string(from: Date()),
                                                "TimeZone": TimeZone.current.secondsFromGMT()])
    }

    /// いま撮った写真ができあがるまで待つ（最大 limit 秒）
    func waitLatestImage(limit: TimeInterval = 6) async {
        let deadline = Date().addingTimeInterval(limit)
        while Date() < deadline {
            if let status = await status(), status.latestImage { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: - カメラから消す（内蔵メモリーをあける）

    /// カメラの中の写真を 1 枚消す（WEBSERVER のとき）
    func delete(_ path: String) async -> Bool {
        guard let json = await request("deleteImage", body: ["file": path], timeout: 8) else { return false }
        return int(json["resp"]) == 0
    }

    /// 新しいほうから count 件の写真（WEBSERVER のとき。カシオのプラグインの updateLatestFileName と同じ頼み方）。
    /// 動画は入れない（リモート撮影で撮った写真だけを受け取って消すため）
    func latestPhotos(_ count: Int, apiVersion: String) async -> [RemoteFile] {
        if Self.versionNumber(apiVersion) >= 100000 {
            _ = await request("setTarget", body: ["target": 0])
        }
        guard count > 0,
              let json = await request("getList", query: "pos=0&num=\(count)&sort=1", timeout: 10),
              let entries = json["files"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry -> RemoteFile? in
            guard int(entry["type"]) == 1, let name = entry["name"] as? String else { return nil }
            return RemoteFile(path: name, isVideo: false, size: Int64(int(entry["size"]) ?? 0),
                              modified: string(entry["mtime"]) ?? "")
        }
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

    /// 動画など大きいものを、メモリに載せずにファイルとして受け取る（受け取っている間も heartBeat を送る）。
    /// 返すのは一時フォルダの中のファイル（拡張子はカメラの名前と同じ。呼んだ側で使い終わったら消す）
    func downloadFile(_ path: String) async throws -> URL {
        let beating = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self.heartBeat()
            }
        }
        defer { beating.cancel() }
        guard let url = URL(string: "http://\(host)/camlink/getImage?file=\(Self.escape(path))") else {
            throw ExilimError.downloadFailed
        }
        await log("→ GET getImage?file=\(path)（ファイルで受け取る）")
        do {
            let (temporary, response) = try await session.download(for: URLRequest(url: url, timeoutInterval: 60))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let size = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? Int) ?? 0
            await log("← getImage \(status) \(size) バイト")
            guard status == 200, size > 0 else { throw ExilimError.downloadFailed }
            let ext = (path as NSString).pathExtension.isEmpty ? "mov" : (path as NSString).pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.lowercased())
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch let error as ExilimError {
            throw error
        } catch {
            await log("× getImage \((error as NSError).localizedDescription)")
            throw ExilimError.downloadFailed
        }
    }

    // MARK: - 通信

    /// 命令を送り、JSON の答えを受け取る（body があれば POST、なければ GET）
    private func request(_ command: String, body: [String: Any]? = nil, query: String? = nil,
                         host: String? = nil, timeout: TimeInterval = 5, silent: Bool = false) async -> [String: Any]? {
        guard let data = await requestData(command, body: body, query: query, host: host, timeout: timeout,
                                           silent: silent) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func requestData(_ command: String, body: [String: Any]? = nil, query: String? = nil,
                             host: String? = nil, timeout: TimeInterval = 5, silent: Bool = false,
                             retried: Bool = false) async -> Data? {
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
        if !quiet && !silent { await log("→ " + line) }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastStatus = status
            if silent && status == 200 { await log("→ " + line) }
            if !quiet || status != 200 {
                let reply = isBinary ? "\(data.count) バイト" : String(String(decoding: data, as: UTF8.self).prefix(300))
                await log("← \(command) \(status) \(reply)")
            }
            return status == 200 ? data : nil
        } catch {
            lastStatus = 0
            lastError = (error as NSError).localizedDescription
            // カメラが使い終わった接続を閉じていたときは、1 回だけ送り直す
            if (error as? URLError)?.code == .networkConnectionLost, !retried {
                return await requestData(command, body: body, query: query, host: host, timeout: timeout,
                                         silent: silent, retried: true)
            }
            // 受け取りが終わって heartBeat を止めたときの「キャンセル」、つなぐ途中の探しは、書かない
            if !silent && !(quiet && (error as? URLError)?.code == .cancelled) {
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
