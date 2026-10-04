import AVFoundation
import UIKit

/// ゲームの音（効果音と BGM）と振動。音のファイルは持たず、その場で音を合成する。
/// マナーモードでも鳴らす（ゲーム中の右上のボタンで消せる）
final class GameAudio {
    static let shared = GameAudio()

    /// 音を出すか（ゲームの画面のボタンで切り替え、次回も覚えておく）
    var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: "gameMuted") }
        set {
            UserDefaults.standard.set(newValue, forKey: "gameMuted")
            lock.lock(); muted = newValue; lock.unlock()
        }
    }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let lock = NSLock()
    private var sampleRate: Double = 44_100
    private var started = false

    // 以下は lock で守る（音を作る処理は別のスレッドで動く）
    private var muted = false
    private var voices: [Voice] = []
    private var music: Music?

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    private init() {
        muted = UserDefaults.standard.bool(forKey: "gameMuted")
    }

    // MARK: - 始める・止める

    func start() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        let format = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 44_100
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList in
            self?.render(frameCount: Int(frameCount), bufferList: bufferList)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = 0.8
        source = node
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
        light.prepare(); medium.prepare()
    }

    func stop() {
        stopMusic()
        guard started else { return }
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        started = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - BGM

    /// BGM の曲（明るいキャンディ風／やさしい塗り絵風）
    enum Song { case candy, jewel }

    func playMusic(_ song: Song) {
        start()
        lock.lock()
        music = Music(song: song, sampleRate: sampleRate)
        lock.unlock()
    }

    func stopMusic() {
        lock.lock(); music = nil; lock.unlock()
    }

    // MARK: - 効果音

    enum Effect {
        case tap, place, swap, invalid, pop(combo: Int), special, bomb, win, lose, complete
    }

    func play(_ effect: Effect) {
        start()
        switch effect {
        case .tap:
            light.impactOccurred(intensity: 0.5)
            add(notes: [(1568, 0.0)], length: 0.06, wave: .sine, volume: 0.25)
        case .place:
            light.impactOccurred(intensity: 0.7)
            let pitches: [Double] = [1047, 1175, 1319, 1568, 1760]
            let pitch: Double = pitches.randomElement() ?? 1319
            add(notes: [(pitch, 0.0), (pitch * 2, 0.02)], length: 0.09, wave: .sine, volume: 0.22)
        case .swap:
            light.impactOccurred()
            add(notes: [(660, 0.0), (880, 0.05)], length: 0.08, wave: .triangle, volume: 0.25)
        case .invalid:
            notify.notificationOccurred(.warning)
            add(notes: [(330, 0.0), (262, 0.08)], length: 0.12, wave: .square, volume: 0.12)
        case .pop(let combo):
            medium.impactOccurred(intensity: min(1, 0.6 + Double(combo) * 0.1))
            // 連鎖するほど高い音で
            let base = 523.25 * pow(2, Double(min(combo - 1, 7)) * 2 / 12)
            add(notes: [(base, 0.0), (base * 1.25, 0.04), (base * 1.5, 0.08)], length: 0.12, wave: .triangle, volume: 0.28)
        case .special:
            heavy.impactOccurred()
            add(notes: [(784, 0.0), (988, 0.05), (1175, 0.1), (1568, 0.15)], length: 0.14, wave: .triangle, volume: 0.3)
        case .bomb:
            heavy.impactOccurred(intensity: 1)
            add(notes: [(110, 0.0), (82, 0.06)], length: 0.35, wave: .noise, volume: 0.35)
            add(notes: [(1319, 0.05), (1568, 0.1), (2093, 0.15)], length: 0.2, wave: .sine, volume: 0.2)
        case .win, .complete:
            notify.notificationOccurred(.success)
            add(notes: [(523, 0.0), (659, 0.12), (784, 0.24), (1047, 0.36), (1319, 0.5)],
                length: 0.3, wave: .triangle, volume: 0.3)
        case .lose:
            notify.notificationOccurred(.error)
            add(notes: [(392, 0.0), (330, 0.2), (262, 0.4)], length: 0.35, wave: .triangle, volume: 0.25)
        }
    }

    /// 振動だけ（音なし）
    func tick() { light.impactOccurred(intensity: 0.4) }

    private func add(notes: [(Double, Double)], length: Double, wave: Wave, volume: Double) {
        lock.lock()
        for (frequency, delay) in notes {
            voices.append(Voice(frequency: frequency, delay: Int(delay * sampleRate),
                                length: Int(length * sampleRate), wave: wave, volume: volume))
        }
        if voices.count > 48 { voices.removeFirst(voices.count - 48) }
        lock.unlock()
    }

    // MARK: - 音を作る（オーディオのスレッドで呼ばれる）

    private func render(frameCount: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        lock.lock()
        defer { lock.unlock() }
        for i in 0..<frameCount {
            var sample: Double = 0
            if !muted {
                if let value = music?.next() { sample += value }
                for v in voices.indices { sample += voices[v].next(sampleRate: sampleRate) }
            }
            data[i] = Float(max(-1, min(1, sample)))
        }
        voices.removeAll { $0.isFinished }
        for buffer in buffers.dropFirst() {
            buffer.mData?.copyMemory(from: data, byteCount: frameCount * MemoryLayout<Float>.size)
        }
    }
}

private enum Wave { case sine, triangle, square, noise }

/// 効果音の 1 音（すぐ立ち上がって減っていく）
private struct Voice {
    let frequency: Double
    var delay: Int
    let length: Int
    let wave: Wave
    let volume: Double
    var position = 0
    var phase = 0.0

    var isFinished: Bool { delay <= 0 && position >= length }

    mutating func next(sampleRate: Double) -> Double {
        if delay > 0 { delay -= 1; return 0 }
        guard position < length else { return 0 }
        let t = Double(position) / Double(length)
        let envelope = min(1, Double(position) / 80) * pow(1 - t, 2)
        phase += frequency / sampleRate
        if phase >= 1 { phase -= 1 }
        position += 1
        return oscillator(wave, phase) * envelope * volume
    }
}

private func oscillator(_ wave: Wave, _ phase: Double) -> Double {
    switch wave {
    case .sine: return sin(phase * 2 * .pi)
    case .triangle: return 4 * abs(phase - 0.5) - 1
    case .square: return phase < 0.5 ? 0.6 : -0.6
    case .noise: return Double.random(in: -1...1)
    }
}

/// BGM：メロディとベースを繰り返す小さな曲
private struct Music {
    let sampleRate: Double
    let melody: [Int]        // 半音（0 = 基準の音、-1 = 休み）
    let bass: [Int]
    let base: Double
    let stepLength: Int
    let wave: Wave
    var sample = 0
    var melodyPhase = 0.0
    var bassPhase = 0.0

    init(song: GameAudio.Song, sampleRate: Double) {
        self.sampleRate = sampleRate
        switch song {
        case .candy:
            // 弾むような長調のメロディ（テンポ 132）
            melody = [0, 4, 7, 12, 7, 4, 9, 7, 5, 9, 12, 9, 7, -1, 4, 7,
                      0, 4, 7, 12, 14, 12, 9, 7, 5, 4, 2, 4, 0, -1, 0, -1]
            bass = [-12, -12, -5, -5, -7, -7, -5, -5]
            base = 523.25
            stepLength = Int(sampleRate * 60 / 132 / 2)
            wave = .triangle
        case .jewel:
            // ゆったりしたオルゴール風（テンポ 96）
            melody = [12, 7, 4, 7, 11, 7, 4, 7, 9, 5, 2, 5, 7, 4, 0, -1,
                      12, 7, 4, 7, 14, 11, 7, 11, 12, 9, 5, 9, 7, -1, -1, -1]
            bass = [-12, -12, -17, -17, -15, -15, -17, -17]
            base = 659.25
            stepLength = Int(sampleRate * 60 / 96 / 2)
            wave = .sine
        }
    }

    mutating func next() -> Double {
        let step = sample / stepLength
        let inStep = Double(sample % stepLength) / Double(stepLength)
        sample += 1
        var out = 0.0
        let note = melody[step % melody.count]
        if note >= 0 {
            let f = base * pow(2, Double(note) / 12)
            melodyPhase += f / sampleRate
            if melodyPhase >= 1 { melodyPhase -= 1 }
            let envelope = min(1, inStep * 40) * pow(1 - inStep, 1.5)
            out += oscillator(wave, melodyPhase) * envelope * 0.09
        }
        let bassNote = bass[(step / 4) % bass.count]
        let fb = base / 2 * pow(2, Double(bassNote) / 12)
        bassPhase += fb / sampleRate
        if bassPhase >= 1 { bassPhase -= 1 }
        let bassEnvelope = pow(1 - Double((sample - 1) % (stepLength * 2)) / Double(stepLength * 2), 1.2)
        out += oscillator(.triangle, bassPhase) * bassEnvelope * 0.07
        return out
    }
}
