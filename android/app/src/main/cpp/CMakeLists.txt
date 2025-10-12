cmake_minimum_required(VERSION 3.22.1)
set(CMAKE_SYSTEM_VERSION 21)

project("stickers")
set(LIBWEBP_SRC_DIR ${CMAKE_SOURCE_DIR}/libwebp/src)
file(GLOB_RECURSE LIBWEBP_SOURCES
        "${LIBWEBP_SRC_DIR}/dsp/*.c"
        "${LIBWEBP_SRC_DIR}/enc/*.c"
        "${LIBWEBP_SRC_DIR}/mux/*.c"
        "${LIBWEBP_SRC_DIR}/demux/*.c"
        "${LIBWEBP_SRC_DIR}/utils/*.c"
        "${LIBWEBP_SRC_DIR}/dec/*.c"
        "${CMAKE_SOURCE_DIR}/libwebp/sharpyuv/*.c"
)
add_library(webp-static STATIC ${LIBWEBP_SOURCES})

target_compile_definitions(webp-static PUBLIC
        ANDROID
        HAVE_MALLOC_H
        HAVE_PTHREAD
        WEBP_USE_THREAD
)
target_include_directories(webp-static PUBLIC ${CMAKE_SOURCE_DIR}/libwebp)

if(ANDROID_ABI STREQUAL "armeabi-v7a" OR ANDROID_ABI STREQUAL "arm64-v8a")
    find_library(cpufeatures-lib cpufeatures)
    if(cpufeatures-lib)
        target_link_libraries(webp-static PRIVATE ${cpufeatures-lib})
        target_compile_definitions(webp-static PRIVATE HAVE_CPU_FEATURES_H)
    endif()
    if(ANDROID_ABI STREQUAL "armeabi-v7a")
        target_compile_options(webp-static PRIVATE -marm)
        target_compile_options(webp-static PRIVATE
                $<$<CONFIG:RELEASE>:-mfpu=neon>
        )
    endif()

endif()

target_compile_options(webp-static PRIVATE
        $<$<CONFIG:RELEASE>:-Ofast>
        $<$<CONFIG:RELEASE>:-finline-functions>
        $<$<CONFIG:RELEASE>:-ffast-math>
        $<$<CONFIG:RELEASE>:-ffunction-sections>
        $<$<CONFIG:RELEASE>:-fdata-sections>
)

target_compile_options(webp-static PRIVATE
        $<$<CONFIG:DEBUG>:-Og>
        $<$<CONFIG:DEBUG>:-g>
)

add_library(${CMAKE_PROJECT_NAME} SHARED
        libwebp_connector.cpp)
target_link_libraries(${CMAKE_PROJECT_NAME}
        webp-static
        android
        log)