import SwiftUI

/// EXILIM（EX-FR100 など）と Wi-Fi で直接つなぐ画面。
/// - リモート撮影：カメラのライブビューを見ながら、iPhone からシャッターを切る。撮った写真をそのまま共有アルバムへ
/// - カメラの写真：カメラの中の写真を一覧で見て、選んだものを共有アルバムへ（写真アプリを通さない）
@MainActor
final class ExilimModel: ObservableObject {
    enum Phase: Equatable {
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
    /// 撮ったらすぐ共有アルバムに入れる
    @Published var autoAdd = UserDefaults.standard.object(forKey: "exilimAutoAdd") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoAdd, forKey: "exilimAutoAdd") }
    }

    let client = ExilimClient()
    private let live = ExilimLiveView()
    private var livePort: UInt16 = 0
    private var heartbeat: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var switching: Task<Void, Never>?

    var model: String {
        if case .connected(let info) = phase { return info.model }
        return "EXILIM"
    }

    // MARK: - つなぐ

    func connect() async {
        phase = .searching
        message = nil
        guard let info = await client.find() else {
            phase = .notFound
            return
        }
        phase = .connected(info)
        show(tab)
    }

    /// タブを切り替える（カメラのモードも切り替わる。前の切り替えが終わってから）
    func show(_ tab: Tab) {
        self.tab = tab
        let previous = switching
        switching = Task {
            await previous?.value
            stopLive()
            thumbnailTask?.cancel()
            switch tab {
            case .remote: await startRemote()
            case .files: await loadFiles()
            }
        }
    }

    func close() async {
        switching?.cancel()
        thumbnailTask?.cancel()
        stopLive()
        heartbeat?.cancel()
        await client.disconnect()
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
            if autoAdd { await addLatest() }
        } catch {
            message = error.localizedDescription
        }
    }

    /// いま撮った写真を共有アルバムに入れる
    func addLatest() async {
        busy = "写真を受け取っています"
        do {
            let data = try await client.latestImage(livePort: livePort)
            add(data, thumbnail: lastShot)
            message = "共有アルバムに入れました"
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
            startHeartbeat()
            loadThumbnails()
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
        guard !file.isVideo else {
            message = "動画は共有アルバムに入れられません"
            return
        }
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
        for file in targets {
            do {
                let data = try await client.download(file.path)
                add(data, thumbnail: thumbnails[file.path])
                selected.remove(file.path)
            } catch {
                failed += 1
            }
            progress = ((progress?.done ?? 0) + 1, targets.count)
        }
        progress = nil
        busy = nil
        message = failed == 0 ? "\(targets.count) 枚を共有アルバムに入れました"
                              : "\(targets.count - failed) 枚を入れました（\(failed) 枚は受け取れませんでした）"
        loadThumbnails()
    }

    private func add(_ data: Data, thumbnail: UIImage?) {
        let small = thumbnail ?? UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 800, height: 800))
        AlbumStore.shared.add(data: data, type: "public.jpeg", thumbnail: small, mode: model,
                              location: LocationProvider.location(inImage: data))
    }
}

struct ExilimView: View {
    @StateObject private var model = ExilimModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                switch model.phase {
                case .searching:
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("カメラをさがしています")
                            .font(.callout)
                            .foregroundStyle(.secondary)
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
            }
            .overlay(alignment: .bottom) { toast }
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
                    step(1, "カメラ（EX-FR100 など）の電源を入れ、スマートフォンとつなぐ待ち受けの状態にします（取扱説明書の「スマートフォンと接続する」）。")
                    step(2, "iPhone の「設定」→「Wi-Fi」で、カメラの名前の Wi-Fi を選びます。パスワードは、カメラに付いていた紙か取扱説明書に書いてあります。")
                    step(3, "「インターネット未接続」と出ても、そのままで大丈夫です。このアプリに戻って、下の「もう一度さがす」を押します。")
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
            Toggle("撮ったらすぐ共有アルバムに入れる", isOn: $model.autoAdd)
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
                        .disabled(model.busy != nil || model.autoAdd)
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
                            Text("選んだ \(model.selected.count) 枚を共有アルバムに入れる")
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
                    }
                }
                .overlay {
                    if isSelected { Rectangle().strokeBorder(.tint, lineWidth: 3) }
                }
                .opacity(file.isVideo ? 0.5 : 1)
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
