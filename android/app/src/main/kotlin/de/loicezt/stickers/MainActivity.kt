package de.loicezt.stickers

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Build
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import de.loicezt.stickers.video.CropAndScale
import de.loicezt.stickers.video.OverlayAndEncode
import de.loicezt.stickers.video.VideoThumbnails
import de.loicezt.stickers.video.WebPConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL_NAME = "de.loicezt.stickers/methods"
    private val TRIM_CHANNEL_NAME = "de.loicezt.stickers/progress_trim"
    private val ECODE_CHANNEL_NAME = "de.loicezt.stickers/progress_encode"
    private val THUMBNAILS_CHANNEL_NAME = "de.loicezt.stickers/thumbnails"

    private lateinit var cropAndScale: CropAndScale
    private lateinit var overlayAndEncode: OverlayAndEncode
    private val scope = CoroutineScope(
        Dispatchers.Main + SupervisorJob()
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        handleViewIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        handleViewIntent(intent)
        setIntent(intent)
        super.onNewIntent(intent)
    }

    private fun handleViewIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return

        val uris = ArrayList<Uri>()
        intent.data?.let { uris.add(it) }
        intent.clipData?.let { clipData ->
            for (i in 0 until clipData.itemCount) {
                val itemUri = clipData.getItemAt(i).uri
                if (itemUri != null && !uris.contains(itemUri)) {
                    uris.add(itemUri)
                }
            }
        }

        if (uris.isEmpty()) return

        if (uris.size == 1) {
            intent.action = Intent.ACTION_SEND
            intent.putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            intent.action = Intent.ACTION_SEND_MULTIPLE
            intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        cropAndScale = CropAndScale()
        overlayAndEncode = OverlayAndEncode()

        // 1. Setup the MethodChannel to receive commands from Flutter
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTrim" -> {
                    val args = call.arguments as Map<*, *>
                    val inputFile = File(args["inputFile"] as String)
                    val outputFile = File(args["outputFile"] as String)
                    val startTimeUs = (args["startTimeUs"] as String).toLong()
                    val endTimeUs = (args["endTimeUs"] as String).toLong()
                    val speed = (args["speed"] as? Number)?.toDouble() ?: 1.0
                    val cropLeft = (args["cropLeft"] as? Number)?.toFloat() ?: 0f
                    val cropTop = (args["cropTop"] as? Number)?.toFloat() ?: 0f
                    val cropRight = (args["cropRight"] as? Number)?.toFloat() ?: 1f
                    val cropBottom = (args["cropBottom"] as? Number)?.toFloat() ?: 1f
                    val rotation = (args["rotation"] as? Number)?.toInt() ?: 0
                    val stretch = (args["stretch"] as? Boolean) ?: false
                    cropAndScale.start(
                        inputFile,
                        outputFile,
                        startTimeUs,
                        endTimeUs,
                        24,
                        speed,
                        cropLeft,
                        cropTop,
                        cropRight,
                        cropBottom,
                        rotation,
                        stretch
                    )
                    result.success(null)
                }

                "startOverlay" -> {
                    val args = call.arguments as? Map<*, *>;
                    if (args == null) {
                        result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val videoFile = File(args["videoFile"]!! as String)
                        val overlayFile = File(args["overlayFile"]!! as String)
                        val outputFile = File(args["outputFile"]!! as String)
                        overlayAndEncode.start(
                            videoFile,
                            overlayFile,
                            outputFile,
                            WebPConfig.fromMap(args["config"]!! as Map<*, *>),
                            args["fps"]!! as Int
                        )
                        result.success(null)
                    } catch (e: NullPointerException) {
                        result.error(
                            "MISSING_ARGUMENT",
                            "Missing a required file path argument.",
                            null
                        )
                    }
                }

                "cancelOverlay" -> {
                    overlayAndEncode.cancel()
                    result.success(null)
                }

                "cancelTrim" -> {
                    cropAndScale.cancel()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // Streams {index, bytes} thumbnails for the video given in the listen arguments
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            THUMBNAILS_CHANNEL_NAME
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var job: Job? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    val args = arguments as Map<*, *>
                    val path = args["path"] as String
                    val count = (args["count"] as Number).toInt()
                    val shortSide = (args["shortSide"] as Number).toInt()
                    job?.cancel()
                    job = scope.launch {
                        try {
                            withContext(Dispatchers.IO) {
                                VideoThumbnails.extract(path, count, shortSide) { index, bytes ->
                                    withContext(Dispatchers.Main) {
                                        events.success(mapOf("index" to index, "bytes" to bytes))
                                    }
                                }
                            }
                            events.endOfStream()
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            events.error("THUMBNAIL_FAILED", e.message, null)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    job?.cancel()
                    job = null
                }
            }
        )

        // 2. Setup the EventChannel to stream updates to Flutter
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TRIM_CHANNEL_NAME
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var eventScope: CoroutineScope? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return
                    // Combine both state and progress flows into a single stream
                    eventScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
                    eventScope?.launch {
                        cropAndScale.status.combine(cropAndScale.progress) { status, progress ->
                            mapOf(
                                "status" to status.name,
                                "progress" to progress.progress,
                                "currentFrame" to progress.currentFrame,
                                "totalFrames" to progress.totalFrames
                            )
                        }.collect { update ->
                            events.success(update)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventScope?.cancel()
                    eventScope = null
                }
            }
        )
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ECODE_CHANNEL_NAME
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var eventScope: CoroutineScope? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return

                    eventScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
                    eventScope?.launch {
                        overlayAndEncode.status.combine(overlayAndEncode.progress) { status, progress ->
                            mapOf(
                                "status" to status.name,
                                "progress" to progress.progress,
                                "currentFrame" to progress.currentFrame,
                                "totalFrames" to progress.totalFrames
                            )
                        }.collect { update ->
                            events.success(update)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventScope?.cancel()
                    eventScope = null
                }
            }
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        cropAndScale.release()
        scope.cancel()
    }
}

