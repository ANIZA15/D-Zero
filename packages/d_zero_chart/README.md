# d_zero_chart

Zero-allocation high-frequency financial and IoT telemetry charts (`ZSparkline`, `ZCandlestickChart`, `ZHeatmap`, `ZOrderBook`) for Flutter and Impeller.

## Features

- **`ZSparkline` (`ZRealtimeChart`)**: Real-time polyline chart backed by `FloatRingBuffer`, `Canvas.drawRawPoints`, and `ZeroNumberPainter`.
- **`ZCandlestickChart`**: Structure-of-Arrays (SoA) OHLC candlestick chart (`ZeroCandlestickBuffer`) with zero per-candle object allocations.
- **`ZHeatmap`**: 2D matrix density chart (`ZeroHeatmapBuffer`) using a pre-baked palette of quantized `Paint` buckets.
- **`ZOrderBook` (`ZDataGrid`)**: Financial L2 depth & bid/ask order book rendered inside a single `ZeroRenderBox` with zero widget rebuilds.
