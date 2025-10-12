package de.loicezt.stickers.video

/**
 * Data class to hold all progress information.
 * @param progress A float between 0.0 and 1.0 representing the overall progress.
 * @param currentFrame The number of frames processed so far.
 * @param totalFrames The estimated total number of frames in the source video.
 */
data class ProgressState(
    val progress: Float = 0f, val currentFrame: Int = 0, val totalFrames: Int = 0
)