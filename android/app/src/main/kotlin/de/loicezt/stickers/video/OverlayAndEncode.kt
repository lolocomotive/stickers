package de.loicezt.stickers.video

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.Rect
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import androidx.core.graphics.createBitmap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.TimeoutException
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import pl.droidsonroids.gif.GifDrawable


class OverlayAndEncode {

    enum class State {
        IDLE, RUNNING, SUCCESS, FAILED, CANCELLED
    }

    private val _status = MutableStateFlow(State.IDLE)
    val status = _status.asStateFlow()

    private val _progress = MutableStateFlow(ProgressState())
    val progress = _progress.asStateFlow()

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var encodeJob: Job? = null

    companion object {
        private const val LOG_TAG = "OverlayAndEncode"
        private const val OUTPUT_DIMENSION = 512
        private const val MAX_ANIMATED_DURATION_MS = 10_000
    }

    /**
     * Starts the video overlay and WebP encoding process.
     * @param videoFile The source video file.
     * @param overlayFile The static WebP image to overlay.
     * @param outputFile The destination file for the animated WebP.
     * @param config Configuration for the WebP encoder.
     * @param maxFps The maximum frames per second for the output. If null, uses original FPS.
     */
    // MODIFIED: Added maxFps parameter
    fun start(
        videoFile: File,
        overlayFile: File,
        outputFile: File,
        config: WebPConfig,
        maxFps: Int
    ) {
        if (_status.value == State.RUNNING) {
            Log.w(LOG_TAG, "Encoding is already in progress. Ignoring new request.")
            return
        }

        encodeJob = scope.launch {
            _status.value = State.RUNNING
            _progress.value = ProgressState()
            try {
                // MODIFIED: Pass maxFps to the encoding function
                val webpData = doOverlayAndEncode(videoFile, overlayFile, config, maxFps)
                if (webpData != null) {
                    outputFile.writeBytes(webpData)
                    _status.value = State.SUCCESS
                    Log.d(LOG_TAG, "Encoding finished successfully.")
                } else {
                    throw IllegalStateException("Encoding produced no data.")
                }
            } catch (e: CancellationException) {
                _status.value = State.CANCELLED
                Log.d(LOG_TAG, "Encoding was cancelled.")
            } catch (e: Exception) {
                _status.value = State.FAILED
                Log.e(LOG_TAG, "Encoding failed with an exception.", e)
            } finally {
                val finalState = _progress.value
                _progress.value =
                    finalState.copy(progress = 1f, currentFrame = finalState.totalFrames)
            }
        }
    }

    fun startGif(
        gifFile: File,
        overlayFile: File,
        outputFile: File,
        startMs: Int,
        endMs: Int,
        config: WebPConfig,
        maxFps: Int
    ) {
        if (_status.value == State.RUNNING) {
            Log.w(LOG_TAG, "Encoding is already in progress. Ignoring new request.")
            return
        }

        encodeJob = scope.launch {
            _status.value = State.RUNNING
            _progress.value = ProgressState()
            try {
                val webpData = doGifOverlayAndEncode(gifFile, overlayFile, startMs, endMs, config, maxFps)
                if (webpData != null) {
                    outputFile.writeBytes(webpData)
                    _status.value = State.SUCCESS
                    Log.d(LOG_TAG, "GIF encoding finished successfully.")
                } else {
                    throw IllegalStateException("GIF encoding produced no data.")
                }
            } catch (e: CancellationException) {
                _status.value = State.CANCELLED
                Log.d(LOG_TAG, "GIF encoding was cancelled.")
            } catch (e: Exception) {
                _status.value = State.FAILED
                Log.e(LOG_TAG, "GIF encoding failed with an exception.", e)
            } finally {
                val finalState = _progress.value
                _progress.value =
                    finalState.copy(progress = 1f, currentFrame = finalState.totalFrames)
            }
        }
    }

    fun cancel() {
        encodeJob?.cancel()
    }

    fun release() {
        scope.cancel()
    }

    private suspend fun doOverlayAndEncode(
        videoFile: File,
        overlayFile: File,
        config: WebPConfig,
        maxFps: Int
    ): ByteArray? {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        val glProcessor = OverlayGL()
        val webpEncoder = LibWebP()
        var webpData: ByteArray? = null
        var overlayBitmap: Bitmap? = null

        return withContext(Dispatchers.IO) {
            try {
                // 1. Extractor Setup
                extractor.setDataSource(videoFile.absolutePath)
                val videoTrackIndex = (0 until extractor.trackCount).indexOfFirst {
                    extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                        ?.startsWith("video/") == true
                }
                if (videoTrackIndex == -1) throw IllegalStateException("No video track found")

                val inputFormat = extractor.getTrackFormat(videoTrackIndex)
                extractor.selectTrack(videoTrackIndex)

                val videoWidth = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
                val videoHeight = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
                val durationUs = inputFormat.getLong(MediaFormat.KEY_DURATION)

                val originalFrameRate = if (inputFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                    inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
                } else {
                    30
                }
                val targetFrameRate = min(max(1, maxFps), max(1, originalFrameRate))
                val totalFrames = ((durationUs / 1_000_000.0) * targetFrameRate).toInt()
                _progress.value = ProgressState(totalFrames = totalFrames)

                val overlay = decodeWebPBitmap(overlayFile, webpEncoder)
                overlayBitmap = overlay

                glProcessor.setup(OUTPUT_DIMENSION, OUTPUT_DIMENSION, videoWidth, videoHeight)
                webpEncoder.nativeInitEncoder(OUTPUT_DIMENSION, OUTPUT_DIMENSION, config)

                decoder = MediaCodec.createDecoderByType(inputFormat.getString(MediaFormat.KEY_MIME)!!)
                decoder.configure(inputFormat, glProcessor.decoderInputSurface, null, 0)
                decoder.start()

                val decoderBufferInfo = MediaCodec.BufferInfo()
                var isInputDone = false
                var isDecoderOutputDone = false
                var currentFrame = 0
                val pixelBufferForReadback =
                    ByteBuffer.allocateDirect(OUTPUT_DIMENSION * OUTPUT_DIMENSION * 4)

                var lastProcessedTimestampUs = -1L
                val frameIntervalUs = 1_000_000L / targetFrameRate

                while (!isDecoderOutputDone && currentCoroutineContext().isActive) {
                    if (!isInputDone) {
                        val inputBufferIndex = decoder.dequeueInputBuffer(10000L)
                        if (inputBufferIndex >= 0) {
                            val sampleSize =
                                extractor.readSampleData(decoder.getInputBuffer(inputBufferIndex)!!, 0)
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(
                                    inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                isInputDone = true
                            } else {
                                decoder.queueInputBuffer(
                                    inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0
                                )
                                extractor.advance()
                            }
                        }
                    }

                    val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, 10000L)
                    if (outputBufferIndex >= 0) {
                        if (decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            isDecoderOutputDone = true
                        }

                        var processThisFrame = decoderBufferInfo.size > 0
                        if (processThisFrame) {
                            val currentTimestampUs = decoderBufferInfo.presentationTimeUs
                            if (lastProcessedTimestampUs != -1L && currentTimestampUs - lastProcessedTimestampUs < frameIntervalUs) {
                                processThisFrame = false // Drop frame
                            } else {
                                lastProcessedTimestampUs = currentTimestampUs
                            }
                        }

                        decoder.releaseOutputBuffer(outputBufferIndex, processThisFrame)

                        if (processThisFrame) {
                            try {
                                glProcessor.awaitNewFrame()
                                glProcessor.drawFrame(overlay)
                                glProcessor.readPixels(pixelBufferForReadback)

                                val timestampMs =
                                    (decoderBufferInfo.presentationTimeUs / 1000).toInt()
                                webpEncoder.nativeAddFrame(pixelBufferForReadback, timestampMs)

                                currentFrame++
                                val progressPercentage =
                                    decoderBufferInfo.presentationTimeUs.toFloat() / durationUs.toFloat()
                                _progress.value =
                                    ProgressState(progressPercentage, currentFrame, totalFrames)

                            } catch (e: TimeoutException) {
                                Log.w(LOG_TAG, "Timeout waiting for frame.")
                            }
                        }
                    }
                }
                webpData = webpEncoder.nativeReleaseEncoder((durationUs / 1000).toInt())
            } finally {
                extractor.release()
                decoder?.stop(); decoder?.release()
                glProcessor.release()
                overlayBitmap?.recycle()
            }
            webpData
        }
    }

    private suspend fun doGifOverlayAndEncode(
        gifFile: File,
        overlayFile: File,
        startMs: Int,
        endMs: Int,
        config: WebPConfig,
        maxFps: Int
    ): ByteArray? {
        val webpEncoder = LibWebP()
        var gifDrawable: GifDrawable? = null
        var overlayBitmap: Bitmap? = null
        var frameBitmap: Bitmap? = null

        return withContext(Dispatchers.IO) {
            try {
                val gif = GifDrawable(gifFile)
                gifDrawable = gif
                gif.stop()
                val gifDurationMs = gif.duration
                if (gifDurationMs <= 0) throw IllegalStateException("GIF has no duration.")

                val effectiveStartMs = startMs.coerceIn(0, gifDurationMs)
                if (effectiveStartMs >= gifDurationMs) {
                    throw IllegalArgumentException("Start time must be before the end of the GIF.")
                }
                val effectiveEndMs = endMs.coerceIn(effectiveStartMs + 1, gifDurationMs)
                val trimmedDurationMs = min(effectiveEndMs - effectiveStartMs, MAX_ANIMATED_DURATION_MS)
                if (trimmedDurationMs <= 0) throw IllegalArgumentException("End time must be after start time.")

                val overlay = decodeWebPBitmap(overlayFile, webpEncoder)
                overlayBitmap = overlay
                val frameCanvasBitmap = createBitmap(OUTPUT_DIMENSION, OUTPUT_DIMENSION)
                frameBitmap = frameCanvasBitmap
                val canvas = Canvas(frameCanvasBitmap)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
                val gifBounds = aspectFitBounds(
                    gif.intrinsicWidth,
                    gif.intrinsicHeight,
                    OUTPUT_DIMENSION,
                    OUTPUT_DIMENSION
                )

                val originalFrameRate = max(1, ceil(gif.numberOfFrames * 1000.0 / gifDurationMs).toInt())
                val targetFrameRate = min(max(1, maxFps), originalFrameRate)
                val frameIntervalMs = max(1, 1000 / targetFrameRate)
                val totalFrames = max(1, ceil(trimmedDurationMs / frameIntervalMs.toDouble()).toInt())
                _progress.value = ProgressState(totalFrames = totalFrames)

                if (!webpEncoder.nativeInitEncoder(OUTPUT_DIMENSION, OUTPUT_DIMENSION, config)) {
                    throw IllegalStateException("Failed to initialize WebP encoder.")
                }

                val pixelBuffer = ByteBuffer.allocateDirect(OUTPUT_DIMENSION * OUTPUT_DIMENSION * 4)
                for (frame in 0 until totalFrames) {
                    if (!currentCoroutineContext().isActive) break
                    val outputTimestampMs = min(frame * frameIntervalMs, trimmedDurationMs - 1)
                    val sourceTimestampMs = min(effectiveStartMs + outputTimestampMs, max(0, gifDurationMs - 1))

                    canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                    val gifFrame = gif.seekToPositionAndGet(sourceTimestampMs)
                    canvas.drawBitmap(gifFrame, null, gifBounds, paint)
                    canvas.drawBitmap(overlay, null, Rect(0, 0, OUTPUT_DIMENSION, OUTPUT_DIMENSION), paint)

                    pixelBuffer.rewind()
                    frameCanvasBitmap.copyPixelsToBuffer(pixelBuffer)
                    pixelBuffer.rewind()
                    webpEncoder.nativeAddFrame(pixelBuffer, outputTimestampMs)

                    _progress.value = ProgressState(
                        outputTimestampMs.toFloat() / trimmedDurationMs.toFloat(),
                        frame + 1,
                        totalFrames
                    )
                }

                webpEncoder.nativeReleaseEncoder(trimmedDurationMs)
            } finally {
                overlayBitmap?.recycle()
                frameBitmap?.recycle()
                gifDrawable?.recycle()
            }
        }
    }

    private fun decodeWebPBitmap(file: File, webpEncoder: LibWebP): Bitmap {
        val webpBytes = file.readBytes()
        val webpInfo = webpEncoder.nativeGetInfo(webpBytes)
            ?: throw IllegalStateException("Could not read WebP overlay info.")
        val bitmap = createBitmap(webpInfo[0], webpInfo[1])
        val pixelBuffer = ByteBuffer.allocateDirect(webpInfo[0] * webpInfo[1] * 4)
        if (!webpEncoder.nativeDecode(webpBytes, pixelBuffer, webpInfo[0] * 4)) {
            throw IllegalStateException("Failed to decode WebP overlay image.")
        }
        pixelBuffer.rewind()
        bitmap.copyPixelsFromBuffer(pixelBuffer)
        return bitmap
    }

    private fun aspectFitBounds(inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int): Rect {
        if (inputWidth <= 0 || inputHeight <= 0) {
            return Rect(0, 0, outputWidth, outputHeight)
        }
        val inputAspect = inputWidth.toFloat() / inputHeight.toFloat()
        val outputAspect = outputWidth.toFloat() / outputHeight.toFloat()
        val width: Int
        val height: Int
        if (inputAspect > outputAspect) {
            width = outputWidth
            height = (outputWidth / inputAspect).toInt()
        } else {
            height = outputHeight
            width = (outputHeight * inputAspect).toInt()
        }
        val left = (outputWidth - width) / 2
        val top = (outputHeight - height) / 2
        return Rect(left, top, left + width, top + height)
    }
}
