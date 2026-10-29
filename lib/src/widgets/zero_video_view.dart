import 'package:flutter/widgets.dart';
import '../controller.dart';
import 'direct_seek_bar.dart';
import 'direct_time_label.dart';

/// ゼロジャンク・次世代動画プレイヤー Widget
class ZeroPlayerView extends StatelessWidget {
  final ZeroPlayerController controller;
  final Widget? overlay;
  final bool showControls;

  const ZeroPlayerView({
    super.key,
    required this.controller,
    this.overlay,
    this.showControls = true,
  });

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
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      DirectTimeLabel(controller: controller),
                    ],
                  ),
                  const SizedBox(height: 6),
                  DirectSeekBar(
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
