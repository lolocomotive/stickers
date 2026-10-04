package de.loicezt.stickers.video

import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaFormat
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.File

/** Small preview frames and exact source-frame navigation for the trim screen. */
object VideoTimeline {
    fun thumbnails(file: File, count: Int): List<ByteArray?> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val durationUs = (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L) * 1000L
            return (0 until count).map { index ->
                // Sample the middle of each segment, including the final segment.
                val timeUs = if (durationUs > 0) durationUs * (2L * index + 1) / (2L * count) else 0L
                val frame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST, 96, 72)
                } else {
                    retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                }
                frame?.let {
                    val scaled = if (it.width > 96 || it.height > 72) {
                        Bitmap.createScaledBitmap(it, 96, 72, true).also { bitmap -> it.recycle() }
                    } else it
                    try {
                        ByteArrayOutputStream().use { output ->
                            scaled.compress(Bitmap.CompressFormat.JPEG, 72, output)
                            output.toByteArray()
                        }
                    } finally {
                        scaled.recycle()
                    }
                }
            }
        } finally {
            retriever.release()
        }
    }

    fun adjacentFrameTimeUs(file: File, positionUs: Long, direction: Int): Long {
        require(direction == -1 || direction == 1)
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            val track = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: return positionUs
            extractor.selectTrack(track)
            // Seeking to the preceding sync frame keeps each tap local to the current GOP.
            extractor.seekTo((positionUs - 1).coerceAtLeast(0), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            var previous = 0L
            while (true) {
                val timeUs = extractor.sampleTime
                if (timeUs < 0) return if (direction < 0) previous else positionUs
                if (timeUs < positionUs - 1) previous = timeUs
                if (timeUs > positionUs + 1) return if (direction < 0) previous else timeUs
                if (!extractor.advance()) return if (direction < 0) previous else positionUs
            }
        } finally {
            extractor.release()
        }
    }
}
