import 'dart:convert';
import 'dart:io';

/// D-Zero 配布用 Widget パッケージ一括検証・同期・パブリッシュ & バンドルツール
///
/// 使い方:
///   dart run tool/distribute_widgets.dart [options]
///
/// 主なオプション:
///   --dry-run             pub.dev パブリッシュの事前検証を実行 (デフォルト)
///   --publish             依存関係のトポロジカル順序で pub.dev へ一括公開
///   --yes, -y             --publish 時の確認プロンプトをスキップ (CI 用)
///   --sync-only           LICENSE / .pubignore / 内部依存バージョンの同期と Z-Widget 監査のみ実行
///   --set-version=X.Y.Z   対象パッケージのバージョンを一括設定し内部依存制約も更新
///   --bump=TYPE           バージョンを一括バンプ (patch | minor | major)
///   --packages=a,b        対象パッケージをカンマ区切りで指定 (例: d_zero_core,d_zero_counter)
///   --skip-checks         事前品質ゲート (analyze / complexity / test) をスキップ
///   --with-benchmark      事前品質ゲートにマイクロベンチマークを追加
///   --bundle              dist/ ディレクトリに配布用アーカイブ (.tar.gz) とマニフェストを出力
///   --help, -h            ヘルプを表示
Future<void> main(List<String> args) async {
  final config = _CliConfig.parse(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  _printBanner();

  final allPackages = _discoverPublishablePackages(Directory('packages'));
  if (allPackages.isEmpty) {
    stderr.writeln('❌ packages/ 配下に配布可能なパッケージが見つかりませんでした。');
    exit(1);
  }

  final sortedAll = _topologicalSort(allPackages);
  final targetPackages = _filterPackages(sortedAll, config.packageFilter);

  if (config.newVersion != null || config.bumpType != null) {
    _applyVersionUpdate(sortedAll, targetPackages, config);
  }

  _syncPackageMetadata(sortedAll);
  _auditExportedWidgets(targetPackages);
  _printPackageTable(targetPackages);

  if (config.syncOnly) {
    stdout.writeln('\n✅ パッケージ同期および Z-Prefix Widget 監査が完了しました。');
    return;
  }

  if (!config.skipChecks) {
    await _runQualityGates(
      allPackages: sortedAll,
      withBenchmark: config.withBenchmark,
    );
  }

  if (config.createBundle) {
    await _generateDistributionBundle(targetPackages, config.bundleDir);
  }

  final publishOk = await _executePubWorkflow(targetPackages, config);
  if (!publishOk) {
    exit(1);
  }
}

class _CliConfig {
  final bool showHelp;
  final bool publish;
  final bool autoConfirm;
  final bool syncOnly;
  final bool skipChecks;
  final bool withBenchmark;
  final bool createBundle;
  final String bundleDir;
  final String? newVersion;
  final String? bumpType;
  final Set<String> packageFilter;

  const _CliConfig({
    required this.showHelp,
    required this.publish,
    required this.autoConfirm,
    required this.syncOnly,
    required this.skipChecks,
    required this.withBenchmark,
    required this.createBundle,
    required this.bundleDir,
    required this.newVersion,
    required this.bumpType,
    required this.packageFilter,
  });

  static _CliConfig parse(List<String> args) {
    final flagSet = args.toSet();
    final kvMap = <String, String>{};
    for (final arg in args) {
      final eqIndex = arg.indexOf('=');
      if (arg.startsWith('--') && eqIndex > 2) {
        kvMap[arg.substring(2, eqIndex)] = arg.substring(eqIndex + 1);
      }
    }

    final pkgRaw = kvMap['packages'] ?? kvMap['only'] ?? '';
    final filter = pkgRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    return _CliConfig(
      showHelp: flagSet.contains('--help') || flagSet.contains('-h'),
      publish: flagSet.contains('--publish'),
      autoConfirm: flagSet.contains('--yes') || flagSet.contains('-y'),
      syncOnly: flagSet.contains('--sync-only'),
      skipChecks: flagSet.contains('--skip-checks'),
      withBenchmark: flagSet.contains('--with-benchmark'),
      createBundle:
          flagSet.contains('--bundle') || kvMap.containsKey('output'),
      bundleDir: kvMap['output'] ?? 'dist',
      newVersion: kvMap['set-version'],
      bumpType: kvMap['bump'],
      packageFilter: filter,
    );
  }
}

class _PackageInfo {
  final String name;
  String version;
  final String description;
  final Directory directory;
  final List<String> internalDeps;
  final List<String> exportedZWidgets = [];
  final List<String> nonCompliantWidgets = [];

  _PackageInfo({
    required this.name,
    required this.version,
    required this.description,
    required this.directory,
    required this.internalDeps,
  });
}

void _printBanner() {
  stdout.writeln('===============================================================');
  stdout.writeln('🚀 D-Zero Widget Suite 一括配布・パブリッシュパイプライン');
  stdout.writeln('===============================================================');
}

void _printUsage() {
  stdout.writeln('''
使い方: dart run tool/distribute_widgets.dart [オプション]

オプション:
  --dry-run               pub.dev パブリッシュの事前検証 (dry-run) を一括実行 [デフォルト]
  --publish               依存順 (d_zero_core -> 各 Widget パッケージ) に pub.dev へ一括公開
  --yes, -y               --publish 実行時の確認プロンプトをスキップ
  --sync-only             LICENSE / .pubignore / 内部依存バージョン同期と Z-Widget 監査のみ実行
  --set-version=X.Y.Z     対象パッケージのバージョンを一括変更し、内部依存バージョンも同期
  --bump=patch|minor|major セマンティックバージョンを一括インクリメント
  --packages=pkg1,pkg2    特定パッケージのみを対象に指定 (例: --packages=d_zero_counter,d_zero_particles)
  --skip-checks           事前品質ゲート (analyze / complexity / test) をスキップ
  --with-benchmark        品質ゲートにマイクロベンチマーク実行を含める
  --bundle                dist/ にリリース用アーカイブ (.tar.gz) と統合 barrel ファイルを生成
  --output=DIR            --bundle の出力先ディレクトリを指定 (デフォルト: dist)
  --help, -h              このヘルプメッセージを表示
''');
}

List<_PackageInfo> _discoverPublishablePackages(Directory packagesRoot) {
  if (!packagesRoot.existsSync()) return [];

  final subdirs = packagesRoot.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final knownNames = _collectWorkspacePackageNames(subdirs);

  final discovered = <_PackageInfo>[];
  for (final dir in subdirs) {
    final pkg = _parsePackageDirectory(dir, knownNames);
    if (pkg != null) discovered.add(pkg);
  }
  return discovered;
}

Set<String> _collectWorkspacePackageNames(List<Directory> subdirs) {
  final names = <String>{};
  for (final dir in subdirs) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final name = _extractYamlScalar(pubspec.readAsStringSync(), 'name');
    if (name != null) names.add(name);
  }
  return names;
}

_PackageInfo? _parsePackageDirectory(Directory dir, Set<String> knownNames) {
  final pubspecFile = File('${dir.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) return null;

  final content = pubspecFile.readAsStringSync();
  if (_isPublishDisabled(content)) return null;

  final name = _extractYamlScalar(content, 'name') ??
      dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
  return _PackageInfo(
    name: name,
    version: _extractYamlScalar(content, 'version') ?? '0.0.1',
    description: _extractYamlScalar(content, 'description') ?? '',
    directory: dir,
    internalDeps: _extractInternalDeps(content, knownNames, name),
  );
}

bool _isPublishDisabled(String yamlContent) {
  final publishTo = _extractYamlScalar(yamlContent, 'publish_to');
  return publishTo == 'none';
}

String? _extractYamlScalar(String yamlContent, String key) {
  final regExp = RegExp('^$key:\\s*(.+)\$', multiLine: true);
  final match = regExp.firstMatch(yamlContent);
  if (match == null) return null;
  var raw = match.group(1)!.trim();
  if ((raw.startsWith('"') && raw.endsWith('"')) ||
      (raw.startsWith("'") && raw.endsWith("'"))) {
    raw = raw.substring(1, raw.length - 1);
  }
  return raw;
}

List<String> _extractInternalDeps(
  String yamlContent,
  Set<String> workspacePackageNames,
  String selfName,
) {
  final deps = <String>[];
  for (final candidate in workspacePackageNames) {
    if (candidate == selfName) continue;
    final depPattern = RegExp('^\\s+$candidate\\s*:', multiLine: true);
    if (depPattern.hasMatch(yamlContent)) {
      deps.add(candidate);
    }
  }
  return deps;
}

List<_PackageInfo> _topologicalSort(List<_PackageInfo> packages) {
  final byName = {for (final p in packages) p.name: p};
  final visited = <String>{};
  final result = <_PackageInfo>[];

  void visit(_PackageInfo pkg) {
    if (visited.contains(pkg.name)) return;
    visited.add(pkg.name);
    for (final depName in pkg.internalDeps) {
      final depPkg = byName[depName];
      if (depPkg != null) visit(depPkg);
    }
    result.add(pkg);
  }

  for (final pkg in packages) {
    visit(pkg);
  }
  return result;
}

List<_PackageInfo> _filterPackages(
  List<_PackageInfo> sortedPackages,
  Set<String> filter,
) {
  if (filter.isEmpty) return sortedPackages;
  final matched =
      sortedPackages.where((p) => filter.contains(p.name)).toList();
  if (matched.isEmpty) {
    stderr.writeln('❌ 指定されたパッケージが見つかりません: ${filter.join(', ')}');
    exit(1);
  }
  return matched;
}

void _applyVersionUpdate(
  List<_PackageInfo> allPackages,
  List<_PackageInfo> targetPackages,
  _CliConfig config,
) {
  stdout.writeln('\n🏷️  パッケージバージョンの一括更新を実行中...');
  for (final pkg in targetPackages) {
    final nextVersion =
        config.newVersion ?? _bumpSemver(pkg.version, config.bumpType!);
    _updatePubspecVersion(pkg, nextVersion);
    _ensureChangelogVersion(pkg, nextVersion);
    stdout.writeln('  ✔ ${pkg.name}: ${pkg.version} -> $nextVersion');
    pkg.version = nextVersion;
  }
}

String _bumpSemver(String current, String bumpType) {
  final core = current.split('+').first.split('-').first;
  final parts = core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  if (bumpType == 'major') return '${parts[0] + 1}.0.0';
  if (bumpType == 'minor') return '${parts[0]}.${parts[1] + 1}.0';
  if (bumpType == 'patch') return '${parts[0]}.${parts[1]}.${parts[2] + 1}';
  stderr.writeln('❌ 不正な --bump 指定です ($bumpType)。patch / minor / major を指定してください。');
  exit(1);
}

void _updatePubspecVersion(_PackageInfo pkg, String nextVersion) {
  final file = File('${pkg.directory.path}/pubspec.yaml');
  final updated = file.readAsStringSync().replaceFirst(
        RegExp(r'^version:\s*.+$', multiLine: true),
        'version: $nextVersion',
      );
  file.writeAsStringSync(updated);
}

void _ensureChangelogVersion(_PackageInfo pkg, String version) {
  final file = File('${pkg.directory.path}/CHANGELOG.md');
  final header = '## $version';
  if (!file.existsSync()) {
    file.writeAsStringSync('$header\n\n* Release `${pkg.name}` v$version.\n');
    return;
  }
  final existing = file.readAsStringSync();
  if (existing.contains(header)) return;
  file.writeAsStringSync(
    '$header\n\n* Synchronized release of `${pkg.name}` v$version.\n\n$existing',
  );
}

void _syncPackageMetadata(List<_PackageInfo> allPackages) {
  stdout.writeln('\n🔄 配布用メタデータ (LICENSE / .pubignore / 内部依存制約) を同期中...');
  final rootLicense = File('LICENSE');
  final licenseText = rootLicense.existsSync() ? rootLicense.readAsStringSync() : null;
  final versionMap = {for (final p in allPackages) p.name: p.version};

  for (final pkg in allPackages) {
    if (licenseText != null) {
      File('${pkg.directory.path}/LICENSE').writeAsStringSync(licenseText);
    }
    File('${pkg.directory.path}/.pubignore')
        .writeAsStringSync(_defaultPubignore);
    _syncInternalDependencyConstraints(pkg, versionMap);
    _syncNativeSpmSourcesIfPresent(pkg);
  }
  stdout.writeln('  ✔ 全 ${allPackages.length} パッケージのメタデータ同期が完了しました。');
}

void _syncNativeSpmSourcesIfPresent(_PackageInfo pkg) {
  final spmDir = Directory('${pkg.directory.path}/ios/${pkg.name}/Sources/${pkg.name}');
  if (!spmDir.existsSync()) return;

  final sourceDirs = [
    Directory('${pkg.directory.path}/src'),
    Directory('${pkg.directory.path}/ios/Classes'),
  ];
  for (final dir in sourceDirs) {
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (name == 'CMakeLists.txt') continue;
      file.copySync('${spmDir.path}/$name');
    }
  }
}

void _syncInternalDependencyConstraints(
  _PackageInfo pkg,
  Map<String, String> versionMap,
) {
  if (pkg.internalDeps.isEmpty) return;
  final pubspecFile = File('${pkg.directory.path}/pubspec.yaml');
  var content = pubspecFile.readAsStringSync();

  for (final dep in pkg.internalDeps) {
    final depVersion = versionMap[dep];
    if (depVersion == null) continue;
    final depRegex = RegExp('^(\\s+$dep):\\s*.*\$', multiLine: true);
    content = content.replaceFirstMapped(
      depRegex,
      (m) => '${m.group(1)}: ^$depVersion',
    );
  }
  pubspecFile.writeAsStringSync(content);
}

void _auditExportedWidgets(List<_PackageInfo> packages) {
  final widgetClassRegExp = RegExp(
    r'class\s+([A-Za-z0-9_]+)(?:<[^{]+>)?\s+(?:extends|implements)\s+(?:ZLeafWidget|ZSingleChildWidget|ZWidget|LeafRenderObjectWidget|SingleChildRenderObjectWidget|StatelessWidget|StatefulWidget|RenderObjectWidget|Widget)\b',
  );
  final activeAliasRegExp = RegExp(
    r'^(?!\s*@Deprecated)[^\n]*\btypedef\s+(Z[A-Za-z0-9_]+)\s*=\s*(Z[A-Za-z0-9_]+)\s*;',
    multiLine: true,
  );

  for (final pkg in packages) {
    final libDir = Directory('${pkg.directory.path}/lib');
    if (!libDir.existsSync()) continue;

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      _scanFileForWidgets(
        file.readAsStringSync(),
        pkg,
        widgetClassRegExp,
        activeAliasRegExp,
      );
    }
    pkg.exportedZWidgets.sort();
  }
}

void _scanFileForWidgets(
  String source,
  _PackageInfo pkg,
  RegExp classRegex,
  RegExp typedefRegex,
) {
  for (final match in classRegex.allMatches(source)) {
    final name = match.group(1)!;
    if (name.startsWith('_')) continue;
    if (name.startsWith('Z')) {
      if (!pkg.exportedZWidgets.contains(name)) pkg.exportedZWidgets.add(name);
    } else {
      pkg.nonCompliantWidgets.add(name);
    }
  }

  for (final match in typedefRegex.allMatches(source)) {
    final alias = match.group(1)!;
    if (!alias.startsWith('Zero') && !pkg.exportedZWidgets.contains(alias)) {
      pkg.exportedZWidgets.add(alias);
    }
  }
}

void _printPackageTable(List<_PackageInfo> packages) {
  stdout.writeln('\n📦 配布パッケージ一覧 (トポロジカル公開順):');
  stdout.writeln('---------------------------------------------------------------');
  for (var i = 0; i < packages.length; i++) {
    final p = packages[i];
    final deps = p.internalDeps.isEmpty ? 'なし (基盤)' : p.internalDeps.join(', ');
    final widgets =
        p.exportedZWidgets.isEmpty ? '-' : p.exportedZWidgets.join(', ');
    stdout.writeln(
      '  ${i + 1}. ${p.name.padRight(15)} v${p.version.padRight(8)} '
      '| 依存: ${deps.padRight(10)} | 公開 Widget: $widgets',
    );
    if (p.nonCompliantWidgets.isNotEmpty) {
      stderr.writeln(
        '     ⚠️ Z-Prefix 規約違反の公開 Widget が検出されました: '
        '${p.nonCompliantWidgets.join(', ')}',
      );
      exit(1);
    }
  }
  stdout.writeln('---------------------------------------------------------------');
}

Future<void> _runQualityGates({
  required List<_PackageInfo> allPackages,
  required bool withBenchmark,
}) async {
  stdout.writeln('\n🛡️  ワークスペース品質ゲートを実行中...');

  await _runStepOrExit(
    title: '1/3 静的解析 (flutter analyze)',
    executable: 'flutter',
    arguments: ['analyze'],
  );

  await _runStepOrExit(
    title: '2/3 循環的複雑度チェック (CC <= 15)',
    executable: 'dart',
    arguments: ['run', 'tool/check_complexity.dart'],
  );

  final testDirs = allPackages
      .map((p) => '${p.directory.path}/test')
      .where((path) => Directory(path).existsSync())
      .toList();

  if (testDirs.isNotEmpty) {
    await _runStepOrExit(
      title: '3/3 ユニット・Widget ライフサイクル・メモリ安全性テスト (flutter test)',
      executable: 'flutter',
      arguments: ['test', ...testDirs],
    );
  }

  if (withBenchmark) {
    await _runStepOrExit(
      title: '追加: マイクロベンチマーク検証',
      executable: 'dart',
      arguments: ['run', 'benchmarks/run_benchmarks.dart'],
    );
  }
}

Future<void> _runStepOrExit({
  required String title,
  required String executable,
  required List<String> arguments,
  String? workingDirectory,
}) async {
  stdout.write('  ⏳ $title ... ');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    stdout.writeln('❌ 失敗');
    stdout.writeln(result.stdout);
    stderr.writeln(result.stderr);
    exit(result.exitCode);
  }
  stdout.writeln('✅ PASS');
}

Future<void> _generateDistributionBundle(
  List<_PackageInfo> packages,
  String bundleDirPath,
) async {
  stdout.writeln('\n🎁 ローカル配布バンドルを $bundleDirPath/ に生成中...');
  final outDir = Directory(bundleDirPath);
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final manifestEntries = <Map<String, Object>>[];
  for (final pkg in packages) {
    final archiveName = '${pkg.name}-${pkg.version}.tar.gz';
    final archivePath = '${outDir.path}/$archiveName';
    await _createTarArchive(pkg, archivePath);
    manifestEntries.add({
      'name': pkg.name,
      'version': pkg.version,
      'description': pkg.description,
      'archive': archiveName,
      'dependencies': pkg.internalDeps,
      'widgets': pkg.exportedZWidgets,
    });
    stdout.writeln('  ✔ アーカイブ作成: $archivePath');
  }

  final manifestFile = File('${outDir.path}/manifest.json');
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'packages': manifestEntries,
    }),
  );

  final barrelFile = File('${outDir.path}/d_zero_widgets.dart');
  final exports = packages
      .map((p) => "export 'package:${p.name}/${p.name}.dart';")
      .join('\n');
  barrelFile.writeAsStringSync(
    '/// D-Zero 全配布 Widget 一括エクスポート Barrel ファイル\n'
    'library d_zero_widgets;\n\n$exports\n',
  );
  stdout.writeln('  ✔ マニフェスト & 統合 Barrel 生成完了: ${outDir.path}/manifest.json');
}

Future<void> _createTarArchive(_PackageInfo pkg, String outputPath) async {
  final absOut = File(outputPath).absolute.path;
  final result = await Process.run(
    'tar',
    [
      '-czf',
      absOut,
      '--exclude=.dart_tool',
      '--exclude=build',
      '--exclude=example/build',
      '--exclude=example/.dart_tool',
      '--exclude=example/ios/Flutter/ephemeral',
      '-C',
      pkg.directory.path,
      '.',
    ],
  );
  if (result.exitCode != 0) {
    stderr.writeln('⚠️ アーカイブ生成に失敗しました (${pkg.name}): ${result.stderr}');
    exit(result.exitCode);
  }
}

Future<bool> _executePubWorkflow(
  List<_PackageInfo> packages,
  _CliConfig config,
) async {
  if (config.publish && !config.autoConfirm) {
    if (!_confirmLivePublish(packages)) {
      stdout.writeln('🛑 パブリッシュをキャンセルしました。');
      return true;
    }
  }

  final modeLabel =
      config.publish ? '🚀 pub.dev 本番公開 (--force)' : '🔍 pub.dev 事前検証 (--dry-run)';
  stdout.writeln('\n$modeLabel をトポロジカル順序で実行します...');

  var allSucceeded = true;
  for (var i = 0; i < packages.length; i++) {
    final pkg = packages[i];
    stdout.write(
      '  [${i + 1}/${packages.length}] ${pkg.name} (v${pkg.version}) ... ',
    );

    final ok = await _publishSinglePackage(pkg, isLivePublish: config.publish);
    if (!ok) {
      allSucceeded = false;
      break;
    }
  }

  stdout.writeln('===============================================================');
  if (allSucceeded) {
    final msg = config.publish
        ? '🎉 全 ${packages.length} パッケージの pub.dev 公開が正常に完了しました！'
        : '🎉 全 ${packages.length} パッケージが pub.dev 配布検証 (dry-run) をパスしました！';
    stdout.writeln(msg);
  }
  return allSucceeded;
}

Future<bool> _publishSinglePackage(
  _PackageInfo pkg, {
  required bool isLivePublish,
}) async {
  final pubArgs = isLivePublish
      ? ['pub', 'publish', '--force', '-C', pkg.directory.path]
      : ['pub', 'publish', '--dry-run', '-C', pkg.directory.path];

  final maxAttempts = isLivePublish ? 4 : 1;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final result = await Process.run('dart', pubArgs);
    final combinedOut = '${result.stdout}\n${result.stderr}';
    if (_handlePubResult(result.exitCode, combinedOut, isLivePublish)) {
      if (isLivePublish && pkg.internalDeps.isEmpty) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      return true;
    }
    if (attempt < maxAttempts && _isPropagationDelay(combinedOut)) {
      stdout.write('⏳ (pub.dev インデックス反映待機中...) ');
      await Future<void>.delayed(const Duration(seconds: 5));
      continue;
    }
    stdout.writeln('❌ FAILED');
    stdout.writeln(result.stdout);
    stderr.writeln(result.stderr);
    return false;
  }
  return false;
}

bool _handlePubResult(int exitCode, String combinedOut, bool isLivePublish) {
  final sizeInfo = _extractArchiveSize(combinedOut);
  if (exitCode == 0) {
    stdout.writeln('✅ OK $sizeInfo');
    return true;
  }
  if (!isLivePublish && _isOnlyGitDirtyWarning(combinedOut)) {
    stdout.writeln('✅ OK $sizeInfo (※未コミットの変更あり)');
    return true;
  }
  if (isLivePublish && combinedOut.contains('already exists')) {
    stdout.writeln('✅ SKIP (同バージョンが既に公開済み)');
    return true;
  }
  return false;
}

bool _isPropagationDelay(String output) {
  return output.contains('d_zero_core') &&
      (output.contains('version solving failed') ||
          output.contains('does not exist') ||
          output.contains("doesn't exist"));
}

bool _confirmLivePublish(List<_PackageInfo> packages) {
  final listStr = packages.map((p) => '${p.name}@${p.version}').join(', ');
  stdout.write('\n⚠️ 以下のパッケージを pub.dev に本番公開します:\n  $listStr\nよろしいですか？ [y/N]: ');
  final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  return answer == 'y' || answer == 'yes';
}

String _extractArchiveSize(String output) {
  final match =
      RegExp(r'Total compressed archive size:\s*([^\n.]+)').firstMatch(output);
  return match != null ? '(${match.group(1)!.trim()})' : '';
}

bool _isOnlyGitDirtyWarning(String output) {
  if (output.contains('missing a requirement')) return false;
  if (output.contains('Package validation found the following error')) {
    return false;
  }
  return output.contains('Package has 1 warning.') &&
      output.contains('modified in git');
}

const String _defaultPubignore = '''
# Build and test artifacts
.dart_tool/
build/
*.dylib
*.so
*.dll
*.exe
test/native_stress_test
src/libzero_player_native.dylib
tool/

# Example build & local platform scaffolds
example/.dart_tool/
example/build/
example/.metadata
example/macos/
example/linux/
example/windows/
example/web/
example/test/
example/ios/Flutter/ephemeral/
example/ios/Flutter/Generated.xcconfig
example/ios/Flutter/flutter_export_environment.sh
example/ios/Pods/
example/android/.gradle/
example/android/local.properties

# IDE & OS
.idea/
.vscode/
*.iml
.DS_Store
Thumbs.db
''';
