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

    /// いま撮った写真を、もう受け取ったか（消したあとに latest.jpg を頼むと前の写真が来るので、二度は受け取らない）
    @Published var lastShotReceived = false
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
        while Date() < deadline {
            if Task.isCancelled { return }
            round += 1
            if let info = await client.find(quick: round % 15 != 0, timeout: 0.6, silent: true) {
                ExilimLog.shared.add(String(format: "カメラが答えました（つなぎ始めから %.1f 秒）",
                                            Date().timeIntervalSince(started)))
                connected(info)
                return
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
        live.onFrame = { [weak self] image in self?.liveImage = image }
        guard let port = live.start() else {
            message = "ライブビューを受け取る準備ができませんでした"
            return
        }
        livePort = port
        guard await client.startLive(port: port) else {
            message = "ライブビューを始められませんでした"
            return
        }
        startHeartbeat()
    }

    private func stopLive() {
        live.stop()
        live.onFrame = nil
        liveImage = nil
    }

    func shoot() async {
        guard busy == nil else { return }
        busy = "撮影しています"
        defer { busy = nil }
        do {
            try await client.shutter()
            lastShot = await client.waitLatestThumbnail()
            lastShotReceived = false
            if autoAdd { await addLatest() }
        } catch {
            message = error.localizedDescription
        }
    }

    /// いま撮った写真を共有アルバムに入れる
    func addLatest() async {
        guard !lastShotReceived else { return }
        busy = "写真を受け取っています"
        do {
            let data = try await client.latestImage(livePort: livePort)
            add(data, thumbnail: lastShot)
            lastShotReceived = true
            message = "受け取りました（閉じると共有アルバムに送ります）"
            // 受け取って端末に置けたものだけ、カメラから消す
            if deleteShots, case .connected(let info) = phase {
                busy = "カメラの内蔵メモリーをあけています"
                if await client.deleteLatestShot(apiVersion: info.apiVersion, livePort: livePort) {
                    message = "受け取って、カメラからは消しました（閉じると共有アルバムに送ります）"
                }
            }
        } catch {
            message = error.localizedDescription
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

struct ExilimView: View {
    @StateObject private var model = ExilimModel()
    @State private var showingLog = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                switch model.phase {
                case .searching, .joining:
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text(model.phase == .joining ? "カメラの Wi-Fi につないでいます" : "カメラをさがしています")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let since = model.waitingSince {
                            TimelineView(.periodic(from: since, by: 1)) { context in
                                let seconds = Int(context.date.timeIntervalSince(since))
                                VStack(spacing: 10) {
                                    Text("\(seconds) 秒（カメラの Wi-Fi が立ち上がるまで 10〜20 秒かかります）")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    if seconds >= 15 {
                                        Text("カメラの青いランプが消えていたら、もう一度待ち受けにしてください（電源を切ってから、ムービーボタンを押したまま電源ボタンを約 1 秒）")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 24)
                                    }
                                }
                                .multilineTextAlignment(.center)
                            }
                        }
                    }
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
            .navigationTitle("EXILIM とつなぐ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        Task {
                            await model.close()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingLog = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("通信ログ")
                }
            }
            .overlay(alignment: .bottom) { toast }
            .sheet(isPresented: $showingLog) { ExilimLogView() }
        }
        .preferredColorScheme(.dark)
        .task { await model.connect() }
    }

    // MARK: つなぎ方

    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "camera.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                Text("カメラが見つかりませんでした")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "カメラ部の電源ボタンを約 2 秒押して、いったん電源を切ります。")
                    step(2, "ムービーボタンを押したまま、電源ボタンを約 1 秒押します。カメラの無線 LAN のランプが青く点滅したら、待ち受けの状態です（コントローラーからは「無線モード」→「スマートフォンで撮影」→「開始」でも同じ）。")
                    step(3, "下の「もう一度さがす」を押します。パスワードを 00000000 から変えている場合や、FR100 以外のカメラは「Wi-Fi の設定を変える」で名前とパスワードを入れてください。")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
                Text("はじめて使うときは「ローカルネットワーク上のデバイスの検索」の許可をたずねられます。「許可」を選んでください。EXILIM Connect などほかのアプリがカメラとつながっていると、つなげないことがあります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await model.connect() }
                } label: {
                    Label("もう一度さがす", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                Button("Wi-Fi の設定を変える") {
                    model.phase = .setup
                }
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
                .foregroundStyle(.black)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: つながった

    private func connected(_ info: ExilimClient.Info) -> some View {
        VStack(spacing: 12) {
            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text(info.model)
                    .font(.headline)
                Text("とつながっています")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let busy = model.busy {
                    ProgressView().controlSize(.small)
                    Text(busy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)
            Picker("表示", selection: Binding(get: { model.tab }, set: { model.show($0) })) {
                ForEach(ExilimModel.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            if model.pending > 0 {
                Label("受け取った \(model.pending) 枚は、閉じると共有アルバムに送ります", systemImage: "tray.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch model.tab {
            case .remote: remote
            case .files: cameraFiles
            }
        }
        .padding(.top, 8)
    }

    private var remote: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06))
                if let image = model.liveImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.title)
                        Text("ライブビューを待っています")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .padding(.horizontal)
            VStack(spacing: 10) {
                Toggle("撮った写真をすぐ受け取る（閉じると共有アルバムへ）", isOn: $model.autoAdd)
                Toggle("受け取ったらカメラから消す（カードなしでも撮り続けられる）", isOn: $model.deleteShots)
            }
            .font(.callout)
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
            HStack {
                Group {
                    if let shot = model.lastShot {
                        Button {
                            Task { await model.addLatest() }
                        } label: {
                            Image(uiImage: shot)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(model.busy != nil || model.lastShotReceived)
                        .accessibilityLabel("いま撮った写真を共有アルバムに入れる")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 56, height: 56)
                Spacer()
                Button {
                    Task { await model.shoot() }
                } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(.white).frame(width: 64, height: 64)
                    }
                }
                .disabled(model.busy != nil)
                .opacity(model.busy != nil ? 0.5 : 1)
                .accessibilityLabel("シャッター")
                Spacer()
                Color.clear.frame(width: 56, height: 56)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.lastShot)
    }

    private var cameraFiles: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                Toggle("受け取ったらカメラから消す", isOn: $model.deleteReceived)
                    .font(.callout)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                if model.files.isEmpty && model.busy == nil {
                    Text("カメラの中に写真がありません")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 3)], spacing: 3) {
                    ForEach(model.files) { file in
                        fileCell(file)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 100)
            }
            if !model.selected.isEmpty || model.progress != nil {
                Button {
                    Task { await model.addSelected() }
                } label: {
                    Group {
                        if let progress = model.progress {
                            Text("受け取っています \(progress.done) / \(progress.total)")
                        } else {
                            Text("選んだ \(model.selected.count) 件を受け取る")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
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
            Color.white.opacity(0.08)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = model.thumbnails[file.path] {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if file.isVideo {
                        Image(systemName: "video.fill")
                            .font(.caption)
                            .padding(5)
                            .foregroundStyle(.white)
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
                    if isSelected { Rectangle().strokeBorder(.tint, lineWidth: 3) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(file.fileName)
    }

    @ViewBuilder
    private var toast: some View {
        if let message = model.message {
            Text(message)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.15)))
                .padding(.bottom, 110)
                .transition(.opacity)
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(3))
                    if model.message == message { model.message = nil }
                }
        }
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
