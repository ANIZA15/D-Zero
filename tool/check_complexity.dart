import 'dart:io';

/// 循環的複雑度（Cyclomatic Complexity, McCabe Metric）計測ツール (D-Zero ワークスペース全体対応)
///
/// 各関数・メソッドごとの分岐点（if, for, while, case, catch, &&, ||, ?, ??）
/// を解析し、保守性（しきい値: 10以下が理想・推奨、15超過で警告・エラー）を判定します。
void main(List<String> args) {
  final targetDirs = [
    Directory('packages'),
    Directory('apps'),
    Directory('tool'),
  ];

  stdout.writeln('===============================================================');
  stdout.writeln('📊 D-Zero ワークスペース 循環的複雑度（Cyclomatic Complexity）計測');
  stdout.writeln('===============================================================');

  final results = <_FunctionMetric>[];

  for (final dir in targetDirs) {
    if (!dir.existsSync()) continue;
    final files = dir.listSync(recursive: true).whereType<File>().where((f) {
      final p = f.path;
      // build や .dart_tool などの生成ディレクトリは除外
      if (p.contains('/.dart_tool/') || p.contains('/build/')) return false;
      return p.endsWith('.dart') || p.endsWith('.cpp') || p.endsWith('.h');
    });

    for (final file in files) {
      results.addAll(_analyzeFile(file));
    }
  }

  if (results.isEmpty) {
    stdout.writeln('計測対象の関数が見つかりませんでした。');
    return;
  }

  // 複雑度が高い順にソート
  results.sort((a, b) => b.complexity.compareTo(a.complexity));

  int okCount = 0;
  int warnCount = 0;
  int dangerCount = 0;

  for (final m in results) {
    // 厳格な基準: <= 10 良好, 11..15 注意, > 15 警告
    final status = m.complexity <= 10
        ? '🟢 OK'
        : m.complexity <= 15
            ? '🟡 注意'
            : '🔴 警告';

    if (m.complexity <= 10) {
      okCount++;
    } else if (m.complexity <= 15) {
      warnCount++;
    } else {
      dangerCount++;
    }

    stdout.writeln(
      '${status.padRight(5)} | CC: ${m.complexity.toString().padLeft(2)} | '
      '${m.filePath}:${m.line} -> ${m.name}',
    );
  }

  final avg =
      results.map((e) => e.complexity).reduce((a, b) => a + b) / results.length;

  stdout.writeln('---------------------------------------------------------------');
  stdout.writeln('📈 サマリー:');
  stdout.writeln('  総関数・メソッド数 : ${results.length}');
  stdout.writeln('  平均複雑度 (Avg CC) : ${avg.toStringAsFixed(2)}');
  stdout.writeln('  🟢 良好 (CC <= 10) : $okCount 件');
  stdout.writeln('  🟡 注意 (11-15)    : $warnCount 件');
  stdout.writeln('  🔴 警告 (CC > 15)  : $dangerCount 件');
  stdout.writeln('===============================================================');

  if (dangerCount > 0) {
    stderr.writeln('⚠️ 循環的複雑度が 15 を超える高リスクな関数が存在します。リファクタリングを義務付けます。');
    exit(1);
  } else {
    stdout.writeln('🎉 全ての関数が許容基準（CC <= 15）を満たしています！保守性は極めて良好です。');
  }
}

class _FunctionMetric {
  final String filePath;
  final int line;
  final String name;
  final int complexity;

  _FunctionMetric({
    required this.filePath,
    required this.line,
    required this.name,
    required this.complexity,
  });
}

List<_FunctionMetric> _analyzeFile(File file) {
  final lines = file.readAsLinesSync();
  final metrics = <_FunctionMetric>[];

  // 簡易パーサー: 関数開始ブロックと複雑度分岐の検出
  final funcHeaderRegExp = RegExp(
    r'^\s*(?:@override\s+)?(?:[A-Za-z0-9_<>?]+\s+)?([A-Za-z0-9_]+)\s*\([^)]*\)\s*(?:async\s*)?(?:=>|\{)',
  );
  final getterSetterRegExp = RegExp(
    r'^\s*(?:@override\s+)?(?:[A-Za-z0-9_<>?]+\s+)?(?:get|set)\s+([A-Za-z0-9_]+)\s*(?:=>|\{)',
  );

  bool inFunction = false;
  String currentFuncName = '';
  int currentFuncLine = 0;
  int currentComplexity = 1;
  int braceDepth = 0;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();

    // コメント行のスキップ
    if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
      continue;
    }

    if (!inFunction) {
      final match = funcHeaderRegExp.firstMatch(line) ?? getterSetterRegExp.firstMatch(line);
      if (match != null) {
        final name = match.group(1)!;
        // キーワードや除外すべき構造（if, for, while, switch等）の誤検知排除
        if (!_isReservedKeyword(name)) {
          inFunction = true;
          currentFuncName = name;
          currentFuncLine = i + 1;
          currentComplexity = 1;
          braceDepth = 0;
        }
      }
    }

    if (inFunction) {
      // 複雑度分岐トークンのカウント
      currentComplexity += _countComplexityTokens(line);

      // 中括弧の深さ追跡
      braceDepth += '{'.allMatches(line).length;
      braceDepth -= '}'.allMatches(line).length;

      // 1行式アロー関数 (=>) の終了判定、または中括弧が閉じた時に関数終了
      if (line.contains('=>') && braceDepth <= 0 && line.trimRight().endsWith(';')) {
        metrics.add(_FunctionMetric(
          filePath: file.path,
          line: currentFuncLine,
          name: currentFuncName,
          complexity: currentComplexity,
        ));
        inFunction = false;
      } else if (braceDepth <= 0 && line.contains('}')) {
        metrics.add(_FunctionMetric(
          filePath: file.path,
          line: currentFuncLine,
          name: currentFuncName,
          complexity: currentComplexity,
        ));
        inFunction = false;
      }
    }
  }

  return metrics;
}

bool _isReservedKeyword(String name) {
  const keywords = {
    'if', 'else', 'switch', 'case', 'default', 'for', 'while', 'do',
    'return', 'class', 'enum', 'mixin', 'typedef', 'import', 'export', 'library'
  };
  return keywords.contains(name);
}

int _countComplexityTokens(String line) {
  int count = 0;

  // 分岐キーワードと演算子
  if (RegExp(r'\bif\b').hasMatch(line)) count++;
  if (RegExp(r'\bfor\b').hasMatch(line)) count++;
  if (RegExp(r'\bwhile\b').hasMatch(line)) count++;
  if (RegExp(r'\bcase\b').hasMatch(line)) count++;
  if (RegExp(r'\bcatch\b').hasMatch(line)) count++;

  // 演算子分岐 (&&, ||, ?:, ??)
  count += '&&'.allMatches(line).length;
  count += '||'.allMatches(line).length;
  count += '??'.allMatches(line).length;

  // 三項演算子 (単独の ? で、型定義 ? や null-safe ?. は除外)
  final ternaryMatches = RegExp(r'\s+\?\s+').allMatches(line).length;
  count += ternaryMatches;

  return count;
}
