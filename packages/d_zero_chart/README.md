# ⚡️ d_zero_chart

**Zero-allocation high-frequency financial, 3D surface, virtual grid, and IoT telemetry charts (`Z3DSurface`, `ZVirtualGrid`, `ZSparkline`, `ZCandlestickChart`, `ZHeatmap`, `ZOrderBook`) for Flutter and Impeller.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](../../LICENSE)
[![Impeller: Vulkan & Metal](https://img.shields.io/badge/Impeller-Vulkan%20%2F%20Metal-red.svg?style=flat-square)](https://flutter.dev/to/impeller)

---

## 📦 Distributed `Z` Widgets & Buffers

| Widget | Active Alias | Controller / Buffer | Zero-Allocation Architecture |
| :--- | :--- | :--- | :--- |
| **`Z3DSurface`** | `ZWaterfallChart` | `Zero3DSurfaceController` | 3D surface plot & waterfall spectrogram (`rows × cols` `Float32List` height map) rendered with perspective projection via a single `Canvas.drawVertices` + wireframe `drawRawPoints` pass. |
| **`ZVirtualGrid`** | `ZTimeSeriesTable` | `ZeroGridDataController` | Million-cell capable 2D virtualized numeric data grid backed by a contiguous `Float64List`, rendering only visible viewport cells via `ZeroNumberPainter` (`0` `String` / `Row` / `TableCell` allocations). |
| **`ZSparkline`** | `ZRealtimeChart` | `ZeroChartController` | Circular `FloatRingBuffer` + pre-allocated `Float32List` coordinate buffer flushed via `Canvas.drawRawPoints(PointMode.polygon)` + `ZeroNumberPainter` min/max/latest labels. |
| **`ZCandlestickChart`** | - | `ZeroCandlestickBuffer` | Structure-of-Arrays (SoA) `Float32List` ring buffer storing `open, high, low, close` (`4` floats/candle) with zero `Candle` object allocations. |
| **`ZHeatmap`** | - | `ZeroHeatmapBuffer` | Contiguous `rows × cols` `Float32List` matrix rendered with a pre-baked 32-bucket quantized `Paint` palette (`0` `Color.lerp` or `Paint` allocations in `paintZero`). |
| **`ZOrderBook`** | `ZDataGrid` | `ZeroOrderBookController` | L2 market depth Bid/Ask ladder rendered inside a single `ZeroRenderBox` using `ZeroNumberPainter` (`0` `Row`/`Column`/`Text` widget rebuilds). |
| **`ZActivityRings`** | `ZConcentricRings` | `ZeroActivityRingsController` | Concentric fitness activity rings (`Float32List(3)`) with centered average `ZeroNumberPainter.paintPercent` readout. |
| **`ZRadarChart`** | `ZSpiderChart` | `ZeroRadarChartController` | Multi-axis spider/radar polygon chart (`Float32List` axes + precomputed trig tables) flushed via `Canvas.drawRawPoints`. |
| **`ZDonutChart`** | `ZPieChart` | `ZeroDonutChartController` | Multi-segment ring/pie chart (`Float32List` values) with centered `ZeroNumberPainter.paintDouble` total readout. |
| **`ZContributionGraph`** | `ZHabitGrid` | `ZeroContributionBuffer` | GitHub-style `rows × cols` (`Uint8List`) contribution heatmap grid rendered with a 5-level quantized `Paint` LUT (`0` cell widgets). |

---

## 🚀 Installation & Usage

```yaml
dependencies:
  d_zero_chart: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:d_zero_chart/d_zero_chart.dart';

final sparklineCtrl = ZeroChartController(capacity: 128)..pushBatch([100.0, 102.5, 101.8, 104.2]);
final candleBuffer = ZeroCandlestickBuffer(capacity: 32)..addCandle(100.0, 105.0, 99.0, 103.5);
final heatmapBuffer = ZeroHeatmapBuffer(rows: 6, cols: 16);
final orderBookCtrl = ZeroOrderBookController(maxDepth: 6)
  ..updateBid(0, 64250.0, 1.45)
  ..updateAsk(0, 64252.5, 0.95);

Column(
  children: [
    SizedBox(height: 90, child: ZSparkline(controller: sparklineCtrl)),
    SizedBox(height: 120, child: ZCandlestickChart(buffer: candleBuffer)),
    SizedBox(height: 120, child: ZOrderBook(controller: orderBookCtrl)),
    SizedBox(height: 120, child: ZHeatmap(buffer: heatmapBuffer)),
  ],
);
```

---

## 📱 High-Load Comparison Benchmark App (`example/`)

The [`example/`](example) app streams high-frequency market ticks across `ZSparkline`, `ZCandlestickChart`, `ZOrderBook`, and `ZHeatmap` simultaneously, comparing `d_zero_chart` against traditional `CustomPaint` (`Path` allocations) and `Row`/`Column` order books with live **FPS, UI CPU Load (%), RSS Memory (MB), and Rebuild counters**.

```bash
cd packages/d_zero_chart/example
flutter run
```

## 📄 License

MIT License © 2026 fexcy
