# Security Policy

## Supported Versions

All packages in the `D-Zero` monorepo (`d_zero_core`, `d_zero_player`, `d_zero_counter`, `d_zero_ui`, `d_zero_chart`, `d_zero_waveform`, `d_zero_particles`, `d_zero_fx`, `d_zero_canvas`, `d_zero_sensor`) currently receive security updates on the latest `0.1.x` release line.

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| < 0.1.0 | :x:                |

## Scope of Security Focus

We pay special attention to memory safety and resource lifecycle issues, including:
* **Native C++ / Dart FFI Shared Memory (`d_zero_player`)**: Use-after-free, double-free, out-of-bounds pointer reads, or data races across native decoder threads and the Dart UI thread.
* **Typed Data & Ring Buffer Bounds (`d_zero_core`, `d_zero_particles`, etc.)**: Buffer overflows or unvalidated index access in `Float32List` / SIMD pipelines.
* **Resource Exhaustion**: Unbounded GPU `ui.Image` / `ui.Picture` atlas leaks on widget disposal.

## Reporting a Vulnerability

Please **do not** report security vulnerabilities through public GitHub issues.

Instead, please report them privately via [GitHub Private Vulnerability Reporting](https://github.com/ANIZA15/D-Zero/security/advisories/new) on the repository.

Include the following details in your report:
1. Affected package(s) and version(s).
2. Target platform (iOS / Android / macOS / Web / etc.) and Flutter version.
3. Minimal reproduction code or native stack trace.

We will acknowledge receipt within 72 hours and work with you to validate and release a fix.
