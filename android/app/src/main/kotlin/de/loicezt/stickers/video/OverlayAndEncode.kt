package de.loicezt.stickers.video

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
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
import kotlin.math.min


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
                val targetFrameRate = maxFps.let { min(it, originalFrameRate) } ?: originalFrameRate
                val totalFrames = ((durationUs / 1_000_000.0) * targetFrameRate).toInt()
                _progress.value = ProgressState(totalFrames = totalFrames)

                val webpBytes = overlayFile.readBytes()
                val webpInfo = webpEncoder.nativeGetInfo(webpBytes)
                    ?: throw IllegalStateException("Could not read WebP overlay info.")
                val overlayWidth = webpInfo[0]
                val overlayHeight = webpInfo[1]

                overlayBitmap = createBitmap(overlayWidth, overlayHeight)
                val pixelBufferForOverlay = ByteBuffer.allocateDirect(overlayWidth * overlayHeight * 4)
                if (!webpEncoder.nativeDecode(webpBytes, pixelBufferForOverlay, overlayWidth * 4)) {
                    throw IllegalStateException("Failed to decode WebP overlay image.")
                }
                pixelBufferForOverlay.rewind()
                overlayBitmap.copyPixelsFromBuffer(pixelBufferForOverlay)

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
                                glProcessor.drawFrame(overlayBitmap)
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
                webpData = webpEncoder.nativeReleaseEncoder()
            } finally {
                extractor.release()
                decoder?.stop(); decoder?.release()
                glProcessor.release()
                overlayBitmap?.recycle()
            }
            webpData
        }
    }
}