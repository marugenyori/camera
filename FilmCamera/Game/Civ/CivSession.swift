import CloudKit
import MultipeerConnectivity
import SwiftUI

/// 「ふたりの文明」の同期。遊び方は 3 つ：
/// - ひとりで：この端末だけ（UserDefaults に保存）
/// - 近くで：2 台の iPhone を Wi-Fi・Bluetooth で直接つなぐ（MultipeerConnectivity）。作る人が待ち受け、参加する人が探して入る。
///   変わるたびに状態をまるごと送り、version が大きいほうを使う
/// - 離れて：共有アルバムのゾーンに「CivGame」レコード（state＝状態の JSON、turnOf＝番の人、version）を 1 つ置く。
///   番が終わると保存し、相手は数秒おきに読み直す（アプリを閉じていても、番が来たら通知が届く）
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
    private var pollTask: Task<Void, Never>?
    private var saving: Task<Void, Never>?

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

    var isMyTurn: Bool {
        guard let state, state.players.indices.contains(state.current) else { return false }
        return state.players[state.current].id == myID
    }

    var currentName: String {
        guard let state, state.players.indices.contains(state.current) else { return "" }
        return state.players[state.current].name
    }

    // MARK: - 始める・やめる

    func start() async {
        switch mode {
        case .solo:
            state = loadLocal("civSolo") ?? CivState.new(host: me)
            status = "ひとりで遊んでいます"
            saveLocal()
        case .nearbyHost:
            if let saved = loadLocal("civNearby"), saved.players.first?.id == myID {
                state = saved
            } else {
                state = CivState.new(host: me)
            }
            saveLocal()
            startNearby(host: true)
            status = "相手を待っています（相手は「参加する」を押してください）"
        case .nearbyJoin:
            startNearby(host: false)
            status = "近くの文明をさがしています"
        case .cloud(let album):
            status = "iCloud から読み込んでいます"
            if let id = try? await CKContainer.default().userRecordID().recordName { myID = id }
            let cloud = CivCloud(album: album)
            self.cloud = cloud
            do {
                if var remote = try await cloud.fetch() {
                    if remote.join(me) {
                        try await cloud.save(remote)
                    }
                    state = remote
                } else {
                    let fresh = CivState.new(host: me)
                    try await cloud.save(fresh)
                    state = fresh
                }
                status = "iCloud と同期しています"
                startPolling()
            } catch {
                status = "iCloud に保存できませんでした"
                message = Self.describe(error)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        nearby?.stop()
        nearby = nil
    }

    /// 最初から作り直す（作った人・ひとり・離れての誰でも）
    func restart() {
        var fresh = CivState.new(host: me)
        if let old = state {
            fresh.version = old.version + 1
            // 相手はそのまま 2 人目に入れておく
            for player in old.players where player.id != myID { _ = fresh.join(player) }
        }
        commit(fresh)
    }

    // MARK: - 行動

    func act(_ action: CivState.Action) {
        guard var next = state, isMyTurn, let who = myIndex else { return }
        if next.perform(action, by: who) {
            commit(next)
            if case .research = action { GameAudio.shared.tick() } else { GameAudio.shared.play(.place) }
        } else {
            GameAudio.shared.play(.invalid)
        }
    }

    func endTurn() {
        guard var next = state, isMyTurn else { return }
        next.endTurn()
        commit(next)
        GameAudio.shared.play(.swap)
        if next.won { GameAudio.shared.play(.win) }
    }

    private func commit(_ next: CivState) {
        let learned = (state?.techs.count ?? 0) < next.techs.count
        state = next
        if learned { GameAudio.shared.play(.special) }
        switch mode {
        case .solo:
            saveLocal()
        case .nearbyHost, .nearbyJoin:
            saveLocal()
            send(.state(next))
        case .cloud:
            pushToCloud(next)
        }
    }

    // MARK: - ひとり・近く：端末に保存

    private var localKey: String { mode == .solo ? "civSolo" : "civNearby" }

    private func loadLocal(_ key: String) -> CivState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
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
    }

    private func startNearby(host: Bool) {
        let nearby = CivNearby(name: myName, host: host)
        nearby.onPeers = { [weak self] count in
            guard let self else { return }
            self.partnerConnected = count > 0
            if count > 0 {
                self.status = "相手とつながりました"
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
                commit(next)
                GameAudio.shared.play(.complete)
            } else {
                send(.state(next))
            }
        case .state(let incoming):
            if state == nil || incoming.version > (state?.version ?? -1) {
                let wasMyTurn = isMyTurn
                state = incoming
                saveLocal()
                if !host, !incoming.players.contains(where: { $0.id == myID }) {
                    status = "この文明はもう 2 人で遊んでいます"
                } else if !wasMyTurn && isMyTurn {
                    GameAudio.shared.play(.complete)
                }
            }
        }
    }

    // MARK: - 離れて：iCloud

    private func pushToCloud(_ next: CivState) {
        guard let cloud else { return }
        let previous = saving
        status = "iCloud に送っています"
        saving = Task {
            await previous?.value
            do {
                if let newer = try await cloud.save(next) {
                    // 相手のほうが新しかった：相手の状態にそろえる
                    state = newer
                    message = "相手の変更と重なったので、相手の状態にそろえました"
                }
                status = "iCloud と同期しています"
            } catch {
                status = "iCloud に送れませんでした"
                message = Self.describe(error)
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let wait = (self?.isMyTurn ?? false) ? 15.0 : 4.0
                try? await Task.sleep(for: .seconds(wait))
                guard let self, let cloud = self.cloud else { return }
                await self.saving?.value
                guard let remote = try? await cloud.fetch(), remote.version > (self.state?.version ?? -1) else { continue }
                let wasMyTurn = self.isMyTurn
                self.state = remote
                self.partnerConnected = remote.players.count > 1
                if !wasMyTurn && self.isMyTurn { GameAudio.shared.play(.complete) }
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
    static let service = "filmciv"

    private let peer: MCPeerID
    private let session: MCSession
    private let host: Bool
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// メインスレッドで呼ぶ
    var onReceive: (@MainActor (Data) -> Void)?
    var onPeers: (@MainActor (Int) -> Void)?

    init(name: String, host: Bool) {
        peer = MCPeerID(displayName: String(name.prefix(30)))
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        self.host = host
        super.init()
        session.delegate = self
    }

    func start() {
        if host {
            let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: Self.service)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        } else {
            let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
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

    func send(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
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

    /// 保存する。相手のほうが新しい状態を持っていたら、その状態を返す（保存はしない）
    @discardableResult
    func save(_ state: CivState) async throws -> CivState? {
        let target = record ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        fill(target, with: state)
        do {
            try await write(target)
            return nil
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let server = error.serverRecord else { throw error }
            record = server
            if let theirs = Self.decode(server), theirs.version >= state.version { return theirs }
            fill(server, with: state)
            try await write(server)
            return nil
        } catch let error as CKError where error.code == .zoneNotFound && album.isOwner {
            _ = try await db.modifyRecordZones(saving: [CKRecordZone(zoneID: album.zoneID)], deleting: [])
            try await write(target)
            return nil
        }
    }

    private func write(_ target: CKRecord) async throws {
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
        let turnOf = state.players.indices.contains(state.current) ? state.players[state.current].id : ""
        target["turnOf"] = turnOf as CKRecordValue
    }

    private static func decode(_ record: CKRecord) -> CivState? {
        guard let data = record["state"] as? Data else { return nil }
        return try? JSONDecoder().decode(CivState.self, from: data)
    }
}
