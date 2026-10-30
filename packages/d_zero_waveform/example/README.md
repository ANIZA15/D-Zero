# ⚡️ d_zero_waveform Audio DSP Benchmark App

Compares `d_zero_waveform` (`ZWaveform`, `ZSpectrumAnalyzer`, `ZAudioMeter`) against traditional `Row`/`Container` FFT bar trees and `LinearProgressIndicator` widgets at 120Hz.

## 📊 Live Metrics Displayed
- **FPS & Frame Histogram** (`ZFPSMonitor`)
- **CPU Load (%)** (`ZPriceTicker`)
- **RSS Memory / Peak MB** (`ZPriceTicker`)
- **D-Zero vs Traditional Rebuilds & Allocations** (`ZCounter`)

```bash
flutter run
```
