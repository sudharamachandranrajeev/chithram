cmake_minimum_required(VERSION 3.18)
project(nova_jni C)

# CPython's official Android build (python.org). Headers are per ABI (pyconfig.h);
# the shared library is the one packaged in jniLibs (see tool/fetch_cpython_android.py).
set(PY_INC ${CMAKE_CURRENT_SOURCE_DIR}/../../../cpython/${ANDROID_ABI}/include/python3.14)
set(PY_LIB ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libpython3.14.so)

add_library(nova_jni SHARED nova_jni.c)
target_include_directories(nova_jni PRIVATE ${PY_INC})
target_link_libraries(nova_jni ${PY_LIB} log)
