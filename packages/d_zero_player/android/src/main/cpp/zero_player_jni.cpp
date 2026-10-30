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
Java_com_fexcy_zero_1player_ZeroNativeBridge_setPositionAnchor(JNIEnv *env, jclass clazz, jlong statePtr, jlong positionMs, jfloat speed) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_set_position_anchor(state, positionMs, speed);
}

JNIEXPORT void JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_setPlaybackSpeed(JNIEnv *env, jclass clazz, jlong statePtr, jfloat speed) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_set_playback_speed(state, speed);
}

JNIEXPORT void JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_setDuration(JNIEnv *env, jclass clazz, jlong statePtr, jlong durationMs) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_set_duration(state, durationMs);
}

JNIEXPORT void JNICALL
Java_com_fexcy_zero_1player_ZeroNativeBridge_setBuffered(JNIEnv *env, jclass clazz, jlong statePtr, jlong bufferedMs) {
    auto* state = reinterpret_cast<ZeroPlaybackState*>(statePtr);
    zero_set_buffered(state, bufferedMs);
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
