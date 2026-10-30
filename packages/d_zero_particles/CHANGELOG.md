## 0.1.0

* Unified monorepo initial release of `d_zero_particles`.
* Added `ZParticles` (legacy alias: `ZeroParticles`) for zero-allocation GPU-batched particle rendering via `Canvas.drawRawPoints`.
* Added `ZeroParticleController` and `ZeroParticleBuffer` with Structure-of-Arrays (`Float32List`) layout and 4-lane SIMD (`Float32x4`) branchless physics stepping.
* Added `ZConfetti` (legacy alias: `ZeroConfetti`) and `ZeroConfettiController` for multi-palette celebration confetti bursts with zero per-frame object allocations.
