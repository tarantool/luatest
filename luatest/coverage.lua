-- Initialize luacov when script luatest is running with enabled code coverage
-- collector.
-- This file is expected to be run before any other lua code (ex., with `-l` option).
require('luatest.coverage_utils').enable()
