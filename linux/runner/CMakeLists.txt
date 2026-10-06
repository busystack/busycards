cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "gtk_header_icons.cc"
  "gtk_search_entry_theme.cc"
  "gtk_window_preferences.cc"
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::HANDY)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

if(BUILD_TESTING)
  foreach(component gtk_header_icons gtk_search_entry_theme gtk_window_preferences)
    add_executable(${component}_test "tests/${component}_test.cc" "${component}.cc")
    target_compile_features(${component}_test PRIVATE cxx_std_17)
    target_compile_options(${component}_test PRIVATE -Wall -Werror)
    target_link_libraries(${component}_test PRIVATE PkgConfig::GTK)
    add_test(NAME ${component} COMMAND ${component}_test)
  endforeach()
endif()
