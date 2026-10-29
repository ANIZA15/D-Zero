package com.fexcy.zero_player

object ZeroNativeBridge {
    init {
        System.loadLibrary("zero_player_native")
    }

    external fun createState(): Long
    external fun destroyState(statePtr: Long)
    external fun setPosition(statePtr: Long, positionMs: Long)
    external fun setPositionAnchor(statePtr: Long, positionMs: Long, speed: Float)
    external fun setPlaybackSpeed(statePtr: Long, speed: Float)
    external fun setDuration(statePtr: Long, durationMs: Long)
    external fun setBuffered(statePtr: Long, bufferedMs: Long)
    external fun setStatus(statePtr: Long, status: Int)
    external fun setVideoSize(statePtr: Long, width: Int, height: Int)
}
