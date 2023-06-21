include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(grain_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(grain_setup_options)
  option(grain_ENABLE_HARDENING "Enable hardening" ON)
  option(grain_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    grain_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    grain_ENABLE_HARDENING
    OFF)

  grain_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR grain_PACKAGING_MAINTAINER_MODE)
    option(grain_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(grain_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(grain_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(grain_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(grain_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(grain_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(grain_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(grain_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(grain_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(grain_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(grain_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(grain_ENABLE_PCH "Enable precompiled headers" OFF)
    option(grain_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(grain_ENABLE_IPO "Enable IPO/LTO" ON)
    option(grain_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(grain_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(grain_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(grain_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(grain_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(grain_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(grain_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(grain_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(grain_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(grain_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(grain_ENABLE_PCH "Enable precompiled headers" OFF)
    option(grain_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      grain_ENABLE_IPO
      grain_WARNINGS_AS_ERRORS
      grain_ENABLE_USER_LINKER
      grain_ENABLE_SANITIZER_ADDRESS
      grain_ENABLE_SANITIZER_LEAK
      grain_ENABLE_SANITIZER_UNDEFINED
      grain_ENABLE_SANITIZER_THREAD
      grain_ENABLE_SANITIZER_MEMORY
      grain_ENABLE_UNITY_BUILD
      grain_ENABLE_CLANG_TIDY
      grain_ENABLE_CPPCHECK
      grain_ENABLE_COVERAGE
      grain_ENABLE_PCH
      grain_ENABLE_CACHE)
  endif()

  grain_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (grain_ENABLE_SANITIZER_ADDRESS OR grain_ENABLE_SANITIZER_THREAD OR grain_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(grain_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(grain_global_options)
  if(grain_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    grain_enable_ipo()
  endif()

  grain_supports_sanitizers()

  if(grain_ENABLE_HARDENING AND grain_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR grain_ENABLE_SANITIZER_UNDEFINED
       OR grain_ENABLE_SANITIZER_ADDRESS
       OR grain_ENABLE_SANITIZER_THREAD
       OR grain_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${grain_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${grain_ENABLE_SANITIZER_UNDEFINED}")
    grain_enable_hardening(grain_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(grain_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(grain_warnings INTERFACE)
  add_library(grain_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  grain_set_project_warnings(
    grain_warnings
    ${grain_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(grain_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(grain_options)
  endif()

  include(cmake/Sanitizers.cmake)
  grain_enable_sanitizers(
    grain_options
    ${grain_ENABLE_SANITIZER_ADDRESS}
    ${grain_ENABLE_SANITIZER_LEAK}
    ${grain_ENABLE_SANITIZER_UNDEFINED}
    ${grain_ENABLE_SANITIZER_THREAD}
    ${grain_ENABLE_SANITIZER_MEMORY})

  set_target_properties(grain_options PROPERTIES UNITY_BUILD ${grain_ENABLE_UNITY_BUILD})

  if(grain_ENABLE_PCH)
    target_precompile_headers(
      grain_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(grain_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    grain_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(grain_ENABLE_CLANG_TIDY)
    grain_enable_clang_tidy(grain_options ${grain_WARNINGS_AS_ERRORS})
  endif()

  if(grain_ENABLE_CPPCHECK)
    grain_enable_cppcheck(${grain_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(grain_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    grain_enable_coverage(grain_options)
  endif()

  if(grain_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(grain_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(grain_ENABLE_HARDENING AND NOT grain_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR grain_ENABLE_SANITIZER_UNDEFINED
       OR grain_ENABLE_SANITIZER_ADDRESS
       OR grain_ENABLE_SANITIZER_THREAD
       OR grain_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    grain_enable_hardening(grain_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
