package de.loicezt.stickers.video


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