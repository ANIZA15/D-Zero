/// A next-generation, zero-jank Flutter video player optimized for Impeller,
/// utilizing FFI shared-memory and custom RenderBoxes for zero rebuilds.
library d_zero_player;

export 'src/controller.dart';
export 'src/playback_state_ffi.dart' show ZeroPlaybackStatus;
export 'src/widgets/direct_seek_bar.dart';
export 'src/widgets/direct_time_label.dart';
export 'src/widgets/zero_video_view.dart';
