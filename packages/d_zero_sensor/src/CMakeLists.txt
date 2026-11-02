cmake_minimum_required(VERSION 3.10)
project(zero_sensor_native VERSION 0.1.4 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(zero_sensor_native SHARED
    zero_camera_state.cpp
)

set_target_properties(zero_sensor_native PROPERTIES
    PUBLIC_HEADER zero_camera_state.h
    OUTPUT_NAME "zero_sensor_native"
)

target_compile_definitions(zero_sensor_native PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size.
  target_link_options(zero_sensor_native PRIVATE "-Wl,-z,max-page-size=16384")
endif()
