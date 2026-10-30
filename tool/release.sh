#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# D-Zero 一括リリーススクリプト (Version Bump -> Quality Gate -> Commit/Push -> pub.dev)
#
# 使い方:
#   ./tool/release.sh [patch|minor|major] [options]
#
# オプション:
#   patch | minor | major   バンプ種別 (デフォルト: patch)
#   --version=X.Y.Z         明示的にバージョンを指定する場合
#   --no-publish            pub.dev への公開をスキップ (バンプ + commit + push のみ)
#   --no-push               git push をスキップ
#   --skip-checks           事前品質ゲート (analyze / complexity / test) をスキップ
#   --allow-dirty           未コミットの変更があってもそのまま含めてリリースコミットを作成
#   -y, --yes               確認プロンプトをスキップ
#   -h, --help              ヘルプを表示
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUMP_TYPE="patch"
EXPLICIT_VERSION=""
DO_PUBLISH=true
DO_PUSH=true
SKIP_CHECKS=false
ALLOW_DIRTY=false
AUTO_YES=false

print_usage() {
  cat <<EOF
使い方: ./tool/release.sh [patch|minor|major] [オプション]

引数・オプション:
  patch | minor | major   セマンティックバージョンのバンプ種別 (デフォルト: patch)
  --version=X.Y.Z         バージョンを直接指定 (例: --version=0.2.0)
  --no-publish            pub.dev へのアップロードをスキップ
  --no-push               git push をスキップ
  --skip-checks           ローカル品質ゲート (analyze / complexity / test) をスキップ
  --allow-dirty           作業ツリーに未コミットの変更があっても続行
  -y, --yes               確認プロンプトをスキップ
  -h, --help              このヘルプを表示
EOF
}

for arg in "$@"; do
  case "$arg" in
    patch|minor|major)
      BUMP_TYPE="$arg"
      ;;
    --version=*)
      EXPLICIT_VERSION="${arg#*=}"
      ;;
    --no-publish)
      DO_PUBLISH=false
      ;;
    --no-push)
      DO_PUSH=false
      ;;
    --skip-checks)
      SKIP_CHECKS=true
      ;;
    --allow-dirty)
      ALLOW_DIRTY=true
      ;;
    -y|--yes)
      AUTO_YES=true
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "❌ 不明なオプションです: $arg" >&2
      print_usage
      exit 1
      ;;
  esac
done

echo "==============================================================="
echo "🚀 D-Zero リリースパイプライン"
echo "==============================================================="

# 1. 作業ツリーのクリーンチェック
if [ "$ALLOW_DIRTY" = false ] && [ -n "$(git status --porcelain)" ]; then
  echo "❌ 未コミットの変更があります。先に変更をコミットするか、--allow-dirty を指定してください。" >&2
  git status -s
  exit 1
fi

CURRENT_VERSION=$(grep -E '^version:[[:space:]]*' packages/d_zero_core/pubspec.yaml | head -n 1 | sed -E 's/^version:[[:space:]]*["'\'']?([^"'\''[:space:]]+)["'\'']?/\1/')
echo "📌 現在のバージョン: v${CURRENT_VERSION}"

# 2. バージョンバンプ & メタデータ同期
if [ -n "$EXPLICIT_VERSION" ]; then
  BUMP_ARG="--set-version=${EXPLICIT_VERSION}"
else
  BUMP_ARG="--bump=${BUMP_TYPE}"
fi

echo ""
echo "🏷️  [1/4] バージョン更新 & メタデータ同期 (${BUMP_ARG})..."
dart run tool/distribute_widgets.dart "$BUMP_ARG" --sync-only

NEW_VERSION=$(grep -E '^version:[[:space:]]*' packages/d_zero_core/pubspec.yaml | head -n 1 | sed -E 's/^version:[[:space:]]*["'\'']?([^"'\''[:space:]]+)["'\'']?/\1/')
echo "✨ 新バージョン: v${CURRENT_VERSION} -> v${NEW_VERSION}"

if [ "$AUTO_YES" = false ]; then
  echo ""
  read -r -p "v${NEW_VERSION} のリリース処理 (品質検証 -> git commit/push -> pub.dev 公開) を続行しますか？ [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *)
      echo "🛑 リリースをキャンセルし、バージョン変更を元に戻します..."
      git checkout -- CHANGELOG.md packages/
      exit 0
      ;;
  esac
fi

# 3. 品質ゲート (コミット前に検証し、壊れたリリースコミットを防ぐ)
if [ "$SKIP_CHECKS" = false ]; then
  echo ""
  echo "🛡️  [2/4] ワークスペース品質ゲートを実行中..."
  flutter analyze
  dart run tool/check_complexity.dart
  flutter test \
    packages/d_zero_core/test \
    packages/d_zero_counter/test \
    packages/d_zero_particles/test \
    packages/d_zero_ui/test \
    packages/d_zero_waveform/test \
    packages/d_zero_chart/test \
    packages/d_zero_fx/test \
    packages/d_zero_canvas/test \
    packages/d_zero_sensor/test \
    packages/d_zero_player/test
else
  echo ""
  echo "⏭️  [2/4] 品質ゲートをスキップしました (--skip-checks)"
fi

# 4. Git Commit & Push (push により GitHub Actions CI -> 自動タグ & Release が起動)
echo ""
echo "📦 [3/4] バージョン v${NEW_VERSION} を Git コミット中..."
git add -A
git commit -m "chore(release): bump version to ${NEW_VERSION}"

if [ "$DO_PUSH" = true ]; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo "⬆️  origin/${CURRENT_BRANCH} へ push 中 (CI 成功後に GitHub Tag & Release '${NEW_VERSION}' が自動作成されます)..."
  git push origin "$CURRENT_BRANCH"
else
  echo "⏭️  git push をスキップしました (--no-push)"
fi

# 5. pub.dev へ一括公開 (ツリーがクリーンな状態で実行)
if [ "$DO_PUBLISH" = true ]; then
  echo ""
  echo "🌐 [4/4] pub.dev へ v${NEW_VERSION} をトポロジカル順で公開中..."
  dart run tool/distribute_widgets.dart --publish --yes --skip-checks
else
  echo ""
  echo "⏭️  [4/4] pub.dev への公開をスキップしました (--no-publish)"
fi

echo ""
echo "==============================================================="
echo "🎉 D-Zero v${NEW_VERSION} のリリース処理が完了しました！"
echo "==============================================================="
