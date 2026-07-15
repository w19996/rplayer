cmake_minimum_required(VERSION 3.14)

option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

function(download_and_extract name url sha256 archive destination marker)
  if(EXISTS "${archive}")
    file(SHA256 "${archive}" actual_sha256)
    if(NOT actual_sha256 STREQUAL sha256)
      file(REMOVE "${archive}")
    endif()
  endif()

  if(NOT EXISTS "${archive}")
    message(STATUS "Downloading ${name} from ${url}")
    file(DOWNLOAD "${url}" "${archive}"
      EXPECTED_HASH "SHA256=${sha256}"
      SHOW_PROGRESS
    )
  endif()

  set(stamp "${destination}/.rplayer-${name}.sha256")
  set(installed_sha256 "")
  if(EXISTS "${stamp}")
    file(READ "${stamp}" installed_sha256)
  endif()

  if(NOT EXISTS "${destination}/${marker}" OR
     NOT installed_sha256 STREQUAL sha256)
    file(REMOVE_RECURSE "${destination}")
    file(MAKE_DIRECTORY "${destination}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "${archive}"
      WORKING_DIRECTORY "${destination}"
      RESULT_VARIABLE extract_result
    )
    if(NOT extract_result EQUAL 0)
      message(FATAL_ERROR "Failed to extract ${name}: ${extract_result}")
    endif()
    file(WRITE "${stamp}" "${sha256}")
  endif()

  # media_kit_video includes client.h directly, while current mpv development
  # archives place it under include/mpv/client.h.
  if(EXISTS "${destination}/include/mpv/client.h" AND
     NOT EXISTS "${destination}/include/client.h")
    file(COPY "${destination}/include/mpv/" DESTINATION "${destination}/include")
  endif()
endfunction()

set(LIBMPV "mpv-dev-x86_64-20260713-git-e5486b96d7.7z")
set(LIBMPV_URL "https://github.com/zhongfly/mpv-winbuild/releases/download/2026-07-13-e5486b96d7/${LIBMPV}")
set(LIBMPV_SHA256 "49b7c64b970b2ada81100094aa62b63dd78795f5024ac414ca9cc7507a467cdb")
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

download_and_extract(
  "libmpv"
  "${LIBMPV_URL}"
  "${LIBMPV_SHA256}"
  "${LIBMPV_ARCHIVE}"
  "${LIBMPV_SRC}"
  "libmpv-2.dll"
)

set(ANGLE "ANGLE.7z")
set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(ANGLE_SHA256 "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a")
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

download_and_extract(
  "ANGLE"
  "${ANGLE_URL}"
  "${ANGLE_SHA256}"
  "${ANGLE_ARCHIVE}"
  "${ANGLE_SRC}"
  "lib/libEGL.dll.lib"
)

set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)
