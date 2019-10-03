cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(luatest)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

# Find Tarantool and Lua dependecies
set(TARANTOOL_FIND_REQUIRED ON)
find_package(Tarantool)
include_directories(${TARANTOOL_INCLUDE_DIRS})

# Install module
install(FILES
  luatest/capture.lua
  luatest/capturing.lua
  luatest/helpers.lua
  luatest/hooks.lua
  luatest/init.lua
  luatest/loader.lua
  luatest/luaunit.lua
  luatest/process.lua
  luatest/reporting.lua
  luatest/runner.lua
  luatest/sandboxed_runner.lua
  luatest/server.lua
  luatest/utils.lua
  DESTINATION ${TARANTOOL_INSTALL_LUADIR}/luatest)

install(FILES
  bin/luatest
  PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ
  GROUP_EXECUTE GROUP_READ
  WORLD_EXECUTE WORLD_READ
  DESTINATION bin)


# testing

set(TARANTOOL tarantool)

enable_testing()

add_test(NAME luacheck
         COMMAND luacheck ./
         WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})

add_test(NAME selftest
         COMMAND bin/luatest
         WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
