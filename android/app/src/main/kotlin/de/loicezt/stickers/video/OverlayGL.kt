package de.loicezt.stickers.video

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

class OverlayGL : SurfaceTexture.OnFrameAvailableListener {


    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    private var videoProgramHandle = 0
    private var overlayProgramHandle = 0

    private var videoTextureHandle = 0
    private var overlayTextureHandle = 0
    private var fboHandle = 0
    private var fboTextureHandle = 0

    private val vertexBuffer: FloatBuffer
    private val texCoordBuffer: FloatBuffer
    private val transformMatrix = FloatArray(16)

    private lateinit var decoderSurfaceTexture: SurfaceTexture
    lateinit var decoderInputSurface: Surface
        private set

    private val frameSemaphore = Semaphore(0)

    private var outputWidth = 0
    private var outputHeight = 0
    private var viewportX = 0
    private var viewportY = 0
    private var viewportWidth = 0
    private var viewportHeight = 0

    private val flipMatrix = FloatArray(16)      // Our vertical flip
    private val finalMatrix = FloatArray(16)     // The combined res

    init {
        val vertexData = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)
        vertexBuffer = ByteBuffer.allocateDirect(vertexData.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        vertexBuffer.put(vertexData).position(0)


        val texCoordData = floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f)
        texCoordBuffer = ByteBuffer.allocateDirect(texCoordData.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        texCoordBuffer.put(texCoordData).position(0)

        Matrix.setIdentityM(flipMatrix, 0)
        Matrix.translateM(flipMatrix, 0, 0f, 1f, 0f)
        Matrix.scaleM(flipMatrix, 0, 1f, -1f, 1f)
    }

    override fun onFrameAvailable(st: SurfaceTexture?) {
        frameSemaphore.release()
    }

    fun setup(outputWidth: Int, outputHeight: Int, videoWidth: Int, videoHeight: Int) {
        this.outputWidth = outputWidth
        this.outputHeight = outputHeight
        calculateViewport(videoWidth, videoHeight)

        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        EGL14.eglInitialize(eglDisplay, IntArray(2), 0, IntArray(2), 1)
        val eglConfig = chooseEglConfig()
        val contextAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        eglContext = EGL14.eglCreateContext(eglDisplay, eglConfig, EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
        val surfaceAttribs = intArrayOf(EGL14.EGL_WIDTH, outputWidth, EGL14.EGL_HEIGHT, outputHeight, EGL14.EGL_NONE)
        eglSurface = EGL14.eglCreatePbufferSurface(eglDisplay, eglConfig, surfaceAttribs, 0)
        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

        videoProgramHandle = createProgram(VIDEO_VERTEX_SHADER, VIDEO_FRAGMENT_SHADER)
        overlayProgramHandle = createProgram(OVERLAY_VERTEX_SHADER, OVERLAY_FRAGMENT_SHADER)
        videoTextureHandle = createExternalOESTexture()
        overlayTextureHandle = create2DTexture()
        setupFBO()

        decoderSurfaceTexture = SurfaceTexture(videoTextureHandle)
        decoderSurfaceTexture.setOnFrameAvailableListener(this)
        decoderInputSurface = Surface(decoderSurfaceTexture)
    }

    private fun calculateViewport(videoWidth: Int, videoHeight: Int) {
        val videoAspect = videoWidth.toFloat() / videoHeight.toFloat()
        if (videoAspect > 1f) {
            viewportWidth = outputWidth
            viewportHeight = (outputWidth / videoAspect).toInt()
            viewportX = 0
            viewportY = (outputHeight - viewportHeight) / 2
        } else {
            viewportHeight = outputHeight
            viewportWidth = (outputHeight * videoAspect).toInt()
            viewportY = 0
            viewportX = (outputWidth - viewportWidth) / 2
        }
    }

    fun awaitNewFrame() {
        if (!frameSemaphore.tryAcquire(5, TimeUnit.SECONDS)) {
            throw TimeoutException("Timeout waiting for new video frame")
        }
    }

    fun drawFrame(overlayBitmap: Bitmap) {
        decoderSurfaceTexture.updateTexImage()
        decoderSurfaceTexture.getTransformMatrix(transformMatrix)
        Matrix.multiplyMM(finalMatrix, 0, transformMatrix, 0, flipMatrix, 0)

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fboHandle)

        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClearColor(0f, 0f, 0f, 0f) // Transparent Black
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        GLES20.glViewport(viewportX, viewportY, viewportWidth, viewportHeight)
        drawVideo()

        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        drawOverlay(overlayBitmap)

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
    }

    fun readPixels(buffer: ByteBuffer) {
        buffer.order(ByteOrder.nativeOrder())
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fboHandle)
        GLES20.glReadPixels(0, 0, outputWidth, outputHeight, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        buffer.rewind()
    }

    fun release() {
        if (this::decoderInputSurface.isInitialized) {
            decoderInputSurface.release()
        }
        if (this::decoderSurfaceTexture.isInitialized) {
            decoderSurfaceTexture.release()
        }
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglDestroySurface(eglDisplay, eglSurface)
            EGL14.eglDestroyContext(eglDisplay, eglContext)
            EGL14.eglReleaseThread()
            EGL14.eglTerminate(eglDisplay)
        }
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglContext = EGL14.EGL_NO_CONTEXT
        eglSurface = EGL14.EGL_NO_SURFACE
    }

    private fun drawVideo() {
        GLES20.glUseProgram(videoProgramHandle)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, videoTextureHandle)
        val uTransformMatrixHandle = GLES20.glGetUniformLocation(videoProgramHandle, "uTransformMatrix")
        GLES20.glUniformMatrix4fv(uTransformMatrixHandle, 1, false, finalMatrix, 0)
        renderQuad(GLES20.glGetAttribLocation(videoProgramHandle, "aPosition"),
            GLES20.glGetAttribLocation(videoProgramHandle, "aTexCoord"), texCoordBuffer)
    }

    private fun drawOverlay(bitmap: Bitmap) {
        GLES20.glUseProgram(overlayProgramHandle)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureHandle)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)

        val uTextureHandle = GLES20.glGetUniformLocation(overlayProgramHandle, "sTexture")
        GLES20.glUniform1i(uTextureHandle, 1)

        renderQuad(GLES20.glGetAttribLocation(overlayProgramHandle, "aPosition"),
            GLES20.glGetAttribLocation(overlayProgramHandle, "aTexCoord"), texCoordBuffer)

        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun renderQuad(posHandle: Int, texHandle: Int, texBuffer: FloatBuffer) {
        GLES20.glEnableVertexAttribArray(posHandle)
        GLES20.glVertexAttribPointer(posHandle, 2, GLES20.GL_FLOAT, false, 8, vertexBuffer)
        GLES20.glEnableVertexAttribArray(texHandle)
        GLES20.glVertexAttribPointer(texHandle, 2, GLES20.GL_FLOAT, false, 8, texBuffer)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(posHandle)
        GLES20.glDisableVertexAttribArray(texHandle)
    }

    private fun setupFBO() {
        val fbo = IntArray(1)
        val fboTex = IntArray(1)

        GLES20.glGenFramebuffers(1, fbo, 0)
        GLES20.glGenTextures(1, fboTex, 0)

        fboHandle = fbo[0]
        fboTextureHandle = fboTex[0]

        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, fboTextureHandle)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D,
            0,
            GLES20.GL_RGBA,
            512,
            512,
            0,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            null
        )
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fboHandle)
        GLES20.glFramebufferTexture2D(
            GLES20.GL_FRAMEBUFFER,
            GLES20.GL_COLOR_ATTACHMENT0,
            GLES20.GL_TEXTURE_2D,
            fboTextureHandle,
            0
        )

        if (GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER) != GLES20.GL_FRAMEBUFFER_COMPLETE) {
            throw RuntimeException("Framebuffer is not complete")
        }
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
    }

    private fun chooseEglConfig(): EGLConfig {
        val attribList = intArrayOf(
            EGL14.EGL_RED_SIZE,
            8,
            EGL14.EGL_GREEN_SIZE,
            8,
            EGL14.EGL_BLUE_SIZE,
            8,
            EGL14.EGL_ALPHA_SIZE,
            8,
            EGL14.EGL_RENDERABLE_TYPE,
            EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE,
            EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        if (!EGL14.eglChooseConfig(eglDisplay, attribList, 0, configs, 0, 1, numConfigs, 0)) {
            throw RuntimeException("eglChooseConfig failed")
        }
        return configs[0]!!
    }

    private fun createExternalOESTexture(): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val textureId = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR
        )
        return textureId
    }

    private fun create2DTexture(): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val textureId = textures[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST
        )
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST
        )
        return textureId
    }

    private fun createProgram(vertexSource: String, fragmentSource: String): Int {
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)
        return program
    }

    private fun loadShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        return shader
    }

    private val VIDEO_VERTEX_SHADER = """
        uniform mat4 uTransformMatrix;
        attribute vec4 aPosition;
        attribute vec2 aTexCoord;
        varying vec2 vTexCoord;
        void main() {
            gl_Position = aPosition;
            vTexCoord = (uTransformMatrix * vec4(aTexCoord, 0.0, 1.0)).xy;
        }
    """.trimIndent()

    private val VIDEO_FRAGMENT_SHADER = """
        #extension GL_OES_EGL_image_external : require
        precision mediump float;
        varying vec2 vTexCoord;
        uniform samplerExternalOES sTexture;
        void main() {
            gl_FragColor = texture2D(sTexture, vTexCoord);
        }
    """.trimIndent()

    // Shaders for drawing the overlay
    private val OVERLAY_VERTEX_SHADER = """
        attribute vec4 aPosition;
        attribute vec2 aTexCoord;
        varying vec2 vTexCoord;
        void main() {
            gl_Position = aPosition;
            vTexCoord = aTexCoord;
        }
    """.trimIndent()

    private val OVERLAY_FRAGMENT_SHADER = """
        precision mediump float;
        varying vec2 vTexCoord;
        uniform sampler2D sTexture;
        void main() {
            gl_FragColor = texture2D(sTexture, vTexCoord);
        }
    """.trimIndent()
}