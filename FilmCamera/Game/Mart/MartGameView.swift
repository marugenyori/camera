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
            }
        }
        link.start()
        nearby = link
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
                .ignoresSafeArea()
            joystick
            VStack(spacing: 8) {
                hud
                if !session.status.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text(session.status)
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.45)))
                }
                Spacer()
                if let banner = game.banner {
                    Text(banner)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.7, blue: 0.2), Color(red: 1, green: 0.45, blue: 0.2)],
                                                          startPoint: .top, endPoint: .bottom))
                                .shadow(color: Color(red: 0.8, green: 0.35, blue: 0.1), radius: 0, x: 0, y: 5)
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .task(id: banner) {
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation { game.banner = nil }
                        }
                        .padding(.bottom, 140)
                        .allowsHitTesting(false)
                }
            }
        }
        .preferredColorScheme(.light)
        .animation(.spring(duration: 0.4, bounce: 0.5), value: game.banner)
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

    @MainActor
    private func run() async {
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            session.step(min(now.timeIntervalSince(last), 0.05))
            last = now
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

    @ViewBuilder
    private var joystick: some View {
        if let start = touchStart, let now = touchNow {
            let dx = now.x - start.x, dy = now.y - start.y
            let length = hypot(dx, dy)
            let clamp = min(length, 45) / max(length, 0.001)
            ZStack {
                Circle()
                    .fill(.black.opacity(0.18))
                    .frame(width: 120, height: 120)
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 4))
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
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 2)
                    .frame(width: 48, height: 48)
            }
            // レベル（星と、次までのバー）
            HStack(spacing: 0) {
                ZStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.3), Color(red: 1, green: 0.65, blue: 0.1)],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color(red: 0.75, green: 0.45, blue: 0.05), radius: 0, x: 0, y: 2)
                    Text("\(game.level + 1)")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 1)
                        .offset(y: 2)
                }
                .zIndex(1)
                GeometryReader { geo in
                    let fraction = CGFloat(game.level) / CGFloat(MartGame.steps.count)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white)
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.5, green: 0.9, blue: 0.35), Color(red: 0.3, green: 0.75, blue: 0.25)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: max(geo.size.width * fraction, 14))
                            .padding(2)
                        Text(fraction >= 1 ? "MAX" : "\(game.level)/\(MartGame.steps.count)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 22)
                .padding(.leading, -12)
            }
            .frame(maxWidth: 160)
            Spacer()
            HStack(spacing: 6) {
                Text("💵")
                    .font(.system(size: 22))
                Text("\(game.money)")
                    .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(red: 0.2, green: 0.25, blue: 0.3))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: game.money)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white).shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: 3))
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
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
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(red: 0.62, green: 0.85, blue: 0.48, alpha: 1)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
