# ⚡️ ZERO OVERDRIVE (`apps/games`)

`D-Zero` の全パッケージ群（パーティクル・エフェクト・ゼロアロケーションUI・カウンター・キャンバス・波形・チャート）をフル活用した、**大量パーティクル＆ネオン弾幕サバイバルシューティングゲーム** です。

プレイ中にいつでも **「⚡️ D-Zero System (Zero-Allocation / SIMD SoA)」** と **「❌ Flutter Standard (`setState` + `CustomPainter` + OOP)」** をリアルタイムに切り替え、FPS・Widget Rebuild 数・Heap Allocation 数の圧倒的な差を体感できます。

---

## 🚀 起動方法

```bash
cd apps/games
flutter run -d macos
```

---

## 🎮 操作方法

- **移動**:
  - 画面左下の `ZJoystick`（仮想アナログパッド）をドラッグ
  - またはキーボードの `WASD` / `矢印キー`
  - デフォルトで **🤖 Auto-Pilot（自動戦闘デモモード）** が ON になっているため、起動直後からエンジン比較やエフェクト負荷テストに集中できます。
- **照準 & ショックウェーブ**:
  - ステージ上をタップ / ドラッグ（クリック位置に `ZRipple` 衝撃波が発生し、その方向へプラズマ弾を連射）
- **必殺技 (`💥 OVERDRIVE NOVA`)**:
  - 画面右下の `ZLiquidProgress` エネルギーコア、または `Space` キーで発動（全方位72連プラズマ弾 ＋ マルチカラー `ZConfetti` バースト ＋ 多層 `ZRipple` 衝撃波）
- **エンジン切替 & 負荷プリセット**:
  - 画面上部の `⚡️ D-Zero System` / `❌ Flutter Standard` ボタン（または `E` キー）で即座にシステムを切り替え可能（スコア・敵・パーティクル状態はそのまま引き継がれます）。
  - `Normal (3K)` / `Heavy (10K)` / `Extreme (22K)` プリセットおよび `💥 Chaos Burst (+500)` ボタン（`C` キー）でパーティクル＆弾幕密度を一気に引き上げられます。

---

## 🧩 使用している D-Zero コンポーネント

| パッケージ | 使用 Widget / Controller | 役割 |
| :--- | :--- | :--- |
| `d_zero_particles` | `ZParticles`, `ZeroParticleController`, `ZConfetti`, `ZeroConfettiController` | 4レーン SIMD 駆動の背景粒子（最大 22,000 個）＆撃破時リボン破片バースト |
| `d_zero_fx` | `ZRipple`, `ZLiquidProgress`, `ZBlur`, `ZShimmer` | 衝撃波エフェクト、必殺技液体ゲージ、すりガラス HUD、ネオンシマーバナー |
| `d_zero_canvas` | `ZInfiniteGrid`, `ZDanmaku` | パララックス無限サイバーグリッド、キルストリーク＆エンジン切替弾幕通知 |
| `d_zero_counter` | `ZFPSMonitor`, `ZCounter`, `ZStopwatch`, `ZPriceTicker` | 0 String アロケーションのスコア・撃破数・Rebuild カウンター・メモリ・FPS 監視 |
| `d_zero_ui` | `ZJoystick`, `ZLinearProgress`, `ZButton`, `ZCard`, `ZBadge`, `ZSlider` | 仮想ジョイスティック、HP/熱量バー、火花倍率スライダー、ウェーブバッジ |
| `d_zero_waveform` | `ZSpectrumAnalyzer`, `ZeroSpectrumController` | 射撃・爆発に連動するリアルタイム・バトルスペクトラム |
| `d_zero_chart` | `ZSparkline`, `ZeroChartController` | フレームタイム (ms) のリアルタイム推移スパークライン |
| `d_zero_core` | `ZLeafWidget`, `ZeroRenderBox`, `ZeroNumberPainter`, `ZeroIntNotifier` | カスタムステージ `ZGameStage` (`RenderZGameStage`) の GPU バッチ描画基盤 |
