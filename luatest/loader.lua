-- Module to load test files from certain directory recursievly.

local fio = require('fio')
local fun = require('fun')

-- Returns list of all nested files within given path.
-- As fio.glob does not support `**/*` this method adds `/*` to path and glog it
-- until result is empty.
local function glob_recursive(path)
    local pattern = path
    local result = {}
    repeat
        pattern = pattern .. '/*'
        local last_result = fio.glob(pattern)
        for _, item in ipairs(last_result) do
            result[#result + 1] = item
        end
    until #last_result == 0
    return result
end

-- If directory is given then it's scanned recursievly for files ending with `_test.lua`.
-- If `.lua` file is given then it's used as is.
-- Resulting list of files is mapped to lua's module names.
local function get_test_modules_list(path)
    local files
    if path:endswith('.lua') then
        files = fun.iter({path})
    else
        local list = glob_recursive(path)
        table.sort(list)
        files = fun.iter(list):filter(function(x) return x:endswith('_test.lua') end)
    end
    return files:
        map(function(x) return x:gsub('%.lua$', '') end):
        map(function(x) return x:gsub('/', '.') end):
        totable()
end

-- Uses get_test_modules_list to retrieve modules list for given path and requires them.
local function require_tests(path)
    for _, mod in ipairs(get_test_modules_list(path)) do
        require(mod)
    end
end

return {require_tests = require_tests}
