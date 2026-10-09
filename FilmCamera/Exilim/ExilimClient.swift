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
            case .notReady: return "カメラが撮影できる状態ではありません"
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

    /// カメラを探す（いつもの 192.168.100.2 から、近くのアドレスも順に試す）
    func find() async -> Info? {
        let candidates = [2, 1, 3, 4, 5, 10, 100, 254].map { "192.168.100.\($0)" }
        for candidate in candidates {
            guard let json = await request("getApiVersion", host: candidate, timeout: 1.5),
                  let model = json["MDL"] as? String else { continue }
            host = candidate
            return Info(model: model, apiVersion: string(json["resp"]) ?? "")
        }
        return nil
    }

    // MARK: - モード

    func appMode() async -> Mode? {
        guard let json = await request("getAppMode") else { return nil }
        return (json["app_mode"] as? String).flatMap(Mode.init(rawValue:))
    }

    /// モードを切り替えて、つなぎ直す（返り値：connect の答え。live / web / free）
    @discardableResult
    func switchMode(to target: Mode) async throws -> String {
        var current = await appMode()
        if current == .request {
            // 「リクエスト待ち」なら、まずライブビューにしてもらう
            _ = await request("setAppMode", body: ["app_mode": Mode.liveView.rawValue])
            try? await Task.sleep(for: .milliseconds(150))
            current = await appMode()
        }
        if current != target {
            _ = await request("changeAppMode", body: ["app_mode": target.rawValue])
            var tries = 0
            while await appMode() != target {
                tries += 1
                if tries > 100 { throw ExilimError.modeChangeFailed }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        guard let json = await request("connect", body: ["name": clientName, "port": 8081]),
              int(json["resp"]) == 0, let mode = json["mode"] as? String else {
            throw ExilimError.notConnected
        }
        return mode
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
    func shutter() async throws {
        guard let status = await status(), status.captureEnable else { throw ExilimError.notReady }
        _ = await request("shutter", body: ["action": 1])
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
        defer { Task { _ = await self.startLive(port: livePort) } }
        return try await download("latest.jpg")
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
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
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
