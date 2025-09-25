cmake_minimum_required(VERSION 3.22.1)
set(CMAKE_SYSTEM_VERSION 21)

project("stickers")

# Add libwebp
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Ofast -s")
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
target_include_directories(webp-static PUBLIC ${CMAKE_SOURCE_DIR}/libwebp)


add_library(${CMAKE_PROJECT_NAME} SHARED
        libwebp_connector.cpp)
target_link_libraries(${CMAKE_PROJECT_NAME}
        webp-static
        android
        log)