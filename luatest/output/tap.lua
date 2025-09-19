local utils = require('luatest.utils')
-- For a good reference for TAP format, check: http://testanything.org/tap-specification.html
local Output = require('luatest.output.generic'):new_class()

function Output.mt:start_suite()
    print("TAP version 13")
    print("1.."..self.result.selected_count)
    print('# Started on ' .. os.date(nil, self.result.start_time))
end

function Output.mt:start_group(group) -- luacheck: no unused
    print('# Starting group: ' .. group.name)
end

function Output.mt:update_status(node)
    if node:is('xfail') then
        return
    end

    if node:is('skip') then
        io.stdout:write("ok ", node.serial_number, "\t# SKIP ", node.message or '', "\n")
        return
    end

    io.stdout:write("not ok ", node.serial_number, "\t", node.name, "\n")
    local prefix = '#   '
    if self.verbosity > self.class.VERBOSITY.QUIET then
        print(prefix .. node.message:gsub('\n', '\n' .. prefix))
    end
    if (node:is('fail') or node:is('error')) and self.verbosity >= self.class.VERBOSITY.VERBOSE then
        print(prefix .. node.trace:gsub('\n', '\n' .. prefix))
        if node.locals ~= nil then
            print(prefix .. 'locals:')
            print(prefix .. node.locals:gsub('\n', '\n' .. prefix))
        end
        if utils.table_len(node.servers) > 0 then
            print(prefix .. 'artifacts:')
            for _, server in pairs(node.servers) do
                print(('%s\t%s -> %s'):format(prefix, server.alias, server.artifacts))
            end
        end
    end
end

function Output.mt:end_test(node) -- luacheck: no unused
    if node:is('success') then
        io.stdout:write("ok     ", node.serial_number, "\t", node.name, "\n")
    end
    if node:is('xfail') then
        io.stdout:write("ok     ", node.serial_number, "\t# XFAIL ", node.message or '', "\n")
    end
end

function Output.mt:end_suite()
    print('# ' .. self:status_line())
end

return Output
