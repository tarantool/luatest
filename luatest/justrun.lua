--- Simple Tarantool runner and output catcher.
--
-- Sometimes it is necessary to run tarantool with particular arguments and
-- verify its output. `luatest.server` provides a supervisor like
-- interface: an instance is started, calls box.cfg() and we can
-- communicate with it using net.box. Another helper in tarantool/tarantool,
-- `test.interactive_tarantool`, aims to solve all the problems around
-- readline console and also provides ability to communicate with the
-- instance interactively.
--
-- However, there is nothing like 'just run tarantool with given args and
-- give me its output'.
--
-- @module luatest.justrun

local checks = require('checks')
local fun = require('fun')
local json = require('json')
local fiber = require('fiber')

local log = require('luatest.log')

local justrun = {}

local function collect_stderr(ph)
    local f = fiber.new(function()
        local fiber_name = "child's stderr collector"
        fiber.name(fiber_name, {truncate = true})

        local chunks = {}

        while true do
            local chunk, err = ph:read({stderr = true})
            if chunk == nil then
                log.warn('%s: got error, exiting: %s', fiber_name, err)
                break
            end
            if chunk == '' then
                log.info('%s: got EOF, exiting', fiber_name)
                break
            end
            table.insert(chunks, chunk)
        end

        -- Glue all chunks, strip trailing newline.
        return table.concat(chunks):rstrip()
    end)
    f:set_joinable(true)
    return f
end

local function cancel_stderr_fiber(stderr_fiber)
    if stderr_fiber == nil then
        return
    end
    stderr_fiber:cancel()
end

local function join_stderr_fiber(stderr_fiber)
    if stderr_fiber == nil then
        return
    end
    return select(2, assert(stderr_fiber:join()))
end

--- Run tarantool in given directory with given environment and
-- command line arguments and catch its output.
--
-- Expects JSON lines as the output and parses it into an array
-- (it can be disabled using `nojson` option).
--
-- Options:
--
-- - nojson (boolean, default: false)
--
--   Don't attempt to decode stdout as a stream of JSON lines,
--   return as is.
--
-- - stderr (boolean, default: false)
--
--   Collect stderr and place it into the `stderr` field of the
--   return value
--
-- - quote_args (boolean, default: false)
--
--   Quote CLI arguments before concatenating them into a shell
--   command.
--
-- @string dir Directory where the process will run.
-- @tparam table env Environment variables for the process.
-- @tparam table args Options that will be passed when the process starts.
-- @tparam[opt] table opts Custom options: nojson, stderr and quote_args.
-- @treturn table
function justrun.tarantool(dir, env, args, opts)
    checks('string', 'table', 'table', '?table')
    opts = opts or {}

    local popen = require('popen')

    -- Prevent system/user inputrc configuration file from
    -- influencing testing code.
    env['INPUTRC'] = '/dev/null'

    local tarantool_exe = arg[-1]
    -- Use popen.shell() instead of popen.new() due to lack of
    -- cwd option in popen (gh-5633).
    local env_str = table.concat(fun.iter(env):map(function(k, v)
        return ('%s=%q'):format(k, v)
    end):totable(), ' ')
    local args_str = table.concat(fun.iter(args):map(function(v)
        return opts.quote_args and ('%q'):format(v) or v
    end):totable(), ' ')
    local command = ('cd %s && %s %s %s'):format(dir, env_str, tarantool_exe,
                                                 args_str)
    log.info('Running a command: %s', command)
    local mode = opts.stderr and 'rR' or 'r'
    local ph = popen.shell(command, mode)

    local stderr_fiber
    if opts.stderr then
        stderr_fiber = collect_stderr(ph)
    end

    -- Read everything until EOF.
    local chunks = {}
    while true do
        local chunk, err = ph:read()
        if chunk == nil then
            cancel_stderr_fiber(stderr_fiber)
            ph:close()
            error(err)
        end
        if chunk == '' then -- EOF
            break
        end
        table.insert(chunks, chunk)
    end

    local exit_code = ph:wait().exit_code
    local stderr = join_stderr_fiber(stderr_fiber)
    ph:close()

    -- If an error occurs, discard the output and return only the
    -- exit code. However, return stderr.
    if exit_code ~= 0 then
        return {
            exit_code = exit_code,
            stderr = stderr,
        }
    end

    -- Glue all chunks, strip trailing newline.
    local res = table.concat(chunks):rstrip()
    log.info('Command output:\n%s', res)

    -- Decode JSON object per line into array of tables (if
    -- `nojson` option is not passed).
    local decoded
    if opts.nojson then
        decoded = res
    else
        decoded = fun.iter(res:split('\n')):map(json.decode):totable()
    end

    return {
        exit_code = exit_code,
        stdout = decoded,
        stderr = stderr,
    }
end

return justrun
