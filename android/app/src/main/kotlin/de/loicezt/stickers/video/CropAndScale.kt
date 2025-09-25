package de.loicezt.stickers.video

import android.media.*
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeoutException

/**
 * Data class to hold all progress information.
 * @param progress A float between 0.0 and 1.0 representing the overall progress.
 * @param currentFrame The number of frames processed so far.
 * @param totalFrames The estimated total number of frames in the source video.
 */
data class ProgressState(
    val progress: Float = 0f,
    val currentFrame: Int = 0,
    val totalFrames: Int = 0
)

class CropAndScale {

    /**
     * Represents the current state of the transcoder.
     */
    enum class State {
        IDLE,       // Not doing anything.
        RUNNING,    // Transcoding is in progress.
        SUCCESS,    // Transcoding finished successfully.
        FAILED,     // Transcoding failed with an error.
        CANCELLED   // Transcoding was cancelled by the user.
    }

    private val _status = MutableStateFlow(State.IDLE)
    val status = _status.asStateFlow()

    private val _progress = MutableStateFlow(ProgressState())
    val progress = _progress.asStateFlow()

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var transcodeJob: Job? = null

    companion object {
        private const val LOG_TAG = "CropAndScale"
        private const val TARGET_LONGEST_SIDE = 512
    }

    /**
     * Starts the video transcoding process.
     * This function is non-blocking. Observe the `status` and `progress` flows for updates.
     * @param inputFile The source video file.
     * @param outputFile The destination for the transcoded MP4 file.
     */
    fun start(inputFile: File, outputFile: File) {
        if (_status.value == State.RUNNING) {
            Log.w(LOG_TAG, "Transcoding is already in progress. Ignoring new request.")
            return
        }

        transcodeJob = scope.launch {
            _status.value = State.RUNNING
            _progress.value = ProgressState() // Reset progress
            try {
                doTranscode(inputFile, outputFile)
                _status.value = State.SUCCESS
                Log.d(LOG_TAG, "Transcoding finished successfully.")
            } catch (e: CancellationException) {
                _status.value = State.CANCELLED
                Log.d(LOG_TAG, "Transcoding was cancelled.")
            } catch (e: Exception) {
                _status.value = State.FAILED
                Log.e(LOG_TAG, "Transcoding failed with an exception.", e)
            } finally {
                // On completion, failure, or cancellation, set progress to 100%
                val finalState = _progress.value
                _progress.value = finalState.copy(progress = 1f, currentFrame = finalState.totalFrames)
            }
        }
    }

    /**
     * Cancels the currently running transcoding job.
     */
    fun cancel() {
        transcodeJob?.cancel()
    }

    /**
     * Cleans up resources. Should be called when the transcoder is no longer needed.
     */
    fun release() {
        scope.cancel()
    }

    private suspend fun doTranscode(inputFile: File, outputFile: File) {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        val glProcessor = CropScaleGL()
        val transcoderExecutor = Executors.newSingleThreadExecutor()

        try {
            // 1. Extractor Setup
            extractor.setDataSource(inputFile.absolutePath)
            var videoTrackIndex = -1
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                if (format.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true) {
                    videoTrackIndex = i
                    break
                }
            }
            if (videoTrackIndex == -1) throw IllegalStateException("No video track found")
            val inputFormat = extractor.getTrackFormat(videoTrackIndex)
            val videoWidth = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
            val videoHeight = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val durationUs = inputFormat.getLong(MediaFormat.KEY_DURATION)
            extractor.selectTrack(videoTrackIndex)

            // --- NEW: Calculate total frames for progress ---
            val frameRate = if (inputFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            } else {
                30 // A reasonable fallback if frame rate is not in metadata
            }
            val totalFrames = ((durationUs / 1_000_000.0) * frameRate).toInt()
            _progress.value = ProgressState(totalFrames = totalFrames)
            // ---

            // Calculate output dimensions
            val outputWidth: Int
            val outputHeight: Int
            if (videoWidth > videoHeight) {
                outputWidth = TARGET_LONGEST_SIDE
                outputHeight = (TARGET_LONGEST_SIDE * (videoHeight.toFloat() / videoWidth.toFloat())).toInt()
            } else {
                outputHeight = TARGET_LONGEST_SIDE
                outputWidth = (TARGET_LONGEST_SIDE * (videoWidth.toFloat() / videoHeight.toFloat())).toInt()
            }
            val finalOutputWidth = if (outputWidth % 2 == 1) outputWidth - 1 else outputWidth
            val finalOutputHeight = if (outputHeight % 2 == 1) outputHeight - 1 else outputHeight

            // 2. Muxer and Encoder Setup
            muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outputFormat = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC, finalOutputWidth, finalOutputHeight
            ).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, 6_000_000)
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }
            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            encoder.configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val encoderInputSurface = encoder.createInputSurface()
            encoder.start()

            // 3. Decoder and GL Setup
            glProcessor.setup(encoderInputSurface, finalOutputWidth, finalOutputHeight)
            decoder = MediaCodec.createDecoderByType(inputFormat.getString(MediaFormat.KEY_MIME)!!)
            decoder.configure(inputFormat, glProcessor.decoderInputSurface, null, 0)
            decoder.start()

            // 4. Start Encoder Consumer
            var videoTrackMuxerIndex = -1
            var isMuxerStarted = false
            val encoderDone = Job()
            scope.launch(transcoderExecutor.asCoroutineDispatcher()) {
                val bufferInfo = MediaCodec.BufferInfo()
                while (isActive) {
                    val bufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 10000L)
                    if (bufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        videoTrackMuxerIndex = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        isMuxerStarted = true
                    } else if (bufferIndex >= 0) {
                        if (!isMuxerStarted) throw IllegalStateException("Muxer not started")
                        val encodedData = encoder.getOutputBuffer(bufferIndex)!!
                        muxer.writeSampleData(videoTrackMuxerIndex, encodedData, bufferInfo)
                        encoder.releaseOutputBuffer(bufferIndex, false)
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
                encoderDone.complete()
            }

            // 5. Start Decoder-Renderer Producer
            val decoderBufferInfo = MediaCodec.BufferInfo()
            var isInputDone = false
            var isDecoderOutputDone = false
            var currentFrame = 0
            while (!isDecoderOutputDone && currentCoroutineContext().isActive) {
                if (!isInputDone) {
                    val inputBufferIndex = decoder.dequeueInputBuffer(10000L)
                    if (inputBufferIndex >= 0) {
                        val sampleSize = extractor.readSampleData(decoder.getInputBuffer(inputBufferIndex)!!, 0)
                        if (sampleSize < 0) {
                            decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            isInputDone = true
                        } else {
                            decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outputBufferIndex = decoder.dequeueOutputBuffer(decoderBufferInfo, 10000L)
                if (outputBufferIndex >= 0) {
                    if (decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        encoder.signalEndOfInputStream()
                        isDecoderOutputDone = true
                    }
                    val doRender = decoderBufferInfo.size > 0
                    decoder.releaseOutputBuffer(outputBufferIndex, doRender)
                    if (doRender) {
                        try {
                            glProcessor.awaitNewFrame()
                            val timestampNs = decoderBufferInfo.presentationTimeUs * 1000
                            glProcessor.drawFrame(timestampNs)

                            // Update progress with frame count
                            currentFrame++
                            val progressPercentage = decoderBufferInfo.presentationTimeUs.toFloat() / durationUs.toFloat()
                            _progress.value = ProgressState(progressPercentage, currentFrame, totalFrames)

                        } catch (e: TimeoutException) {
                            Log.w(LOG_TAG, "Timeout waiting for frame.")
                        }
                    }
                }
            }
            encoderDone.join()
        } finally {
            extractor.release()
            decoder?.stop(); decoder?.release()
            encoder?.stop(); encoder?.release()
            muxer?.stop(); muxer?.release()
            glProcessor.release()
            transcoderExecutor.shutdown()
        }
    }
}

