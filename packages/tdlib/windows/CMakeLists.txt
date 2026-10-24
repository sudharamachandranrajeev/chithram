cmake_minimum_required(VERSION 3.14)
project(tdlib_library VERSION 0.0.1 LANGUAGES C)

# Prebuilt tdjson.dll (tdlib.yml, fetched by tool/fetch_tdlib.py) in prebuilt/windows-x64/.
# Flutter's Windows runner installs <plugin>_bundled_libraries next to the exe.
set(_tdjson_lib "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/windows-x64/tdjson.dll")
if(EXISTS "${_tdjson_lib}")
  set(tdlib_bundled_libraries "${_tdjson_lib}" PARENT_SCOPE)
else()
  message(WARNING "tdlib: tdjson.dll not found in prebuilt/windows-x64; Telegram will report that this build has no TDLib")
endif()
