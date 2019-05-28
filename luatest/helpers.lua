local clock = require('clock')
local fiber = require('fiber')
local log = require('log')

local helpers = {}

local function repeat_value(value, length)
    if type(value) == 'string' then
        return string.rep(value, length / value:len())
    else
        return string.format('%0' .. length .. 'd', value)
    end
end

-- Generates uuids from its 5 parts.
-- Strings are repeated and numbers are padded to match required part length.
-- If number of arguments is less than 5 then first and last arguments are used
-- for corresponding parts, missing parts are set to 0.
--
--     'aaaaaaaa-0000-0000-0000-000000000000' == uuid('a')
--     'abababab-0000-0000-0000-000000000001' == uuid('ab', 1)
--     '00000001-0002-0000-0000-000000000003' == uuid(1, 2, 3)
--     '11111111-2222-0000-0000-333333333333' == uuid('1', '2', '3')
--     '12121212-3434-5656-7878-909090909090' == uuid('12', '34', '56', '78', '90')
function helpers.uuid(a, ...)
    local input = {...}
    local e = table.remove(input)
    local b, c, d = unpack(input)
    return table.concat({
        repeat_value(a, 8),
        repeat_value(b or 0, 4),
        repeat_value(c or 0, 4),
        repeat_value(d or 0, 4),
        repeat_value(e or 0, 12),
    }, '-')
end

helpers.RETRYING_TIMEOUT = 5
helpers.RETRYING_DELAY = 0.1

-- Keep calling fn until it returns without error.
-- Throws last error if config.timeout is elapsed.
-- Default options are taken from helpers.RETRYING_TIMEOUT and helpers.RETRYING_DELAY.
--
--     helpers.retrying({}, fn, arg1, arg2)
--     helpers.retrying({timeout = 2, delay = 0.5}, fn, arg1, arg2)
function helpers.retrying(config, fn, ...)
    local timeout = config.timeout or helpers.RETRYING_TIMEOUT
    local delay = config.delay or helpers.RETRYING_DELAY
    local started_at = clock.time()
    while true do
        local ok, result = pcall(fn, ...)
        if ok then
            return result
        end
        log.debug('Retrying in ' .. delay .. ' sec. due to error:')
        log.debug(result)
        if (clock.time() - started_at) > timeout then
            error(result)
        end
        fiber.sleep(delay)
    end
end

return helpers
