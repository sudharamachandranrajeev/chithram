cmake_minimum_required(VERSION 3.10)
project(torrent_library VERSION 0.0.1 LANGUAGES C)

# Prebuilt Rust cdylib (native/torrent, built by CI) dropped into prebuilt/linux-x64/.
# Flutter's Linux runner installs everything listed in <plugin>_bundled_libraries
# into the bundle's lib/ directory, which is on the runner's RPATH.
set(_torrent_lib "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/linux-x64/libchithram_torrent.so")
if(EXISTS "${_torrent_lib}")
  set(torrent_bundled_libraries "${_torrent_lib}" PARENT_SCOPE)
else()
  message(WARNING "torrent: libchithram_torrent.so not found in prebuilt/linux-x64; the torrent engine will not load")
endif()
