cmake_minimum_required(VERSION 3.10)
project(tdlib_library VERSION 0.0.1 LANGUAGES C)

# Prebuilt libtdjson.so (tdlib.yml, fetched by tool/fetch_tdlib.py) in prebuilt/linux-x64/.
# Flutter's Linux runner installs everything listed in <plugin>_bundled_libraries
# into the bundle's lib/ directory, which is on the runner's RPATH.
set(_tdjson_lib "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/linux-x64/libtdjson.so")
if(EXISTS "${_tdjson_lib}")
  set(tdlib_bundled_libraries "${_tdjson_lib}" PARENT_SCOPE)
else()
  message(WARNING "tdlib: libtdjson.so not found in prebuilt/linux-x64; Telegram will report that this build has no TDLib")
endif()
