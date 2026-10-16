import SceneKit
import SwiftUI

/// 「まちかどマート」の入口：ひとりで遊ぶか、近くの友だちと 2 人で遊ぶか
struct MartGameView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("martName") private var name = ""
    @State private var session: MartSession?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4), Color(red: 1, green: 0.6, blue: 0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "cart.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
                Text("まちかどマート")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 3)
                Text("商品を運んで、棚に並べて、レジでお会計。\nお金をためてお店を大きくしよう！")
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                bigButton("ひとりで遊ぶ", symbol: "person.fill", color: Color(red: 0.25, green: 0.7, blue: 0.35)) {
                    session = MartSession(role: .solo, name: name)
                }
                VStack(spacing: 10) {
                    Text("2 人で遊ぶ（近くの iPhone と直接つなぐ）")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                    HStack(spacing: 10) {
                        bigButton("お店を開く", symbol: "storefront.fill", color: Color(red: 0.2, green: 0.5, blue: 0.9)) {
                            session = MartSession(role: .host, name: name)
                        }
                        bigButton("友だちの\nお店へ行く", symbol: "figure.walk", color: Color(red: 0.9, green: 0.35, blue: 0.35)) {
                            session = MartSession(role: .guest, name: name)
                        }
                    }
                    Text("1 人が「お店を開く」、もう 1 人が「友だちのお店へ行く」を押します。お店は開いた人のものになり、お金は 2 人で共通です。")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Button("もどる") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
        .fullScreenCover(item: $session) { session in
            MartPlayView(session: session)
        }
    }

    private func bigButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .font(.headline.weight(.heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(0.6), radius: 0, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - お店と通信をまとめる

/// ゲームの中身（MartGame）・3D（MartScene）・2 人の通信をまとめる
@MainActor
final class MartSession: ObservableObject, Identifiable {
    let id = UUID()
    let game: MartGame
    let scene = MartScene()
    @Published private(set) var status = ""
    @Published private(set) var connected = false
    private var nearby: CivNearby?
    private var sendTimer: Double = 0

    enum Message: Codable {
        case guest(MartWalker)
        case snapshot(MartSnapshot)
        case claim
        case upgrade(MartUpgrade)
    }

    init(role: MartGame.Role, name: String) {
        game = MartGame(role: role)
        guard role != .solo else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let link = CivNearby(name: trimmed.isEmpty ? "店員" : String(trimmed.prefix(20)), host: role == .host, service: "filmmart")
        link.onPeers = { [weak self] count in
            guard let self else { return }
            let was = self.connected
            self.connected = count > 0
            if count > 0 {
                self.status = ""
                if role == .host, !was { self.game.addGuest() }
            } else {
                self.status = role == .host ? "友だちを待っています" : "友だちのお店をさがしています"
                if role == .host { self.game.removeGuest() }
            }
        }
        link.onReceive = { [weak self] data in
            guard let self, let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
            switch message {
            case .guest(let walker):
                if role == .host { self.game.setGuest(walker) }
            case .snapshot(let snapshot):
                if role == .guest { self.game.apply(snapshot) }
            case .claim:
                if role == .host { self.game.claimQuest() }
            case .upgrade(let upgrade):
                if role == .host { self.game.buyUpgrade(upgrade) }
            }
        }
        link.start()
        nearby = link
        if role == .guest {
            game.onClaim = { [weak link] in
                if let data = try? JSONEncoder().encode(Message.claim) { link?.send(data) }
            }
            game.onUpgrade = { [weak link] upgrade in
                if let data = try? JSONEncoder().encode(Message.upgrade(upgrade)) { link?.send(data) }
            }
        }
        status = role == .host ? "友だちを待っています" : "友だちのお店をさがしています"
    }

    func step(_ dt: Double) {
        game.update(dt)
        scene.sync(game, dt: dt)
        guard let nearby, connected else { return }
        sendTimer -= dt
        guard sendTimer <= 0 else { return }
        switch game.role {
        case .host:
            sendTimer = 1.0 / 15
            if let data = try? JSONEncoder().encode(Message.snapshot(game.snapshot())) { nearby.send(data) }
        case .guest:
            sendTimer = 1.0 / 20
            if game.players.indices.contains(game.me),
               let data = try? JSONEncoder().encode(Message.guest(game.players[game.me])) {
                nearby.send(data, reliable: false)
            }
        case .solo:
            break
        }
    }

    func stop() {
        game.save()
        nearby?.stop()
        nearby = nil
    }
}

// MARK: - 遊ぶ画面

struct MartPlayView: View {
    @ObservedObject var session: MartSession
    @ObservedObject private var game: MartGame
    @Environment(\.dismiss) private var dismiss
    @State private var touchStart: CGPoint?
    @State private var touchNow: CGPoint?
    @State private var muted = GameAudio.shared.isMuted
    @State private var confirmingReset = false
    @State private var zoomStart: CGFloat?

    init(session: MartSession) {
        _session = ObservedObject(wrappedValue: session)
        _game = ObservedObject(wrappedValue: session.game)
    }

    var body: some View {
        ZStack {
            MartSceneView(scene: session.scene)
                .ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle())
                .gesture(stickGesture)
                .simultaneousGesture(zoomGesture)
                .ignoresSafeArea()
            joystick
            VStack(spacing: 8) {
                hud
                questCard
                if !session.status.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text(session.status)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
                    .environment(\.colorScheme, .dark)
                }
                Spacer()
                if game.atUpgrade {
                    upgradePanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let banner = game.banner {
                    Text(banner)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.18, green: 0.2, blue: 0.25))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: banner) {
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation { game.banner = nil }
                        }
                        .padding(.bottom, 140)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay {
            if game.offlineEarned > 0 { offlinePopup }
        }
        .preferredColorScheme(.light)
        .animation(.spring(duration: 0.4, bounce: 0.5), value: game.banner)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: game.atUpgrade)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: game.offlineEarned)
        .statusBarHidden()
        .task { await run() }
        .onDisappear {
            session.stop()
            GameAudio.shared.stop()
        }
        .confirmationDialog("最初からやり直しますか？", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("やり直す", role: .destructive) { game.reset() }
        }
    }

    /// 画面の書き換えに合わせて動かす（対応機種は 1 秒 120 コマ）。決まった間隔で寝て起きるより、ずっとなめらか
    @MainActor
    private func run() async {
        let ticker = MartTicker { dt in session.step(dt) }
        ticker.start()
        defer { ticker.stop() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    private var stickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if touchStart == nil { touchStart = value.startLocation }
                touchNow = value.location
                let dx = value.location.x - value.startLocation.x
                let dy = value.location.y - value.startLocation.y
                let length = max(hypot(dx, dy), 0.001)
                let scale = min(length / 45, 1) / length
                game.stick = CGVector(dx: dx * scale, dy: dy * scale)
            }
            .onEnded { _ in
                touchStart = nil
                touchNow = nil
                game.stick = .zero
            }
    }

    /// クエスト（左上のカード）。こなしたら「受け取る」
    private var questCard: some View {
        let quest = game.quest
        let progress = game.questProgress
        return HStack(spacing: 10) {
            Image(systemName: quest.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.78, blue: 0.62), Color(red: 0.3, green: 0.62, blue: 0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.2, green: 0.22, blue: 0.3))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.88))
                        Capsule().fill(Color(red: 0.35, green: 0.8, blue: 0.35))
                            .frame(width: max(geo.size.width * CGFloat(progress) / CGFloat(max(quest.target, 1)), 8))
                    }
                }
                .frame(height: 8)
                Text((quest.kind == .earn ? "\(MartYen.text(progress))/\(MartYen.text(quest.target))" : "\(progress)/\(quest.target)")
                     + "　報酬 \(MartYen.text(quest.reward))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if game.questDone {
                Button {
                    game.claimQuest()
                } label: {
                    Text("受け取る")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.36, green: 0.78, blue: 0.62),
                                                                           Color(red: 0.3, green: 0.62, blue: 0.95)],
                                                                  startPoint: .leading, endPoint: .trailing)))
                }
                .buttonStyle(.plain)
                .phaseAnimator([1.0, 1.08]) { content, scale in
                    content.scaleEffect(scale)
                } animation: { _ in .easeInOut(duration: 0.5) }
            }
        }
        .padding(10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    /// アップグレード（床の UPGRADE に立つと出る）
    private var upgradePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("⬆️ アップグレード")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                Spacer()
                Text("出ると閉じます")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            ForEach(MartUpgrade.allCases) { upgrade in
                let level = game.upgradeLevel(upgrade)
                let maxed = level >= MartUpgrade.maxLevel
                let cost = upgrade.cost(level)
                HStack(spacing: 10) {
                    Image(systemName: upgrade.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(red: 0.45, green: 0.35, blue: 0.95)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(upgrade.title)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                        HStack(spacing: 3) {
                            ForEach(0..<MartUpgrade.maxLevel, id: \.self) { index in
                                Capsule()
                                    .fill(index < level ? Color(red: 0.45, green: 0.35, blue: 0.95) : Color(white: 0.85))
                                    .frame(width: 14, height: 5)
                            }
                            Text(upgrade.effect(level))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                    }
                    Spacer()
                    Button {
                        game.buyUpgrade(upgrade)
                    } label: {
                        Text(maxed ? "MAX" : MartYen.text(cost))
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(minWidth: 86)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(maxed ? Color(white: 0.6)
                                                       : game.money >= cost ? Color(red: 0.3, green: 0.75, blue: 0.35) : Color(white: 0.72)))
                    }
                    .buttonStyle(.plain)
                    .disabled(maxed)
                }
            }
        }
        .foregroundStyle(Color(red: 0.18, green: 0.2, blue: 0.28))
        .padding(14)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 24)
    }

    /// 留守のあいだにかせいだお金
    private var offlinePopup: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("おかえりなさい！")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                Text("留守のあいだも、お店は\nがんばってかせいでいました")
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("💴").font(.system(size: 40))
                    Text(MartYen.text(game.offlineEarned))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.25))
                }
                Text("レジの横に置いてあります。拾いに行こう！")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                Button {
                    game.offlineEarned = 0
                    GameAudio.shared.play(.complete)
                } label: {
                    Text("OK")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 160, height: 52)
                        .background(Capsule().fill(Color(red: 0.3, green: 0.75, blue: 0.35))
                            .shadow(color: Color(red: 0.2, green: 0.5, blue: 0.2), radius: 0, x: 0, y: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
            .padding(30)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    /// 2 本指で広げると寄る、つまむと引く（写真と同じ感覚）
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = session.scene.zoom }
                if let start = zoomStart { session.scene.zoom = start / value.magnification }
                // 2 本指の間は歩かない
                touchStart = nil
                touchNow = nil
                game.stick = .zero
            }
            .onEnded { _ in
                zoomStart = nil
                session.scene.saveZoom()
            }
    }

    @ViewBuilder
    private var joystick: some View {
        if let start = touchStart, let now = touchNow {
            let dx = now.x - start.x, dy = now.y - start.y
            let length = hypot(dx, dy)
            let clamp = min(length, 45) / max(length, 0.001)
            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 116, height: 116)
                    .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 2))
                Circle()
                    .fill(.white)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    .offset(x: dx * clamp, y: dy * clamp)
            }
            .position(start)
            .allowsHitTesting(false)
        }
    }

    private var hud: some View {
        HStack(alignment: .center, spacing: 10) {
            Menu {
                Button {
                    muted.toggle()
                    GameAudio.shared.isMuted = muted
                } label: {
                    Label(muted ? "音を出す" : "音を消す", systemImage: muted ? "speaker.wave.2" : "speaker.slash")
                }
                if game.role != .guest {
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        Label("最初からやり直す", systemImage: "arrow.counterclockwise")
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Label("ゲームをやめる", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.2, blue: 0.25))
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
            // レベル（お店の成長）
            let fraction = CGFloat(game.level) / CGFloat(MartGame.steps.count)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("LV")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(game.level + 1)")
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    Spacer(minLength: 0)
                    Text(fraction >= 1 ? "MAX" : "\(Int(fraction * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.78, blue: 0.62), Color(red: 0.3, green: 0.62, blue: 0.95)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * fraction, 5))
                    }
                }
                .frame(height: 5)
            }
            .foregroundStyle(Color(red: 0.18, green: 0.2, blue: 0.25))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: 150)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .animation(.smooth, value: game.level)
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.7, blue: 0.45))
                Text(MartYen.text(game.money))
                    .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(red: 0.18, green: 0.2, blue: 0.25))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: game.money)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

/// 画面の書き換えのたびに呼ぶ（CADisplayLink）
@MainActor
final class MartTicker: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private let onTick: (Double) -> Void

    init(onTick: @escaping (Double) -> Void) {
        self.onTick = onTick
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = last == 0 ? link.duration : now - last
        last = now
        onTick(min(max(dt, 1.0 / 240), 0.05))
    }
}

/// SceneKit の画面（さわる操作は上の SwiftUI で受け取る）
struct MartSceneView: UIViewRepresentable {
    let scene: MartScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = scene.scene
        view.pointOfView = scene.cameraNode
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 120
        view.rendersContinuously = true
        view.isPlaying = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(red: 0.62, green: 0.85, blue: 0.48, alpha: 1)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
