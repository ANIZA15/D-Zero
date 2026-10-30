# d_zero_waveform

Zero-allocation real-time audio waveform (`ZWaveform` / `ZAudioVisualizer`), FFT spectrum analyzer (`ZSpectrumAnalyzer`), and stereo VU peak meter (`ZAudioMeter` / `ZVUMeter`) widgets for Flutter and Impeller.

## Features

- **`ZWaveform` (`ZAudioVisualizer`)**: Renders real-time audio waveforms using pre-allocated `Float32List` vertex buffers and `Canvas.drawRawPoints` with zero per-frame allocations.
- **`ZSpectrumAnalyzer`**: Renders FFT frequency bands and gravity-decayed peak-hold indicators inside a `ZeroRenderBox`.
- **`ZAudioMeter` (`ZVUMeter`)**: Renders stereo/mono green/yellow/red RMS zones, peak-hold markers, clip-hold indicator, and zero-allocation dBFS numeric readout via `ZeroNumberPainter`.
