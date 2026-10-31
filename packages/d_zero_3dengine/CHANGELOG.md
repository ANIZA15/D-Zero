## 0.1.4

* Initial release of `d_zero_3dengine` v0.1.4.
* Added 128-byte (2 cache lines) C++ FFI shared memory (`Zero3DEngineState`) with `ZERO_3D_MAGIC_ALIVE` canary protection, seqlock synchronization, and ASan/UBSan/TSan verification.
* Added `ZViewport3D` (`ZScene3D`) and `ZEngineTelemetryHud` (`Z3DStatsOverlay`) with 60Hz / 120Hz / 144Hz / 240Hz / Uncapped FPS support, Nanite-style meshlet cluster DAG culling, and Metal 3 / Impeller GLSL 460 Ray Tracing.
