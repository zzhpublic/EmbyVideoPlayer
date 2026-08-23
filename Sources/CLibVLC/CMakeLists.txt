# CMake configuration for finding libvlc on Windows
# This is used when building on Windows

cmake_minimum_required(VERSION 3.20)

# Find VLC installation
find_path(VLC_INCLUDE_DIR vlc/vlc.h
    PATHS
    "C:/Program Files/VideoLAN/VLC/sdk/include"
    "C:/Program Files (x86)/VideoLAN/VLC/sdk/include"
    "$ENV{VLC_SDK_PATH}/include"
    )

find_library(VLC_LIBRARY
    NAMES libvlc
    PATHS
    "C:/Program Files/VideoLAN/VLC/sdk/lib"
    "C:/Program Files (x86)/VideoLAN/VLC/sdk/lib"
    "$ENV{VLC_SDK_PATH}/lib"
    )

find_library(VLCCORE_LIBRARY
    NAMES libvlccore
    PATHS
    "C:/Program Files/VideoLAN/VLC/sdk/lib"
    "C:/Program Files (x86)/VideoLAN/VLC/sdk/lib"
    "$ENV{VLC_SDK_PATH}/lib"
    )

if(VLC_INCLUDE_DIR AND VLC_LIBRARY AND VLCCORE_LIBRARY)
    set(VLC_FOUND TRUE)
    message(STATUS "Found VLC: ${VLC_INCLUDE_DIR}")
else()
    message(WARNING "VLC SDK not found. Please install VLC and set VLC_SDK_PATH environment variable.")
    set(VLC_FOUND FALSE)
endif()