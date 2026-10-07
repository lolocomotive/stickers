package de.loicezt.stickers.video

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

object VideoThumbnails {
    /** Above this duration, frames are taken at the nearest keyframe, which is much faster. */
    private const val EXACT_FRAME_MAX_DURATION_US = 10_000_000L

    /**
     * Extracts [count] evenly spaced frames from the video at [path], each scaled down so its
     * shorter side is [shortSide] pixels and JPEG-encoded, passing each one to [onFrame] with its
     * index as soon as it's ready. Frames that can't be decoded are skipped.
     */
    suspend fun extract(
        path: String,
        count: Int,
        shortSide: Int,
        onFrame: suspend (index: Int, bytes: ByteArray) -> Unit
    ) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val durationUs = (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L) * 1000
            val target = targetSize(retriever, shortSide)
            val option = if (durationUs > EXACT_FRAME_MAX_DURATION_US) {
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            } else {
                MediaMetadataRetriever.OPTION_CLOSEST
            }
            for (i in 0 until count) {
                // Sample the middle of each slot so the thumbnail represents its segment
                val timeUs = durationUs * (2 * i + 1) / (2 * count)
                val bitmap = frameAt(retriever, timeUs, option, target?.first, target?.second, shortSide) ?: continue
                val out = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
                bitmap.recycle()
                onFrame(i, out.toByteArray())
            }
        } finally {
            retriever.release()
        }
    }

    /** Frame size with the shorter side scaled to [shortSide], or null if the metadata is missing. */
    private fun targetSize(retriever: MediaMetadataRetriever, shortSide: Int): Pair<Int, Int>? {
        var width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            ?.toIntOrNull() ?: return null
        var height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            ?.toIntOrNull() ?: return null
        val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            ?.toIntOrNull() ?: 0
        // Retrieved frames have the rotation applied
        if (rotation % 180 != 0) {
            width = height.also { height = width }
        }
        if (width <= 0 || height <= 0) return null
        val scale = min(1f, shortSide.toFloat() / min(width, height))
        return Pair(max(1, (width * scale).roundToInt()), max(1, (height * scale).roundToInt()))
    }

    private fun frameAt(
        retriever: MediaMetadataRetriever,
        timeUs: Long,
        option: Int,
        dstWidth: Int?,
        dstHeight: Int?,
        shortSide: Int
    ): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 && dstWidth != null && dstHeight != null) {
            return retriever.getScaledFrameAtTime(timeUs, option, dstWidth, dstHeight)
        }
        val full = retriever.getFrameAtTime(timeUs, option) ?: return null
        val scale = shortSide.toFloat() / min(full.width, full.height)
        if (scale >= 1f) return full
        val scaled = Bitmap.createScaledBitmap(
            full,
            max(1, (full.width * scale).roundToInt()),
            max(1, (full.height * scale).roundToInt()),
            true
        )
        full.recycle()
        return scaled
    }
}
