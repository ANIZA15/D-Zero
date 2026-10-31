cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "d_zero_3dengine")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "d_zero_3dengine_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/d_zero_3dengine/zero_3d_engine_plugin_c_api.h"
  "zero_3d_engine_plugin.cpp"
  "../src/zero_3d_engine_state.cpp"
  "../src/zero_3d_engine_state.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(d_zero_3dengine_bundled_libraries
  ""
  PARENT_SCOPE
)
