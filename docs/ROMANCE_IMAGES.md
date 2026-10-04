# 放課後メモリーズの画像の入れ方

画像は `FilmCamera/Game/Romance/Images/` に、下の名前で置く（PNG か JPG）。
置いた画像だけが使われ、ない画像は今までどおり図形の絵になる。全部そろえなくてよい。

- 他人が描いた絵（To Heart などの公式絵、ネットで拾った絵）は使わない。自分で描いた絵、AI で作った絵、利用規約で使ってよいと書かれた素材だけ
- 画像の大きさは 1 枚 2MB くらいまでが目安（多すぎるとアプリが重くなる）

## 立ち絵（背景が透明の PNG）

胸〜腰から上、正面向き、縦長（2:3 くらい）。名前は `子_表情.png`。
**最低限 `hinata_normal.png` `shizuku_normal.png` `rin_normal.png` の 3 枚**があれば、ほかの表情はその絵で代用する。

| 子 | ふつう | にっこり | 笑う | 驚き | 悲しい | 怒り | 照れ（赤面） | 恥ずかしい（目をそらす） |
|---|---|---|---|---|---|---|---|---|
| ひなた | hinata_normal | hinata_smile | hinata_laugh | hinata_surprised | hinata_sad | hinata_angry | hinata_blush | hinata_shy |
| しずく | shizuku_normal | shizuku_smile | shizuku_laugh | shizuku_surprised | shizuku_sad | shizuku_angry | shizuku_blush | shizuku_shy |
| リン | rin_normal | rin_smile | rin_laugh | rin_surprised | rin_sad | rin_angry | rin_blush | rin_shy |

## 背景（縦長 9:16）

| 名前 | 場所 |
|---|---|
| bg_room_morning | 朝の主人公の部屋 |
| bg_street | 桜並木の通学路（朝） |
| bg_classroom | 教室（昼） |
| bg_classroom_evening | 夕方の教室 |
| bg_library | 図書室 |
| bg_library_evening | 夕方の図書室 |
| bg_rooftop | 屋上（昼） |
| bg_rooftop_sunset | 夕焼けの屋上 |
| bg_rooftop_night | 夜の屋上（星空） |
| bg_clubroom | 写真部の部室（壁に写真、赤い暗室ランプ） |
| bg_courtyard | 中庭（桜の木とベンチ） |
| bg_shopping | 夕方の商店街 |
| bg_sakura_hill | 夜の桜の丘（大きな桜、ぼんぼり） |
| title | タイトル画面の絵 |

## イベント CG（縦長 9:16、画面いっぱいに出る一枚絵）

| 名前 | 場面 |
|---|---|
| cg_bump | 通学路の角でリンとぶつかって、リンがしりもち |
| cg_hinata_sunset | 夕焼けの屋上で、フェンスにもたれるひなた |
| cg_shizuku_stars | 夜の屋上で、星を見上げるしずく |
| cg_rin_photo | リンが現像した、中庭で笑う主人公の写真 |
| cg_hinata_end | 夜の桜の下、涙ぐんで笑うひなた（告白） |
| cg_shizuku_end | 星空と桜の下、めがねのしずくがほほえむ（告白） |
| cg_rin_end | ぼんぼりの灯りの中、カメラを構えて赤くなるリン（告白） |

## AI で作るときの頼み方（ChatGPT などの画像生成）

同じ子の表情違いは、**同じ会話の中で**「さっきと同じキャラ・同じ服で、表情だけ〇〇にして」と頼むと、顔がそろいやすい。

共通で最初に付ける文：

> 2000年代前半の PC 恋愛アドベンチャーゲームの立ち絵。セル画風のアニメ塗り、大きな瞳、やわらかい色。胸から上、正面向き。紺のセーラー服。背景は透明（透過 PNG）。縦長。

- ひなた：「明るい幼なじみの女子高生。肩までのオレンジがかった茶髪のショートボブ、前髪に黄色い星のヘアピン、琥珀色の瞳、赤いスカーフ。元気な笑顔」
- しずく：「物静かな図書委員の女子高生。腰までの青みがかった黒髪ストレート、ぱっつん前髪、細いめがね、紫の瞳、赤いスカーフ。落ち着いた表情」
- リン：「勝ち気な一年生の女子高生。金髪のツインテールに赤いリボン、水色の瞳、緑のスカーフ、首から古いフィルムカメラを下げている。ツンとした表情」

背景：「2000年代の PC 恋愛アドベンチャーゲームの背景画。人物なし。縦長 9:16。〇〇（上の表の場所）」

## アプリに入れる方法

どちらか好きなほうで。

1. **チャットに画像を貼る（いちばん簡単）**：iPhone から Claude に画像を送り、「これを hinata_smile にして」のように名前を伝える。Claude がリポジトリに入れてビルドする
2. **GitHub に自分で上げる**：PC のブラウザで https://github.com/marugenyori/camera/tree/main/FilmCamera/Game/Romance/Images を開き、右上の「Add file」→「Upload files」で画像をまとめて入れ、「Commit changes」。そのあと TestFlight 付きでビルドする
