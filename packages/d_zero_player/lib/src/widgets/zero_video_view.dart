import 'package:flutter/widgets.dart';
import 'package:d_zero_core/d_zero_core.dart';
import '../controller.dart';
import 'direct_seek_bar.dart';
import 'direct_time_label.dart';

/// A zero-jank, high-performance Flutter video player widget with Impeller zero-copy texture support.
class ZPlayer extends StatelessWidget implements ZWidget {
  /// The [ZeroPlayerController] managing the active video session.
  final ZeroPlayerController controller;

  /// An optional custom overlay widget placed above the video frame.
  final Widget? overlay;

  /// Whether to display the built-in zero-rebuild controls HUD.
  final bool showControls;

  /// Creates a [ZPlayer].
  const ZPlayer({
    super.key,
    required this.controller,
    this.overlay,
    this.showControls = true,
  });

  @override
  bool get isZeroAllocation => true;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. ネイティブ映像テクスチャ (Impeller Zero-Copy Texture)
          if (controller.textureId != -1)
            Texture(textureId: controller.textureId)
          else
            const ColoredBox(color: Color(0xFF000000)),

          // 2. カスタムオーバーレイ
          if (overlay != null) overlay!,

          // 3. ゼロリビルド・コントロールレイヤー (120fps VSync 完全同期)
          if (showControls)
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZDirectTimeLabel(controller: controller),
                  const SizedBox(height: 6),
                  ZDirectSeekBar(
                    controller: controller,
                    onSeek: (position) {
                      controller.seekTo(position);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Backward compatibility alias for [ZPlayer].
@Deprecated('Use ZPlayer instead.')
typedef ZeroPlayerView = ZPlayer;

/// Optional alias for [ZPlayer].
typedef ZPlayerView = ZPlayer;
