add_executable(sandbox sandbox_app.cpp)

target_link_libraries(
        sandbox
        PRIVATE prometheus::prometheus_options
        prometheus::prometheus_warnings)

target_link_system_libraries(
        sandbox
        PRIVATE
        spdlog::spdlog
        lefticus::tools
        )