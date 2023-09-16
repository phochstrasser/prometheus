include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(prometheus_supports_sanitizers)
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

macro(prometheus_setup_options)
  option(prometheus_ENABLE_HARDENING "Enable hardening" ON)
  option(prometheus_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    prometheus_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    prometheus_ENABLE_HARDENING
    OFF)

  prometheus_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR prometheus_PACKAGING_MAINTAINER_MODE)
    option(prometheus_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(prometheus_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(prometheus_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(prometheus_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(prometheus_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(prometheus_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(prometheus_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(prometheus_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(prometheus_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(prometheus_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(prometheus_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(prometheus_ENABLE_PCH "Enable precompiled headers" OFF)
    option(prometheus_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(prometheus_ENABLE_IPO "Enable IPO/LTO" ON)
    option(prometheus_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(prometheus_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(prometheus_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(prometheus_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(prometheus_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(prometheus_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(prometheus_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(prometheus_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(prometheus_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(prometheus_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(prometheus_ENABLE_PCH "Enable precompiled headers" OFF)
    option(prometheus_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      prometheus_ENABLE_IPO
      prometheus_WARNINGS_AS_ERRORS
      prometheus_ENABLE_USER_LINKER
      prometheus_ENABLE_SANITIZER_ADDRESS
      prometheus_ENABLE_SANITIZER_LEAK
      prometheus_ENABLE_SANITIZER_UNDEFINED
      prometheus_ENABLE_SANITIZER_THREAD
      prometheus_ENABLE_SANITIZER_MEMORY
      prometheus_ENABLE_UNITY_BUILD
      prometheus_ENABLE_CLANG_TIDY
      prometheus_ENABLE_CPPCHECK
      prometheus_ENABLE_COVERAGE
      prometheus_ENABLE_PCH
      prometheus_ENABLE_CACHE)
  endif()

  prometheus_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (prometheus_ENABLE_SANITIZER_ADDRESS OR prometheus_ENABLE_SANITIZER_THREAD OR prometheus_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(prometheus_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(prometheus_global_options)
  if(prometheus_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    prometheus_enable_ipo()
  endif()

  prometheus_supports_sanitizers()

  if(prometheus_ENABLE_HARDENING AND prometheus_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR prometheus_ENABLE_SANITIZER_UNDEFINED
       OR prometheus_ENABLE_SANITIZER_ADDRESS
       OR prometheus_ENABLE_SANITIZER_THREAD
       OR prometheus_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${prometheus_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${prometheus_ENABLE_SANITIZER_UNDEFINED}")
    prometheus_enable_hardening(prometheus_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(prometheus_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(prometheus_warnings INTERFACE)
  add_library(prometheus_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  prometheus_set_project_warnings(
    prometheus_warnings
    ${prometheus_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(prometheus_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(prometheus_options)
  endif()

  include(cmake/Sanitizers.cmake)
  prometheus_enable_sanitizers(
    prometheus_options
    ${prometheus_ENABLE_SANITIZER_ADDRESS}
    ${prometheus_ENABLE_SANITIZER_LEAK}
    ${prometheus_ENABLE_SANITIZER_UNDEFINED}
    ${prometheus_ENABLE_SANITIZER_THREAD}
    ${prometheus_ENABLE_SANITIZER_MEMORY})

  set_target_properties(prometheus_options PROPERTIES UNITY_BUILD ${prometheus_ENABLE_UNITY_BUILD})

  if(prometheus_ENABLE_PCH)
    target_precompile_headers(
      prometheus_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(prometheus_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    prometheus_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(prometheus_ENABLE_CLANG_TIDY)
    prometheus_enable_clang_tidy(prometheus_options ${prometheus_WARNINGS_AS_ERRORS})
  endif()

  if(prometheus_ENABLE_CPPCHECK)
    prometheus_enable_cppcheck(${prometheus_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(prometheus_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    prometheus_enable_coverage(prometheus_options)
  endif()

  if(prometheus_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(prometheus_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(prometheus_ENABLE_HARDENING AND NOT prometheus_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR prometheus_ENABLE_SANITIZER_UNDEFINED
       OR prometheus_ENABLE_SANITIZER_ADDRESS
       OR prometheus_ENABLE_SANITIZER_THREAD
       OR prometheus_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    prometheus_enable_hardening(prometheus_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
