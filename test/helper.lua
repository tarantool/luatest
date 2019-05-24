local runner = require('luatest').runner

local helper = {}

function helper.run_suite(load_tests)
    local lu = dofile(package.search('luatest.luaunit'))
    -- Need to supply any option to prevent luaunit from taking args from _G
    return runner:run({'-x', '!none!'}, {luaunit = lu, load_tests = function() load_tests(lu) end})
end

return helper
