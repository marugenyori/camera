import Foundation
import Network

/// カメラからの呼びかけを受ける、iPhone 側の小さな HTTP の受け口（カシオのプラグインもポート 8081 で開いている）。
/// connect のときにこのポートをカメラに伝えると、カメラはここに /camlink/stopShutter や /camlink/notifyEvent などを送ってくる。
/// 受け口がないと、カメラは「つなぎ途中（LIVE_CONNECTING）」のまま撮影できる状態にならないことがあった
final class ExilimCallbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "exilim.callback")
    private(set) var port: UInt16 = 8081

    private func log(_ text: String) {
        Task { @MainActor in ExilimLog.shared.add(text) }
    }

    /// 受け口を開く（ふさがっていたら次の番号）。開いたポート番号を返す
    func start() -> UInt16? {
        if listener != nil { return port }
        for candidate in UInt16(8081)...UInt16(8095) {
            guard let nwPort = NWEndpoint.Port(rawValue: candidate),
                  let listener = try? NWListener(using: .tcp, on: nwPort) else { continue }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.log("受け口 \(candidate)：\(state)")
            }
            listener.start(queue: queue)
            self.listener = listener
            port = candidate
            return candidate
        }
        return nil
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    /// 頭（ヘッダー）と、Content-Length の分の本文がそろうまで読む
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.log("カメラから：\(request.path) \(request.body)")
                self.reply(connection)
            } else if isComplete || error != nil || buffer.count > 200_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func reply(_ connection: NWConnection) {
        let body = "{\"resp\":0}"
        let text = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func parse(_ data: Data) -> (path: String, body: String)? {
        let text = String(decoding: data, as: UTF8.self)
        guard let headerEnd = text.range(of: "\r\n\r\n") ?? text.range(of: "\n\n") else { return nil }
        let header = text[..<headerEnd.lowerBound]
        let body = String(text[headerEnd.upperBound...])
        let length = header.split(whereSeparator: \.isNewline)
            .first { $0.lowercased().hasPrefix("content-length") }
            .flatMap { Int($0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        guard body.utf8.count >= length else { return nil }
        let path = header.split(separator: " ").dropFirst().first.map(String.init) ?? "?"
        return (path, body)
    }
}
