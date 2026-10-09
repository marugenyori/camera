import Foundation
import Network
import UIKit

/// EXILIM のライブビューを受け取る。カメラは 1 コマの JPEG をいくつかの UDP パケットに分けて、
/// startLive で伝えた iPhone のポートに送ってくる。パケットの頭 12 バイトが見出し：
/// - 2〜3 バイト目：1 コマの JPEG の大きさ
/// - 4〜7 バイト目：パケットの通し番号
/// - 8〜11 バイト目：コマの番号（同じコマのパケットは同じ番号）
/// 13 バイト目からが JPEG の一部。通し番号の順に並べ直して、そろったら画像にする（カシオのプラグインと同じ組み立て方）
final class ExilimLiveView: @unchecked Sendable {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "exilim.liveview")
    private var frames: [UInt32: Frame] = [:]
    private var lastShown: UInt32 = 0
    /// 新しいコマができたとき（メインスレッドで呼ぶ）
    var onFrame: (@MainActor (UIImage) -> Void)?
    private(set) var port: UInt16 = 0
    private var packets = 0
    private var decoded = 0
    private var broken = 0

    private func log(_ text: String) {
        Task { @MainActor in ExilimLog.shared.add(text) }
    }

    private struct Frame {
        let size: Int
        var data: Data
        var firstPacket: UInt32 = 0
        var chunkSize = 0
        var copied = 0
        let created = Date()

        init(size: Int) {
            self.size = size
            data = Data(count: size)
        }
    }

    /// UDP のポートを開く（ふさがっていたら次の番号を試す）。開いたポート番号を返す
    func start() -> UInt16? {
        stop()
        for candidate in UInt16(54321)...UInt16(54340) {
            guard let port = NWEndpoint.Port(rawValue: candidate),
                  let listener = try? NWListener(using: .udp, on: port) else { continue }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: self.queue)
                self.receive(on: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.log("UDP ポート \(candidate)：\(state)")
            }
            listener.start(queue: queue)
            self.listener = listener
            packets = 0
            decoded = 0
            broken = 0
            self.port = candidate
            return candidate
        }
        return nil
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            self?.connections.forEach { $0.cancel() }
            self?.connections.removeAll()
            self?.frames.removeAll()
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, data.count > 12 { self.store(data) }
            if error == nil { self.receive(on: connection) }
        }
    }

    private func store(_ packet: Data) {
        packets += 1
        if packets == 1 || packets % 300 == 0 {
            log("UDP 受信 \(packets) パケット目（\(packet.count) バイト）")
        }
        let bytes = [UInt8](packet)
        let size = Int(bytes[2]) << 8 | Int(bytes[3])
        let number = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
        let id = UInt32(bytes[8]) << 24 | UInt32(bytes[9]) << 16 | UInt32(bytes[10]) << 8 | UInt32(bytes[11])
        let payload = bytes.count - 12
        guard size > 0, payload > 0, id > lastShown || lastShown - id > 1_000_000 else { return }

        var frame = frames[id] ?? Frame(size: size)
        if frame.firstPacket == 0 {
            frame.firstPacket = number
            frame.chunkSize = payload
        } else if number < frame.firstPacket {
            // 先頭より前のパケットがあとから届いた：中身を後ろにずらす
            let shift = Int(frame.firstPacket - number) * payload
            guard shift > 0, shift < frame.size else { return }
            var moved = Data(count: frame.size)
            moved.replaceSubrange(shift..<frame.size, with: frame.data.prefix(frame.size - shift))
            frame.data = moved
            frame.firstPacket = number
        }
        let offset = Int(number - frame.firstPacket) * frame.chunkSize
        guard offset >= 0, offset + payload <= frame.size else { return }
        frame.data.replaceSubrange(offset..<offset + payload, with: bytes[12...])
        frame.copied += payload

        if frame.copied >= frame.size {
            frames[id] = nil
            // 古い作りかけのコマは捨てる
            frames = frames.filter { $0.key > id && Date().timeIntervalSince($0.value.created) < 2 }
            lastShown = id
            if let image = UIImage(data: frame.data) {
                decoded += 1
                if decoded == 1 || decoded % 100 == 0 { log("ライブビュー \(decoded) コマ目を表示") }
                let handler = onFrame
                Task { @MainActor in handler?(image) }
            } else {
                broken += 1
                if broken == 1 || broken % 50 == 0 { log("ライブビューの画像を読めませんでした（\(broken) 回目、\(frame.size) バイト）") }
            }
        } else {
            frames[id] = frame
        }
    }
}
