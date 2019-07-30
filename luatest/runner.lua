local capturing = require('luatest.capturing')
local Capture = require('luatest.capture')
local hooks = require('luatest.hooks')
local loader = require('luatest.loader')
local reporting = require('luatest.reporting')
local utils = require('luatest.utils')

local runner = {
    SOURCE_DIR = 'test',
    HELPER_MODULE = 'test.helper',
}

-- Adds functions to luatest which can be patched in `hooks` or `capturing` module.
local function patch_luatest(lu)
    lu.GLOBAL_TESTS = false

    function lu.load_tests(options)
        if package.search(runner.HELPER_MODULE) then
            require(runner.HELPER_MODULE)
        end

        local paths = options.paths
        if #options.paths == 0 then
            paths = {runner.SOURCE_DIR}
        end
        local load_tests = options.load_tests or loader.require_tests
        for _, path in pairs(paths) do
            load_tests(path)
        end
    end

    function lu.print_error(err)
        io.stderr:write(utils.traceback(err, 1))
    end
end

function runner:run(args, options)
    args = args or rawget(_G, 'arg')
    options = utils.merge({
        enable_capture = true,
    }, self.parse_args(args), options or {})

    local lu = options.luaunit or require('luatest.luaunit')
    local capture = options.capture or Capture:new()

    patch_luatest(lu)
    reporting(lu)
    hooks(lu)
    if options.enable_capture then
        capturing(lu, capture)
    end

    local ok, result = xpcall(function()
        lu.load_tests(options)
        return lu.LuaUnit.run(unpack(args))
    end, function(err)
        if err.type ~= 'LUAUNIT_EXIT' then
            lu.print_error(err)
        end
        return err
    end)
    if ok then
        return result
    elseif result.type == 'LUAUNIT_EXIT' then
        return result.code
    else
        return -1
    end
end

local OPTIONS = {
    ['-c'] = function(x) x.enable_capture = false end,
}

-- Parses runner specific cli args. All matching args are removed from the list.
-- All remaining arguments are parsed by luaunit.
function runner.parse_args(args)
    local result = {paths = {}}

    local i = 1
    while i <= #args do
        local arg = args[i]
        if OPTIONS[arg] then
            OPTIONS[arg](result)
            table.remove(args, i)
        -- If argument contains / then it's treated as file path.
        -- This assumption to support luaunit's test names along with file paths.
        elseif arg:find('/') then
            table.insert(result.paths, arg)
            table.remove(args, i)
        else
            i = i + 1
        end
    end

    return result
end

return runner
