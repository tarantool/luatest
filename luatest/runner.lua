local luaunit = require('luatest.luaunit')

local hooks = require('luatest.hooks')
local capturing = require('luatest.capturing')
local Capture = require('luatest.capture')
local loader = require('luatest.loader')
local utils = require('luatest.utils')

local runner = {
    SOURCE_DIR = 'test',
    HELPER_MODULE = 'test.helper',
}

function runner:run(args, options)
    args = args or rawget(_G, 'arg')
    options = utils.reverse_merge(self.parse_args(args), options or {}, {
        path = self.SOURCE_DIR,
        luaunit = luaunit,
        capture = Capture:new(),
        enable_capture = true,
    })

    local lu = options.luaunit
    local capture = options.capture

    hooks(lu)
    if options.enable_capture then
        capturing(lu, capture)
    end

    lu.GLOBAL_TESTS = false
    local ok, result = capture:wrap(options.enable_capture, function()
        self:require_helper()
        local load_tests = options.load_tests or loader.require_tests
        if #options.paths > 0 then
            for _, path in pairs(options.paths) do
                load_tests(path)
            end
        else
            load_tests(self.SOURCE_DIR)
        end
        lu.run_before_suite()
    end)
    if ok then
        ok, result = capture:wrap(false, function() return lu.LuaUnit.run(unpack(args)) end)
    end
    ok = capture:wrap(options.enable_capture, function() lu.run_after_suite() end) and ok
    return ok and result or 1
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

function runner:require_helper()
    if package.search(self.HELPER_MODULE) then
        require(self.HELPER_MODULE)
    end
end

return runner
