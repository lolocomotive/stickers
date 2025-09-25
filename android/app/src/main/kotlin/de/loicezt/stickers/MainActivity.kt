package de.loicezt.stickers

import androidx.annotation.NonNull
import de.loicezt.stickers.video.CropAndScale
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

class MainActivity: FlutterActivity(){
    private val METHOD_CHANNEL_NAME = "de.loicezt.stickers/methods"
    private val EVENT_CHANNEL_NAME = "de.loicezt.stickers/events"

    private lateinit var cropAndScale: CropAndScale
    private val scope = CoroutineScope(
        Dispatchers.Main + SupervisorJob())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        cropAndScale = CropAndScale()

        // 1. Setup the MethodChannel to receive commands from Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL_NAME).setMethodCallHandler {
                call, result ->
            when (call.method) {
                "start" -> {
                    val args = call.arguments as Map<String, String>
                    val inputFile = File(args["inputFile"]!!)
                    val outputFile = File(args["outputFile"]!!)
                    cropAndScale.start(inputFile, outputFile)
                    result.success(null)
                }
                "cancel" -> {
                    cropAndScale.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 2. Setup the EventChannel to stream updates to Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var eventScope: CoroutineScope? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (events == null) return

                    // Combine both state and progress flows into a single stream
                    eventScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
                    eventScope?.launch {
                        cropAndScale.status.combine(cropAndScale.progress) { status, progress ->
                            // Create a map to send to Flutter
                            mapOf(
                                "status" to status.name,
                                "progress" to progress.progress,
                                "currentFrame" to progress.currentFrame,
                                "totalFrames" to progress.totalFrames
                            )
                        }.collect { update ->
                            // Send the map to Flutter
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

