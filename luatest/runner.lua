--- Class to run test suite.
--
-- @classmod luatest.runner

local clock = require('clock')
local fio = require('fio')

local assertions = require('luatest.assertions')
local capturing = require('luatest.capturing')
local Class = require('luatest.class')
local GenericOutput = require('luatest.output.generic')
local hooks = require('luatest.hooks')
local loader = require('luatest.loader')
local pp = require('luatest.pp')
local Server = require('luatest.server')
local sorted_pairs = require('luatest.sorted_pairs')
local TestInstance = require('luatest.test_instance')
local utils = require('luatest.utils')

local ROCK_VERSION = require('luatest.VERSION')

local Runner = Class.new({
    HELPER_MODULE = 'test.helper',
})

-- Default options
Runner.mt.output = 'text'
Runner.mt.verbosity = GenericOutput.VERBOSITY.DEFAULT
Runner.mt.shuffle = 'none'
Runner.mt.tests_path = 'test'

--- Main entrypoint to run test suite.
--
-- @tab[opt=_G.args] args List of CLI arguments
-- @param[opt] options
-- @int[opt] options.verbosity
-- @bool[opt=false] options.fail_fast
-- @string[opt] options.output_file_name Filename for JUnit report
-- @int[opt] options.exe_repeat Times to repeat each test
-- @int[opt] options.exe_repeat_group Times to repeat each group of tests
-- @tab[opt] options.tests_pattern Patterns to filter tests
-- @tab[opt] options.tests_names List of test names or groups to run
-- @tab[opt={'test'}] options.paths List of directories to load tests from.
-- @func[opt] options.load_tests Function to load tests. Called once for every item in `paths`.
-- @string[opt='none'] options.shuffle Shuffle method (none, all, group)
-- @int[opt] options.seed Random seed for shuffle
-- @string[opt='text'] options.output Output formatter (text, tap, junit, nil)
function Runner.run(args, options)
    args = args or rawget(_G, 'arg')
    options = options or {}
    options.luatest = options.luatest or require('luatest')

    local _, code = xpcall(function()
        if package.search(Runner.HELPER_MODULE) then
            require(Runner.HELPER_MODULE)
        end
        options = utils.merge(options.luatest.configure(), Runner.parse_cmd_line(args), options)

        if options.help then
            print(Runner.USAGE)
            return 0
        elseif options.version then
            print('luatest v' .. ROCK_VERSION)
            return 0
        end

        return Runner:from(options):run()
    end, function(err)
        io.stderr:write(utils.traceback(err))
        return -1
    end)
    return code
end

Runner.USAGE = [[Usage: luatest [options] [path ...] [group ...]

Positional arguments:
  path1 path2 ...:        Run tests from specified paths.
                          Considered as a path only if it contains `/`,
                          otherwise, it will be considered as a group name.
                          Examples: `luatest ./test.lua` or `luatest dir/`
  group1 group2 ...:      Run tests from specified groups.
  group.test ...:         Run one test from the group.

Options:
  -h, --help:             Print this help
  --version:              Print version information
  -v, --verbose:          Increase verbosity
  -q, --quiet:            Set verbosity to minimum
  -c                      Disable capture
  -b                      Print full backtrace (don't remove luatest frames)
  -e, --error:            Stop on first error
  -f, --failure:          Stop on first failure or error
  --shuffle VALUE:        Set execution order:
                            - group[:seed] - shuffle tests within group
                            - all[:seed] - shuffle all tests
                            - none - sort tests within group by line number (default)
  --seed NUMBER:          Set seed value for shuffler
  -o, --output OUTPUT:    Set output type to OUTPUT
                          Possible values: text, tap, junit, nil
  -n, --name NAME:        For junit only, mandatory name of xml file
  -r, --repeat NUM:       Execute all tests NUM times, e.g. to trig the JIT
  -R, --repeat-group NUM: Execute all groups of tests NUM times, e.g. to trig the JIT
  -p, --pattern PATTERN:  Execute all test names matching the Lua PATTERN
                          May be repeated to include several patterns
                          Make sure you escape magic chars like +? with %
  -x, --exclude PATTERN:  Exclude all test names matching the Lua PATTERN
                          May be repeated to exclude several patterns
                          Make sure you escape magic chars like +? with %
  --coverage:             Use luacov to collect code coverage.
  --no-clean:             Disable the var directory (default: /tmp/t) deletion before
                          running tests.
]]

function Runner.parse_cmd_line(args)
    local result = {}

    local arg_n = 0
    local function next_arg(optional)
        arg_n = arg_n + 1
        local arg = args and args[arg_n]
        if arg == nil and not optional then
            error('Missing argument after ' .. args[#args])
        end
        return arg
    end

    while true do
        local arg = next_arg(true)
        if arg == nil then
            break
        elseif arg == '--help' or arg == '-h' then
            result.help = true
        elseif arg == '--version' then
            result.version = true
        elseif arg == '--verbose' or arg == '-v' then
            result.verbosity = GenericOutput.VERBOSITY.VERBOSE
        elseif arg == '--quiet' or arg == '-q' then
            result.verbosity = GenericOutput.VERBOSITY.QUIET
        elseif arg == '--fail-fast' or arg == '-f' then
            result.fail_fast = true
        elseif arg == '--shuffle' or arg == '-s' then
            local seed
            result.shuffle, seed = unpack(next_arg():split(':'))
            if seed then
                result.seed = tonumber(seed) or error('Invalid seed value')
            end
        elseif arg == '--seed' then
            result.seed = tonumber(next_arg()) or error('Invalid seed value')
        elseif arg == '--output' or arg == '-o' then
            result.output = next_arg()
        elseif arg == '--name' or arg == '-n' then
            result.output_file_name = next_arg()
        elseif arg == '--repeat' or arg == '-r' then
            result.exe_repeat = tonumber(next_arg())
            if result.exe_repeat == nil or result.exe_repeat < 1 then
                error(('Invalid value for %s option. Positive integer required'):format(arg))
            end
        elseif arg == '--repeat-group' or arg == '-R' then
            result.exe_repeat_group = tonumber(next_arg())
            if result.exe_repeat_group == nil or result.exe_repeat_group <= 0 then
                error(('Invalid value for %s option. Positive integer required.'):format(arg))
            end
        elseif arg == '--pattern' or arg == '-p' then
            result.tests_pattern = result.tests_pattern or {}
            table.insert(result.tests_pattern, next_arg())
        elseif arg == '--exclude' or arg == '-x' then
            result.tests_pattern = result.tests_pattern or {}
            table.insert(result.tests_pattern, '!' .. next_arg())
        elseif arg == '-b' then
            result.full_backtrace = true
        elseif arg == '-c' then
            result.enable_capture = false
        elseif arg == '--coverage' then
            result.coverage_report = true
        elseif arg == '--no-clean' then
            result.no_clean = true
        elseif arg:sub(1,1) == '-' then
            error('Unknown option: ' .. arg)
        elseif arg:find('/') then
            -- If the argument contains '/' then it's treated as a file path.
            -- This assumption to support test names along with file paths.
            if not fio.path.exists(arg) then
                error(string.format("Path '%s' does not exist", arg))
            end
            result.paths = result.paths or {}
            table.insert(result.paths, arg)
        else
            result.test_names = result.test_names or {}
            table.insert(result.test_names, arg)
        end
    end

    -- end_test will repeat test name for prettier output when capture
    -- is disabled.
    if result.enable_capture == false
    and result.verbosity == GenericOutput.VERBOSITY.VERBOSE then
        result.verbosity = GenericOutput.VERBOSITY.REPEAT
    end

    return result
end

--- Split `some.group.name.method` into `some.group.name` and `method`.
-- Returns `nil, input` if input value does not have a dot.
function Runner.split_test_method_name(someName)
    local separator
    for i = #someName, 1, -1 do
        if someName:sub(i, i) == '.' then
            separator = i
            break
        end
    end
    if separator then
        return someName:sub(1, separator - 1), someName:sub(separator + 1)
    end
    return nil, someName
end

--- Check that string matches the name of a test method.
-- Default rule is that is starts with 'test'
function Runner.is_test_name(s)
    return string.sub(s, 1, 4):lower() == 'test'
end

function Runner.filter_tests(tests, patterns)
    local result = {[true] = {}, [false] = {}}
    for _, test in ipairs(tests) do
        table.insert(result[utils.pattern_filter(patterns, test.name)], test)
    end
    return result
end

--- Exrtact all test methods from group.
function Runner:expand_group(group)
    local result = {}
    for method_name in sorted_pairs(group) do
        if self.is_test_name(method_name) then
            table.insert(result, TestInstance:build(group, method_name))
        end
    end
    return result
end

--- Instance methods
-- @section methods

function Runner.mt:initialize()
    if self.coverage_report then
        require('luatest.coverage_utils').enable()
    end

    if self.shuffle == 'group' or self.shuffle == 'all' then
        if not self.seed then
            math.randomseed(os.time())
            self.seed = math.random(1000, 10000)
        end
    elseif self.shuffle ~= 'none' then
        error('Invalid shuffle value')
    end

    self.output = self.output:lower()
    if self.output == 'junit' and self.output_file_name == nil then
        error('With junit output, a filename must be supplied with -n or --name')
    end
    local ok, output_class = pcall(require, 'luatest.output.' .. self.output)
    assert(ok, 'Can not load output module: ' .. self.output)
    self.output = output_class:new(self)

    self.paths = self.paths or {self.tests_path}
end

function Runner.mt:bootstrap()
    local load_tests = self.load_tests or loader.require_tests
    for _, path in pairs(self.paths) do
        load_tests(path)
    end
    self.groups = self.luatest.groups
end

function Runner.mt:cleanup()
    if not self.no_clean then
        fio.rmtree(Server.vardir)
    end
end

function Runner.mt:run()
    self:bootstrap()
    local filtered_list = self.class.filter_tests(self:find_tests(), self.tests_pattern)
    self:start_suite(#filtered_list[true], #filtered_list[false])
    self:cleanup()
    self:run_tests(filtered_list[true])
    self:end_suite()
    if self.result.aborted then
        print("Test suite ABORTED because of --fail-fast option")
        return -2
    end
    return self.result.failures_count
end

function Runner.mt:start_suite(selected_count, not_selected_count)
    self.result = {
        selected_count = selected_count,
        not_selected_count = not_selected_count,
        start_time = clock.time(),
        tests = {
            all = {},
            success = {},
            fail = {},
            error = {},
            skip = {},
            xfail = {},
            xsuccess = {},
        },
    }
    self.output.result = self.result
    self.output:start_suite()
end

function Runner.mt:start_group(group)
    self.output:start_group(group)
end

function Runner.mt:start_test(test)
    test.serial_number = #self.result.tests.all + 1
    test.start_time = clock.time()
    table.insert(self.result.tests.all, test)
    self.output:start_test(test)
end

function Runner.mt:update_status(node, err)
    -- "err" is expected to be a table / result from protected_call()
    if err.status == 'success' then
        return
    -- if the node is already in failure/error, just don't report the new error (see above)
    elseif not node:is('success') then
        return
    elseif err.status == 'fail' or err.status == 'error' or err.status == 'skip'
        or err.status == 'xfail' or err.status == 'xsuccess' then
        node:update_status(err.status, err.message, err.trace)
        if utils.table_len(node.servers) > 0 then
            for _, server in pairs(node.servers) do
                server:save_artifacts()
            end
        end
    else
        error('No such status: ' .. pp.tostring(err.status))
    end
    self.output:update_status(node)
end

function Runner.mt:end_test(node)
    node.duration = clock.time() - node.start_time
    node.start_time = nil
    self.output:end_test(node)

    if node:is('error') or node:is('fail') or node:is('xsuccess') then
        self.result.aborted = self.fail_fast
    elseif not node:is('success') and not node:is('skip')
        and not node:is('xfail') then
        error('No such node status: ' .. pp.tostring(node.status))
    end
end

function Runner.mt:end_group(group)
    self.output:end_group(group)
end

function Runner.mt:end_suite()
    if self.result.duration then
        error('Suite was already ended')
    end
    self.result.duration = clock.time() - self.result.start_time
    for _, test in pairs(self.result.tests.all) do
        table.insert(self.result.tests[test.status], test)
    end
    self.result.failures_count = #self.result.tests.fail + #self.result.tests.error + #self.result.tests.xsuccess
    self.output:end_suite()
end

function Runner.mt:protected_call(instance, method, pretty_name)
    local _, err = xpcall(function()
        method(instance)
        return {status = 'success'}
    end, function(e)
        -- transform error into a table, adding the traceback information
        local trace = debug.traceback('', 3):sub(2)
        if utils.is_luatest_error(e) then
            return {status = e.status, message = e.message, trace = trace}
        else
            return {status = 'error', message = e, trace = trace}
        end
    end)

    -- check if test was marked as xfail and reset xfail flag
    local xfail = assertions.private.is_xfail()

    if type(err.message) ~= 'string' then
        err.message = pp.tostring(err.message)
    end

    if (err.status == 'success' and not xfail) or err.status == 'skip' then
        err.trace = nil
        return err
    end

    if xfail and err.status ~= 'error' and err.status ~= 'skip' then
        err.status = 'x' .. err.status

        if err.status == 'xsuccess' then
            err.trace = ''
            err.message = type(xfail) == 'string' and xfail
            or 'Test expected to fail has succeeded. Consider removing xfail.'
        end

        return err
    end

    -- reformat / improve the stack trace
    if pretty_name then -- we do have the real method name
        err.trace = err.trace:gsub("in (%a+) 'method'", "in %1 '" .. pretty_name .. "'")
    end
    if not self.full_backtrace then
        err.trace = utils.strip_luatest_trace(err.trace)
    end

    return err
end

function Runner.mt:run_tests(tests_list)
    -- Make seed for ordering not affect other random numbers.
    math.randomseed(os.time())
    rawset(_G, 'current_test', {value = nil})
    for _ = 1, self.exe_repeat_group or 1 do
        local last_group
        for _, test in ipairs(tests_list) do
            if last_group ~= test.group then
                if last_group then
                    rawget(_G, 'current_test').value = nil
                    self:end_group(last_group)
                end
                self:start_group(test.group)
                last_group = test.group
            end
            rawget(_G, 'current_test').value = test
            self:run_test(test)
            if self.result.aborted then
                break
            end
        end
        if last_group then
            self:end_group(last_group)
        end
    end
end

function Runner.mt:run_test(test)
    self:start_test(test)
    self:invoke_test_function(test)
    self:end_test(test)
end

function Runner.mt:invoke_test_function(test)
    local err = self:protected_call(test.group, test.method, test.name)
    self:update_status(test, err)
end

function Runner.mt:find_test(groups, name)
    local group_name, method_name = self.class.split_test_method_name(name)
    assert(group_name and method_name, 'Invalid test name: ' .. name)
    local group = assert(groups[group_name], 'Group not found: ' .. group_name)
    return TestInstance:build(group, method_name)
end

function Runner.mt:find_tests()
    -- Set seed for ordering.
    if self.seed then
        math.randomseed(self.seed)
    end

    local result = {}

    for _, name in ipairs(self.test_names or self:all_test_names()) do
        local group = self.groups[name]
        if group then
            local fns = self.class:expand_group(group)
            if self.shuffle == 'group' then
                utils.randomize_table(fns)
            elseif self.shuffle == 'none' then
                table.sort(fns, function(a, b) return a.line < b.line end)
            end
            for _, x in pairs(fns) do
                table.insert(result, x)
            end
        else
            table.insert(result, self:find_test(self.groups, name))
        end
    end

    if self.shuffle == 'all' then
        utils.randomize_table(result)
    end

    return result
end

function Runner.mt:all_test_names()
    local result = {}
    for name in sorted_pairs(self.groups) do
        table.insert(result, name)
    end
    return result
end

hooks.patch_runner(Runner)
capturing(Runner)

return Runner
