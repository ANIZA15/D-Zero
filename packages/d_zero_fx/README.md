# d_zero_fx

Zero-allocation, zero-`saveLayer` visual effects for Flutter & Impeller:
- `ZShimmer` (`ZSkeleton`): 120fps skeleton placeholder sweep without `ShaderMask` or offscreen buffers.
- `ZBlur` (`ZGlassContainer`): Specular frosted glass panel without `BackdropFilter` save layers.
- `ZRipple` (`ZInkWell`) & `ZeroRippleController`: Multi-touch SoA ring-buffer ripple surface.
- `ZLiquidProgress` (`ZWaveFilter`): Raw point-buffer sine wave gauge with `ZeroNumberPainter` percentage readout.
