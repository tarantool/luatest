local capturing = require('luatest.capturing')
local Capture = require('luatest.capture')
local hooks = require('luatest.hooks')
local loader = require('luatest.loader')
local utils = require('luatest.utils')

local runner = {
    SOURCE_DIR = 'test',
    HELPER_MODULE = 'test.helper',
}

-- Adds functions to luatest which can be patched in `hooks` or `capturing` module.
local function patch_luatest(lu)
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

function runner.run(args, options)
    args = args or rawget(_G, 'arg')
    options = options or {}
    local lu = options.luaunit or require('luatest.luaunit')
    patch_luatest(lu)

    local _, code = xpcall(function()
        options = utils.merge({
            enable_capture = true,
        }, lu.LuaUnit.parse_cmd_line(args), options)

        local capture = options.capture or Capture:new()

        hooks(lu)
        if options.enable_capture then
            capturing(lu, capture)
        end

        if options.coverage_report then
            require('luatest.coverage_utils').enable()
        end

        lu.load_tests(options)
        return lu.LuaUnit.run(options)
    end, function(err)
        if err.type == 'LUAUNIT_EXIT' then
            return err.code
        else
            lu.print_error(err)
            return -1
        end
    end)
    return code
end

return runner
