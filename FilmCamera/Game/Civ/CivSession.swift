import CloudKit
import MultipeerConnectivity
import SwiftUI

/// 「ふたりの文明」の同期（リアルタイム。番はない）。遊び方は 3 つ：
/// - ひとりで：この端末で時間を進める（UserDefaults に保存）
/// - 近くで：2 台の iPhone を Wi-Fi・Bluetooth で直接つなぐ（MultipeerConnectivity）。作った人（ホスト）が時間を進め、
///   参加した人の行動はホストに送ってホストが行う。ホストは変わるたびに状態をまるごと送る
/// - 離れて：共有アルバムのゾーンに「CivGame」レコード（state＝状態の JSON、version）を 1 つ置く。
///   自分の行動はすぐ画面に出して「送る予定」にため、数秒おきに「iCloud の最新を読む → 時間を進める → ためた行動を行う → 保存」する。
///   2 人が同時に保存してぶつかったら、読み直してやり直す。だれも開いていない間の時間は、次に開いた人が進める
@MainActor
final class CivSession: ObservableObject {
    enum Mode: Equatable {
        case solo
        case nearbyHost
        case nearbyJoin
        case cloud(AlbumRef)
    }

    @Published private(set) var state: CivState?
    @Published private(set) var status = ""
    @Published private(set) var partnerConnected = false
    @Published var message: String?

    let mode: Mode
    let myName: String
    private(set) var myID: String
    private var nearby: CivNearby?
    private var cloud: CivCloud?
    private var clock: Task<Void, Never>?
    /// 離れて：まだ iCloud に送っていない自分の行動
    private var pending: [CivState.Action] = []
    private var syncing = false
    private var lastSync = Date.distantPast

    init(mode: Mode, name: String) {
        self.mode = mode
        myName = name.isEmpty ? "プレイヤー" : name
        myID = Self.deviceID
    }

    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "civDeviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "civDeviceID")
        return id
    }

    var me: CivPlayer { CivPlayer(id: myID, name: myName, color: 0) }
    var myIndex: Int? { state?.players.firstIndex { $0.id == myID } }
    /// 行動できるか（近くで参加した人は、ホストとつながっている間だけ）
    var canAct: Bool {
        guard let state, !state.won else { return false }
        if mode == .nearbyJoin { return partnerConnected && myIndex != nil }
        return true
    }

    // MARK: - 始める・やめる

    func start() async {
        switch mode {
        case .solo:
            state = loadLocal() ?? CivState.new(host: me)
            status = "ひとりで遊んでいます"
            saveLocal()
            startClock()
        case .nearbyHost:
            if let saved = loadLocal(), saved.players.first?.id == myID {
                state = saved
            } else {
                state = CivState.new(host: me)
            }
            saveLocal()
            startNearby(host: true)
            status = "相手を待っています（相手は「参加する」を押してください）"
            startClock()
        case .nearbyJoin:
            startNearby(host: false)
            status = "近くの文明をさがしています"
        case .cloud(let album):
            status = "iCloud から読み込んでいます"
            if let id = try? await CKContainer.default().userRecordID().recordName { myID = id }
            cloud = CivCloud(album: album)
            await syncCloud()
            startClock()
        }
    }

    func stop() {
        clock?.cancel()
        nearby?.stop()
        nearby = nil
        if case .cloud = mode, !pending.isEmpty {
            Task { await syncCloud() }
        }
    }

    /// 最初から作り直す（相手はそのまま 2 人目に入れておく）
    func restart() {
        var fresh = CivState.new(host: me)
        if let old = state {
            fresh.version = old.version + 1
            for player in old.players where player.id != myID { _ = fresh.join(player) }
        }
        switch mode {
        case .cloud:
            pending = []
            state = fresh
            Task { await syncCloud(replacing: fresh) }
        case .nearbyJoin:
            break
        default:
            state = fresh
            changed()
        }
    }

    /// 0.5 秒ごとに時間を進める（ホスト・ひとり）、または iCloud と同期する（離れて）
    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                switch self.mode {
                case .solo, .nearbyHost:
                    guard var next = self.state else { continue }
                    let before = next.techs.count
                    if next.advance(to: Date()) > 0 {
                        if next.techs.count > before { GameAudio.shared.play(.special) }
                        self.state = next
                        self.changed()
                    }
                case .cloud:
                    // 自分の行動があればすぐ、なければ 3 秒おきに
                    if !self.pending.isEmpty || Date().timeIntervalSince(self.lastSync) > 3 {
                        await self.syncCloud()
                    }
                case .nearbyJoin:
                    return
                }
            }
        }
    }

    // MARK: - 行動

    func act(_ action: CivState.Action) {
        guard var next = state, canAct, let who = myIndex else { return }
        switch mode {
        case .nearbyJoin:
            // ホストに頼む（結果はホストから届く）
            guard next.problem(action) == nil else {
                GameAudio.shared.play(.invalid)
                return
            }
            send(.action(action, myID))
            feedback(action)
        default:
            let before = next.techs.count
            guard next.perform(action, by: who) else {
                GameAudio.shared.play(.invalid)
                return
            }
            state = next
            feedback(action)
            if next.won { GameAudio.shared.play(.win) } else if next.techs.count > before { GameAudio.shared.play(.special) }
            if case .cloud = mode { pending.append(action) }
            changed()
        }
    }

    private func feedback(_ action: CivState.Action) {
        if case .research = action { GameAudio.shared.tick() } else { GameAudio.shared.play(.place) }
    }

    /// 状態が変わったあと：保存して、相手に送る
    private func changed() {
        switch mode {
        case .solo:
            saveLocal()
        case .nearbyHost:
            saveLocal()
            if let state { send(.state(state)) }
        case .nearbyJoin, .cloud:
            break
        }
    }

    // MARK: - ひとり・近く：端末に保存

    private var localKey: String { mode == .solo ? "civSolo2" : "civNearby2" }

    private func loadLocal() -> CivState? {
        guard let data = UserDefaults.standard.data(forKey: localKey) else { return nil }
        return try? JSONDecoder().decode(CivState.self, from: data)
    }

    private func saveLocal() {
        guard let state, let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: localKey)
    }

    // MARK: - 近く

    enum Message: Codable {
        case hello(CivPlayer)
        case state(CivState)
        case action(CivState.Action, String)
    }

    private func startNearby(host: Bool) {
        let nearby = CivNearby(name: myName, host: host)
        nearby.onPeers = { [weak self] count in
            guard let self else { return }
            self.partnerConnected = count > 0
            if count > 0 {
                self.status = "相手とつながっています"
                if host, let state = self.state {
                    self.send(.state(state))
                } else if !host {
                    self.send(.hello(self.me))
                }
            } else {
                self.status = host ? "相手を待っています" : "近くの文明をさがしています"
            }
        }
        nearby.onReceive = { [weak self] data in
            self?.receive(data, host: host)
        }
        nearby.start()
        self.nearby = nearby
    }

    private func send(_ message: Message) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        nearby?.send(data)
    }

    private func receive(_ data: Data, host: Bool) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        switch message {
        case .hello(let player):
            guard host, var next = state else { return }
            if next.join(player) {
                state = next
                changed()
                GameAudio.shared.play(.complete)
            } else {
                send(.state(next))
            }
        case .action(let action, let playerID):
            guard host, var next = state, let who = next.players.firstIndex(where: { $0.id == playerID }) else { return }
            let before = next.techs.count
            if next.perform(action, by: who) {
                state = next
                if next.won { GameAudio.shared.play(.win) } else if next.techs.count > before { GameAudio.shared.play(.special) }
            }
            // できなかったときも、いまの状態を送り直す（相手の画面をそろえる）
            changed()
            if let state { send(.state(state)) }
        case .state(let incoming):
            guard !host, state == nil || incoming.version >= (state?.version ?? -1) else { return }
            let before = state?.techs.count ?? incoming.techs.count
            state = incoming
            saveLocal()
            if incoming.techs.count > before { GameAudio.shared.play(.special) }
            if !incoming.players.contains(where: { $0.id == myID }) {
                status = "この文明はもう 2 人で遊んでいます"
            }
        }
    }

    // MARK: - 離れて：iCloud

    /// iCloud の最新を読み、時間を進め、ためた行動を行って保存する（ぶつかったら読み直してやり直す）
    private func syncCloud(replacing fresh: CivState? = nil) async {
        guard let cloud, !syncing else { return }
        syncing = true
        defer {
            syncing = false
            lastSync = Date()
        }
        for _ in 0..<3 {
            do {
                let remote = try await cloud.fetch()
                var next: CivState
                var dirty = false
                if let fresh {
                    next = fresh
                    next.version = (remote?.version ?? 0) + 1
                    dirty = true
                } else if let remote {
                    next = remote
                } else {
                    next = state ?? CivState.new(host: me)
                    dirty = true
                }
                if next.join(me) { dirty = true }
                let before = next.techs.count
                if next.advance(to: Date()) > 0 { dirty = true }
                let actions = pending
                if let who = next.players.firstIndex(where: { $0.id == myID }) {
                    for action in actions where next.perform(action, by: who) { dirty = true }
                }
                if dirty { try await cloud.write(next) }
                pending.removeFirst(min(actions.count, pending.count))
                if next.techs.count > before, (state?.techs.count ?? 0) < next.techs.count { GameAudio.shared.play(.special) }
                if next.won && !(state?.won ?? false) { GameAudio.shared.play(.win) }
                state = next
                partnerConnected = next.players.count > 1
                status = "iCloud と同期しています"
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                // 相手が先に保存した：読み直してやり直す
                continue
            } catch {
                status = "iCloud に送れませんでした"
                message = Self.describe(error)
                return
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated:
                return "iCloud にサインインしてください"
            case .networkUnavailable, .networkFailure:
                return "インターネットにつながっていません"
            case .permissionFailure:
                return "このアルバムに書き込む許可がありません"
            default:
                break
            }
        }
        return "iCloud に保存できませんでした。CloudKit Console で「CivGame」の Deploy がまだかもしれません（\(error.localizedDescription)）"
    }
}

// MARK: - 近く（MultipeerConnectivity）

/// 近くの iPhone と直接つなぐ。作る人は待ち受け（advertiser）、参加する人は探して（browser）招待を送る
final class CivNearby: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate,
    @unchecked Sendable {
    private let service: String

    private let peer: MCPeerID
    private let session: MCSession
    private let host: Bool
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// メインスレッドで呼ぶ
    var onReceive: (@MainActor (Data) -> Void)?
    var onPeers: (@MainActor (Int) -> Void)?

    /// service は Info.plist の NSBonjourServices に書いた名前（_名前._tcp）
    init(name: String, host: Bool, service: String = "filmciv") {
        self.service = service
        peer = MCPeerID(displayName: String(name.prefix(30)))
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        self.host = host
        super.init()
        session.delegate = self
    }

    func start() {
        if host {
            let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: service)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        } else {
            let browser = MCNearbyServiceBrowser(peer: peer, serviceType: service)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        }
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    func send(_ data: Data, reliable: Bool = true) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(session.connectedPeers.isEmpty, session)
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard session.connectedPeers.isEmpty else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard state != .connecting else { return }
        let count = session.connectedPeers.count
        let handler = onPeers
        Task { @MainActor in handler?(count) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let handler = onReceive
        Task { @MainActor in handler?(data) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                 with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                 at localURL: URL?, withError error: Error?) {}
}

// MARK: - 離れて（CloudKit）

/// 共有アルバムのゾーンにある「CivGame」レコードを読み書きする
@MainActor
final class CivCloud {
    static let recordType = "CivGame"
    let album: AlbumRef
    private let db: CKDatabase
    private let recordID: CKRecord.ID
    private var record: CKRecord?

    init(album: AlbumRef) {
        self.album = album
        let container = CKContainer.default()
        db = album.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        recordID = CKRecord.ID(recordName: "civ-game", zoneID: album.zoneID)
    }

    func fetch() async throws -> CivState? {
        do {
            let fetched = try await db.record(for: recordID)
            record = fetched
            return Self.decode(fetched)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// 保存する（直前に fetch したレコードに上書き）。相手が先に保存していたら serverRecordChanged を投げる
    func write(_ state: CivState) async throws {
        let target = record ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        fill(target, with: state)
        do {
            try await save(target)
        } catch let error as CKError where error.code == .zoneNotFound && album.isOwner {
            _ = try await db.modifyRecordZones(saving: [CKRecordZone(zoneID: album.zoneID)], deleting: [])
            try await save(target)
        } catch let error as CKError where error.code == .serverRecordChanged {
            record = error.serverRecord
            throw error
        }
    }

    private func save(_ target: CKRecord) async throws {
        let (results, _) = try await db.modifyRecords(saving: [target], deleting: [], savePolicy: .ifServerRecordUnchanged)
        switch results[recordID] {
        case .success(let saved)?:
            record = saved
        case .failure(let error)?:
            throw error
        case nil:
            break
        }
    }

    private func fill(_ target: CKRecord, with state: CivState) {
        target["state"] = (try? JSONEncoder().encode(state)) as CKRecordValue?
        target["version"] = state.version as CKRecordValue
        target["turnOf"] = "" as CKRecordValue
    }

    private static func decode(_ record: CKRecord) -> CivState? {
        guard let data = record["state"] as? Data else { return nil }
        return try? JSONDecoder().decode(CivState.self, from: data)
    }
}
