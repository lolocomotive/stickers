package de.loicezt.stickers.video

import java.nio.ByteBuffer

class LibWebP {

    private external fun nativeAddFrameYuv(
        yBuffer: ByteBuffer, yStride: Int,
        uBuffer: ByteBuffer, uStride: Int,
        vBuffer: ByteBuffer, vStride: Int,
        timestampMs: Int
    )

    /**
     * Initializes the WebP encoder with output settings.
     * @param path The full path to the output .webp file.
     * @param width The width of the frames.
     * @param height The height of the frames.
     * @return True if initialization was successful.
     */
    private external fun nativeInitEncoder(width: Int, height: Int): Boolean

    /**
     * Adds a single RGBA frame to the WebP animation.
     * @param frameBuffer A direct ByteBuffer containing the RGBA pixel data.
     * @param timestampMs The timestamp for this frame in milliseconds.
     */
    private external fun nativeAddFrame(frameBuffer: ByteBuffer, timestampMs: Int)

    /**
     * Finalizes the WebP file, writes it to disk, and cleans up resources.
     * @return The path to the output file if successful, otherwise null.
     */
    private external fun nativeReleaseEncoder(): ByteArray?
}