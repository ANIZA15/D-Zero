#include <jni.h>
#include "zero_playback_state.h"

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_createState(JNIEnv *env, jclass clazz) {
    ZeroPlaybackState* state = zero_create_playback_state();
    return reinterpret_cast<jlong>(state);
}

JNIEXPORT void JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_destroyState(JNIEnv *env, jclass clazz, jlong statePtr) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_destroy_playback_state(state);
}

JNIEXPORT void JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_setPosition(JNIEnv *env, jclass clazz, jlong statePtr, jlong positionMs) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_set_position(state, positionMs);
}

JNIEXPORT void JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_setDuration(JNIEnv *env, jclass clazz, jlong statePtr, jlong durationMs) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_set_duration(state, durationMs);
}

JNIEXPORT void JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_setStatus(JNIEnv *env, jclass clazz, jlong statePtr, jint status) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_set_status(state, status);
}

JNIEXPORT void JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_setVideoSize(JNIEnv *env, jclass clazz, jlong statePtr, jint width, jint height) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_set_video_size(state, width, height);
}

}
