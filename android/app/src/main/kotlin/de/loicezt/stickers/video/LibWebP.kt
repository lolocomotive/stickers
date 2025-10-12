package de.loicezt.stickers.video

import androidx.annotation.Keep
import java.nio.ByteBuffer

@Keep
enum class WebPImageHint {
    DEFAULT,
    PICTURE,
    PHOTO,
    GRAPH,
    LAST
}

@Keep
data class WebPConfig(
    val lossless: Boolean?,
    val quality: Float?,
    val method: Int?,
    val imageHint: WebPImageHint?,
    val targetSize: Int?,
    val targetPSNR: Float?,
    val segments: Int?,
    val snsStrength: Int?,
    val filterStrength: Int?,
    val filterSharpness: Int?,
    val filterType: Int?,
    val autofilter: Int?,
    val alphaCompression: Int?,
    val alphaFiltering: Int?,
    val alphaQuality: Int?,
    val pass: Int?,
    val showCompressed: Int?,
    val preprocessing: Int?,
    val partitions: Int?,
    val partitionLimit: Int?,
    val emulateJpegSize: Int?,
    val threadLevel: Int?,
    val lowMemory: Int?,
    val nearLossless: Int?,
    val exact: Int?,
){
    companion object {
        fun fromMap(map: Map<*, *>): WebPConfig {
            fun boolToInt(value: Any?): Int? = (value as? Boolean)?.let { if (it) 1 else 0 }

            val imageHint = (map["imageHint"] as? String)?.let {
                when (it) {
                    "defaultHint" -> WebPImageHint.DEFAULT
                    "picture" -> WebPImageHint.PICTURE
                    "photo" -> WebPImageHint.PHOTO
                    "graph" -> WebPImageHint.GRAPH
                    else -> null
                }
            }

            return WebPConfig(
                lossless = map["lossless"] as? Boolean,
                quality = (map["quality"] as? Double)?.toFloat(),
                method = map["method"] as? Int,
                imageHint = imageHint,
                targetSize = map["targetSize"] as? Int,
                targetPSNR = (map["targetPSNR"] as? Double)?.toFloat(),
                segments = map["segments"] as? Int,
                snsStrength = map["snsStrength"] as? Int,
                filterStrength = map["filterStrength"] as? Int,
                filterSharpness = map["filterSharpness"] as? Int,
                filterType = map["filterType"] as? Int,
                autofilter = boolToInt(map["autofilter"]),
                alphaCompression = map["alphaCompression"] as? Int,
                alphaFiltering = map["alphaFiltering"] as? Int,
                alphaQuality = map["alphaQuality"] as? Int,
                pass = map["pass"] as? Int,
                showCompressed = boolToInt(map["showCompressed"]),
                preprocessing = map["preprocessing"] as? Int,
                partitions = map["partitions"] as? Int,
                partitionLimit = map["partitionLimit"] as? Int,
                emulateJpegSize = boolToInt(map["emulateJpegSize"]),
                threadLevel = boolToInt(map["threadLevel"]),
                lowMemory = boolToInt(map["lowMemory"]),
                nearLossless = map["nearLossless"] as? Int,
                exact = boolToInt(map["exact"])
            )
        }
    }
}

class LibWebP {
    /**
     * Retrieves the width and height of a WebP image.
     * @param data The raw byte array of the .webp file.
     * @return An IntArray containing [width, height], or null on failure.
     */
    external fun nativeGetInfo(data: ByteArray): IntArray?

    /**
     * Decodes a WebP image into a pre-allocated raw RGBA pixel buffer.
     * @param data The raw byte array of the .webp file.
     * @param outBuffer A direct ByteBuffer to write the RGBA pixel data into.
     * @param stride The number of bytes per row in the output buffer (width * 4).
     * @return True if decoding was successful.
     */
    external fun nativeDecode(data: ByteArray, outBuffer: ByteBuffer, stride: Int): Boolean


    external fun nativeAddFrameYuv(
        yBuffer: ByteBuffer,
        yStride: Int,
        uBuffer: ByteBuffer,
        uStride: Int,
        vBuffer: ByteBuffer,
        vStride: Int,
        timestampMs: Int
    )

    /**
     * Initializes the WebP encoder with output settings.
     * @param path The full path to the output .webp file.
     * @param width The width of the frames.
     * @param height The height of the frames.
     * @return True if initialization was successful.
     */
    external fun nativeInitEncoder(
        width: Int, height: Int, config: WebPConfig
    ): Boolean

    /**
     * Adds a single RGBA frame to the WebP animation.
     * @param frameBuffer A direct ByteBuffer containing the RGBA pixel data.
     * @param timestampMs The timestamp for this frame in milliseconds.
     */
    external fun nativeAddFrame(frameBuffer: ByteBuffer, timestampMs: Int)

    /**
     * Finalizes the WebP file, writes it to disk, and cleans up resources.
     * @return The path to the output file if successful, otherwise null.
     */
    external fun nativeReleaseEncoder(): ByteArray?

    companion object {
        init {
            System.loadLibrary("stickers")
        }
    }
}