import SceneKit
import SwiftUI

/// 「まちかどマート」の入口：ひとりで遊ぶか、近くの友だちと 2 人で遊ぶか
struct MartGameView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("martName") private var name = ""
    @State private var session: MartSession?

    var body: some View {
        ZStack {
            HalftoneBackground()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "cart.fill")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(GameStyle.ink)
                    .frame(width: 96, height: 96)
                    .background(BurstShape().fill(.white))
                    .rotationEffect(.degrees(-8))
                RansomText(text: "まちかどマート", size: 30)
                    .rotationEffect(.degrees(-4))
                Text("運んで、並べて、お会計。\nお金をためてお店を大きくしよう！")
                    .font(GameStyle.font(15, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(GameStyle.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(SlantShape(skew: 10).fill(.white))
                    .rotationEffect(.degrees(2))
                Spacer()
                bigButton("ひとりで遊ぶ", symbol: "person.fill", accent: GameStyle.red) {
                    session = MartSession(role: .solo, name: name)
                }
                VStack(spacing: 12) {
                    Text("2 人で遊ぶ（近くの iPhone と直接つなぐ）")
                        .font(GameStyle.font(12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(SlantShape(skew: 6).fill(GameStyle.ink))
                    HStack(spacing: 12) {
                        bigButton("お店を開く", symbol: "storefront.fill", accent: .white) {
                            session = MartSession(role: .host, name: name)
                        }
                        bigButton("友だちの\nお店へ行く", symbol: "figure.walk", accent: .white) {
                            session = MartSession(role: .guest, name: name)
                        }
                    }
                    Text("1 人が「お店を開く」、もう 1 人が「友だちのお店へ行く」を押します。お店は開いた人のものになり、お金は 2 人で共通です。")
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
                Button {
                    dismiss()
                } label: {
                    Text("もどる")
                        .font(GameStyle.font(16))
                        .foregroundStyle(GameStyle.ink)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 9)
                        .slantCard(fill: .white, shadow: GameStyle.ink, border: GameStyle.ink)
                }
                .buttonStyle(SlantButtonStyle())
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
        .fullScreenCover(item: $session) { session in
            MartPlayView(session: session)
        }
    }

    private func bigButton(_ title: String, symbol: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(accent == .white ? GameStyle.red : .white)
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .font(GameStyle.font(18))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .slantCard(skew: 14, shadow: accent == .white ? .white : GameStyle.red, border: accent == .white ? GameStyle.red : .white)
        }
        .buttonStyle(SlantButtonStyle())
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
                eventPills
                questCard
                if !session.status.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text(session.status)
                    }
                    .font(GameStyle.font(13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .slantCard()
                }
                Spacer()
                if game.atUpgrade {
                    upgradePanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let banner = game.banner {
                    // ギザギザの赤い吹き出しに、白い斜体（黒い影をずらして重ねる）
                    Text(banner)
                        .font(GameStyle.font(21))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 30)
                        .background(
                            ZStack {
                                BurstShape(spikes: 20, depth: 0.12).fill(GameStyle.ink).offset(x: 6, y: 6)
                                BurstShape(spikes: 20, depth: 0.12).fill(GameStyle.red)
                                BurstShape(spikes: 20, depth: 0.12).stroke(.white, lineWidth: 3)
                            }
                        )
                        .rotationEffect(.degrees(-4))
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .task(id: banner) {
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation { game.banner = nil }
                        }
                        .padding(.bottom, 120)
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
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 38, height: 36)
                .background(SlantShape(skew: 6).fill(GameStyle.red))
                .rotationEffect(.degrees(-6))
            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title)
                    .font(GameStyle.font(13, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        SlantShape(skew: 4).fill(.white.opacity(0.2))
                        SlantShape(skew: 4).fill(GameStyle.red)
                            .frame(width: max(geo.size.width * CGFloat(progress) / CGFloat(max(quest.target, 1)), 10))
                    }
                }
                .frame(height: 8)
                Text((quest.kind == .earn ? "\(MartYen.text(progress))/\(MartYen.text(quest.target))" : "\(progress)/\(quest.target)")
                     + "　報酬 \(MartYen.text(quest.reward))")
                    .font(.system(size: 11, weight: .bold).italic())
                    .foregroundStyle(.white.opacity(0.75))
            }
            if game.questDone {
                Button {
                    game.claimQuest()
                } label: {
                    Text("受け取る")
                        .font(GameStyle.font(14))
                        .foregroundStyle(GameStyle.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(BurstShape(spikes: 12, depth: 0.1).fill(GameStyle.gold))
                }
                .buttonStyle(SlantButtonStyle())
                .phaseAnimator([1.0, 1.1]) { content, scale in
                    content.scaleEffect(scale)
                } animation: { _ in .easeInOut(duration: 0.45) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 310, alignment: .leading)
        .slantCard(skew: 12)
        .rotationEffect(.degrees(-1.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    /// アップグレード（床の UPGRADE に立つと出る）
    private var upgradePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RansomText(text: "UPGRADE", size: 20)
                Spacer()
                Text("タップで買う")
                    .font(GameStyle.font(11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
            }
            // 2 列のタイル：アイコンと名前、レベル、「いま → つぎ」の効果、値段
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(MartUpgrade.allCases) { upgrade in
                    upgradeTile(upgrade)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 430)
        .slantCard(skew: 16)
        .padding(.horizontal, 14)
        .padding(.bottom, 24)
    }

    private func upgradeTile(_ upgrade: MartUpgrade) -> some View {
        let level = game.upgradeLevel(upgrade)
        let maxed = level >= MartUpgrade.maxLevel
        let cost = upgrade.cost(level)
        let affordable = !maxed && game.money >= cost
        return Button {
            game.buyUpgrade(upgrade)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: upgrade.symbol)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 26)
                        .background(SlantShape(skew: 5).fill(GameStyle.red))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(upgrade.title)
                            .font(GameStyle.font(12, weight: .heavy))
                            .foregroundStyle(GameStyle.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack(spacing: 2) {
                            ForEach(0..<MartUpgrade.maxLevel, id: \.self) { index in
                                SlantShape(skew: 2)
                                    .fill(index < level ? GameStyle.red : Color(white: 0.82))
                                    .frame(width: 10, height: 5)
                            }
                        }
                    }
                }
                Text(maxed ? upgrade.effect(level) : (level == 0 ? "なし" : upgrade.effect(level)) + " → " + upgrade.effect(level + 1))
                    .font(.system(size: 11, weight: .bold).italic())
                    .foregroundStyle(Color(white: 0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(maxed ? "MAX" : MartYen.text(cost))
                    .font(GameStyle.font(13))
                    .foregroundStyle(maxed ? GameStyle.ink : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(SlantShape(skew: 6).fill(maxed ? GameStyle.gold : affordable ? GameStyle.red : Color(white: 0.55)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(SlantShape(skew: 8).fill(.white))
        }
        .buttonStyle(SlantButtonStyle())
        .disabled(maxed)
    }

    /// 評判の星と、タイムセールの残り時間
    private var eventPills: some View {
        HStack(spacing: 10) {
            Spacer()
            if game.saleSeconds > 0 {
                Text("SALE \(game.saleSeconds)")
                    .font(GameStyle.font(14))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(BurstShape(spikes: 14, depth: 0.14).fill(GameStyle.red))
                    .rotationEffect(.degrees(-6))
                    .transition(.scale.combined(with: .opacity))
            }
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { index in
                    let value = game.stars - Double(index)
                    Image(systemName: value >= 1 ? "star.fill" : value >= 0.5 ? "star.leadinghalf.filled" : "star")
                }
            }
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(GameStyle.gold)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .slantCard(skew: 8)
            .accessibilityLabel("評判 \(game.stars)")
        }
        .padding(.horizontal, 18)
        .animation(.spring(duration: 0.3), value: game.saleSeconds > 0)
    }

    /// 留守のあいだにかせいだお金
    private var offlinePopup: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                RansomText(text: "おかえり！", size: 30)
                    .rotationEffect(.degrees(-4))
                Text("留守のあいだも、お店は\nがんばってかせいでいました")
                    .font(GameStyle.font(14, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                Text(MartYen.text(game.offlineEarned))
                    .font(GameStyle.font(44))
                    .foregroundStyle(GameStyle.ink)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 26)
                    .background(BurstShape(spikes: 18, depth: 0.12).fill(GameStyle.gold))
                    .rotationEffect(.degrees(3))
                Text("レジの横に置いてあります。拾いに行こう！")
                    .font(.footnote.weight(.bold).italic())
                    .foregroundStyle(.white.opacity(0.8))
                Button {
                    game.offlineEarned = 0
                    GameAudio.shared.play(.complete)
                } label: {
                    Text("OK")
                        .font(GameStyle.font(22))
                        .foregroundStyle(.white)
                        .frame(width: 160, height: 52)
                        .slantCard(skew: 14, fill: GameStyle.red, shadow: .white)
                }
                .buttonStyle(SlantButtonStyle())
            }
            .padding(30)
            .slantCard(skew: 20)
            .padding(26)
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
                    .fill(GameStyle.ink.opacity(0.35))
                    .frame(width: 116, height: 116)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                Circle()
                    .fill(GameStyle.red)
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: GameStyle.ink, radius: 0, x: 3, y: 3)
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
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 42)
                    .slantCard(skew: 8)
            }
            // レベル（お店の成長）
            let fraction = CGFloat(game.level) / CGFloat(MartGame.steps.count)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("LV")
                        .font(GameStyle.font(11))
                        .foregroundStyle(GameStyle.red)
                    Text("\(game.level + 1)")
                        .font(GameStyle.font(22).monospacedDigit())
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text(fraction >= 1 ? "MAX" : "\(Int(fraction * 100))%")
                        .font(GameStyle.font(11, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        SlantShape(skew: 4).fill(.white.opacity(0.2))
                        SlantShape(skew: 4).fill(GameStyle.red)
                            .frame(width: max(geo.size.width * fraction, 8))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .frame(width: 150)
            .slantCard(skew: 12)
            .rotationEffect(.degrees(-2))
            .animation(.smooth, value: game.level)
            Spacer()
            // 所持金：黒い斜めの帯に、白い太い斜体
            HStack(spacing: 6) {
                Text("¥")
                    .font(GameStyle.font(16))
                    .foregroundStyle(GameStyle.ink)
                    .frame(width: 24, height: 24)
                    .background(BurstShape(spikes: 10, depth: 0.14).fill(GameStyle.gold))
                Text(MartYen.text(game.money).replacingOccurrences(of: "¥", with: ""))
                    .font(GameStyle.font(21).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: game.money)
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .slantCard(skew: 12)
            .rotationEffect(.degrees(1.5))
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
