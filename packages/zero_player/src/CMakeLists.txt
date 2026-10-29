cmake_minimum_required(VERSION 3.10)
project(zero_player_native LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SOURCES
    zero_playback_state.cpp
)

if (ANDROID)
    list(APPEND SOURCES ../android/src/main/cpp/zero_player_jni.cpp)
endif()

add_library(zero_player_native SHARED
    ${SOURCES}
)

set_target_properties(zero_player_native PROPERTIES
    OUTPUT_NAME "zero_player_native"
    PREFIX "lib"
)

target_include_directories(zero_player_native PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)
