cmake_minimum_required(VERSION 3.14)
project(torrent_library VERSION 0.0.1 LANGUAGES C)

# Prebuilt Rust cdylib (native/torrent, built by CI) dropped into prebuilt/windows-x64/.
# Flutter's Windows runner installs <plugin>_bundled_libraries next to the exe.
set(_torrent_lib "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/windows-x64/chithram_torrent.dll")
if(EXISTS "${_torrent_lib}")
  set(torrent_bundled_libraries "${_torrent_lib}" PARENT_SCOPE)
else()
  message(WARNING "torrent: chithram_torrent.dll not found in prebuilt/windows-x64; the torrent engine will not load")
endif()
