import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_zero_core/d_zero_core.dart';
import 'package:d_zero_terminal/d_zero_terminal.dart';

void main() {
  group('C++17 FFI Shared Memory & VT100/TrueColor Parser', () {
    test('aligns ZeroTerminalState to 64-byte cache line and parses ANSI SGR', () {
      final ctrl = ZeroPtyController(cols: 80, rows: 24, scrollbackCapacity: 512);
      addTearDown(ctrl.dispose);

      expect(ctrl.statePointer.address & 63, equals(0));
      expect(ctrl.isNativeValid, isTrue);
      expect(ctrl.cols, equals(80));
      expect(ctrl.rows, equals(24));

      ctrl.feedAnsiText(
        '\x1b[1;4;38;2;255;128;64;48;2;16;32;48mD-Zero\x1b[0m Terminal\r\n',
      );

      expect(ctrl.readVisibleLine(0), equals('D-Zero Terminal'));
      expect(ctrl.cursorRow, equals(1));
      expect(ctrl.cursorCol, equals(0));

      // Verify cell 0 ('D') has 24-bit TrueColor FG & BG and Bold+Underline attrs
      expect(ctrl.viewportCodepoints[0], equals(0x44));
      expect(ctrl.viewportFgArgb[0], equals(0xFFFF8040));
      expect(ctrl.viewportBgArgb[0], equals(0xFF102030));
      expect(ctrl.viewportAttrs[0] & 0x09, equals(0x09));
    });

    test('parses 256-color SGR, UTF-8 multi-byte codepoints, and cursor motion', () {
      final ctrl = ZeroPtyController(cols: 40, rows: 10);
      addTearDown(ctrl.dispose);

      ctrl.feedAnsiText('Hello World');
      ctrl.feedAnsiText('\x1b[1;7H\x1b[38;5;208mD-Zero\x1b[K');
      expect(ctrl.readVisibleLine(0), equals('Hello D-Zero'));

      // UTF-8 multi-byte sequence ('⚡' = U+26A1)
      ctrl.feedAnsiText('\r\n⚡OK');
      expect(ctrl.viewportCodepoints[256], equals(0x26A1));
      expect(ctrl.viewportCodepoints[257], equals(0x4F));
      expect(ctrl.viewportCodepoints[258], equals(0x4B));
    });

    test('supports Alternate Screen Buffer (?1049h / ?1049l) state preservation', () {
      final ctrl = ZeroPtyController(cols: 60, rows: 16);
      addTearDown(ctrl.dispose);

      ctrl.feedAnsiText('Primary Shell Prompt \$ ');
      expect(ctrl.readVisibleLine(0), equals('Primary Shell Prompt \$'));
      expect(ctrl.altScreenActive, isFalse);

      // Enter alternate screen (e.g. vim / htop)
      ctrl.feedAnsiText('\x1b[?1049h\x1b[1;1H--- VIM ALTERNATE BUFFER ---');
      expect(ctrl.altScreenActive, isTrue);
      expect(ctrl.readVisibleLine(0), equals('--- VIM ALTERNATE BUFFER ---'));

      // Exit alternate screen and verify primary screen is restored
      ctrl.feedAnsiText('\x1b[?1049l');
      expect(ctrl.altScreenActive, isFalse);
      expect(ctrl.readVisibleLine(0), equals('Primary Shell Prompt \$'));
    });

    test('retains scrollback history and supports scrollBy / setScrollOffset', () {
      final ctrl = ZeroPtyController(cols: 40, rows: 6, scrollbackCapacity: 64);
      addTearDown(ctrl.dispose);

      for (int i = 0; i < 20; i++) {
        ctrl.feedAnsiText('LINE_${i.toString().padLeft(2, '0')}\r\n');
      }
      expect(ctrl.scrollOffset, equals(0));
      expect(ctrl.readVisibleLine(4), equals('LINE_19'));

      ctrl.scrollBy(5);
      expect(ctrl.scrollOffset, equals(5));
      expect(ctrl.readVisibleLine(4), equals('LINE_14'));

      ctrl.setScrollOffset(0);
      expect(ctrl.scrollOffset, equals(0));
      expect(ctrl.readVisibleLine(4), equals('LINE_19'));
    });

    test('spawns real POSIX forkpty shell and reads stdout on macOS/Linux', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;
      final ctrl = ZeroPtyController(cols: 80, rows: 24);
      addTearDown(ctrl.dispose);

      final pid = ctrl.spawnShell(shellPath: '/bin/sh');
      expect(pid, greaterThan(0));
      expect(ctrl.status, equals(ZeroTerminalStatus.ptyRunning));

      ctrl.writeInputText('echo DZERO_PTY_VERIFIED\n');
      bool foundOutput = false;
      for (int attempt = 0; attempt < 40; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        ctrl.pollNativeUpdates();
        for (int r = 0; r < ctrl.rows; r++) {
          if (ctrl.readVisibleLine(r).contains('DZERO_PTY_VERIFIED')) {
            foundOutput = true;
            break;
          }
        }
        if (foundOutput) break;
      }
      expect(foundOutput, isTrue);
      ctrl.stopShell();
      expect(ctrl.status, equals(ZeroTerminalStatus.exited));
    });
  });

  group('Memory Safety: Double-Free & Use-After-Free Resilience', () {
    test('survives double dispose and post-dispose calls safely', () {
      final ctrl = ZeroPtyController(cols: 80, rows: 24);
      final rawPtr = ctrl.statePointer;
      ctrl.feedAnsiText('Before dispose');
      ctrl.dispose();

      // Double-Free must be a safe no-op both at Dart and C++ FFI levels
      expect(() => ctrl.dispose(), returnsNormally);
      expect(
        () => ZeroTerminalNativeBindings.instance.destroyState(rawPtr),
        returnsNormally,
      );

      // Post-dispose reads and writes must return safe fallback values
      expect(ctrl.isDisposed, isTrue);
      expect(ctrl.isNativeValid, isFalse);
      expect(ctrl.cols, equals(0));
      expect(ctrl.rows, equals(0));
      expect(ctrl.bytesProcessed, equals(0));
      expect(ctrl.viewportCodepoints, isEmpty);
      expect(ctrl.feedAnsiText('After dispose'), equals(0));
      expect(ctrl.writeInputText('ls\n'), equals(0));
      expect(ctrl.sendKey(ZeroTerminalKeyCode.enter), equals(0));
      expect(ctrl.runStressBurst(lineCount: 100), equals(0));
      expect(() => ctrl.resize(100, 40), returnsNormally);
      expect(() => ctrl.clearScreen(), returnsNormally);
      expect(() => ctrl.reset(), returnsNormally);
    });
  });

  group('Widget Lifecycle, Unmount & Zero-Allocation Stress Tests', () {
    testWidgets(
      'ZPtyTerminal, ZTerminalHud, and ZTerminalMinimap mount, interact, and unmount cleanly',
      (tester) async {
        final ctrl = ZeroPtyController(cols: 80, rows: 24, scrollbackCapacity: 512);
        addTearDown(ctrl.dispose);

        int buildCount = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                buildCount++;
                return SizedBox(
                  width: 800,
                  height: 500,
                  child: Row(
                    children: [
                      Expanded(
                        child: ZPtyTerminal(
                          controller: ctrl,
                          autoResize: true,
                        ),
                      ),
                      ZTerminalMinimap(controller: ctrl),
                      ZTerminalHud(controller: ctrl),
                    ],
                  ),
                );
              },
            ),
          ),
        );

        expect(buildCount, equals(1));

        // Stream 2,000 TrueColor lines in bursts and verify 0 Widget rebuilds
        for (int i = 0; i < 10; i++) {
          ctrl.runStressBurst(lineCount: 200, seed: i + 1);
          await tester.pump(const Duration(milliseconds: 8));
        }
        expect(buildCount, equals(1));
        expect(ctrl.bytesProcessed, greaterThan(100000));

        // Pointer interaction & keyboard input on ZPtyTerminal
        final termFinder = find.byType(ZPtyTerminal);
        await tester.tap(termFinder);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        // Drag on ZTerminalMinimap to scrub scrollback
        final minimapFinder = find.byType(ZTerminalMinimap);
        await tester.drag(minimapFinder, const Offset(0, -40));
        await tester.pump();

        // Unmount all widgets and verify scheduler & listener cleanup
        await tester.pumpWidget(const SizedBox.shrink());
        expect(ZeroFrameScheduler.instance.subscriberCount, equals(0));
        expect(() => ctrl.runStressBurst(lineCount: 50), returnsNormally);
      },
    );
  });
}
