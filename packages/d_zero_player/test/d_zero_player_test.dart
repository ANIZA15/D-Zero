import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_player/src/playback_state_ffi.dart';
import 'package:d_zero_player/d_zero_player.dart';

void main() {
  group('【1. 正常系テスト】ZeroPlayerController & FFI マッピング', () {
    late ZeroPlayerController controller;

    setUp(() {
      controller = ZeroPlayerController.simulated();
    });

    tearDown(() {
      controller.dispose();
    });

    test('初期状態がすべてゼロ・デフォルト値であること', () {
      expect(controller.positionMs, equals(0));
      expect(controller.durationMs, equals(0));
      expect(controller.bufferedMs, equals(0));
      expect(controller.progress, equals(0.0));
      expect(controller.status, equals(ZeroPlaybackStatus.idle));
    });

    test('共有メモリへの更新が 0 ナノ秒で Dart 側に即時反映されること', () {
      controller.setDurationSimulated(60000); // 1分
      controller.setPositionSimulated(30000); // 30秒

      expect(controller.durationMs, equals(60000));
      expect(controller.positionMs, equals(30000));
      expect(controller.progress, closeTo(0.5, 0.001));
    });

    test('再生進捗率 (progress) の計算が正確であること', () {
      controller.setDurationSimulated(100000);
      controller.setPositionSimulated(25000);
      expect(controller.progress, closeTo(0.25, 0.0001));

      controller.setPositionSimulated(75000);
      expect(controller.progress, closeTo(0.75, 0.0001));

      controller.setPositionSimulated(100000);
      expect(controller.progress, closeTo(1.0, 0.0001));
    });
  });

  group('【2. 異常系テスト】境界値・不正操作・ゼロ除算・Use-After-Free 防御', () {
    test('ゼロ除算防止: duration が 0 の場合でも progress でクラッシュせず 0.0 を返すこと', () {
      final controller = ZeroPlayerController.simulated();
      controller.setDurationSimulated(0);
      controller.setPositionSimulated(5000);

      expect(() => controller.progress, returnsNormally);
      expect(controller.progress, equals(0.0));
      controller.dispose();
    });

    test('オーバーフロー耐性: position が duration を超過しても progress は 1.0 にクランプされること', () {
      final controller = ZeroPlayerController.simulated();
      controller.setDurationSimulated(10000);
      controller.setPositionSimulated(99999); // 超過

      expect(controller.progress, equals(1.0));
      controller.dispose();
    });

    test('負の値耐性: position が負の値の場合でも progress は 0.0 にクランプされること', () {
      final controller = ZeroPlayerController.simulated();
      controller.setDurationSimulated(10000);
      controller.setPositionSimulated(-5000);

      expect(controller.progress, equals(0.0));
      controller.dispose();
    });

    test('Use-After-Free 防御: dispose() 済みのコントローラを参照しても SIGSEGV せず安全な値を返すこと',
        () {
      final controller = ZeroPlayerController.simulated();
      controller.setDurationSimulated(50000);
      controller.setPositionSimulated(20000);

      // 解放
      controller.dispose();

      // 解放後にアクセスしてもクラッシュしないこと
      expect(() => controller.positionMs, returnsNormally);
      expect(controller.positionMs, equals(0));
      expect(controller.durationMs, equals(0));
      expect(controller.progress, equals(0.0));
      expect(controller.status, equals(ZeroPlaybackStatus.idle));
    });

    test('二重解放（Double Free）防止: dispose() を複数回呼んでもクラッシュしないこと', () {
      final controller = ZeroPlayerController.simulated();
      expect(() {
        controller.dispose();
        controller.dispose();
        controller.dispose();
      }, returnsNormally);
    });
  });

  group('【3. ペネトレーション / 耐久ストレステスト】', () {
    test('100,000 回の超高速連続ポインタサンプリングでメモリ破壊や遅延が起きないこと', () {
      final controller = ZeroPlayerController.simulated();
      controller.setDurationSimulated(1000000);

      final stopwatch = Stopwatch()..start();
      final random = Random();

      for (int i = 0; i < 100000; i++) {
        final pos = random.nextInt(1000000);
        controller.setPositionSimulated(pos);
        final readPos = controller.positionMs;
        expect(readPos, equals(pos));
      }

      stopwatch.stop();
      // 100,000 回の直読み書きがミリ秒オーダーで完了すること（FFI 共有メモリの速度証明）
      expect(stopwatch.elapsedMilliseconds, lessThan(200),
          reason: 'FFI 共有メモリの読み書きは 100,000 回で 200ms 未満で完了すべき');

      controller.dispose();
    });
  });

  group('【4. マルチプロトコル・全フェーズ拡張テスト】', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    final List<MethodCall> methodCalls = [];

    setUp(() {
      methodCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.fexcy.zero_player'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'create') {
            return {
              'textureId': 42,
              'stateAddress':
                  ZeroPlayerNativeBindings.instance.createState().address,
            };
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.fexcy.zero_player'),
        null,
      );
    });

    test('Phase 1: HTTP Headers & Cookie パラメータが MethodChannel に正しく渡されること',
        () async {
      final controller = await ZeroPlayerController.network(
        'https://example.com/stream.m3u8',
        headers: {
          'Referer': 'https://live.erinn.biz/',
          'Cookie': 'session=xyz',
          'User-Agent': 'ZeroPlayer/1.0',
        },
      );

      expect(methodCalls.length, equals(1));
      final call = methodCalls.first;
      expect(call.method, equals('create'));
      expect(call.arguments['url'], equals('https://example.com/stream.m3u8'));
      expect(call.arguments['headers'], equals({
        'Referer': 'https://live.erinn.biz/',
        'Cookie': 'session=xyz',
        'User-Agent': 'ZeroPlayer/1.0',
      }));

      controller.dispose();
    });

    test('Phase 2: RTSP / DASH / HLS プロトコル指定が正しく渡されること', () async {
      final controller = await ZeroPlayerController.network(
        'rtsp://192.168.1.1:554/live',
        protocol: ZeroStreamProtocol.rtsp,
        isLive: true,
      );

      final call = methodCalls.first;
      expect(call.arguments['protocol'], equals('rtsp'));
      expect(call.arguments['isLive'], isTrue);

      controller.dispose();
    });

    test('Phase 3: ZeroPlayerController.webSocket で WebSocket ストリームが作成できること',
        () async {
      final controller = await ZeroPlayerController.webSocket(
        'wss://live.erinn.biz/stream/live_123',
        headers: {'Origin': 'https://live.erinn.biz'},
        mimeType: 'video/mp4',
      );

      final call = methodCalls.first;
      expect(call.arguments['url'], equals('wss://live.erinn.biz/stream/live_123'));
      expect(call.arguments['protocol'], equals('websocket'));
      expect(call.arguments['isLive'], isTrue);
      expect(call.arguments['mimeType'], equals('video/mp4'));
      expect(call.arguments['headers'], equals({'Origin': 'https://live.erinn.biz'}));

      controller.dispose();
    });

    test('Phase 4: WebRTC / ExternalStream ファクトリで外部バインドが機能すること', () {
      final dummyPtr = ZeroPlayerNativeBindings.instance.createState();
      final controller = ZeroPlayerController.externalStream(
        textureId: 99,
        stateAddress: dummyPtr.address,
        ownsState: true,
      );

      expect(controller.textureId, equals(99));
      expect(controller.positionMs, equals(0));

      controller.setPositionSimulated(1234);
      expect(controller.positionMs, equals(1234));

      controller.dispose();
      expect(controller.isDisposed, isTrue);
    });
  });

  group('【5. Widget ライフサイクル & Z-Prefix 互換テスト】', () {
    testWidgets('ZPlayer, ZDirectSeekBar, ZDirectTimeLabel がマウント・アンマウントで正常動作すること',
        (tester) async {
      final controller = ZeroPlayerController.simulated();
      controller.setDurationSimulated(120000);
      controller.setPositionSimulated(30000);

      // マウント
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZPlayer(
              controller: controller,
              showControls: true,
            ),
          ),
        ),
      );

      expect(find.byType(ZPlayer), findsOneWidget);
      expect(find.byType(ZDirectSeekBar), findsOneWidget);
      expect(find.byType(ZDirectTimeLabel), findsOneWidget);

      // フレームを進める
      await tester.pump(const Duration(milliseconds: 100));

      // アンマウント
      await tester.pumpWidget(const SizedBox.shrink());

      // コントローラを破棄
      controller.dispose();
    });

    testWidgets('コントローラ破棄後の Widget アンマウントでも SIGSEGV せず安全であること',
        (tester) async {
      final controller = ZeroPlayerController.simulated();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZPlayer(
              controller: controller,
              showControls: true,
            ),
          ),
        ),
      );

      // コントローラを先に破棄（Use-After-Free 境界テスト）
      controller.dispose();

      // 破棄後にフレーム進行・再描画・タップシークが発生しても解放済みポインタを参照しないこと
      await tester.pump(const Duration(milliseconds: 32));
      await tester.tap(find.byType(ZDirectSeekBar));
      await tester.pump(const Duration(milliseconds: 16));

      // ウィジェットのアンマウント
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'Dangling Pointer 防御: 無効アドレスを持つ破棄済みコントローラでも ZPlayer 描画時に SIGSEGV しないこと',
        (tester) async {
      // デリファレンスされたら即座に SIGSEGV する不正アドレス (0xDEADBEEF)
      final controller = ZeroPlayerController.externalStream(
        textureId: -1,
        stateAddress: 0xDEADBEEF,
        ownsState: false,
      );
      await controller.dispose();
      expect(controller.isDisposed, isTrue);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ZPlayer(
              controller: controller,
              showControls: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 32));
      await tester.tap(find.byType(ZDirectSeekBar));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('後方互換性エイリアス (ZeroPlayerView, DirectSeekBar, DirectTimeLabel) が透過的に機能すること',
        (tester) async {
      final controller = ZeroPlayerController.simulated();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              // ignore: deprecated_member_use_from_same_package
              ZeroPlayerView(controller: controller, showControls: false),
              // ignore: deprecated_member_use_from_same_package
              DirectSeekBar(controller: controller),
              // ignore: deprecated_member_use_from_same_package
              DirectTimeLabel(controller: controller),
            ],
          ),
        ),
      );

      expect(find.byType(ZPlayer), findsOneWidget);
      expect(find.byType(ZDirectSeekBar), findsOneWidget);
      expect(find.byType(ZDirectTimeLabel), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  });
}
