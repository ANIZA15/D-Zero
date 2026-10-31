cmake_minimum_required(VERSION 3.10)
project(zero_3dengine_native VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(zero_3dengine_native SHARED
    "zero_3d_engine_state.cpp"
)

set_target_properties(zero_3dengine_native PROPERTIES
    PUBLIC_HEADER "zero_3d_engine_state.h"
    OUTPUT_NAME "zero_3dengine_native"
)
