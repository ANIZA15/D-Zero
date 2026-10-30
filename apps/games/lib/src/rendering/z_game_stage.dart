import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller/zero_game_controller.dart';
import '../model/game_config.dart';
import '../model/soa_entities.dart';

/// Direct-to-Canvas, zero-allocation game arena widget for ZERO OVERDRIVE.
///
/// Steps [ZeroGameController] on VSync ticks and batch-draws projectiles,
/// velocity sparks, enemies, player ship, and floating combo counters inside
/// [RenderZGameStage] without triggering any widget rebuilds or GC pressure.
class ZGameStage extends ZLeafWidget<RenderZGameStage> {
  final ZeroGameController controller;

  const ZGameStage({
    super.key,
    required this.controller,
  });

  @override
  RenderZGameStage createRenderObject(BuildContext context) {
    return RenderZGameStage(controller: controller);
  }

  @override
  void updateRenderObject(BuildContext context, RenderZGameStage renderObject) {
    renderObject.controller = controller;
  }
}

/// Custom [ZeroRenderBox] executing batched GPU rendering for [ZGameStage].
class RenderZGameStage extends ZeroRenderBox {
  ZeroGameController _controller;
  Duration _lastElapsed = Duration.zero;

  final Paint _playerBoltPaint = Paint()
    ..color = ZeroGamePalette.neonCyan
    ..strokeWidth = 3.2
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final Paint _novaBoltPaint = Paint()
    ..color = ZeroGamePalette.neonAmber
    ..strokeWidth = 4.2
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final Paint _enemyOrbPaint = Paint()
    ..color = ZeroGamePalette.neonMagenta
    ..strokeWidth = 7.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final Paint _enemyOrbCorePaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..strokeWidth = 3.2
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  final List<Paint> _sparkPaints = List<Paint>.generate(
    SoaSparkPool.bucketCount,
    (i) => Paint()
      ..color = ZeroGamePalette.sparkBucketColors[i]
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke,
    growable: false,
  );

  final Paint _dronePaint = Paint()
    ..color = const Color(0xFFFF4081)
    ..strokeWidth = 2.2
    ..style = PaintingStyle.stroke;

  final Paint _weaverPaint = Paint()
    ..color = ZeroGamePalette.neonPurple
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke;

  final Paint _bossPaint = Paint()
    ..color = ZeroGamePalette.neonAmber
    ..strokeWidth = 3.2
    ..style = PaintingStyle.stroke;

  final Paint _bossFillPaint = Paint()
    ..color = const Color(0x33FFD740)
    ..style = PaintingStyle.fill;

  final Paint _hpTrackPaint = Paint()
    ..color = const Color(0x881E293B)
    ..style = PaintingStyle.fill;

  final Paint _hpFillPaint = Paint()
    ..color = ZeroGamePalette.neonGreen
    ..style = PaintingStyle.fill;

  final Paint _shipFillPaint = Paint()
    ..color = const Color(0xFF00E5FF)
    ..style = PaintingStyle.fill;

  final Paint _shipOutlinePaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  final Paint _shieldPaint = Paint()
    ..color = const Color(0x5500FF88)
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  final Paint _novaRingPaint = Paint()
    ..color = const Color(0xAA00E5FF)
    ..strokeWidth = 6.0
    ..style = PaintingStyle.stroke;

  final Float32List _shipLineScratch = Float32List(12);
  late final ZeroNumberPainter _comboPainter;

  RenderZGameStage({
    required ZeroGameController controller,
  })  : _controller = controller,
        super(animatePerFrame: true) {
    _comboPainter = ZeroNumberPainter(
      style: const TextStyle(
        color: ZeroGamePalette.neonAmber,
        fontSize: 13.0,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    );
  }

  ZeroGameController get controller => _controller;
  set controller(ZeroGameController value) {
    if (identical(_controller, value)) return;
    _controller = value;
    markDirty();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (_controller.isDisposed) return;
    if (event is PointerDownEvent) {
      final Offset pos = event.localPosition;
      _controller.setPointerAim(pos.dx, pos.dy, active: true);
      _controller.rippleCtrl.trigger(pos.dx, pos.dy);
      return;
    }
    if (event is PointerMoveEvent || event is PointerHoverEvent) {
      final Offset pos = event.localPosition;
      _controller.setPointerAim(pos.dx, pos.dy, active: true);
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _controller.setPointerAim(0.0, 0.0, active: false);
    }
  }

  @override
  void performLayout() {
    final double w = constraints.hasBoundedWidth ? constraints.maxWidth : 720.0;
    final double h = constraints.hasBoundedHeight ? constraints.maxHeight : 460.0;
    size = constraints.constrain(Size(w, h));
    _controller.updateArenaSize(size.width, size.height);
  }

  @override
  bool onFrameTick(Duration elapsed) {
    if (_controller.isDisposed) return false;
    final double dt = _computeDt(elapsed);
    _lastElapsed = elapsed;
    _controller.recordFrameTimeMs(dt * 1000.0);
    _controller.step(dt);
    return true;
  }

  double _computeDt(Duration elapsed) {
    if (_lastElapsed == Duration.zero) return 1.0 / 60.0;
    final int us = (elapsed - _lastElapsed).inMicroseconds;
    if (us <= 0) return 1.0 / 60.0;
    final double dt = us / 1000000.0;
    return dt > 0.05 ? 0.05 : dt;
  }

  @override
  void detach() {
    _lastElapsed = Duration.zero;
    super.detach();
  }

  @override
  void dispose() {
    _comboPainter.dispose();
    super.dispose();
  }

  @override
  void paintZero(PaintingContext context, Offset offset) {
    if (_controller.isDisposed) return;
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);
    if (offset != Offset.zero) {
      canvas.translate(offset.dx, offset.dy);
    }

    _paintSparksBatch(canvas);
    _paintProjectilesBatch(canvas);
    _paintEnemies(canvas);
    _paintNovaShockwave(canvas);
    _paintPlayerShip(canvas);

    canvas.restore();
  }

  void _paintSparksBatch(Canvas canvas) {
    final SoaSparkPool sparkPool = _controller.sparks;
    for (int b = 0; b < SoaSparkPool.bucketCount; b++) {
      final Float32List segs = sparkPool.bucketSegments(b);
      if (segs.isNotEmpty) {
        canvas.drawRawPoints(ui.PointMode.lines, segs, _sparkPaints[b]);
      }
    }
  }

  void _paintProjectilesBatch(Canvas canvas) {
    final SoaProjectilePool proj = _controller.projectiles;
    final Float32List playerSegs = proj.playerBoltSegments;
    if (playerSegs.isNotEmpty) {
      canvas.drawRawPoints(ui.PointMode.lines, playerSegs, _playerBoltPaint);
    }
    final Float32List novaSegs = proj.novaBoltSegments;
    if (novaSegs.isNotEmpty) {
      canvas.drawRawPoints(ui.PointMode.lines, novaSegs, _novaBoltPaint);
    }
    final Float32List enemyPts = proj.enemyOrbPoints;
    if (enemyPts.isNotEmpty) {
      canvas.drawRawPoints(ui.PointMode.points, enemyPts, _enemyOrbPaint);
      canvas.drawRawPoints(ui.PointMode.points, enemyPts, _enemyOrbCorePaint);
    }
  }

  void _paintEnemies(Canvas canvas) {
    final SoaEnemyPool pool = _controller.enemies;
    final int cap = pool.capacity;
    for (int i = 0; i < cap; i++) {
      if (pool.active[i] != 0) {
        _paintSingleEnemy(canvas, pool, i);
      }
    }
  }

  void _paintSingleEnemy(Canvas canvas, SoaEnemyPool pool, int i) {
    final double ex = pool.x[i];
    final double ey = pool.y[i];
    final double r = pool.radius[i];
    final int k = pool.kind[i];
    final Offset center = Offset(ex, ey);

    if (k == 2) {
      canvas.drawCircle(center, r, _bossFillPaint);
      canvas.drawCircle(center, r, _bossPaint);
      canvas.drawCircle(center, r * 0.55, _bossPaint);
    } else if (k == 1) {
      canvas.drawCircle(center, r, _weaverPaint);
      canvas.drawCircle(center, r * 0.4, _weaverPaint);
    } else {
      final Rect rect = Rect.fromCircle(center: center, radius: r * 0.85);
      canvas.drawRect(rect, _dronePaint);
    }

    final double ratio = (pool.hp[i] / pool.maxHp[i]).clamp(0.0, 1.0);
    if (ratio < 0.99) {
      final double barW = r * 2.0;
      final double left = ex - r;
      final double top = ey - r - 7.0;
      canvas.drawRect(Rect.fromLTWH(left, top, barW, 3.0), _hpTrackPaint);
      canvas.drawRect(Rect.fromLTWH(left, top, barW * ratio, 3.0), _hpFillPaint);
    }
  }

  void _paintNovaShockwave(Canvas canvas) {
    final double p = _controller.novaRingProgress;
    if (p <= 0.0) return;
    final double maxR = math.max(size.width, size.height) * 0.75;
    final double radius = 24.0 + maxR * p;
    canvas.drawCircle(
      Offset(_controller.playerX, _controller.playerY),
      radius,
      _novaRingPaint,
    );
  }

  void _paintPlayerShip(Canvas canvas) {
    final double px = _controller.playerX;
    final double py = _controller.playerY;
    final double ang = _controller.aimAngle;
    final Offset center = Offset(px, py);

    // Shield ring
    final double shieldRadius = 20.0 + _controller.shieldFlash * 6.0;
    canvas.drawCircle(center, shieldRadius, _shieldPaint);

    // Triangle hull geometry via pre-allocated line scratch buffer
    final double noseX = px + math.cos(ang) * 16.0;
    final double noseY = py + math.sin(ang) * 16.0;
    final double leftX = px + math.cos(ang + 2.45) * 13.0;
    final double leftY = py + math.sin(ang + 2.45) * 13.0;
    final double rightX = px + math.cos(ang - 2.45) * 13.0;
    final double rightY = py + math.sin(ang - 2.45) * 13.0;

    _shipLineScratch[0] = noseX;
    _shipLineScratch[1] = noseY;
    _shipLineScratch[2] = leftX;
    _shipLineScratch[3] = leftY;
    _shipLineScratch[4] = leftX;
    _shipLineScratch[5] = leftY;
    _shipLineScratch[6] = rightX;
    _shipLineScratch[7] = rightY;
    _shipLineScratch[8] = rightX;
    _shipLineScratch[9] = rightY;
    _shipLineScratch[10] = noseX;
    _shipLineScratch[11] = noseY;

    canvas.drawCircle(center, 6.5, _shipFillPaint);
    canvas.drawRawPoints(ui.PointMode.lines, _shipLineScratch, _shipOutlinePaint);

    // Zero-allocation combo readout next to player ship
    _comboPainter.paintInt(
      canvas,
      Offset(px - 14.0, py + 22.0),
      _controller.comboNotifier.value,
      minDigits: 2,
    );
  }
}
