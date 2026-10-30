# Project Guidelines & Agent Instructions for D-Zero

> このファイルは [AGENTS.md](./AGENTS.md) と同一のプロジェクトルールを定義しています。

`D-Zero` は、Flutter / Impeller 向けの超高性能・ゼロジャンク・ゼロアロケーション（Zero Allocation & Zero Rebuild）ライブラリ群です。
当プロジェクトでコードの追加・変更・リファクタリングを行うすべてのエージェントおよび開発者は、以下の設計原則・命名規約・品質基準を厳格に遵守してください。

---

## 1. Widget 命名規則 (Z-Prefix Rule)

* **配布用 Widget クラスの命名**:
  外部ユーザー・アプリ開発者に配布して利用してもらうすべての公開 Widget クラスは、**必ず prefix に「`Z`」を付与** してください。
  * **例**:
    * `ZPlayer` (ビデオ再生プレイヤー Widget)
    * `ZCounter` (直接描画カウンター Widget)
    * `ZStopwatch` (直接描画ストップウォッチ Widget)
    * `ZDirectSeekBar` / `ZSeekBar` (シークバー Widget)
    * `ZDirectTimeLabel` / `ZTimeLabel` (タイムコード表示 Widget)
* **下位互換性**:
  既存のクラス名を変更した場合は、旧クラス名を `typedef` および `@Deprecated` を用いて提供し、既存コードの破壊的変更を緩和します。
* **内部 RenderBox / 非公開 Widget**:
  Widget ツリーに直接配置する配布 Widget 以外の RenderBox や内部パーツには、`RenderZ...` または実装意図が明確な内部名（例: `RenderZeroCounter`, `RenderDirectSeekBar`）を適切に使用します。

---

## 2. 循環的複雑度計測の遵守 (Cyclomatic Complexity Compliance)

* **複雑度 (McCabe Metric) の上限値**:
  * **推奨**: 1 メソッド / 関数あたりの循環的複雑度（CC）は **10 以下** を維持すること。
  * **許容上限**: いかなるメソッドも **15 を超えてはならない**（CC > 15 はコミット・マージ不可）。
* **リファクタリング基準**:
  * 分岐（`if`, `else`, `switch-case`, `while`, `for`, 三項演算子 `?:`, null 合体 `??`, 論理演算子 `&&`, `||`）が過多になった場合、早期リターン（Guard Clauses）、テーブル駆動、ポリモーフィズム、状態オブジェクト分離を行い、CC を低減します。
  * 特に描画ループ（`paint`）、ジェスチャー判定、プロトコル分岐での複雑化を厳重に抑止します。
* **計測コマンド**:
  ```bash
  # プロジェクト全体の循環的複雑度を自動計測
  dart run tool/check_complexity.dart
  # または Melos スクリプト
  melos run complexity
  ```
  すべての CI パイプラインおよびプルリクエスト前検証で本コマンドが成功（CC > 15 の警告ゼロ）することを必須とします。

---

## 3. テストの厳格化（特にメモリ周りとライフサイクル）

当プロジェクトは「直接描画」「FFI共有メモリ」「ゼロアロケーション」を核としているため、一般的な機能テストに加えて以下のメモリ・リソース周りのテストを厳格に実施します。

* **メモリリーク & ライフサイクルのテスト**:
  * **Widget Unmount / Dispose 時のリソース解放**:
    Widget がツリーから破棄（unmount）された際、関連する `Ticker`、`ChangeNotifier` / `ValueListenable` のリスナー、および内部キャッシュが確実に破棄・停止・購読解除されることを検証するテストを作成すること。
  * **Native FFI 共有メモリの解放**:
    `ZeroPlayerController` などのネイティブメモリを抱えるコンポーネントは、`dispose()` 呼び出し後に C++ 側の構造体が安全に破棄され、メモリリークが発生しないことを検証すること。
* **安全性テスト (Use-After-Free & Double-Free 耐性)**:
  * `dispose()` 済みのコントローラや破棄済みポインタに対してアクセスが行われても、SIGSEGV / クラッシュせず、安全なフォールバック値を返すこと。
  * `dispose()` が複数回連続で呼ばれた場合（二重解放）でも安全に無視されること。
* **ホットパスのゼロアロケーション (Zero-Allocation) ストレステスト**:
  * 描画フレームループ（60fps / 120fps）やホットパスにおいて、ループ毎の String 生成、クロージャ生成、新規 Paint / Path / TextPainter のインスタンス化が発生していないことをストレステストで検証すること。
  * `ZeroPool` や `FloatRingBuffer` を活用し、高頻度処理（10万回以上の反復等）でヒープメモリの肥大化や GC プレッシャーが発生しないことを確認すること。

---

## 4. プロジェクト追加推奨ルール (Best Practices)

### 4.1 Zero Rebuild 原則
* 状態の変更に伴い `State.setState()` をホットパス（タイマー、動画フレーム、センサー入力等）で呼び出してはならない。
* 描画更新は `LeafRenderObjectWidget` + `RenderBox` 内の `markNeedsPaint()` をトリガーにし、Widget ツリーの再構築カスケードを完全に排除する。
* すべてのカスタム RenderBox は `isRepaintBoundary = true` を設定し、祖先・兄弟ウィジェットへの再描画波及を遮断する。

### 4.2 レンダリング時のキャッシュとゼロコピー
* `Canvas.draw...` で使用する `Paint`、フォント描画用のキャッシュ（`ZeroNumberPainter` 等）はフレーム毎に再生成せず、メンバ変数に保持して再利用する。
* 数値・タイムコード描画時は `.toString()` や文字列補間を行わず、ASCII / UTF-16 グリフテーブルから直接描画する。

### 4.3 ワークスペース品質ゲート
すべての変更はコミット前に以下の全検証をパスしなければならない：
```bash
# 1. 解析
melos run analyze
# 2. 循環的複雑度
melos run complexity
# 3. テスト（メモリ・異常系含む）
melos run test
# 4. ベンチマーク（任意だが重要変更時は必須）
melos run benchmark
```
