local errno = require('errno')
local digest = require('digest')
local fio = require('fio')
local fun = require('fun')
local yaml = require('yaml')

local utils = {}

-- Helper to override methods.
--
--     utils.patch(target, 'method_name', function(super) return function(...)
--       print('from patched method')
--       super(...)
--     end end)
function utils.patch(object, name, fn)
    local super = assert(object[name], 'Original function is not defined: ' .. name)
    object[name] = fn(super)
end

-- Merges multiple maps.
function utils.merge(...)
    return fun.chain(...):tomap()
end

-- Pretty traceback for error.
function utils.traceback(err, skip)
    if type(err) ~= 'string' then
        err = yaml.encode(err)
    end
    return debug.traceback(err, 2 + (skip or 0)) .. '\n'
end

-- Default value for rescue.
local function bypass_error(err)
    return err
end

-- Reraises error but calls `ensure` in both cases of success and failure.
function utils.reraise_and_ensure(fn, rescue, ensure)
    local result = {xpcall(fn, rescue or bypass_error)}
    if ensure then
        ensure()
    end
    if result[1] then
        return unpack(result, 2)
    else
        return error(result[2])
    end
end

local error_class_name = 'LuatestError'

function utils.luatest_error(status, message, level)
    local _
    _, message = pcall(error, message, (level or 1) + 2)
    error({class = error_class_name, status = status, message = message})
end

function utils.is_luatest_error(err)
    return type(err) == 'table' and err.class == error_class_name
end

-- Check if line of stack trace comes from inside luatest.
local function is_luatest_internal_line(s)
    return s:find('[/\\]luatest[/\\]') or s:find('bin[/\\]luatest')
end

function utils.strip_luatest_trace(trace)
    local lines = trace:split('\n')
    local result = {lines[1]} -- always keep 1st line
    local keep = true
    for i = 2, table.maxn(lines) do
        local line = lines[i]
        -- `[C]:` lines don't change context
        if not line:find('^%s+%[C%]:') then
            keep = not is_luatest_internal_line(line)
        end
        if keep then
            table.insert(result, line)
        end
    end
    return table.concat(result, '\n')
end

function utils.randomize_table(t)
    -- randomize the item orders of the table t
    for i = #t, 2, -1 do
        local j = math.random(i)
        if i ~= j then
            t[i], t[j] = t[j], t[i]
        end
    end
end

-- Run `expr` through the inclusion and exclusion rules defined in patterns
-- and return true if expr shall be included, false for excluded.
-- Inclusion pattern are defined as normal patterns, exclusions
-- patterns start with `!` and are followed by a normal pattern
function utils.pattern_filter(patterns, expr)
    -- nil = UNKNOWN (not matched yet), true = ACCEPT, false = REJECT
    local result = nil
    -- true if no explicit "include" is found, set to false otherwise
    local default = true

    for _, pattern in ipairs(patterns or {}) do
        local exclude = pattern:sub(1, 1) == '!'
        if exclude then
            pattern = pattern:sub(2)
        else
            -- at least one include pattern specified, a match is required
            default = false
        end

        if string.find(expr, pattern) then
            -- set result to false when excluding, true otherwise
            result = not exclude
        end
    end

    if result == nil then
        result = default
    end
    return result
end

function utils.split_test_name(test_name)
    local test_name_parts = string.split(test_name, '.')
    return test_name_parts, #test_name_parts
end

function utils.table_len(t)
    local counter = 0
    for _, _ in pairs(t) do
        counter = counter + 1
    end
    return counter
end

function utils.upvalues(fn)
    local ret = {}
    for i = 1, debug.getinfo(fn, 'u').nups do
        ret[i] = debug.getupvalue(fn, i)
    end

    return ret
end

function utils.get_fn_location(fn)
    local fn_details = debug.getinfo(fn)
    local fn_source = fn_details.source:split('/')
    return ('%s:%s'):format(fn_source[#fn_source], fn_details.linedefined)
end

function utils.generate_id(length, urlsafe)
    if not length then length = 9 end
    if urlsafe == nil then urlsafe = true end
    return digest.base64_encode(digest.urandom(length), {urlsafe = urlsafe})
end

function utils.version(major, minor, patch)
    return {
        major = major or 0,
        minor = minor or 0,
        patch = patch or 0,
    }
end

function utils.get_tarantool_version()
    local version = require('tarantool').version
    version = version:split('.')
    local major = tonumber(version[1]:match('%d+'))
    local minor = tonumber(version[2]:match('%d+'))
    local patch = tonumber(version[3]:match('%d+'))
    return utils.version(major, minor, patch)
end

function utils.version_ge(version1, version2)
    if version1.major ~= version2.major then
        return version1.major > version2.major
    elseif version1.minor ~= version2.minor then
        return version1.minor > version2.minor
    else
        return version1.patch >= version2.patch
    end
end

function utils.is_tarantool_binary(path)
    return path:find('^.*/tarantool[^/]*$') ~= nil
end

--- Search a string pattern in the a log file.
--
-- @string pattern String pattern to search in the log file.
-- @number[opt] bytes_num Number of bytes to read from the log file.
-- @tab[opt] opts
-- @bool[opt] opts.reset Reset the result when `Tarantool %d+.%d+.%d+-.*%d+-g.*`
--   pattern is found, which means that the server was restarted.
--   Defaults to `true`.
-- @string[opt] opts.filename Path to the the log file.
--   Defaults to `box.cfg.log`.
-- @return string|nil
function utils.grep_log(pattern, bytes_num, opts)
    local options = opts or {}
    local reset = options.reset or true
    local filename = options.filename
    local file = fio.open(filename, {'O_RDONLY', 'O_NONBLOCK'})

    local function fail(msg)
        local err = errno.strerror()
        if file ~= nil then
            file:close()
        end
        error(string.format('%s: %s: %s', msg, filename, err))
    end

    if file == nil then
        fail('Failed to open log file')
    end

    io.flush() -- attempt to flush stdout == log fd

    local filesize = file:seek(0, 'SEEK_END')
    if filesize == nil then
        fail('Failed to get log file size')
    end

    local bytes = bytes_num or 65536 -- don't read the whole log -- it can be huge
    bytes = bytes > filesize and filesize or bytes
    if file:seek(-bytes, 'SEEK_END') == nil then
        fail('Failed to seek log file')
    end

    local found, buf
    repeat -- read file in chunks
        local s = file:read(2048)
        if s == nil then
            fail('Failed to read log file')
        end
        local pos = 1
        repeat -- split read string in lines
            local endpos = string.find(s, '\n', pos)
            endpos = endpos and endpos - 1 -- strip terminating \n
            local line = string.sub(s, pos, endpos)
            if endpos == nil and s ~= '' then
                -- Line doesn't end with \n or EOF, append it to buffer
                -- to be checked on next iteration.
                buf = buf or {}
                table.insert(buf, line)
            else
                if buf ~= nil then
                    -- Prepend line with buffered data.
                    table.insert(buf, line)
                    line = table.concat(buf)
                    buf = nil
                end
                if string.match(line, '> Tarantool %d+.%d+.%d+-.*%d+-g.*$') and reset then
                    found = nil -- server was restarted, reset the result
                else
                    found = string.match(line, pattern) or found
                end
            end
            pos = endpos and endpos + 2 -- jump to char after \n
        until pos == nil
    until s == ''

    file:close()

    return found
end

return utils
