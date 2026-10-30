import 'dart:io';

/// 循環的複雑度（Cyclomatic Complexity, McCabe Metric）計測ツール
///
/// 各関数・メソッドごとの分岐点（if, for, while, case, catch, &&, ||, ?, ??）
/// を解析し、保守性（しきい値: 10以下が理想、20超過で警告）を判定します。
void main(List<String> args) {
  final targetDirs = [Directory('lib'), Directory('src')];

  stdout.writeln(
      '===============================================================');
  stdout.writeln('📊 d_zero_player 循環的複雑度（Cyclomatic Complexity）計測');
  stdout.writeln(
      '===============================================================');

  final results = <_FunctionMetric>[];

  for (final dir in targetDirs) {
    if (!dir.existsSync()) continue;
    final files = dir.listSync(recursive: true).whereType<File>().where((f) {
      final p = f.path;
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
    final status = m.complexity <= 10
        ? '🟢 OK'
        : m.complexity <= 20
            ? '🟡 注意'
            : '🔴 警告';

    if (m.complexity <= 10) {
      okCount++;
    } else if (m.complexity <= 20) {
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

  stdout.writeln(
      '---------------------------------------------------------------');
  stdout.writeln('📈 サマリー:');
  stdout.writeln('  総関数・メソッド数 : ${results.length}');
  stdout.writeln('  平均複雑度 (Avg CC) : ${avg.toStringAsFixed(2)}');
  stdout.writeln('  🟢 良好 (CC <= 10) : $okCount 件');
  stdout.writeln('  🟡 注意 (11-20)    : $warnCount 件');
  stdout.writeln('  🔴 警告 (CC > 20)  : $dangerCount 件');
  stdout.writeln(
      '===============================================================');

  if (dangerCount > 0) {
    stderr.writeln('⚠️ 循環的複雑度が 20 を超える高リスクな関数が存在します。リファクタリングを推奨します。');
    exit(1);
  } else {
    stdout.writeln('🎉 全ての関数が許容基準（CC <= 20）を満たしています！保守性は極めて良好です。');
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

  // 関数・メソッドのシグネチャを検出する正規表現
  final funcRegex = RegExp(
    r'^\s*(?:@\w+\s+)*(?:(?:static|final|external|const|async)\s+)*(?:[\w<>, ?]+\s+)?([a-zA-Z_]\w*)\s*\([^)]*\)\s*(?:async\s*)?(?:=>|\{)',
  );

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final match = funcRegex.firstMatch(line);
    if (match != null) {
      final funcName = match.group(1)!;
      // 制御構文やキーワードを除外
      if (['if', 'for', 'while', 'switch', 'catch'].contains(funcName))
        continue;

      // 関数本体の行を収集
      final bodyLines = <String>[];
      int braceDepth = 0;
      bool started = false;

      for (int j = i; j < lines.length; j++) {
        final cur = lines[j];
        bodyLines.add(cur);

        for (int c = 0; c < cur.length; c++) {
          if (cur[c] == '{') {
            braceDepth++;
            started = true;
          } else if (cur[c] == '}') {
            braceDepth--;
          }
        }

        if (started && braceDepth <= 0) break;
        if (!started && cur.contains('=>') && cur.contains(';')) break;
      }

      final complexity = _calculateComplexity(bodyLines.join('\n'));
      metrics.add(_FunctionMetric(
        filePath: file.path,
        line: i + 1,
        name: funcName,
        complexity: complexity,
      ));
    }
  }

  return metrics;
}

int _calculateComplexity(String code) {
  int complexity = 1;

  // 分岐キーワードのカウント (McCabe Metric)
  final patterns = [
    RegExp(r'\bif\b'),
    RegExp(r'\bfor\b'),
    RegExp(r'\bwhile\b'),
    RegExp(r'\bcase\b'),
    RegExp(r'\bcatch\b'),
    RegExp(r'\&\&'),
    RegExp(r'\|\|'),
    RegExp(r'\?[^.:?]'), // 三項演算子
    RegExp(r'\?\?'), // null-coalescing
  ];

  for (final p in patterns) {
    complexity += p.allMatches(code).length;
  }

  return complexity;
}
