package de.loicezt.stickers

import android.os.Build
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import de.loicezt.stickers.video.CropAndScale
import de.loicezt.stickers.video.OverlayAndEncode
import de.loicezt.stickers.video.WebPConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.io.File

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL_NAME = "de.loicezt.stickers/methods"
    private val TRIM_CHANNEL_NAME = "de.loicezt.stickers/progress_trim"
    private val ECODE_CHANNEL_NAME = "de.loicezt.stickers/progress_encode"

    private lateinit var cropAndScale: CropAndScale
    private lateinit var overlayAndEncode: OverlayAndEncode
    private val scope = CoroutineScope(
        Dispatchers.Main + SupervisorJob()
    )

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
                    val args = call.arguments as Map<String, String>
                    val inputFile = File(args["inputFile"]!!)
                    val outputFile = File(args["outputFile"]!!)
                    val startTimeUs = args["startTimeUs"]!!.toLong()
                    val endTimeUs = args["endTimeUs"]!!.toLong()
                    cropAndScale.start(inputFile, outputFile, startTimeUs, endTimeUs, 24)
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

