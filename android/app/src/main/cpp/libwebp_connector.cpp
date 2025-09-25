#include <jni.h>
#include <string>
#include <android/log.h>

// libwebp headers
#include "src/webp/encode.h"
#include "src/webp/mux.h"
#include "src/webp/encode.h"
#include "src/webp/mux.h"

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

JNIEXPORT jboolean JNICALL
Java_de_loicezt_stickers_video_LibWebP_nativeInitEncoder(
        JNIEnv *env,
        jobject /* this */,
        jint width,
        jint height) {

    if (state != nullptr) {
        LOGE("Encoder already initialized. Please release it first.");
        return JNI_FALSE;
    }

    state = new EncoderState();
    state->frame_width = width;
    state->frame_height = height;

    // 1. Configure the encoder
    // Quality=75 is a good starting point.
    if (!WebPConfigInit(&state->config) || !WebPValidateConfig(&state->config)) {
        LOGE("Failed to initialize WebPConfig.");
        delete state;
        state = nullptr;
        return JNI_FALSE;
    }
    state->config.quality = 70.0f;
    state->config.method = 0; // Quality/speed trade-off (0=fast, 6=slowest).
    state->config.thread_level = 1;

    // 2. Setup the animation encoder
    WebPAnimEncoderOptions anim_options;
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
    if (!WebPAnimEncoderAdd(state->anim_encoder, &pic, timestampMs, &state->config)) {
        LOGE("Failed to add frame to WebPAnimEncoder at timestamp %d", timestampMs);
    }
    LOGI("Added frame at Timestamp %d", timestampMs);

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
        // Cleanup and return null
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