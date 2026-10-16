import SwiftUI

/// ゲームの入口（メイン画面のゲームのボタン、または撮影画面の倍率の小窓の長押しで開く）
struct GameHubView: View {
    /// ジュエル塗り絵で最初に使う写真
    let initialImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var playing: Game?

    enum Game: String, Identifiable {
        case jewel, candy, romance, chameleon, hakoniwa, civ, mart
        var id: String { rawValue }
    }

    private struct Entry {
        let game: Game
        let title: String
        let subtitle: String
        let symbol: String
    }

    private let entries: [Entry] = [
        Entry(game: .mart, title: "まちかどマート", subtitle: "商品を運んで並べて、レジでお会計。お店を大きくしよう", symbol: "cart.fill"),
        Entry(game: .jewel, title: "ジュエル塗り絵", subtitle: "宝石を並べ替えて絵を完成させる", symbol: "diamond.fill"),
        Entry(game: .candy, title: "キャンディ・マッチ", subtitle: "3 つそろえて消す、特別なキャンディつき", symbol: "heart.fill"),
        Entry(game: .romance, title: "放課後メモリーズ", subtitle: "2000年代のギャルゲー風・恋愛アドベンチャー", symbol: "envelope.open.fill"),
        Entry(game: .chameleon, title: "かくれカメレオン", subtitle: "体に色を塗って背景にとけこむ、お絵描きかくれんぼ", symbol: "lizard.fill"),
        Entry(game: .hakoniwa, title: "ちいさな箱庭", subtitle: "地面を塗って家や木を置く。人や動物が歩きまわる", symbol: "house.lodge.fill"),
        Entry(game: .civ, title: "ふたりの文明", subtitle: "2 人で一緒に文明を育てる。近くでも、離れていても", symbol: "globe.asia.australia.fill"),
    ]

    var body: some View {
        ZStack {
            HalftoneBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 見出し：切り抜き文字と、斜めの帯
                    VStack(alignment: .leading, spacing: 10) {
                        RansomText(text: "ゲーム", size: 44)
                        Text("SELECT A GAME")
                            .font(GameStyle.font(14))
                            .tracking(3)
                            .foregroundStyle(GameStyle.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                            .background(SlantShape(skew: 8).fill(.white))
                    }
                    .rotationEffect(.degrees(-4))
                    .padding(.top, 36)
                    .padding(.bottom, 10)
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        gameButton(entry, index: index)
                    }
                    Button {
                        dismiss()
                    } label: {
                        Label("もどる", systemImage: "arrow.uturn.backward")
                            .font(GameStyle.font(17))
                            .foregroundStyle(GameStyle.ink)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                            .slantCard(fill: .white, shadow: GameStyle.ink, border: GameStyle.ink)
                    }
                    .buttonStyle(SlantButtonStyle())
                    .rotationEffect(.degrees(-3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
                .padding(.horizontal, 22)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $playing) { game in
            switch game {
            case .jewel: JewelGameView(initialImage: initialImage)
            case .candy: CandyGameView()
            case .romance: RomanceGameView()
            case .chameleon: ChameleonGameView(initialImage: initialImage)
            case .hakoniwa: HakoniwaGameView()
            case .civ: CivGameView()
            case .mart: MartGameView()
            }
        }
    }

    /// 1 つのゲーム：番号・アイコン・名前を斜めの黒いカードに。交互に左右へずらして傾ける
    private func gameButton(_ entry: Entry, index: Int) -> some View {
        let even = index % 2 == 0
        return Button {
            playing = entry.game
        } label: {
            HStack(spacing: 14) {
                Text(String(format: "%02d", index + 1))
                    .font(GameStyle.font(30))
                    .foregroundStyle(GameStyle.red)
                    .frame(width: 44)
                Image(systemName: entry.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GameStyle.ink)
                    .frame(width: 50, height: 46)
                    .background(SlantShape(skew: 8).fill(.white))
                    .rotationEffect(.degrees(even ? -6 : 5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(GameStyle.font(19))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(entry.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(GameStyle.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .slantCard(skew: 14)
        }
        .buttonStyle(SlantButtonStyle())
        .rotationEffect(.degrees(even ? -1.5 : 1.2))
        .offset(x: even ? -4 : 8)
    }
}
