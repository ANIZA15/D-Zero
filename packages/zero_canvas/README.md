# zero_canvas

Zero-allocation massive-element canvas widgets for Flutter & Impeller:
- `ZDanmaku` (`ZChatStream`) & `ZeroDanmakuController`: Pooled SoA live bullet comments without per-comment widgets.
- `ZInfiniteGrid` (`ZCanvasGrid`) & `ZeroViewportController`: Single-batch `drawRawPoints` infinite 2D pan/zoom grid.
- `ZFreehandCanvas` & `ZeroFreehandController`: 120Hz/240Hz direct pointer-to-float-buffer freehand ink canvas.
