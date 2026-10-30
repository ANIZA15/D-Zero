package com.fexcy.zero_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.io.IOException
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.concurrent.TimeUnit

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

                @Suppress("UNCHECKED_CAST")
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                val isLive = call.argument<Boolean>("isLive") ?: false
                val protocol = call.argument<String>("protocol") ?: "auto"
                val mimeType = call.argument<String>("mimeType")

                // Impeller (Vulkan / OpenGLES) ゼロコピー対応の SurfaceProducer を使用
                val surfaceProducer = textureRegistry.createSurfaceProducer()
                val playerWrapper = ZeroExoPlayerWrapper(
                    context = context,
                    surfaceProducer = surfaceProducer,
                    url = url,
                    headers = headers,
                    isLive = isLive,
                    protocol = protocol,
                    customMimeType = mimeType
                )
                players[surfaceProducer.id()] = playerWrapper

                result.success(
                    mapOf(
                        "textureId" to surfaceProducer.id(),
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

/**
 * マルチプロトコル（HLS, DASH, RTSP, WebSocket, HTTP/HTTPS）対応
 * ゼロアロケーション型 ExoPlayer ラッパー
 *
 * - TextureRegistry.SurfaceProducer で Impeller ゼロコピー描画
 * - 16ms ポーリングを廃止し、状態変化時のアンカー書き込み + 再生中のみ 250ms 周期のドリフト補正を実施
 *   (Dart 側が zero_get_display_position で 60/90/120Hz に合わせて連続外挿)
 */
class ZeroExoPlayerWrapper(
    context: Context,
    private val surfaceProducer: TextureRegistry.SurfaceProducer,
    url: String,
    headers: Map<String, String> = emptyMap(),
    isLive: Boolean = false,
    protocol: String = "auto",
    customMimeType: String? = null
) {
    companion object {
        private const val DRIFT_SYNC_INTERVAL_MS = 250L
    }

    val statePtr: Long = ZeroNativeBridge.createState()
    private val exoPlayer: ExoPlayer = ExoPlayer.Builder(context).build()
    private val handler = Handler(Looper.getMainLooper())
    private var isDisposed = false
    private var isDriftSyncScheduled = false
    private var webSocketStreamHandler: ZeroWebSocketStreamHandler? = null

    // 再生中のみ 250ms 間隔でアンカーとバッファ位置を補正する（一時停止中は完全停止）
    private val driftSyncRunnable = object : Runnable {
        override fun run() {
            isDriftSyncScheduled = false
            if (isDisposed || !exoPlayer.isPlaying) return
            syncAnchor()
            scheduleDriftSyncIfNeeded()
        }
    }

    private fun syncAnchor() {
        if (isDisposed) return
        val pos = exoPlayer.currentPosition
        val buffered = exoPlayer.bufferedPosition
        val speed = exoPlayer.playbackParameters.speed
        ZeroNativeBridge.setPositionAnchor(statePtr, pos, speed)
        ZeroNativeBridge.setBuffered(statePtr, buffered)
    }

    private fun scheduleDriftSyncIfNeeded() {
        if (isDisposed || isDriftSyncScheduled || !exoPlayer.isPlaying) return
        isDriftSyncScheduled = true
        handler.postDelayed(driftSyncRunnable, DRIFT_SYNC_INTERVAL_MS)
    }

    private fun stopDriftSync() {
        if (!isDriftSyncScheduled) return
        isDriftSyncScheduled = false
        handler.removeCallbacks(driftSyncRunnable)
    }

    init {
        exoPlayer.setVideoSurface(surfaceProducer.surface)
        surfaceProducer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                if (isDisposed) return
                exoPlayer.setVideoSurface(surfaceProducer.surface)
            }

            override fun onSurfaceCleanup() {
                if (isDisposed) return
                exoPlayer.clearVideoSurface()
            }
        })

        // OkHttp クライアント（HTTP/2, HTTP/3, 高速キープアライブ, リダイレクト追跡）
        val okHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .addInterceptor { chain ->
                val originalRequest = chain.request()
                val requestBuilder = originalRequest.newBuilder()
                if (originalRequest.header("User-Agent") == null) {
                    requestBuilder.header(
                        "User-Agent",
                        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                    )
                }
                chain.proceed(requestBuilder.build())
            }
            .build()

        val isWs = url.startsWith("ws://", ignoreCase = true) || url.startsWith("wss://", ignoreCase = true)

        if (isWs) {
            // =========================================================================
            // Phase 3: ネイティブ WebSocket ストリーミング（kukuluLIVE 等のリアルタイム配信対応）
            // =========================================================================
            val wsHandler = ZeroWebSocketStreamHandler(okHttpClient, url, headers)
            webSocketStreamHandler = wsHandler
            wsHandler.start()

            val dataSourceFactory = DataSource.Factory { wsHandler.createDataSource() }
            val mediaItemBuilder = MediaItem.Builder().setUri(Uri.parse("zero://websocket-stream"))
            if (customMimeType != null) {
                mediaItemBuilder.setMimeType(customMimeType)
            } else {
                mediaItemBuilder.setMimeType(MimeTypes.VIDEO_MP4)
            }
            val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(mediaItemBuilder.build())
            exoPlayer.setMediaSource(mediaSource)
        } else {
            // =========================================================================
            // Phase 1 & 2: HTTP Headers + RTSP / HLS / DASH / Progressive 自動選択
            // =========================================================================
            val httpDataSourceFactory = OkHttpDataSource.Factory(okHttpClient)
            if (headers.isNotEmpty()) {
                httpDataSourceFactory.setDefaultRequestProperties(headers)
            }

            val mediaItemBuilder = MediaItem.Builder().setUri(url)

            // 低遅延ライブ配信（LL-HLS / Live Stream）のレイテンシー最適化
            if (isLive) {
                mediaItemBuilder.setLiveConfiguration(
                    MediaItem.LiveConfiguration.Builder()
                        .setMaxPlaybackSpeed(1.05f)
                        .setMinPlaybackSpeed(0.95f)
                        .setTargetOffsetMs(1500) // 1.5秒低遅延ターゲット
                        .build()
                )
            }

            val lowerUrl = url.lowercase()
            val uri = Uri.parse(url)
            val scheme = uri.scheme?.lowercase() ?: ""
            val isHls = protocol == "hls" || lowerUrl.contains(".m3u8") || lowerUrl.contains("format=m3u8") || lowerUrl.contains("type=m3u8")
            val isDash = protocol == "dash" || lowerUrl.contains(".mpd")
            val isRtsp = protocol == "rtsp" || scheme == "rtsp"

            if (isHls) {
                mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            } else if (isDash) {
                mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
            } else if (customMimeType != null) {
                mediaItemBuilder.setMimeType(customMimeType)
            }

            val mediaItem = mediaItemBuilder.build()

            val mediaSource: MediaSource = when {
                isRtsp -> {
                    android.util.Log.d("ZeroPlayer", "Playing via RtspMediaSource: $url")
                    RtspMediaSource.Factory().createMediaSource(mediaItem)
                }
                isDash -> {
                    android.util.Log.d("ZeroPlayer", "Playing via DashMediaSource: $url")
                    DashMediaSource.Factory(httpDataSourceFactory).createMediaSource(mediaItem)
                }
                isHls -> {
                    android.util.Log.d("ZeroPlayer", "Playing via HlsMediaSource: $url")
                    HlsMediaSource.Factory(httpDataSourceFactory)
                        .setAllowChunklessPreparation(true)
                        .createMediaSource(mediaItem)
                }
                else -> {
                    android.util.Log.d("ZeroPlayer", "Playing via ProgressiveMediaSource: $url")
                    ProgressiveMediaSource.Factory(httpDataSourceFactory).createMediaSource(mediaItem)
                }
            }

            exoPlayer.setMediaSource(mediaSource)
        }

        exoPlayer.prepare()

        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (isDisposed) return
                val dur = exoPlayer.duration
                if (dur > 0 && dur != C.TIME_UNSET) {
                    ZeroNativeBridge.setDuration(statePtr, dur)
                }
                syncAnchor()
                val status = when (playbackState) {
                    Player.STATE_IDLE -> 0
                    Player.STATE_BUFFERING -> 1
                    Player.STATE_READY -> if (exoPlayer.playWhenReady) 2 else 3
                    Player.STATE_ENDED -> 4
                    else -> 0
                }
                ZeroNativeBridge.setStatus(statePtr, status)
                if (status == 2) {
                    scheduleDriftSyncIfNeeded()
                } else {
                    stopDriftSync()
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isDisposed) return
                syncAnchor()
                if (isPlaying) {
                    ZeroNativeBridge.setStatus(statePtr, 2)
                    scheduleDriftSyncIfNeeded()
                } else {
                    stopDriftSync()
                    if (exoPlayer.playbackState == Player.STATE_READY) {
                        ZeroNativeBridge.setStatus(statePtr, 3)
                    }
                }
            }

            override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
                if (isDisposed) return
                ZeroNativeBridge.setPlaybackSpeed(statePtr, playbackParameters.speed)
            }

            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int
            ) {
                if (isDisposed) return
                syncAnchor()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (isDisposed) return
                if (videoSize.width > 0 && videoSize.height > 0) {
                    surfaceProducer.setSize(videoSize.width, videoSize.height)
                }
                ZeroNativeBridge.setVideoSize(statePtr, videoSize.width, videoSize.height)
            }

            override fun onPlayerError(error: PlaybackException) {
                if (isDisposed) return
                stopDriftSync()
                ZeroNativeBridge.setStatus(statePtr, 5) // Error
            }
        })
    }

    fun play() {
        if (isDisposed) return
        exoPlayer.playWhenReady = true
        syncAnchor()
        ZeroNativeBridge.setStatus(statePtr, 2)
        scheduleDriftSyncIfNeeded()
    }

    fun pause() {
        if (isDisposed) return
        exoPlayer.playWhenReady = false
        stopDriftSync()
        syncAnchor()
        ZeroNativeBridge.setStatus(statePtr, 3)
    }

    fun seekTo(positionMs: Long) {
        if (isDisposed) return
        exoPlayer.seekTo(positionMs)
        ZeroNativeBridge.setPositionAnchor(statePtr, positionMs, exoPlayer.playbackParameters.speed)
    }

    fun dispose() {
        if (isDisposed) return
        isDisposed = true
        stopDriftSync()
        webSocketStreamHandler?.dispose()
        exoPlayer.clearVideoSurface()
        exoPlayer.stop()
        exoPlayer.release()
        surfaceProducer.release()
        ZeroNativeBridge.destroyState(statePtr)
    }
}

/**
 * Phase 3: ネイティブ WebSocket ストリームハンドラー
 * Dart のヒープを汚染せず、OkHttp のバックグラウンドスレッドで
 * fMP4 / TS チャンクを受信して PipedStream 経由で ExoPlayer に直結する
 */
class ZeroWebSocketStreamHandler(
    private val client: OkHttpClient,
    private val wsUrl: String,
    private val headers: Map<String, String>
) {
    private var webSocket: WebSocket? = null
    private val pipedOutput = PipedOutputStream()
    private val pipedInput = PipedInputStream(pipedOutput, 1024 * 1024) // 1MB バッファ
    private var isDisposed = false

    fun start() {
        val requestBuilder = Request.Builder().url(wsUrl)
        headers.forEach { (k, v) -> requestBuilder.addHeader(k, v) }
        val request = requestBuilder.build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                if (isDisposed) return
                try {
                    bytes.write(pipedOutput)
                    pipedOutput.flush()
                } catch (e: IOException) {
                    // パイプ破損・クローズ時の例外
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                closeStreams()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                closeStreams()
            }
        })
    }

    fun createDataSource(): DataSource {
        return object : DataSource {
            private var opened = false

            override fun open(dataSpec: DataSpec): Long {
                opened = true
                return C.LENGTH_UNSET.toLong() // ライブストリームなので長さ未定
            }

            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                if (!opened || isDisposed) return C.RESULT_END_OF_INPUT
                val bytesRead = pipedInput.read(buffer, offset, length)
                return if (bytesRead == -1) C.RESULT_END_OF_INPUT else bytesRead
            }

            override fun getUri(): Uri? = Uri.parse(wsUrl)

            override fun close() {
                opened = false
            }

            override fun addTransferListener(transferListener: androidx.media3.datasource.TransferListener) {}
        }
    }

    private fun closeStreams() {
        try {
            pipedOutput.close()
        } catch (_: Exception) {}
    }

    fun dispose() {
        isDisposed = true
        webSocket?.cancel()
        closeStreams()
        try {
            pipedInput.close()
        } catch (_: Exception) {}
    }
}
