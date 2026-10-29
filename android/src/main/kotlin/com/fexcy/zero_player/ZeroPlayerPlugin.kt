package com.fexcy.zero_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class ZeroPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var textureRegistry: TextureRegistry
    private val players = mutableMapOf<Long, ZeroExoPlayerWrapper>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "com.fexcy.zero_player")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("INVALID_ARGUMENT", "URL is required", null)
                    return
                }

                val textureEntry = textureRegistry.createSurfaceTexture()
                val playerWrapper = ZeroExoPlayerWrapper(context, textureEntry, url)
                players[textureEntry.id()] = playerWrapper

                result.success(
                    mapOf(
                        "textureId" to textureEntry.id(),
                        "stateAddress" to playerWrapper.statePtr
                    )
                )
            }
            "play" -> {
                val textureId = (call.argument<Number>("textureId"))?.toLong()
                players[textureId]?.play()
                result.success(null)
            }
            "pause" -> {
                val textureId = (call.argument<Number>("textureId"))?.toLong()
                players[textureId]?.pause()
                result.success(null)
            }
            "seekTo" -> {
                val textureId = (call.argument<Number>("textureId"))?.toLong()
                val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                players[textureId]?.seekTo(positionMs)
                result.success(null)
            }
            "dispose" -> {
                val textureId = (call.argument<Number>("textureId"))?.toLong()
                players.remove(textureId)?.dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        players.values.forEach { it.dispose() }
        players.clear()
    }
}

class ZeroExoPlayerWrapper(
    context: Context,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    url: String
) {
    val statePtr: Long = ZeroNativeBridge.createState()
    private val exoPlayer: ExoPlayer = ExoPlayer.Builder(context).build()
    private val surface: Surface = Surface(textureEntry.surfaceTexture())
    private val handler = Handler(Looper.getMainLooper())
    private var isDisposed = false

    // 再生位置を高速ポーリングして C++ 共有メモリに直接書き込む Runnable
    private val syncRunnable = object : Runnable {
        override fun run() {
            if (isDisposed) return
            val pos = exoPlayer.currentPosition
            ZeroNativeBridge.setPosition(statePtr, pos)
            // 次のフレーム更新をスケジューリング（約16ms間隔）
            handler.postDelayed(this, 16)
        }
    }

    init {
        exoPlayer.setVideoSurface(surface)
        val mediaItem = MediaItem.fromUri(url)
        exoPlayer.setMediaItem(mediaItem)
        exoPlayer.prepare()

        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (isDisposed) return
                val dur = exoPlayer.duration
                if (dur > 0) {
                    ZeroNativeBridge.setDuration(statePtr, dur)
                }

                val status = when (playbackState) {
                    Player.STATE_IDLE -> 0
                    Player.STATE_BUFFERING -> 1
                    Player.STATE_READY -> if (exoPlayer.playWhenReady) 2 else 3
                    Player.STATE_ENDED -> 4
                    else -> 0
                }
                ZeroNativeBridge.setStatus(statePtr, status)
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (isDisposed) return
                ZeroNativeBridge.setVideoSize(statePtr, videoSize.width, videoSize.height)
            }

            override fun onPlayerError(error: PlaybackException) {
                if (isDisposed) return
                ZeroNativeBridge.setStatus(statePtr, 5) // Error
            }
        })

        // 位置同期ループ開始
        handler.post(syncRunnable)
    }

    fun play() {
        if (isDisposed) return
        exoPlayer.playWhenReady = true
        ZeroNativeBridge.setStatus(statePtr, 2)
    }

    fun pause() {
        if (isDisposed) return
        exoPlayer.playWhenReady = false
        ZeroNativeBridge.setStatus(statePtr, 3)
    }

    fun seekTo(positionMs: Long) {
        if (isDisposed) return
        exoPlayer.seekTo(positionMs)
        ZeroNativeBridge.setPosition(statePtr, positionMs)
    }

    fun dispose() {
        if (isDisposed) return
        isDisposed = true
        handler.removeCallbacks(syncRunnable)
        exoPlayer.stop()
        exoPlayer.release()
        surface.release()
        textureEntry.release()
        ZeroNativeBridge.destroyState(statePtr)
    }
}
