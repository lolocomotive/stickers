#include <jni.h>
#include <string>
#include <android/log.h>

// libwebp headers
#include "src/webp/encode.h"
#include "src/webp/mux.h"
#include "src/webp/encode.h"
#include "src/webp/mux.h"
#include "src/webp/decode.h"

// Define a logging tag
#define LOG_TAG "NativeEncoder"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// This struct will hold our encoder's state
struct EncoderState {
    WebPAnimEncoder *anim_encoder = nullptr;
    WebPConfig config;
    int frame_width = 0;
    int frame_height = 0;
};

// Use a static pointer to hold the state across JNI calls.
// In a more complex app, you might pass a pointer back to Kotlin as a long.
static EncoderState *state = nullptr;


extern "C" {


/**
 * Reads a WebP file's raw byte data to get its width and height.
 */
JNIEXPORT jintArray JNICALL
Java_de_loicezt_stickers_video_LibWebP_nativeGetInfo(
        JNIEnv *env,
        jobject /* this */,
        jbyteArray data) {

    // Get a pointer to the raw byte data from the Java byte array
    jbyte *bytes = env->GetByteArrayElements(data, NULL);
    if (bytes == nullptr) {
        LOGE("nativeGetInfo: Could not get byte array elements.");
        return nullptr;
    }
    size_t size = env->GetArrayLength(data);

    int width = 0;
    int height = 0;

    // Use WebPGetInfo to parse the header without decoding the whole image
    if (!WebPGetInfo(reinterpret_cast<const uint8_t *>(bytes), size, &width, &height)) {
        env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);
        LOGE("nativeGetInfo: WebPGetInfo failed. Invalid WebP data.");
        return nullptr;
    }

    // Release the C-style array without copying back changes
    env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);

    // Create a new Java integer array to return the dimensions
    jintArray result = env->NewIntArray(2);
    if (result == nullptr) {
        LOGE("nativeGetInfo: Could not create new int array.");
        return nullptr;
    }

    jint info[2] = {width, height};
    env->SetIntArrayRegion(result, 0, 2, info);

    return result;
}

/**
 * Decodes WebP raw byte data into a pre-allocated direct ByteBuffer as RGBA.
 */
JNIEXPORT jboolean JNICALL
Java_de_loicezt_stickers_video_LibWebP_nativeDecode(
        JNIEnv *env,
        jobject /* this */,
        jbyteArray data,
        jobject out_buffer,
        jint stride) {

    // Get a pointer to the input WebP file data
    jbyte *in_bytes = env->GetByteArrayElements(data, NULL);
    if (in_bytes == nullptr) {
        LOGE("nativeDecode: Could not get byte array elements.");
        return JNI_FALSE;
    }
    size_t in_size = env->GetArrayLength(data);

    // Get a direct pointer to the output ByteBuffer's memory
    auto *out_pixels = static_cast<uint8_t *>(env->GetDirectBufferAddress(out_buffer));
    if (out_pixels == nullptr) {
        env->ReleaseByteArrayElements(data, in_bytes, JNI_ABORT);
        LOGE("nativeDecode: Could not get direct buffer address for output.");
        return JNI_FALSE;
    }
    size_t out_size = env->GetDirectBufferCapacity(out_buffer);

    // Decode the WebP data directly into the provided RGBA buffer
    uint8_t *decoded_data = WebPDecodeRGBAInto(
            reinterpret_cast<const uint8_t *>(in_bytes),
            in_size,
            out_pixels,
            out_size,
            stride);

    // Clean up the input array reference
    env->ReleaseByteArrayElements(data, in_bytes, JNI_ABORT);

    if (decoded_data == nullptr) {
        LOGE("nativeDecode: WebPDecodeRGBAInto failed.");
        return JNI_FALSE;
    }

    return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_de_loicezt_stickers_video_LibWebP_nativeInitEncoder(
        JNIEnv *env,
        jobject /* this */,
        jint width,
        jint height,
        jobject configJava) {

    if (state != nullptr) {
        LOGE("Encoder already initialized. Please release it first.");
        return JNI_FALSE;
    }

    state = new EncoderState();
    state->frame_width = width;
    state->frame_height = height;

    jclass configClass = env->GetObjectClass(configJava);

    if (!WebPConfigInit(&state->config)) {
        LOGE("Failed to initialize WebPConfig.");
        delete state;
        state = nullptr;
        return JNI_FALSE;
    }
    // --- Helper lambdas to reduce boilerplate for JNI calls ---

    // Helper to update an 'int' field in the C struct from a Java 'Integer'.
    auto updateInt = [&](const char *fieldName, int &targetField) {
        jfieldID fid = env->GetFieldID(configClass, fieldName, "Ljava/lang/Integer;");
        if (fid == nullptr) return; // Field not found, skip.
        jobject fieldObj = env->GetObjectField(configJava, fid);
        if (fieldObj != nullptr) {
            jclass intClass = env->FindClass("java/lang/Integer");
            jmethodID mid = env->GetMethodID(intClass, "intValue", "()I");
            targetField = env->CallIntMethod(fieldObj, mid);
            env->DeleteLocalRef(intClass);
            env->DeleteLocalRef(fieldObj);
        }
    };

    // Helper to update a 'float' field in the C struct from a Java 'Float'.
    auto updateFloat = [&](const char *fieldName, float &targetField) {
        jfieldID fid = env->GetFieldID(configClass, fieldName, "Ljava/lang/Float;");
        if (fid == nullptr) return;
        jobject fieldObj = env->GetObjectField(configJava, fid);
        if (fieldObj != nullptr) {
            jclass floatClass = env->FindClass("java/lang/Float");
            jmethodID mid = env->GetMethodID(floatClass, "floatValue", "()F");
            targetField = env->CallFloatMethod(fieldObj, mid);
            env->DeleteLocalRef(floatClass);
            env->DeleteLocalRef(fieldObj);
        }
    };

    // Helper to update an 'int' field in the C struct from a Java 'Boolean'.
    auto updateBoolean = [&](const char *fieldName, int &targetField) {
        jfieldID fid = env->GetFieldID(configClass, fieldName, "Ljava/lang/Boolean;");
        if (fid == nullptr) return;
        jobject fieldObj = env->GetObjectField(configJava, fid);
        if (fieldObj != nullptr) {
            jclass boolClass = env->FindClass("java/lang/Boolean");
            jmethodID mid = env->GetMethodID(boolClass, "booleanValue", "()Z");
            // Assigns 1 for true, 0 for false.
            targetField = env->CallBooleanMethod(fieldObj, mid);
            env->DeleteLocalRef(boolClass);
            env->DeleteLocalRef(fieldObj);
        }
    };

    // Helper to update an enum field in the C struct from a Java Enum.
    // ⚠️ IMPORTANT: Replace "Lcom/yourpackage/WebPImageHint;" with the correct path to your enum class.
    const char *webPImageHintSignature = "Lde/loicezt/stickers/video/WebPImageHint;";
    auto updateEnum = [&](const char *fieldName, WebPImageHint &targetField) {
        jfieldID fid = env->GetFieldID(configClass, fieldName, webPImageHintSignature);
        if (fid == nullptr) return;
        jobject fieldObj = env->GetObjectField(configJava, fid);
        if (fieldObj != nullptr) {
            jclass enumClass = env->GetObjectClass(fieldObj);
            jmethodID mid = env->GetMethodID(enumClass, "ordinal", "()I");
            // Get the enum's ordinal value and cast it to the C enum type.
            targetField = static_cast<WebPImageHint>(env->CallIntMethod(fieldObj, mid));
            env->DeleteLocalRef(enumClass);
            env->DeleteLocalRef(fieldObj);
        }
    };


    // --- Map and Update Each Field ---
    // The first argument is the Kotlin field name (camelCase).
    // The second argument is a reference to the C struct field (snake_case).

    updateBoolean("lossless", state->config.lossless);
    updateFloat("quality", state->config.quality);
    updateInt("method", state->config.method);
    updateEnum("imageHint", state->config.image_hint);
    updateInt("targetSize", state->config.target_size);
    updateFloat("targetPSNR", state->config.target_PSNR);
    updateInt("segments", state->config.segments);
    updateInt("snsStrength", state->config.sns_strength);
    updateInt("filterStrength", state->config.filter_strength);
    updateInt("filterSharpness", state->config.filter_sharpness);
    updateInt("filterType", state->config.filter_type);
    updateInt("autofilter", state->config.autofilter);
    updateInt("alphaCompression", state->config.alpha_compression);
    updateInt("alphaFiltering", state->config.alpha_filtering);
    updateInt("alphaQuality", state->config.alpha_quality);
    updateInt("pass", state->config.pass);
    updateInt("showCompressed", state->config.show_compressed);
    updateInt("preprocessing", state->config.preprocessing);
    updateInt("partitions", state->config.partitions);
    updateInt("partitionLimit", state->config.partition_limit);
    updateInt("emulateJpegSize", state->config.emulate_jpeg_size);
    updateInt("threadLevel", state->config.thread_level);
    updateInt("lowMemory", state->config.low_memory);
    updateInt("nearLossless", state->config.near_lossless);
    updateInt("exact", state->config.exact);

    // Clean up the local reference to the class object.
    env->DeleteLocalRef(configClass);

    if (!WebPValidateConfig(&state->config)) {
        LOGE("Invalid config");
        delete state;
        state = nullptr;
        return JNI_FALSE;
    }

    // 2. Setup the animation encoder
    WebPAnimEncoderOptions anim_options;
    anim_options.verbose = 1;
    WebPAnimEncoderOptionsInit(&anim_options);
    state->anim_encoder = WebPAnimEncoderNew(width, height, &anim_options);
    if (state->anim_encoder == nullptr) {
        LOGE("Failed to create new WebPAnimEncoder.");
        delete state;
        state = nullptr;
        return JNI_FALSE;
    }

    LOGI("Native encoder initialized successfully for %dx%d.", width, height);
    return JNI_TRUE;
}


JNIEXPORT void JNICALL
Java_de_loicezt_stickers_video_LibWebP_nativeAddFrameYuv(
        JNIEnv *env,
        jobject /* this */,
        jobject y_buffer, jint y_stride,
        jobject u_buffer, jint u_stride,
        jobject v_buffer, jint v_stride,
        jint timestamp_ms) {

    if (state == nullptr || state->anim_encoder == nullptr) {
        LOGE("Cannot add frame. Encoder not initialized.");
        return;
    }

    // Get direct pointers to the pixel data for each plane
    auto *y_pixels = static_cast<uint8_t *>(env->GetDirectBufferAddress(y_buffer));
    auto *u_pixels = static_cast<uint8_t *>(env->GetDirectBufferAddress(u_buffer));
    auto *v_pixels = static_cast<uint8_t *>(env->GetDirectBufferAddress(v_buffer));

    if (y_pixels == nullptr || u_pixels == nullptr || v_pixels == nullptr) {
        LOGE("Failed to get direct buffer address for one or more planes.");
        return;
    }

    // --- KEY CHANGE: Manually set up the YUV picture from the planes ---
    WebPPicture pic;
    if (!WebPPictureInit(&pic)) {
        LOGE("Failed to init WebPPicture");
        return;
    }
    pic.width = state->frame_width;
    pic.height = state->frame_height;
    pic.use_argb = 0; // We are providing YUV data

    // Set pointers to the Y, U, and V planes
    pic.y = y_pixels;
    pic.u = u_pixels;
    pic.v = v_pixels;

    // Set the stride for each plane
    pic.y_stride = y_stride;
    pic.uv_stride = u_stride; // For YUV420, U and V strides are the same

    // 4. Add the YUV picture to the animation encoder
    if (!WebPAnimEncoderAdd(state->anim_encoder, &pic, timestamp_ms, &state->config)) {
        LOGE("Failed to add YUV frame to WebPAnimEncoder at timestamp %d", timestamp_ms);
    }

    // WebPPictureFree(&pic) is NOT needed here because we didn't allocate memory with it.
    // The memory is owned by the MediaCodec Image, which we closed in Kotlin.
}
const char *getWebPErrorString(int error_code) {
    switch (error_code) {
        case VP8_ENC_OK:
            return "OK";
        case VP8_ENC_ERROR_OUT_OF_MEMORY:
            return "OUT_OF_MEMORY";
        case VP8_ENC_ERROR_BITSTREAM_OUT_OF_MEMORY:
            return "BITSTREAM_OUT_OF_MEMORY";
        case VP8_ENC_ERROR_NULL_PARAMETER:
            return "NULL_PARAMETER";
        case VP8_ENC_ERROR_INVALID_CONFIGURATION:
            return "INVALID_CONFIGURATION";
        case VP8_ENC_ERROR_BAD_DIMENSION:
            return "BAD_DIMENSION";
        case VP8_ENC_ERROR_PARTITION0_OVERFLOW:
            return "PARTITION0_OVERFLOW";
        case VP8_ENC_ERROR_PARTITION_OVERFLOW:
            return "PARTITION_OVERFLOW";
        case VP8_ENC_ERROR_BAD_WRITE:
            return "BAD_WRITE";
        case VP8_ENC_ERROR_FILE_TOO_BIG:
            return "FILE_TOO_BIG";
        case VP8_ENC_ERROR_USER_ABORT:
            return "USER_ABORT";
        default:
            return "UNKNOWN_ERROR";
    }
}

// --- NEW: Helper function to log the entire WebPConfig struct ---
void logWebPConfig(const WebPConfig *config) {
    LOGI("--- WebPConfig State ---");
    LOGI("  lossless: %d", config->lossless);
    LOGI("  quality: %.1f", config->quality);
    LOGI("  method: %d", config->method);
    LOGI("  image_hint: %d", config->image_hint);
    LOGI("  target_size: %d", config->target_size);
    LOGI("  target_PSNR: %.1f", config->target_PSNR);
    LOGI("  segments: %d", config->segments);
    LOGI("  sns_strength: %d", config->sns_strength);
    LOGI("  filter_strength: %d", config->filter_strength);
    LOGI("  filter_sharpness: %d", config->filter_sharpness);
    LOGI("  filter_type: %d", config->filter_type);
    LOGI("  autofilter: %d", config->autofilter);
    LOGI("  alpha_compression: %d", config->alpha_compression);
    LOGI("  alpha_filtering: %d", config->alpha_filtering);
    LOGI("  alpha_quality: %d", config->alpha_quality);
    LOGI("  pass: %d", config->pass);
    LOGI("  show_compressed: %d", config->show_compressed);
    LOGI("  preprocessing: %d", config->preprocessing);
    LOGI("  partitions: %d", config->partitions);
    LOGI("  partition_limit: %d", config->partition_limit);
    LOGI("  emulate_jpeg_size: %d", config->emulate_jpeg_size);
    LOGI("  thread_level: %d", config->thread_level);
    LOGI("  low_memory: %d", config->low_memory);
    LOGI("  near_lossless: %d", config->near_lossless);
    LOGI("  exact: %d", config->exact);
    LOGI("  use_sharp_yuv: %d", config->use_sharp_yuv);
    LOGI("  qmin: %d", config->qmin);
    LOGI("  qmax: %d", config->qmax);
    LOGI("------------------------");
}
JNIEXPORT void JNICALL
Java_de_loicezt_stickers_video_LibWebP_nativeAddFrame(
        JNIEnv *env,
        jobject /* this */,
        jobject frameBuffer,
        jint timestampMs) {

    if (state == nullptr || state->anim_encoder == nullptr) {
        LOGE("Cannot add frame. Encoder not initialized.");
        return;
    }

    // Get a direct pointer to the pixel data from the Java ByteBuffer
    auto *pixels = static_cast<uint8_t *>(env->GetDirectBufferAddress(frameBuffer));
    if (pixels == nullptr) {
        LOGE("Failed to get direct buffer address.");
        return;
    }

    // 3. Create a WebPPicture and import the pixels
    WebPPicture pic;
    if (!WebPPictureInit(&pic)) {
        LOGE("Failed to init WebPPicture");
        return;
    }
    pic.width = state->frame_width;
    pic.height = state->frame_height;
    pic.use_argb = 1; // We are providing RGBA data

    // Import the RGBA data. The stride is the number of bytes per row.
    WebPPictureImportRGBA(&pic, pixels, state->frame_width * 4);

    // 4. Add the picture to the animation encoder
    //logWebPConfig(&state->config);
    if (!WebPAnimEncoderAdd(state->anim_encoder, &pic, timestampMs, &state->config)) {
        const char *error_string = getWebPErrorString(pic.error_code);
        LOGE("Failed to add frame to WebPAnimEncoder at timestamp %d. Error: %s (%d)",
             timestampMs, error_string, pic.error_code);
    } else {
        LOGI("Added frame at Timestamp %d", timestampMs);
    }

    WebPPictureFree(&pic); // Free the picture memory
}

JNIEXPORT jbyteArray JNICALL
Java_de_loicezt_stickers_video_LibWebP_nativeReleaseEncoder(
        JNIEnv *env,
        jobject /* this */) {


    if (state == nullptr) { /* ... error handling ... */ return nullptr; }

    // Assemble the animation
    WebPAnimEncoderAdd(state->anim_encoder, nullptr, 0, nullptr);
    WebPData webp_data;
    WebPDataInit(&webp_data);
    if (!WebPAnimEncoderAssemble(state->anim_encoder, &webp_data)) {
        LOGE("Failed to assemble final WebP animation.");
        WebPAnimEncoderDelete(state->anim_encoder);
        delete state;
        state = nullptr;
        return nullptr;
    }

    LOGI("Successfully assembled WebP data. Size: %zu bytes", webp_data.size);

    // --- NEW: Create a Java byte array and copy the data into it ---
    jbyteArray byteArray = env->NewByteArray(webp_data.size);
    void *temp = env->GetPrimitiveArrayCritical(byteArray, nullptr);
    memcpy(temp, webp_data.bytes, webp_data.size);
    env->ReleasePrimitiveArrayCritical(byteArray, temp, 0);
    // --- End of new code ---

    // Cleanup
    WebPDataClear(&webp_data);
    WebPAnimEncoderDelete(state->anim_encoder);
    delete state;
    state = nullptr;

    LOGI("Native encoder released.");
    return byteArray; // Return the raw data to Kotlin
}

} // extern "C"