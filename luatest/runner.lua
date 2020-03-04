local capturing = require('luatest.capturing')
local hooks = require('luatest.hooks')
local loader = require('luatest.loader')
local utils = require('luatest.utils')

local ROCK_VERSION = require('luatest.VERSION')

local runner = {
    SOURCE_DIR = 'test',
    HELPER_MODULE = 'test.helper',
}

-- Apply extensions to luaunit's runner.
local function patch_luatest_runner(Runner)
    if Runner.mt.bootstrap then -- already pathced
        return
    end

    function Runner.mt:bootstrap()
        if package.search(runner.HELPER_MODULE) then
            require(runner.HELPER_MODULE)
        end

        local paths = self.paths or {runner.SOURCE_DIR}
        local load_tests = self.load_tests or loader.require_tests
        for _, path in pairs(paths) do
            load_tests(path)
        end

        self.groups = self.luatest.groups
    end

    utils.patch(Runner.mt, 'run_suite', function(super) return function(self)
        self:bootstrap()
        return super(self)
    end end)

    hooks.patch_runner(Runner)
    capturing(Runner)
end

function runner.run(args, options)
    args = args or rawget(_G, 'arg')
    options = options or {}
    options.luatest = options.luatest or require('luatest')
    local Runner = options.luatest.LuaUnit
    patch_luatest_runner(Runner)

    local _, code = xpcall(function()
        options = utils.merge(Runner.parse_cmd_line(args), options)

        if options.help then
            print(options.luatest.USAGE)
            return 0
        elseif options.version then
            print('luatest v' .. ROCK_VERSION)
            return 0
        end

        if options.coverage_report then
            require('luatest.coverage_utils').enable()
        end

        return Runner.run(options)
    end, function(err)
        io.stderr:write(utils.traceback(err))
        return -1
    end)
    return code
end

return runner
