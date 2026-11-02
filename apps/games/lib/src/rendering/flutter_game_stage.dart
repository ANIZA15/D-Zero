import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../controller/zero_game_controller.dart';
import '../model/game_config.dart';
import '../model/soa_entities.dart';

/// Traditional Flutter game arena implementation (`setState` + `CustomPainter`).
///
/// Used when the user switches the in-game engine toggle to [GameEngineMode.flutter]
/// to demonstrate the performance contrast against [ZGameStage]:
/// - Calls `setState()` every frame to trigger widget tree rebuilds.
/// - Instantiates [Paint] and [Offset] objects inside the painting loop and
///   issues individual `drawCircle` / `drawLine` calls per particle/entity.
class FlutterGameStage extends StatefulWidget {
  final ZeroGameController controller;

  const FlutterGameStage({
    super.key,
    required this.controller,
  });

  @override
  State<FlutterGameStage> createState() => _FlutterGameStageState();
}

class _FlutterGameStageState extends State<FlutterGameStage>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  int _frameSerial = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final ZeroGameController ctrl = widget.controller;
    if (ctrl.isDisposed || !mounted) return;
    final double dt = _computeDt(elapsed);
    _lastElapsed = elapsed;

    ctrl.recordFrameTimeMs(dt * 1000.0);
    ctrl.step(dt);
    ctrl.particleCtrl.step(
      dt: dt,
      width: ctrl.arenaWidth,
      height: ctrl.arenaHeight,
    );
    ctrl.confettiCtrl.step(
      dt: dt,
      width: ctrl.arenaWidth,
      height: ctrl.arenaHeight,
    );
    ctrl.rippleCtrl.step(dt);
    ctrl.danmakuCtrl.step(dt);
    ctrl.commitFlutterFrameMetrics();

    // Traditional anti-pattern: full widget rebuild every frame
    setState(() {
      _frameSerial++;
    });
  }

  double _computeDt(Duration elapsed) {
    if (_lastElapsed == Duration.zero) return 1.0 / 60.0;
    final int us = (elapsed - _lastElapsed).inMicroseconds;
    if (us <= 0) return 1.0 / 60.0;
    final double dt = us / 1000000.0;
    return dt > 0.05 ? 0.05 : dt;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ZeroGameController ctrl = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
          ctrl.updateArenaSize(constraints.maxWidth, constraints.maxHeight);
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) {
            ctrl.setPointerAim(d.localPosition.dx, d.localPosition.dy, active: true);
            ctrl.rippleCtrl.trigger(d.localPosition.dx, d.localPosition.dy);
          },
          onPanUpdate: (d) {
            ctrl.setPointerAim(d.localPosition.dx, d.localPosition.dy, active: true);
          },
          onPanEnd: (_) => ctrl.setPointerAim(0.0, 0.0, active: false),
          child: CustomPaint(
            size: Size.infinite,
            painter: _TraditionalArenaPainter(
              controller: ctrl,
              frameSerial: _frameSerial,
            ),
          ),
        );
      },
    );
  }
}

class _TraditionalArenaPainter extends CustomPainter {
  static final Paint _bgPaint = Paint()..color = ZeroGamePalette.bgVoid;
  static final Paint _gridLinePaint = Paint()
    ..color = const Color(0xFF151E32)
    ..strokeWidth = 1.0;
  static final Paint _ambientPaint = Paint()
    ..color = const Color(0x88FF5252)
    ..style = PaintingStyle.fill;
  static final List<Paint> _sparkPaints = List<Paint>.generate(
    ZeroGamePalette.sparkBucketColors.length,
    (b) => Paint()
      ..color = ZeroGamePalette.sparkBucketColors[b]
      ..strokeWidth = 2.0,
    growable: false,
  );
  static final Paint _confettiPaint = Paint()
    ..style = PaintingStyle.fill
    ..strokeWidth = 3.5;
  static final Paint _projTeam0Paint = Paint()
    ..color = ZeroGamePalette.neonCyan
    ..strokeWidth = 3.0;
  static final Paint _projTeam1Paint = Paint()
    ..color = ZeroGamePalette.neonMagenta
    ..strokeWidth = 3.0;
  static final Paint _projTeam2Paint = Paint()
    ..color = ZeroGamePalette.neonAmber
    ..strokeWidth = 3.0;
  static final Paint _enemyKind0Paint = Paint()
    ..color = ZeroGamePalette.dangerRed
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4;
  static final Paint _enemyKind1Paint = Paint()
    ..color = ZeroGamePalette.neonPurple
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4;
  static final Paint _enemyKind2Paint = Paint()
    ..color = ZeroGamePalette.neonAmber
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4;
  static final Paint _ripplePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0;
  static final Paint _shipPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  static final Paint _aimPaint = Paint()
    ..color = ZeroGamePalette.dangerRed
    ..strokeWidth = 2.5;

  final ZeroGameController controller;
  final int frameSerial;

  _TraditionalArenaPainter({
    required this.controller,
    required this.frameSerial,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.isDisposed) return;
    int allocs = 0;
    allocs += _paintTraditionalGrid(canvas, size);
    allocs += _paintTraditionalAmbientParticles(canvas);
    allocs += _paintTraditionalRipples(canvas);
    allocs += _paintTraditionalSparks(canvas);
    allocs += _paintTraditionalConfetti(canvas);
    allocs += _paintTraditionalProjectiles(canvas);
    allocs += _paintTraditionalEnemies(canvas);
    allocs += _paintTraditionalPlayer(canvas);
    controller.stageFlutterPaintAllocs(allocs);
  }

  int _paintTraditionalGrid(Canvas canvas, Size size) {
    int allocs = 1; // Rect
    canvas.drawRect(Offset.zero & size, _bgPaint);

    const double step = 32.0;
    final double ox = controller.gridViewportCtrl.panX % step;
    final double oy = controller.gridViewportCtrl.panY % step;
    for (double x = ox; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0.0), Offset(x, size.height), _gridLinePaint);
      allocs += 2; // 2 Offsets
    }
    for (double y = oy; y < size.height; y += step) {
      canvas.drawLine(Offset(0.0, y), Offset(size.width, y), _gridLinePaint);
      allocs += 2; // 2 Offsets
    }
    return allocs;
  }

  int _paintTraditionalAmbientParticles(Canvas canvas) {
    final positions = controller.particleCtrl.buffer.positions;
    final int count = positions.length >> 1;
    int allocs = 0;
    for (int i = 0; i < count; i++) {
      final int idx = i << 1;
      canvas.drawCircle(
        Offset(positions[idx], positions[idx + 1]),
        1.6,
        _ambientPaint,
      );
      allocs += 1; // Offset
    }
    return allocs;
  }

  int _paintTraditionalRipples(Canvas canvas) {
    final rCtrl = controller.rippleCtrl;
    int allocs = 0;
    for (int i = 0; i < rCtrl.capacity; i++) {
      if (rCtrl.isActiveAt(i)) {
        final double p = rCtrl.progressAt(i);
        _ripplePaint.color =
            ZeroGamePalette.neonCyan.withValues(alpha: (1.0 - p) * 0.45);
        canvas.drawCircle(
          Offset(rCtrl.xAt(i), rCtrl.yAt(i)),
          12.0 + 150.0 * p,
          _ripplePaint,
        );
        allocs += 2; // Color + Offset
      }
    }
    return allocs;
  }

  int _paintTraditionalSparks(Canvas canvas) {
    final SoaSparkPool sparks = controller.sparks;
    int allocs = 0;
    for (int i = 0; i < sparks.capacity; i++) {
      if (sparks.active[i] != 0) {
        final int bucket = sparks.colorBucket[i];
        final double sx = sparks.x[i];
        final double sy = sparks.y[i];
        canvas.drawLine(
          Offset(sx - sparks.vx[i] * 0.03, sy - sparks.vy[i] * 0.03),
          Offset(sx, sy),
          _sparkPaints[bucket],
        );
        allocs += 2; // 2 Offsets
      }
    }
    return allocs;
  }

  int _paintTraditionalConfetti(Canvas canvas) {
    final cCtrl = controller.confettiCtrl;
    final xs = cCtrl.x;
    final ys = cCtrl.y;
    final lifes = cCtrl.life;
    final colors = cCtrl.colors;
    int allocs = 0;
    for (int i = 0; i < xs.length; i++) {
      if (lifes[i] > 0.0) {
        _confettiPaint.color = Color(colors[i]);
        canvas.drawCircle(Offset(xs[i], ys[i]), 3.0, _confettiPaint);
        allocs += 2; // Color + Offset
      }
    }
    return allocs;
  }

  int _paintTraditionalProjectiles(Canvas canvas) {
    final SoaProjectilePool proj = controller.projectiles;
    int allocs = 0;
    for (int i = 0; i < proj.capacity; i++) {
      if (proj.active[i] != 0) {
        final int t = proj.team[i];
        final Paint paint = t == 1
            ? _projTeam1Paint
            : (t == 2 ? _projTeam2Paint : _projTeam0Paint);
        canvas.drawCircle(
          Offset(proj.x[i], proj.y[i]),
          t == 1 ? 4.0 : 2.5,
          paint,
        );
        allocs += 1; // Offset
      }
    }
    return allocs;
  }

  int _paintTraditionalEnemies(Canvas canvas) {
    final SoaEnemyPool pool = controller.enemies;
    int allocs = 0;
    for (int i = 0; i < pool.capacity; i++) {
      if (pool.active[i] != 0) {
        final int k = pool.kind[i];
        final Paint paint = k == 2
            ? _enemyKind2Paint
            : (k == 1 ? _enemyKind1Paint : _enemyKind0Paint);
        canvas.drawCircle(
          Offset(pool.x[i], pool.y[i]),
          pool.radius[i],
          paint,
        );
        allocs += 1; // Offset
      }
    }
    return allocs;
  }

  int _paintTraditionalPlayer(Canvas canvas) {
    final double px = controller.playerX;
    final double py = controller.playerY;
    final double ang = controller.aimAngle;
    canvas.drawCircle(Offset(px, py), 8.0, _shipPaint);

    canvas.drawLine(
      Offset(px, py),
      Offset(px + math.cos(ang) * 20.0, py + math.sin(ang) * 20.0),
      _aimPaint,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '+${controller.comboNotifier.value}x',
        style: const TextStyle(
          color: ZeroGamePalette.neonAmber,
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(px - 14.0, py + 18.0));
    tp.dispose();
    return 7; // 4 Offsets + String + TextSpan + TextPainter
  }

  @override
  bool shouldRepaint(covariant _TraditionalArenaPainter oldDelegate) {
    return oldDelegate.frameSerial != frameSerial;
  }
}
