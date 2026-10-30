# 🛠️ D-Zero リリース & 品質管理ツール (`tool/`)

このディレクトリには、`D-Zero` モノレポ（全 10 パッケージ）の品質ゲート検証・バージョン同期・GitHub タグ連携・`pub.dev` 一括公開を自動化する CLI ツール群が含まれています。

---

## 1. 一括リリーススクリプト (`tool/release.sh`)

バージョンバンプ、品質ゲート検証、Git コミット & push（GitHub Actions での自動タグ & Release 作成）、および `pub.dev` へのトポロジカル順アップロードを **1 コマンド** で実行するシェルスクリプトです。

### 基本的な使い方

```bash
# パッチバージョンを +1 (例: 0.1.2 -> 0.1.3) してリリース (確認プロンプトあり)
./tool/release.sh

# 確認プロンプトをスキップして一括リリース (Melos 経由でも実行可: melos run release)
./tool/release.sh --yes
```

### バージョン種別の指定

```bash
# パッチバンプ (0.1.2 -> 0.1.3) [デフォルト]
./tool/release.sh patch

# マイナーバンプ (0.1.2 -> 0.2.0) [または: melos run release:minor]
./tool/release.sh minor

# メジャーバンプ (0.1.2 -> 1.0.0) [または: melos run release:major]
./tool/release.sh major

# バージョン番号を直接指定する場合
./tool/release.sh --version=0.2.0
```

### オプション一覧

| オプション | 説明 |
| :--- | :--- |
| `patch` \| `minor` \| `major` | セマンティックバージョンのインクリメント種別（デフォルト: `patch`） |
| `--version=X.Y.Z` | バージョン番号を直接指定して全パッケージを一括更新 |
| `--no-publish` | `pub.dev` への公開をスキップ（バージョンバンプ + Git commit/push のみ実行） |
| `--no-push` | `git push` をスキップ |
| `--skip-checks` | 事前品質ゲート（`flutter analyze` / 循環的複雑度 / `flutter test`）をスキップ |
| `--allow-dirty` | 作業ツリーに未コミットの変更があってもそのままリリースコミットに含める |
| `-y`, `--yes` | 実行確認プロンプトをスキップ |
| `-h`, `--help` | ヘルプを表示 |

### 内部の自動実行ステップ

1. **作業ツリーチェック**: 未コミットの変更がないか確認（確認プロンプトで `N` を選んだ場合は自動で変更をロールバック）
2. **`[1/4]` バージョン更新 & メタデータ同期**:
   `dart run tool/distribute_widgets.dart --bump=... --sync-only` を呼び出し、全 10 パッケージの `pubspec.yaml`、内部依存バージョン（`d_zero_core: ^X.Y.Z`）、`CHANGELOG.md`、`LICENSE`、`.pubignore`、iOS/macOS SwiftPM ソースを一括同期
3. **`[2/4]` 品質ゲート**:
   コミット前に `flutter analyze`、`dart run tool/check_complexity.dart`、および全 10 パッケージの `flutter test` を実行
4. **`[3/4]` Git Commit & Push**:
   `chore(release): bump version to X.Y.Z` でコミットし `origin/main` へ push
   → **GitHub Actions の CI ([ci.yml](../.github/workflows/ci.yml)) が成功した直後に、[release_tag.yml](../.github/workflows/release_tag.yml) が自動で Git タグ `X.Y.Z` と GitHub Release を作成・更新**
5. **`[4/4]` `pub.dev` 一括公開**:
   作業ツリーがクリーンな状態で `dart run tool/distribute_widgets.dart --publish --yes --skip-checks` を実行し、`d_zero_core` から各 Widget パッケージへトポロジカル順序で `pub.dev` に公開

---

## 2. パッケージ配布・監査 CLI (`tool/distribute_widgets.dart`)

個別の同期や `pub.dev` の Dry-Run 検証、特定パッケージのみの公開を行う Dart CLI です。

```bash
# LICENSE / .pubignore / 内部依存バージョンの同期と Z-Prefix Widget 規約監査のみ実行
dart run tool/distribute_widgets.dart --sync-only

# pub.dev パブリッシュの事前検証 (dry-run) を一括実行
dart run tool/distribute_widgets.dart --dry-run

# 特定のパッケージのみ pub.dev へ公開
dart run tool/distribute_widgets.dart --publish --yes --packages=d_zero_fx,d_zero_sensor

# dist/ ディレクトリにリリース用アーカイブ (.tar.gz) と統合 barrel ファイルを生成
dart run tool/distribute_widgets.dart --bundle --skip-checks
```

---

## 3. 循環的複雑度チェッカー (`tool/check_complexity.dart`)

ワークスペース内のすべての Dart / C++ / Objective-C++ / Swift / Kotlin ソースの McCabe 循環的複雑度（CC）を計測し、上限（推奨 `CC <= 10`、許容上限 `CC <= 15`）を超える関数がある場合に非ゼロ終了コードで失敗させます。

```bash
dart run tool/check_complexity.dart
```
