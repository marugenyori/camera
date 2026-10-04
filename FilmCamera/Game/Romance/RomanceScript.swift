import SwiftUI

// 恋愛アドベンチャー「放課後メモリーズ」のシナリオ。
// 2000 年代のギャルゲー（To Heart など）の雰囲気をまねた、オリジナルの話と登場人物。
// 1 週間（月〜金）の朝と放課後を過ごし、放課後に会いに行った子と、選択肢で好感度が変わる。
// 土曜の桜まつりで、いちばん仲良くなった子のエンディング（足りなければノーマルエンド）

enum Speaker: Equatable {
    case narration
    case me
    case heroine(Heroine)
}

indirect enum Step {
    case bg(Backdrop)
    case show(Heroine, Face)
    case hide
    case line(Speaker, Face?, String)
    case choice([Option])
    case love(Heroine, Int)
    case music(GameAudio.Song)
    case flash
}

struct Option {
    let text: String
    let steps: [Step]
}

/// 放課後に行ける場所
struct Spot: Identifiable {
    let name: String
    let systemImage: String
    let heroine: Heroine
    var id: String { name }
}

private func n(_ text: String) -> Step { .line(.narration, nil, text) }
private func me(_ text: String) -> Step { .line(.me, nil, text) }
private func h(_ heroine: Heroine, _ face: Face, _ text: String) -> Step { .line(.heroine(heroine), face, text) }
private func opt(_ text: String, _ heroine: Heroine, _ love: Int, _ steps: Step...) -> Option {
    Option(text: text, steps: [.love(heroine, love)] + steps)
}

enum RomanceScript {
    static let title = "放課後メモリーズ"
    static let subtitle = "〜桜色のアルバム〜"
    static let heroName = "ユウ"
    static let days = 5
    /// エンディングに入るのに必要な好感度
    static let endingLove = 8

    static func dayTitle(_ day: Int) -> String {
        ["4月8日（月）", "4月9日（火）", "4月10日（水）", "4月11日（木）", "4月12日（金）", "4月13日（土）"][min(max(day, 1), 6) - 1]
    }

    static func spots(_ day: Int) -> [Spot] {
        switch day {
        case 1: return [Spot(name: "屋上", systemImage: "sun.max", heroine: .hinata),
                        Spot(name: "図書室", systemImage: "books.vertical", heroine: .shizuku),
                        Spot(name: "写真部の部室", systemImage: "camera", heroine: .rin)]
        case 2: return [Spot(name: "商店街", systemImage: "storefront", heroine: .hinata),
                        Spot(name: "図書室", systemImage: "books.vertical", heroine: .shizuku),
                        Spot(name: "中庭", systemImage: "leaf", heroine: .rin)]
        case 3: return [Spot(name: "教室", systemImage: "pencil.and.ruler", heroine: .hinata),
                        Spot(name: "夜の屋上", systemImage: "moon.stars", heroine: .shizuku),
                        Spot(name: "写真部の部室", systemImage: "camera", heroine: .rin)]
        case 4: return [Spot(name: "商店街", systemImage: "storefront", heroine: .hinata),
                        Spot(name: "図書室", systemImage: "books.vertical", heroine: .shizuku),
                        Spot(name: "屋上", systemImage: "sun.max", heroine: .rin)]
        default: return [Spot(name: "夕焼けの屋上", systemImage: "sunset", heroine: .hinata),
                         Spot(name: "図書室", systemImage: "books.vertical", heroine: .shizuku),
                         Spot(name: "写真部の部室", systemImage: "camera", heroine: .rin)]
        }
    }

    // MARK: - 朝

    static func morning(_ day: Int) -> [Step] {
        switch day {
        case 1: return prologue
        case 2: return [
            .music(.school), .bg(.street),
            h(.hinata, .smile, "おはよ、ユウちゃん！　今日はちゃんと起きてたね"),
            me("たまにはな"),
            h(.hinata, .laugh, "えらいえらい。明日もその調子でね"),
            n("坂の上から、聞き覚えのある声が飛んできた。"),
            h(.rin, .smile, "あ、昨日の先輩！　おはようございまーす！"),
            h(.rin, .blush, "……べ、別に先輩にあいさつしたんじゃないから！　ついでよ、ついで！"),
            n("金色のツインテールが、あっという間に遠ざかっていく。"),
            h(.hinata, .surprised, "……ユウちゃん、いつのまに一年生の知り合いができたの？"),
        ]
        case 3: return [
            .music(.school), .bg(.classroom),
            n("教室に入ると、窓際の席から小さな声がした。"),
            h(.shizuku, .normal, "……おはよう"),
            n("白石しずくのほうからあいさつしてくるなんて、めずらしい。"),
            me("お、おはよう"),
            h(.hinata, .surprised, "し、白石さんがあいさつしてる……！"),
            h(.hinata, .normal, "ユウちゃん、何かしたの？"),
            me("何もしてないって"),
        ]
        case 4: return [
            .music(.school), .bg(.street),
            h(.hinata, .smile, "ユウちゃん、今日のお弁当は自信作だよ！"),
            h(.hinata, .shy, "からあげ、ちょっと多めに入れといたから……"),
            .choice([
                opt("ひなたの料理、好きだよ", .hinata, 1,
                    h(.hinata, .blush, "す、好き……！？　お、お料理の話だよね！？　うん！")),
                opt("太らせる気か？", .hinata, 0,
                    h(.hinata, .angry, "もう！　せっかく作ったのに！")),
            ]),
            n("桜並木は、もう葉桜になりかけていた。"),
        ]
        default: return [
            .music(.school), .bg(.street),
            h(.hinata, .normal, "明日はいよいよ、桜まつりだね"),
            h(.hinata, .shy, "……ねえ、ユウちゃんは、誰と行くの？"),
            .choice([
                opt("ひなたは？", .hinata, 1,
                    h(.hinata, .blush, "わ、わたし！？　わたしは……ないしょ！")),
                opt("まだ決めてない", .hinata, 0,
                    h(.hinata, .smile, "……そっか。決まったら、教えてね")),
            ]),
            n("今日の放課後が、たぶん大事になる。なんとなく、そんな気がした。"),
        ]
        }
    }

    private static let prologue: [Step] = [
        .music(.school), .bg(.roomMorning),
        n("春。カーテンのすき間から、やわらかい光が差しこんでいる。"),
        n("「……ユウちゃん！　起きて！　ユウちゃんってば！」"),
        n("窓の外から、聞き慣れた声がする。"),
        h(.hinata, .smile, "やっと起きた！　もう、新学期そうそう遅刻する気？"),
        n("朝倉ひなた。隣の家に住む、生まれたときからの幼なじみだ。"),
        me("……あと五分……"),
        h(.hinata, .angry, "だーめ！　ほら、着替えて！　玄関で待ってるからね！"),
        .hide, .bg(.street),
        n("桜並木の坂道を、ひなたと並んで歩く。"),
        h(.hinata, .smile, "今年も同じクラスだといいね"),
        me("腐れ縁だな"),
        h(.hinata, .blush, "く、腐れ縁って言わないでよ……"),
        .hide,
        n("角を曲がった、そのとき——"),
        .flash,
        n("「きゃっ！？」"),
        n("誰かと思いきりぶつかった。"),
        h(.rin, .surprised, "いったぁ……ちょっと！　どこ見て歩いてるのよ！"),
        n("金色のツインテール。首から古いフィルムカメラを下げた女の子だ。"),
        .choice([
            opt("「ごめん、大丈夫か？」", .rin, 2,
                h(.rin, .shy, "……べ、別に。カメラが無事ならいいのよ")),
            opt("「そっちこそ前見てなかっただろ」", .rin, 1,
                h(.rin, .angry, "なっ……！　し、失礼な先輩ね！")),
        ]),
        h(.rin, .angry, "……覚えてなさいよ！"),
        .hide,
        n("女の子は、ぷんぷんしながら走り去っていった。"),
        h(.hinata, .surprised, "今の子、一年生かな？　カメラ持ってたね"),
        .hide, .bg(.classroom),
        n("教室。窓際の席で、静かに本を読んでいる女の子がいる。"),
        n("白石しずく。去年から同じクラスだけど、ほとんど話したことはない。"),
        h(.shizuku, .normal, "……"),
        n("目が合った……気がする。"),
        h(.shizuku, .normal, "……何か用？"),
        .choice([
            opt("「何読んでるの？」", .shizuku, 2,
                h(.shizuku, .surprised, "……星の本。『銀河鉄道の夜』"),
                h(.shizuku, .shy, "……好きなの、昔から")),
            opt("「いや、なんでもない」", .shizuku, 0,
                h(.shizuku, .normal, "……そう")),
        ]),
        .hide,
        n("始業のチャイムが鳴った。新しい一年が、始まる。"),
    ]

    // MARK: - 放課後

    static func event(_ heroine: Heroine, day: Int) -> [Step] {
        let index = min(max(day, 1), 5) - 1
        switch heroine {
        case .hinata: return hinataEvents[index]
        case .shizuku: return shizukuEvents[index]
        case .rin: return rinEvents[index]
        }
    }

    static func goHome(_ day: Int) -> [Step] {
        [.music(.school), .bg(.street), .hide,
         n("今日は、まっすぐ家に帰ることにした。"),
         n("夕焼けの坂道を、一人で歩く。……少しだけ、さみしい。")]
    }

    private static let hinataEvents: [[Step]] = [
        [
            .music(.school), .bg(.rooftopSunset),
            n("屋上に出ると、フェンスのそばにひなたがいた。"),
            h(.hinata, .smile, "あ、ユウちゃん。来ると思った"),
            me("なんでわかるんだよ"),
            h(.hinata, .laugh, "昔から、何かあるとここに来るでしょ。高いところ好きだよね"),
            h(.hinata, .normal, "ねえ、明日からお弁当作ってきてあげよっか？"),
            .choice([
                opt("「いいのか？　頼む」", .hinata, 2,
                    h(.hinata, .blush, "う、うん！　はりきっちゃうから！")),
                opt("「子どもじゃないんだから」", .hinata, 0,
                    h(.hinata, .sad, "……そっか。そうだよね"),
                    h(.hinata, .smile, "でも、気が変わったら言ってね")),
            ]),
            .hide,
            n("夕焼けの中、二人で並んで帰った。"),
        ],
        [
            .music(.school), .bg(.shopping),
            n("商店街を歩いていると、八百屋の前でひなたが真剣な顔をしていた。"),
            h(.hinata, .surprised, "わっ、ユウちゃん！？"),
            h(.hinata, .shy, "えっと……お弁当の材料、選んでたの。卵焼きは、甘いのとしょっぱいの、どっちが好き？"),
            .choice([
                opt("「甘いの」", .hinata, 2,
                    h(.hinata, .laugh, "やっぱり！　小さいころから変わってないね")),
                opt("「しょっぱいの」", .hinata, 1,
                    h(.hinata, .surprised, "えっ、いつのまに！？"),
                    h(.hinata, .smile, "……ユウちゃんのこと、まだ知らないこと、あるんだね")),
            ]),
            .hide,
            n("買い物袋を半分持つと、ひなたは少しだけうれしそうに笑った。"),
        ],
        [
            .music(.school), .bg(.classroomEvening),
            n("放課後の教室で、ひなたが一人で掃除をしていた。"),
            me("当番、ほかのやつは？"),
            h(.hinata, .sad, "みんな部活があるって……。いいの、すぐ終わるから"),
            .choice([
                opt("「手伝うよ」", .hinata, 2,
                    n("ほうきを取ると、ひなたは目を丸くした。"),
                    h(.hinata, .blush, "……ありがと。ユウちゃんのそういうとこ、ずるい")),
                opt("「たまには断れよ」", .hinata, 1,
                    h(.hinata, .sad, "……うん。わかってるんだけどね"),
                    h(.hinata, .smile, "でも、心配してくれてうれしい")),
            ]),
            h(.hinata, .shy, "ねえ……ユウちゃんは、好きな人とか、いる？"),
            me("な、なんだよ急に"),
            h(.hinata, .laugh, "な、なんでもない！　忘れて！"),
        ],
        [
            .music(.school), .bg(.shopping),
            h(.hinata, .smile, "ユウちゃん！　新しいクレープ屋さんができたんだって。行こ！"),
            n("半ば引っぱられるように、クレープ屋の列に並んだ。"),
            h(.hinata, .laugh, "いちごとチョコ、どっちにしようかなぁ……"),
            .choice([
                opt("「半分こしようぜ」", .hinata, 2,
                    h(.hinata, .blush, "は、半分こ……！？　う、うん……"),
                    n("ひなたの顔は、いちごより赤かった。")),
                opt("「両方食えば？」", .hinata, 1,
                    h(.hinata, .angry, "太っちゃうでしょ！"),
                    h(.hinata, .laugh, "……でも、ユウちゃんのおごりなら考える")),
            ]),
        ],
        [
            .music(.love), .bg(.rooftopSunset),
            n("夕焼けの屋上。ひなたはフェンスにもたれて、遠くを見ていた。"),
            h(.hinata, .normal, "明日、桜まつりだね"),
            h(.hinata, .shy, "……ねえ、ユウちゃん。小さいころ、桜の丘で約束したの、覚えてる？"),
            .choice([
                opt("「覚えてるよ」", .hinata, 3,
                    h(.hinata, .surprised, "……ほんとに？"),
                    h(.hinata, .blush, "……よかった。わたし、ずっと覚えてたんだ")),
                opt("「……なんだっけ」", .hinata, 0,
                    h(.hinata, .sad, "……ううん、いいの。小さいころの話だもんね")),
            ]),
            h(.hinata, .smile, "明日、丘の上で待ってるから"),
        ],
    ]

    private static let shizukuEvents: [[Step]] = [
        [
            .music(.school), .bg(.library),
            n("図書室には、しずくが一人でいた。図書委員らしい。"),
            h(.shizuku, .normal, "……返却？"),
            me("いや、なんとなく"),
            h(.shizuku, .normal, "……そう。静かにしていてくれるなら、いい"),
            n("しずくの読んでいる本の表紙に、星座の絵が見えた。"),
            .choice([
                opt("「星、好きなの？」", .shizuku, 2,
                    h(.shizuku, .surprised, "……どうして"),
                    me("表紙"),
                    h(.shizuku, .shy, "……うん。夜、屋上から見るのが好き")),
                opt("「難しそうな本だな」", .shizuku, 1,
                    h(.shizuku, .normal, "……そうでもない。読めば、わかる")),
            ]),
            .hide,
            n("閉館のチャイムまで、二人で黙って本を読んだ。不思議と、居心地がよかった。"),
        ],
        [
            .music(.school), .bg(.library),
            n("しずくが、高い棚の本に手を伸ばして、つま先立ちしていた。"),
            h(.shizuku, .sad, "……届かない"),
            .choice([
                opt("「取ってやるよ」", .shizuku, 2,
                    n("本を渡すと、しずくは小さく頭を下げた。"),
                    h(.shizuku, .shy, "……ありがとう。あなた、背、高いのね")),
                opt("「台、持ってこようか」", .shizuku, 1,
                    h(.shizuku, .smile, "……気がきくのね")),
            ]),
            h(.shizuku, .normal, "……この本、読んでみる？　わたしの、いちばん好きな話"),
            me("じゃあ、借りてみる"),
            h(.shizuku, .smile, "……感想、聞かせて"),
        ],
        [
            .music(.love), .bg(.rooftopNight),
            n("日が暮れた屋上で、しずくが空を見上げていた。"),
            h(.shizuku, .surprised, "……あなた。どうしてここに"),
            me("星、見てるって言ってたから"),
            h(.shizuku, .shy, "……覚えてたの"),
            h(.shizuku, .normal, "あれが、うしかい座のアークトゥルス。春の夜に、いちばん明るい星"),
            .choice([
                opt("「きれいだな」", .shizuku, 2,
                    h(.shizuku, .smile, "……うん。ひとりで見るより、きれい")),
                opt("「全然わからん」", .shizuku, 1,
                    h(.shizuku, .laugh, "ふふ……正直ね"),
                    n("しずくが声を出して笑うのを、初めて見た。")),
            ]),
        ],
        [
            .music(.school), .bg(.library),
            h(.shizuku, .normal, "……読んだ？"),
            me("ああ。最後、泣きそうになった"),
            h(.shizuku, .surprised, "……あなたも？"),
            h(.shizuku, .shy, "わたし、本の話ができる人、いなかったから……"),
            .choice([
                opt("「これからは俺がいるだろ」", .shizuku, 3,
                    h(.shizuku, .blush, "……っ。……ばか")),
                opt("「また貸してくれよ」", .shizuku, 1,
                    h(.shizuku, .smile, "……うん。たくさん、ある")),
            ]),
        ],
        [
            .music(.love), .bg(.libraryEvening),
            h(.shizuku, .normal, "……明日、桜まつり"),
            h(.shizuku, .shy, "丘の上は、星もよく見えるの。……もし、よかったら"),
            .choice([
                opt("「一緒に行こう」", .shizuku, 3,
                    h(.shizuku, .blush, "……うん。待ってる")),
                opt("「考えとく」", .shizuku, 0,
                    h(.shizuku, .sad, "……そう。無理には、言わない")),
            ]),
        ],
    ]

    private static let rinEvents: [[Step]] = [
        [
            .music(.school), .bg(.clubroom),
            n("「写真部」と書かれた部屋をのぞくと、今朝の女の子がいた。"),
            h(.rin, .surprised, "あーっ！　今朝ぶつかった人！"),
            h(.rin, .angry, "なによ、文句でも言いに来たの？"),
            n("部屋の中には、ほかに誰もいない。"),
            h(.rin, .sad, "……見ればわかるでしょ。部員、わたしひとりなの。来週までに三人集まらないと、廃部"),
            .choice([
                opt("「手伝おうか」", .rin, 2,
                    h(.rin, .surprised, "えっ……"),
                    h(.rin, .shy, "べ、別に頼んでないけど！　……どうしてもって言うなら")),
                opt("「大変だな」", .rin, 1,
                    h(.rin, .angry, "他人事みたいに言わないでよ！")),
            ]),
            h(.rin, .normal, "早乙女リン。一年。……先輩の名前は？"),
            me("ユウ"),
            h(.rin, .smile, "ふーん。じゃあ、ユウ先輩。覚えとく"),
        ],
        [
            .music(.school), .bg(.courtyard),
            n("中庭で、リンがカメラを構えていた。"),
            h(.rin, .normal, "しーっ！　今、ネコがいいとこなの"),
            n("カシャ、とシャッターの音が小さく響いた。"),
            h(.rin, .laugh, "撮れた！　見て見て……って、フィルムだから見られないんだった"),
            .choice([
                opt("「なんでフィルムなんだ？」", .rin, 2,
                    h(.rin, .shy, "……おじいちゃんのカメラなの。現像するまでどう写ってるかわからないのが、ドキドキして好き")),
                opt("「スマホのほうが楽じゃない？」", .rin, 1,
                    h(.rin, .angry, "わかってないなー！　この不便さがいいのよ！")),
            ]),
            h(.rin, .smile, "先輩も撮ってあげる。ほら、笑って！"),
        ],
        [
            .music(.school), .bg(.clubroom),
            h(.rin, .sad, "……部員募集のポスター、全部はがされてた"),
            n("リンの目が、少し赤い。"),
            .choice([
                opt("「一緒に作り直そう」", .rin, 2,
                    h(.rin, .surprised, "……先輩"),
                    h(.rin, .blush, "……ほんと、おせっかいなんだから"),
                    n("二人で、日が暮れるまでポスターを描いた。")),
                opt("「元気出せよ」", .rin, 1,
                    h(.rin, .angry, "……泣いてないし！")),
            ]),
        ],
        [
            .music(.school), .bg(.rooftop),
            h(.rin, .smile, "先輩！　入部希望の子が来たの！　あと一人で三人！"),
            h(.rin, .shy, "……だから、その……先輩、入部してくれない？"),
            .choice([
                opt("「いいよ、入る」", .rin, 3,
                    h(.rin, .laugh, "ほんと！？　やったー！"),
                    h(.rin, .blush, "……べ、別に先輩だからうれしいわけじゃないんだからね！")),
                opt("「考えさせて」", .rin, 0,
                    h(.rin, .sad, "……そっか。そうだよね")),
            ]),
        ],
        [
            .music(.love), .bg(.clubroom),
            h(.rin, .normal, "現像、できたよ"),
            n("写真には、中庭で笑う自分が写っていた。"),
            h(.rin, .shy, "……この一枚、すごくよく撮れたの。先輩、いい顔してる"),
            h(.rin, .blush, "明日の桜まつり……撮影、付き合ってくれない？　二人で"),
            .choice([
                opt("「もちろん」", .rin, 3,
                    h(.rin, .smile, "……約束だからね！")),
                opt("「人ごみはちょっと」", .rin, 0,
                    h(.rin, .angry, "……ばか先輩")),
            ]),
        ],
    ]

    // MARK: - エンディング

    /// エンディングの話と、題名
    static func ending(_ heroine: Heroine?) -> (steps: [Step], title: String) {
        switch heroine {
        case .hinata?:
            return ([
                .music(.love), .bg(.sakuraHill),
                n("桜まつりの夜。ぼんぼりの灯りの中、丘の上の大きな桜の下に、ひなたがいた。"),
                h(.hinata, .smile, "来てくれた"),
                h(.hinata, .shy, "ここでね、小さいころ、ユウちゃんが言ったんだよ。「大きくなったら、ひなたをおよめさんにする」って"),
                me("……言ったな、そんなこと"),
                h(.hinata, .laugh, "ふふ、ユウちゃん、真っ赤"),
                h(.hinata, .blush, "わたしね、あの日からずっと……ユウちゃんのことが好き"),
                h(.hinata, .shy, "幼なじみじゃなくて……わたしを、ユウちゃんの彼女にしてくれますか？"),
                me("……ああ。俺も、ひなたが好きだ"),
                h(.hinata, .sad, "……うれしくて、泣いちゃいそう"),
                h(.hinata, .laugh, "……ううん、笑う！　だって、今いちばん幸せだもん！"),
                .hide,
                n("桜の花びらが、二人の上に降りそそいでいた。"),
            ], "ひなたエンド　〜約束の桜〜")
        case .shizuku?:
            return ([
                .music(.love), .bg(.sakuraHill),
                n("桜まつりの夜。人の少ない丘の上で、しずくが星を見ていた。"),
                h(.shizuku, .smile, "……来てくれた"),
                h(.shizuku, .normal, "今日はね、星と桜、両方見られる日なの"),
                h(.shizuku, .shy, "わたし、ずっと本の中の世界のほうが好きだった。現実は、静かすぎて、さみしくて"),
                h(.shizuku, .blush, "でも、あなたと話すようになって……物語の続きが、知りたくなった"),
                h(.shizuku, .blush, "……好き。あなたのことが"),
                me("俺も、しずくが好きだ"),
                h(.shizuku, .smile, "……ありがとう。これからのお話、二人で読んでいこう"),
                .hide,
                n("夜空のアークトゥルスが、いつもより明るく見えた。"),
            ], "しずくエンド　〜星降る桜〜")
        case .rin?:
            return ([
                .music(.love), .bg(.sakuraHill),
                n("桜まつりの夜。ぼんぼりの灯りを、リンが夢中で撮っている。"),
                h(.rin, .laugh, "先輩、こっちこっち！　桜とぼんぼり、最高の組み合わせ！"),
                h(.rin, .normal, "……ねえ。最後の一枚、何を撮るか決めてたの"),
                n("リンが、カメラをこちらに向けた。"),
                h(.rin, .blush, "わたしがいちばん撮りたいのは……先輩なの"),
                h(.rin, .shy, "……すき。先輩のことが、すき。……返事、現像するまで待てないんだけど"),
                me("俺も、リンが好きだよ"),
                h(.rin, .blush, "……っ！　……い、今の顔、絶対撮ったからね！"),
                .hide,
                n("シャッターの音と一緒に、春の風が吹いた。"),
            ], "リンエンド　〜はじめての一枚〜")
        case nil:
            return ([
                .music(.school), .bg(.sakuraHill),
                n("桜まつりの夜。結局、一人で丘に来てしまった。"),
                n("ぼんぼりの灯りが、少しだけまぶしい。"),
                h(.hinata, .surprised, "……あれ、ユウちゃん？　一人？"),
                h(.hinata, .smile, "わたしも。……じゃあ、一緒に見よっか。幼なじみとして、ね"),
                .hide,
                n("来年の春は、何かが変わっているだろうか。"),
            ], "ノーマルエンド　〜いつもの春〜")
        }
    }
}
