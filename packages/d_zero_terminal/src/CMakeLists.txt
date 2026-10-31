cmake_minimum_required(VERSION 3.10)
project(zero_terminal_native VERSION 0.1.4 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(zero_terminal_native SHARED
    "zero_terminal_state.cpp"
)

set_target_properties(zero_terminal_native PROPERTIES
    PUBLIC_HEADER "zero_terminal_state.h"
    OUTPUT_NAME "zero_terminal_native"
)
