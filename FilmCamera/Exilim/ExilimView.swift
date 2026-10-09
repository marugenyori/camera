import Photos
import SwiftUI

/// EXILIM（EX-FR100 など）と Wi-Fi で直接つなぐ画面。
/// - リモート撮影：カメラのライブビューを見ながら、iPhone からシャッターを切る。撮った写真をそのまま共有アルバムへ
/// - カメラの写真：カメラの中の写真を一覧で見て、選んだものを共有アルバムへ（写真アプリを通さない）
@MainActor
final class ExilimModel: ObservableObject {
    enum Phase: Equatable {
        /// カメラの Wi-Fi の名前とパスワードを入れてもらう（最初の 1 回だけ）
        case setup
        case joining
        case searching
        case notFound
        case connected(ExilimClient.Info)
    }

    enum Tab: String, CaseIterable, Identifiable {
        case remote = "リモート撮影"
        case files = "カメラの写真"
        var id: String { rawValue }
    }

    @Published var phase: Phase = .searching
    /// つなぎ始めた時刻（何秒たったかを画面に出す）
    @Published var waitingSince: Date?
    @Published var tab: Tab = .remote
    @Published var liveImage: UIImage?
    @Published var files: [ExilimClient.RemoteFile] = []
    @Published var thumbnails: [String: UIImage] = [:]
    @Published var selected: Set<String> = []
    /// いま何をしているか（くるくるの横に出す）
    @Published var busy: String?
    @Published var message: String?
    @Published var lastShot: UIImage?
    @Published var progress: (done: Int, total: Int)?
    /// 受け取って、まだ共有アルバムに送っていない枚数（閉じたら送る）
    @Published var pending = ExilimPending.count
    /// 撮ったらすぐ共有アルバムに入れる
    /// リモート撮影で撮った写真は、受け取ったらカメラから消す（カードなしでも内蔵メモリーがいっぱいにならない）
    @Published var deleteShots = UserDefaults.standard.object(forKey: "exilimDeleteShots") as? Bool ?? true {
        didSet { UserDefaults.standard.set(deleteShots, forKey: "exilimDeleteShots") }
    }
    /// 「カメラの写真」で受け取ったものを、カメラから消す
    @Published var deleteReceived = UserDefaults.standard.object(forKey: "exilimDeleteReceived") as? Bool ?? false {
        didSet { UserDefaults.standard.set(deleteReceived, forKey: "exilimDeleteReceived") }
    }
    /// もう受け取った写真（パス・大きさ・日時で見分ける）。同じ写真を二度受け取って、共有アルバムに 2 枚入らないように
    private var received = Set(UserDefaults.standard.stringArray(forKey: "exilimReceived") ?? []) {
        didSet { UserDefaults.standard.set(Array(received.suffix(2000)), forKey: "exilimReceived") }
    }

    func isReceived(_ file: ExilimClient.RemoteFile) -> Bool {
        received.contains(Self.key(file))
    }

    private static func key(_ file: ExilimClient.RemoteFile) -> String {
        "\(file.path)|\(file.size)|\(file.modified)"
    }

    /// 撮って、まだ受け取っていない枚数（何枚かたまるか、撮るのが止まったら、まとめて受け取る）
    @Published var unsaved = 0
    /// シャッターを切っている最中（ほかの操作は止めない）
    @Published var shooting = false
    /// シャッターを切った合図（画面を一瞬白くする）
    @Published var flash = 0
    enum CaptureMode: String, CaseIterable, Identifiable {
        case photo = "写真"
        case movie = "動画"
        var id: String { rawValue }
    }
    @Published var captureMode: CaptureMode = .photo
    /// 動画を撮り始めた時刻（撮っていなければ nil）
    @Published var recordingSince: Date?
    /// カメラの設定（読めなかったものは nil）
    @Published var selfTimer = 0
    @Published var ev: Int?
    @Published var whiteBalance: Int?
    @Published var battery: Int?
    @Published var capacity: Int?
    @Published var autoAdd = UserDefaults.standard.object(forKey: "exilimAutoAdd") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoAdd, forKey: "exilimAutoAdd") }
    }

    let client = ExilimClient()
    private let live = ExilimLiveView()
    private let callback = ExilimCallbackServer()
    private var livePort: UInt16 = 0
    private var heartbeat: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var switching: Task<Void, Never>?
    private var idleCollect: Task<Void, Never>?
    private var clockSynced = false

    var model: String {
        if case .connected(let info) = phase { return info.model }
        return "EXILIM"
    }

    // MARK: - つなぐ

    /// ワンタップでつなぐ：もうカメラの Wi-Fi にいればそのまま。いなければアプリが自分でカメラの Wi-Fi に入って探す
    func connect() async {
        message = nil
        phase = .searching
        // カメラからの呼びかけの受け口を、つなぐ前に開いておく（カシオのプラグインと同じ）
        if let port = callback.start() { await client.setCallbackPort(port) }
        waitingSince = Date()
        defer { waitingSince = nil }
        // カメラの Wi-Fi に入るのと、もう入っているかの確認を、同時に始める
        // （Wi-Fi の名前を登録していなければ、EX-FR100 の名前の頭 FR100- と初期のパスワードで探す）
        phase = .joining
        // async let だと、先につながったときにも Wi-Fi の切り替えが終わるまで待ってしまうので Task にする
        let joining = Task { await ExilimWiFi.join() }
        if let info = await client.find(quick: true, timeout: 0.8, silent: true) {
            connected(info)
            return
        }
        let joinError = await joining.value
        let started = waitingSince ?? Date()
        ExilimLog.shared.add(String(format: "Wi-Fi：%@（%.1f 秒）", joinError ?? "カメラの Wi-Fi に入りました",
                                    Date().timeIntervalSince(started)))
        phase = .searching
        // Wi-Fi が切り替わってカメラが答えるまで、0.3 秒おきに聞く（最大 45 秒）。
        // いつもの 192.168.100.2 だけを聞き、近くのアドレスまで探すのはときどき
        let deadline = Date().addingTimeInterval(joinError == nil ? 45 : 4)
        var round = 0
        var lastReport = Date()
        var lastWiFiCheck = Date()
        var rejoined = false
        while Date() < deadline {
            if Task.isCancelled { return }
            round += 1
            // 2 秒おきに、本当にカメラの Wi-Fi に入れたかを確かめる。
            // 10 秒たっても入れていなければ 1 回だけ入り直し、それでもだめならすぐ知らせる
            // （カメラが前の接続を覚えていて、新しい接続を断ることがある：iOS の「接続できません」）
            if joinError == nil, Date().timeIntervalSince(lastWiFiCheck) >= 2 {
                lastWiFiCheck = Date()
                let elapsed = Date().timeIntervalSince(started)
                if await ExilimWiFi.isOnCameraWiFi() == false, elapsed >= 10 {
                    if !rejoined {
                        rejoined = true
                        ExilimLog.shared.add(String(format: "Wi-Fi：まだカメラの Wi-Fi に入れていません（%.0f 秒）。入り直します", elapsed))
                        ExilimWiFi.leave()
                        try? await Task.sleep(for: .seconds(1))
                        _ = await ExilimWiFi.join()
                    } else if elapsed >= 22 {
                        ExilimLog.shared.add(String(format: "Wi-Fi：カメラの Wi-Fi に入れませんでした（%.0f 秒）", elapsed))
                        message = "カメラが Wi-Fi への接続を断りました。カメラを待ち受けにし直してから、もう一度さがしてください"
                        phase = .notFound
                        return
                    }
                }
            }
            if let info = await client.find(quick: round % 15 != 0, timeout: 0.6, silent: true) {
                ExilimLog.shared.add(String(format: "カメラが答えました（つなぎ始めから %.1f 秒）",
                                            Date().timeIntervalSince(started)))
                connected(info)
                return
            }
            // 3 秒おきに、なぜ答えないかを通信ログに書く（届いていないのか、カメラが受け付けていないのか）
            if Date().timeIntervalSince(lastReport) >= 3, let reason = await client.lastError {
                lastReport = Date()
                ExilimLog.shared.add(String(format: "まだ答えません（%.0f 秒、理由：%@）",
                                            Date().timeIntervalSince(started), reason))
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        message = joinError
        phase = .notFound
    }

    private func connected(_ info: ExilimClient.Info) {
        phase = .connected(info)
        show(tab)
    }

    /// 最初の 1 回：カメラの Wi-Fi の名前とパスワードを覚えて、つなぐ
    func saveWiFi(ssid: String, password: String) async {
        ExilimWiFi.save(ssid: ssid.trimmingCharacters(in: .whitespaces), password: password)
        await connect()
    }

    /// タブを切り替える（カメラのモードも切り替わる。前の切り替えが終わってから）
    func show(_ tab: Tab) {
        self.tab = tab
        let previous = switching
        previous?.cancel()
        switching = Task {
            await previous?.value
            // heartBeat はライブビューのときだけ（写真を見るモードでは受け付けられない。受け取り中は別に送る）
            // 撮ってまだ受け取っていない写真があれば、先に受け取る（一覧に「受け取り済み」と出るように）
            if tab == .files { await collect() }
            idleCollect?.cancel()
            heartbeat?.cancel()
            stopLive()
            thumbnailTask?.cancel()
            switch tab {
            case .remote: await startRemote()
            case .files: await loadFiles()
            }
        }
    }

    /// 閉じる：カメラとの接続を切り、いつもの Wi-Fi に戻って、受け取った写真を共有アルバムに送る
    func close() async {
        idleCollect?.cancel()
        if recordingSince != nil { await toggleMovie() }
        // 撮ってまだ受け取っていない写真を受け取ってから閉じる
        if tab == .remote { await collect(resume: false) }
        switching?.cancel()
        thumbnailTask?.cancel()
        stopLive()
        heartbeat?.cancel()
        await client.disconnect()
        callback.stop()
        ExilimWiFi.leave()
        guard ExilimPending.count > 0 else { return }
        Task { @MainActor in
            // 回線が戻るまで少し待ちながら、何度か送る（送れなかった分は次に開いたときにまた送る）
            for _ in 0..<4 {
                try? await Task.sleep(for: .seconds(4))
                await ExilimPending.flush()
                if ExilimPending.count == 0 { break }
            }
        }
    }

    /// 1 秒ごとに「まだいるよ」を送る。5 回続けて返事がなければ切れたとみなす
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            var misses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if await self.client.heartBeat() {
                    misses = 0
                } else {
                    misses += 1
                    if misses >= 5 {
                        self.stopLive()
                        self.phase = .notFound
                        self.message = "カメラとの接続が切れました"
                        return
                    }
                }
            }
        }
    }

    // MARK: - リモート撮影

    private func startRemote() async {
        busy = "ライブビューを準備しています"
        defer { busy = nil }
        do {
            try await client.switchMode(to: .liveView)
        } catch is CancellationError {
            return
        } catch {
            message = error.localizedDescription
            return
        }
        // カメラの時計を iPhone に合わせる（写真の撮影日時がずれないように。つないだら 1 回だけ）
        if !clockSynced {
            clockSynced = true
            await client.syncClock()
        }
        guard await restartLive() else { return }
        startHeartbeat()
        Task { await loadSettings() }
    }

    /// ライブビューを（もう一度）始める
    @discardableResult
    private func restartLive() async -> Bool {
        live.onFrame = { [weak self] image in self?.liveImage = image }
        guard let port = live.start() else {
            message = "ライブビューを受け取る準備ができませんでした"
            return false
        }
        livePort = port
        guard await client.startLive(port: port) else {
            message = "ライブビューを始められませんでした"
            return false
        }
        return true
    }

    private func stopLive() {
        live.stop()
        live.onFrame = nil
        liveImage = nil
    }

    /// シャッター：切ったらすぐ次が撮れるようにする。
    /// 前は、撮るたびに「小さい画像を待つ → 本体を受け取る → カメラから消す」を終えるまで約 6 秒止まっていた。
    /// いまは切った瞬間のライブビューを「いま撮った写真」として出し、受け取りと消すのは、
    /// 撮るのが止まったとき（3 秒）か 3 枚たまったときにまとめてする
    func shoot() async {
        guard !shooting, busy == nil, recordingSince == nil else { return }
        shooting = true
        defer { shooting = false }
        idleCollect?.cancel()
        let frame = liveImage
        do {
            do {
                try await client.shutterOnly()
            } catch ExilimClient.ExilimError.notReady where unsaved > 0 {
                // 内蔵メモリーがいっぱい：たまっている写真を受け取って消してから、もう一度
                await collect()
                try await client.shutterOnly()
            }
            flash += 1
            if let frame { lastShot = frame }
            unsaved += 1
            scheduleCollect()
        } catch {
            message = error.localizedDescription
        }
    }

    /// 撮るのが止まったら、まとめて受け取る（セルフタイマーのときは、写真ができるまで待ってから）
    private func scheduleCollect() {
        idleCollect?.cancel()
        guard autoAdd else { return }
        let delay = Double(selfTimer) + (unsaved >= 3 ? 1.5 : 3)
        idleCollect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.collect()
        }
    }

    /// 撮ってまだ受け取っていない写真を、まとめて受け取る（写真を見るモードに切り替えて、新しいほうから）。
    /// 「受け取ったらカメラから消す」がオンなら、受け取ったものはカメラから消す
    func collect(resume: Bool = true) async {
        guard unsaved > 0, busy == nil, case .connected(let info) = phase else { return }
        busy = "写真を受け取っています"
        defer { busy = nil }
        let count = unsaved
        // 最後の 1 枚ができあがるまで待つ
        await client.waitLatestImage(limit: Double(selfTimer) + 6)
        // 写真を見るモードでは heartBeat を受け付けないので止める
        heartbeat?.cancel()
        await client.endLive()
        var got = 0
        var deleted = 0
        do {
            try await client.switchMode(to: .webServer)
            let photos = await client.latestPhotos(count, apiVersion: info.apiVersion)
            for file in photos.reversed() {
                if !isReceived(file) {
                    let data = try await client.download(file.path)
                    add(data, thumbnail: nil)
                    received.insert(Self.key(file))
                    got += 1
                    if file.path == photos.first?.path,
                       let image = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 240, height: 240)) {
                        lastShot = image
                    }
                }
                if deleteShots, await client.delete(file.path) { deleted += 1 }
            }
            unsaved = 0
            if got == 0 && deleted == 0 {
                message = "新しい写真が見つかりませんでした"
            } else {
                message = deleted > 0
                    ? "\(got) 枚受け取って、カメラからは消しました（閉じると共有アルバムに送ります）"
                    : "\(got) 枚受け取りました（閉じると共有アルバムに送ります）"
            }
        } catch {
            message = error.localizedDescription
        }
        guard resume, tab == .remote else { return }
        do {
            try await client.switchMode(to: .liveView)
            if await self.restartLive() { startHeartbeat() }
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - 動画

    /// 動画を撮り始める・止める（動画はカメラに残る。「カメラの写真」タブで受け取れる）
    func toggleMovie() async {
        if recordingSince != nil {
            if await client.stopMovie() {
                message = "動画はカメラに保存しました（「カメラの写真」で受け取れます）"
            } else {
                message = "動画を止められませんでした"
            }
            recordingSince = nil
            return
        }
        guard busy == nil else { return }
        idleCollect?.cancel()
        if await client.startMovie() {
            recordingSince = Date()
        } else {
            message = "動画を撮り始められませんでした（内蔵メモリーだけだと、動画はほとんど入りません）"
        }
    }

    // MARK: - カメラの設定

    /// 設定の読み書きは、ライブビューを止めてからでないとカメラが 405 で断る（実機のログ）。
    /// カシオのプラグインも endLive → getParam・setParam → startLive の順にしている
    private func withLivePaused<T>(_ body: () async -> T) async -> T {
        await client.endLive()
        let result = await body()
        if tab == .remote, livePort != 0 { _ = await client.startLive(port: livePort) }
        return result
    }

    func loadSettings() async {
        guard busy == nil else { return }
        await withLivePaused {
            selfTimer = await client.getParam(.selfTimer) ?? selfTimer
            ev = await client.getParam(.ev)
            whiteBalance = await client.getParam(.whiteBalance)
            battery = await client.getParam(.battery)
            capacity = await client.getParam(.snapCapacity)
        }
    }

    func loadBattery() async {
        guard busy == nil else { return }
        await withLivePaused {
            battery = await client.getParam(.battery)
            capacity = await client.getParam(.snapCapacity)
        }
    }

    func set(_ param: ExilimClient.Param, _ value: Int) {
        Task {
            guard busy == nil else { return }
            let ok = await withLivePaused { await client.setParam(param, value) }
            if ok {
                switch param {
                case .selfTimer: selfTimer = value
                case .ev: ev = value
                case .whiteBalance: whiteBalance = value
                default: break
                }
            } else {
                message = "カメラの設定を変えられませんでした"
            }
        }
    }

    // MARK: - カメラの写真

    private func loadFiles() async {
        busy = "カメラの写真を読み込んでいます"
        defer { busy = nil }
        do {
            files = try await client.list()
            selected = selected.filter { path in files.contains { $0.path == path } }
            loadThumbnails()
        } catch is CancellationError {
            return
        } catch {
            message = error.localizedDescription
        }
    }

    /// サムネイルは 1 枚ずつ順に（カメラに一度にたくさん頼まない）
    private func loadThumbnails() {
        thumbnailTask?.cancel()
        let targets = files.filter { thumbnails[$0.path] == nil }
        thumbnailTask = Task { [weak self] in
            for file in targets {
                guard let self, !Task.isCancelled else { return }
                if let image = await self.client.thumbnail(of: file.path) {
                    self.thumbnails[file.path] = image
                }
            }
        }
    }

    func toggle(_ file: ExilimClient.RemoteFile) {
        if selected.contains(file.path) { selected.remove(file.path) } else { selected.insert(file.path) }
    }

    /// 選んだ写真を、元の画質のまま受け取って共有アルバムに入れる
    func addSelected() async {
        let targets = files.filter { selected.contains($0.path) }
        guard !targets.isEmpty, busy == nil else { return }
        thumbnailTask?.cancel()
        busy = "写真を受け取っています"
        progress = (0, targets.count)
        var failed = 0
        var photos = 0
        var videos = 0
        for file in targets {
            do {
                // もう受け取った写真は受け取り直さない（「消す」がオンなら、カメラから消すだけ）
                if !isReceived(file) {
                    if file.isVideo {
                        // 動画は写真アプリに保存する（共有アルバムは写真だけ）
                        let url = try await client.downloadFile(file.path)
                        defer { try? FileManager.default.removeItem(at: url) }
                        try await Self.saveVideoToLibrary(url)
                        videos += 1
                    } else {
                        let data = try await client.download(file.path)
                        add(data, thumbnail: thumbnails[file.path])
                        photos += 1
                    }
                    received.insert(Self.key(file))
                }
                selected.remove(file.path)
                // 受け取って端末に置けたものだけ、カメラから消す
                if deleteReceived, await client.delete(file.path) {
                    files.removeAll { $0.path == file.path }
                    thumbnails[file.path] = nil
                }
            } catch {
                failed += 1
            }
            progress = ((progress?.done ?? 0) + 1, targets.count)
        }
        progress = nil
        busy = nil
        var parts: [String] = []
        if photos > 0 { parts.append("写真 \(photos) 枚は閉じると共有アルバムに送ります") }
        if videos > 0 { parts.append("動画 \(videos) 本は写真アプリに保存しました") }
        if failed > 0 { parts.append("\(failed) 件は受け取れませんでした") }
        message = parts.isEmpty ? "受け取りました" : parts.joined(separator: "。")
        loadThumbnails()
    }

    /// 動画を写真アプリに保存する（写真アプリへの追加の許可は、はじめてのときにたずねられる）
    private static func saveVideoToLibrary(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExilimClient.ExilimError.downloadFailed }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
        }
    }

    /// カメラの Wi-Fi ではインターネットに出られないので、いったん端末に置く（閉じたら送る）
    private func add(_ data: Data, thumbnail: UIImage?) {
        ExilimPending.keep(data, mode: model)
        pending = ExilimPending.count
    }
}

/// EXILIM とつなぐ画面。撮影画面と同じ teenage engineering 風の見た目：
/// アルミ色の筐体に黒い表示窓、ライブビューを大きくはめ込み、下に機能キーと大きな丸いシャッター、オレンジの差し色
struct ExilimView: View {
    @StateObject private var model = ExilimModel()
    @State private var showingLog = false
    @State private var showingSettings = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Rig.body.ignoresSafeArea()
                switch model.phase {
                case .searching, .joining:
                    searching
                case .setup:
                    ExilimWiFiSetup { ssid, password in
                        Task { await model.saveWiFi(ssid: ssid, password: password) }
                    }
                case .notFound:
                    guide
                case .connected(let info):
                    connected(info)
                }
            }
            .navigationTitle("EXILIM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Rig.body, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        Task {
                            await model.close()
                            dismiss()
                        }
                    }
                    .foregroundStyle(Rig.ink)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if case .connected = model.phase {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("設定")
                    }
                    Button {
                        showingLog = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("通信ログ")
                }
            }
            .tint(Rig.ink)
            .overlay(alignment: .bottom) { toast }
            .sheet(isPresented: $showingLog) { ExilimLogView() }
            .sheet(isPresented: $showingSettings) {
                ExilimSettingsSheet(model: model) {
                    showingSettings = false
                    model.phase = .setup
                }
                .presentationDetents([.medium, .large])
            }
        }
        .preferredColorScheme(.light)
        .task { await model.connect() }
    }

    // MARK: さがしている

    private var searching: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Rig.display).frame(width: 96, height: 96)
                Image(systemName: model.phase == .joining ? "wifi" : "camera.aperture")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse)
            }
            Text(model.phase == .joining ? "カメラの Wi-Fi につないでいます" : "カメラをさがしています")
                .font(.headline)
                .foregroundStyle(Rig.ink)
            if let since = model.waitingSince {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSince(since))
                    VStack(spacing: 12) {
                        Text(String(format: "%02d 秒", seconds))
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Rig.display))
                        Text("カメラの Wi-Fi が立ち上がるまで 10〜20 秒かかります")
                            .font(.caption)
                            .foregroundStyle(Rig.print)
                        if seconds >= 15 {
                            Text("カメラの青いランプが消えていたら、もう一度待ち受けにしてください（電源を切ってから、ムービーボタンを押したまま電源ボタンを約 1 秒）")
                                .font(.caption)
                                .foregroundStyle(Rig.ink)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Rig.key))
                                .padding(.horizontal, 24)
                        }
                    }
                    .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: つなぎ方

    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Rig.display).frame(width: 72, height: 72)
                        Image(systemName: "camera.on.rectangle")
                            .font(.title)
                            .foregroundStyle(.tint)
                    }
                    Text("カメラが見つかりませんでした")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Rig.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "カメラ部の電源ボタンを約 2 秒押して、いったん電源を切ります。")
                    step(2, "ムービーボタンを押したまま、電源ボタンを約 1 秒押します。カメラの無線 LAN のランプが青く点滅したら、待ち受けの状態です（コントローラーからは「無線モード」→「スマートフォンで撮影」→「開始」でも同じ）。")
                    step(3, "下の「もう一度さがす」を押します。パスワードを 00000000 から変えている場合や、FR100 以外のカメラは「Wi-Fi の設定を変える」で名前とパスワードを入れてください。")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rig.key))
                Text("はじめて使うときは「ローカルネットワーク上のデバイスの検索」の許可をたずねられます。「許可」を選んでください。EXILIM Connect などほかのアプリがカメラとつながっていると、つなげないことがあります。")
                    .font(.footnote)
                    .foregroundStyle(Rig.print)
                Button {
                    Task { await model.connect() }
                } label: {
                    Label("もう一度さがす", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Rig.display))
                }
                .buttonStyle(.plain)
                Button("Wi-Fi の設定を変える") {
                    model.phase = .setup
                }
                .font(.callout)
                .foregroundStyle(Rig.ink)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.tint))
                .foregroundStyle(.white)
            Text(text)
                .font(.callout)
                .foregroundStyle(Rig.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: つながった

    private func connected(_ info: ExilimClient.Info) -> some View {
        VStack(spacing: 10) {
            displayWindow(info)
            TabSwitch(tab: model.tab) { model.show($0) }
            switch model.tab {
            case .remote: remote
            case .files: cameraFiles
            }
        }
        .padding(.top, 6)
    }

    /// 上の黒い表示窓：機種名・いまの動き・電池・あと何枚
    private func displayWindow(_ info: ExilimClient.Info) -> some View {
        HStack(spacing: 10) {
            Circle().fill(.green).frame(width: 7, height: 7)
            Text(info.model)
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            if let busy = model.busy {
                ProgressView().controlSize(.mini).tint(.white)
                Text(busy)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                if model.pending > 0 {
                    Label("\(model.pending)", systemImage: "tray.and.arrow.up")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("閉じると共有アルバムに送る写真 \(model.pending) 枚")
                }
                if let capacity = model.capacity {
                    Text("残 \(capacity)")
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityLabel("あと \(capacity) 枚撮れます")
                }
                if let battery = model.battery {
                    Image(systemName: Self.batterySymbol(battery))
                        .foregroundStyle(battery <= 1 ? Color.red : Color.white.opacity(0.8))
                        .accessibilityLabel("電池 \(Self.batteryLabels[safe: battery] ?? "")")
                }
            }
        }
        .font(.caption.weight(.semibold).monospaced())
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(Rig.display))
        .padding(.horizontal, 12)
    }

    private static let evLabels = ["-2.0", "-1.7", "-1.3", "-1.0", "-0.7", "-0.3", "±0",
                                   "+0.3", "+0.7", "+1.0", "+1.3", "+1.7", "+2.0"]
    private static let whiteBalanceLabels = ["オート", "太陽光", "曇天", "日陰", "昼白色蛍光灯", "昼光色蛍光灯", "電球"]
    private static let whiteBalanceSymbols = ["a.circle", "sun.max", "cloud", "building", "lightbulb.led",
                                              "lightbulb.led.wide", "lightbulb"]
    static let batteryLabels = ["わずか", "30%", "50%", "60%", "99%", "満タン"]

    private static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ...1: return "battery.25"
        case 2...3: return "battery.50"
        case 4: return "battery.75"
        default: return "battery.100"
        }
    }

    // MARK: リモート撮影

    private var remote: some View {
        VStack(spacing: 10) {
            liveView
            HStack(spacing: 8) {
                keyMenu(symbol: "timer",
                        value: model.selfTimer == 0 ? "切" : "\(model.selfTimer)秒",
                        lit: model.selfTimer > 0, label: "セルフタイマー") {
                    Picker("セルフタイマー", selection: Binding(get: { model.selfTimer },
                                                          set: { model.set(.selfTimer, $0) })) {
                        Text("切").tag(0)
                        Text("5 秒").tag(5)
                        Text("10 秒").tag(10)
                    }
                }
                keyMenu(symbol: "plusminus.circle",
                        value: model.ev.flatMap { Self.evLabels[safe: $0 - 1] } ?? "±0",
                        lit: (model.ev ?? 7) != 7, label: "露出補正") {
                    Picker("露出補正", selection: Binding(get: { model.ev ?? 7 }, set: { model.set(.ev, $0) })) {
                        ForEach(Array(Self.evLabels.enumerated().reversed()), id: \.offset) { index, label in
                            Text(label).tag(index + 1)
                        }
                    }
                }
                keyMenu(symbol: model.whiteBalance.flatMap { Self.whiteBalanceSymbols[safe: $0 - 1] } ?? "a.circle",
                        value: model.whiteBalance.flatMap { Self.whiteBalanceLabels[safe: $0 - 1] } ?? "オート",
                        lit: (model.whiteBalance ?? 1) != 1, label: "ホワイトバランス") {
                    Picker("ホワイトバランス", selection: Binding(get: { model.whiteBalance ?? 1 },
                                                           set: { model.set(.whiteBalance, $0) })) {
                        ForEach(Array(Self.whiteBalanceLabels.enumerated()), id: \.offset) { index, label in
                            Label(label, systemImage: Self.whiteBalanceSymbols[index]).tag(index + 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
            HStack {
                lastShotButton
                    .frame(width: 104, alignment: .leading)
                Spacer()
                shutterButton
                Spacer()
                ExilimKindSwitch(mode: model.captureMode) { mode in
                    withAnimation(.snappy(duration: 0.25)) { model.captureMode = mode }
                }
                .disabled(model.recordingSince != nil || model.busy != nil)
                .frame(width: 104, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.flash)
    }

    private var liveView: some View {
        ZStack {
            Rig.display
            if let image = model.liveImage {
                // カメラが送ってくるライブビューは 320×240（カメラ側で決まっている）。拡大するときになめらかにする
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.title2)
                    Text("ライブビューを待っています")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            FlashView(trigger: model.flash)
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let since = model.recordingSince {
                TimelineView(.periodic(from: since, by: 0.5)) { context in
                    let seconds = Int(context.date.timeIntervalSince(since))
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text(String(format: "REC %02d:%02d", seconds / 60, seconds % 60))
                    }
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.6)))
                }
                .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.selfTimer > 0 && model.recordingSince == nil {
                Label("\(model.selfTimer)", systemImage: "timer")
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(10)
            }
        }
        .overlay(alignment: .bottom) {
            if model.busy == "写真を受け取っています" {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("写真を受け取っています")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.65)))
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .task(id: model.tab) {
            // 電池とあと何枚かは、ときどき読み直す
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if model.recordingSince == nil { await model.loadBattery() }
            }
        }
    }

    /// いま撮った写真。数字はまだ受け取っていない枚数（押すとすぐ受け取る）
    private var lastShotButton: some View {
        Button {
            Task { await model.collect() }
        } label: {
            Group {
                if let shot = model.lastShot {
                    Image(uiImage: shot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rig.display
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Rig.ink.opacity(0.25), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if model.unsaved > 0 {
                    Text("\(model.unsaved)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(.tint))
                        .offset(x: 7, y: -7)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busy != nil || model.unsaved == 0)
        .accessibilityLabel(model.unsaved > 0 ? "まだ受け取っていない \(model.unsaved) 枚をいま受け取る" : "いま撮った写真")
    }

    private var shutterButton: some View {
        Button {
            Task {
                if model.captureMode == .movie {
                    await model.toggleMovie()
                } else {
                    await model.shoot()
                }
            }
        } label: {
            EmptyView()
        }
        .buttonStyle(ExilimShutterStyle(isMovie: model.captureMode == .movie,
                                        isRecording: model.recordingSince != nil,
                                        isBusy: model.shooting))
        .disabled(model.busy != nil || (model.shooting && model.captureMode == .photo))
        .accessibilityLabel(model.captureMode == .movie
                            ? (model.recordingSince != nil ? "動画を止める" : "動画を撮る")
                            : "シャッター")
    }

    /// 機能キー：アイコンと今の値。押すと選べる（値が初期値でなければランプが光る）
    private func keyMenu<Content: View>(symbol: String, value: String, lit: Bool, label: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                    Text(value)
                        .font(.caption2.weight(.bold).monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(Rig.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                Circle()
                    .fill(lit ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Rig.print.opacity(0.3)))
                    .frame(width: 5, height: 5)
                    .padding(6)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Rig.key)
                    .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 2)
            )
        }
        .disabled(model.busy != nil || model.recordingSince != nil)
        .opacity(model.busy != nil || model.recordingSince != nil ? 0.5 : 1)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    // MARK: カメラの写真

    private var cameraFiles: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                if model.files.isEmpty && model.busy == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                        Text("カメラの中に写真がありません")
                            .font(.callout)
                    }
                    .foregroundStyle(Rig.print)
                    .padding(.top, 80)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(model.files) { file in
                        fileCell(file)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 100)
            }
            if !model.selected.isEmpty || model.progress != nil {
                Button {
                    Task { await model.addSelected() }
                } label: {
                    HStack(spacing: 10) {
                        if let progress = model.progress {
                            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                                .tint(.white)
                                .frame(width: 60)
                            Text("受け取っています \(progress.done) / \(progress.total)")
                        } else {
                            Image(systemName: "square.and.arrow.down")
                            Text("選んだ \(model.selected.count) 件を受け取る")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Rig.display))
                }
                .buttonStyle(.plain)
                .disabled(model.progress != nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func fileCell(_ file: ExilimClient.RemoteFile) -> some View {
        let isSelected = model.selected.contains(file.path)
        return Button {
            model.toggle(file)
        } label: {
            Rig.display
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = model.thumbnails[file.path] {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if file.isVideo {
                        Image(systemName: "video.fill")
                            .font(.caption)
                            .padding(6)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .tint)
                            .padding(5)
                    } else if model.isReceived(file) {
                        // もう受け取った写真
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.white, .green)
                            .padding(5)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.tint, lineWidth: 3)
                    }
                }
                .scaleEffect(isSelected ? 0.94 : 1)
                .animation(.snappy(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(file.fileName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var toast: some View {
        if let message = model.message {
            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Rig.display.opacity(0.92)))
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
                .transition(.opacity)
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(3))
                    if model.message == message { model.message = nil }
                }
        }
    }
}

// MARK: - 見た目の部品（撮影画面 ContentView の筐体と同じ色）

private enum Rig {
    static let body = Color(red: 0xDD / 255, green: 0xDC / 255, blue: 0xD7 / 255)
    static let key = Color(red: 0xF5 / 255, green: 0xF4 / 255, blue: 0xF0 / 255)
    static let ink = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255)
    /// 筐体に印刷された小さな文字
    static let print = Color(red: 0x76 / 255, green: 0x75 / 255, blue: 0x6F / 255)
    static let display = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
}

/// リモート撮影／カメラの写真の切り替え（黒い窓にオレンジの札）
private struct TabSwitch: View {
    let tab: ExilimModel.Tab
    let onChange: (ExilimModel.Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ExilimModel.Tab.allCases) { item in
                let selected = item == tab
                Button {
                    onChange(item)
                } label: {
                    Label(item.rawValue, systemImage: item == .remote ? "camera.viewfinder" : "photo.stack")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if selected { Capsule().fill(.tint) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Rig.display))
        .padding(.horizontal, 12)
        .animation(.snappy(duration: 0.2), value: tab)
    }
}

/// 写真／動画のスライドスイッチ（撮影画面と同じ形）
private struct ExilimKindSwitch: View {
    let mode: ExilimModel.CaptureMode
    let onChange: (ExilimModel.CaptureMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("camera.fill", .photo)
            segment("video.fill", .movie)
        }
        .padding(3)
        .background(Capsule().fill(Rig.display))
    }

    private func segment(_ systemImage: String, _ value: ExilimModel.CaptureMode) -> some View {
        let selected = mode == value
        return Button {
            onChange(value)
        } label: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
                .frame(width: 46, height: 38)
                .background {
                    if selected {
                        Capsule().fill(value == .movie ? AnyShapeStyle(Color.red) : AnyShapeStyle(TintShapeStyle()))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.rawValue)
    }
}

/// シャッター：黒い縁の大きな丸いキー（動画は赤、撮影中は中に白い四角）
private struct ExilimShutterStyle: ButtonStyle {
    let isMovie: Bool
    let isRecording: Bool
    let isBusy: Bool

    func makeBody(configuration: Configuration) -> some View {
        ShutterKey(pressed: configuration.isPressed, isMovie: isMovie, isRecording: isRecording, isBusy: isBusy)
    }

    private struct ShutterKey: View {
        let pressed: Bool
        let isMovie: Bool
        let isRecording: Bool
        let isBusy: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            ZStack {
                Circle()
                    .fill(Rig.ink)
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(isMovie ? AnyShapeStyle(Color.red) : AnyShapeStyle(Rig.key))
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(pressed ? 0 : 0.35), radius: 0, x: 0, y: pressed ? 0 : 3)
                    .offset(y: pressed ? 3 : 0)
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.white)
                            .frame(width: 24, height: 24)
                    } else if isBusy {
                        ProgressView().tint(isMovie ? .white : Rig.ink)
                    } else if !isMovie {
                        Circle()
                            .fill(.tint)
                            .frame(width: 10, height: 10)
                    }
                }
                .offset(y: pressed ? 3 : 0)
            }
            .opacity(isEnabled || isBusy ? 1 : 0.45)
            .animation(.snappy(duration: 0.1), value: pressed)
            .animation(.snappy(duration: 0.25), value: isRecording)
            .animation(.snappy(duration: 0.25), value: isMovie)
        }
    }
}

/// 設定（右上の歯車）：受け取り方・消し方と、カメラの状態
private struct ExilimSettingsSheet: View {
    @ObservedObject var model: ExilimModel
    var onChangeWiFi: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("撮った写真を受け取る", isOn: $model.autoAdd)
                    Toggle("受け取ったらカメラから消す", isOn: $model.deleteShots)
                } header: {
                    Text("リモート撮影")
                } footer: {
                    Text("撮るのが止まったときにまとめて受け取ります。消すと、メモリーカードがなくても内蔵メモリーがいっぱいにならずに撮り続けられます。受け取った写真は、閉じると共有アルバムに送ります。")
                }
                Section {
                    Toggle("受け取ったらカメラから消す", isOn: $model.deleteReceived)
                } header: {
                    Text("カメラの写真")
                }
                if model.battery != nil || model.capacity != nil {
                    Section("カメラ") {
                        if let battery = model.battery {
                            LabeledContent("電池", value: ExilimView.batteryLabels[safe: battery] ?? "—")
                        }
                        if let capacity = model.capacity {
                            LabeledContent("あと撮れる枚数", value: "\(capacity) 枚")
                        }
                    }
                }
                Section {
                    Button("Wi-Fi の設定を変える", action: onChangeWiFi)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

/// シャッターを切ったとき、ライブビューを一瞬白くする
private struct FlashView: View {
    let trigger: Int
    @State private var opacity = 0.0

    var body: some View {
        Color.white
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: trigger) {
                opacity = 0.8
                withAnimation(.easeOut(duration: 0.35)) { opacity = 0 }
            }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// 最初の 1 回だけ：カメラの Wi-Fi の名前とパスワードを入れてもらう
private struct ExilimWiFiSetup: View {
    var onSave: (String, String) -> Void
    @State private var ssid = ExilimWiFi.ssid ?? ""
    @State private var password = ExilimWiFi.password ?? ""

    var body: some View {
        Form {
            Section {
                TextField("Wi-Fi の名前（例：EX-FR100_xxxx）", text: $ssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("パスワード", text: $password)
            } header: {
                Text("カメラの Wi-Fi")
            } footer: {
                Text("カメラに付いていた紙か取扱説明書に書いてあります。最初の 1 回だけ入れれば、次からはボタンひとつでつながります（パスワードはこの iPhone のキーチェーンに保存）。")
            }
            Section {
                Button {
                    onSave(ssid, password)
                } label: {
                    Text("保存してつなぐ")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(ssid.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// カメラとのやりとりの記録。うまくいかないとき、ここをコピーして送ってもらうと原因が分かる（パスワードは入っていない）
private struct ExilimLogView: View {
    @ObservedObject private var log = ExilimLog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(log.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .onAppear { proxy.scrollTo(log.lines.count - 1, anchor: .bottom) }
            }
            .navigationTitle("通信ログ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(copied ? "コピーしました" : "全部コピー") {
                        UIPasteboard.general.string = log.lines.joined(separator: "\n")
                        copied = true
                    }
                }
            }
        }
    }
}
