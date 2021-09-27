local ROCK_VERSION = require('luatest.VERSION')

-- See directory junitxml for more information about the junit format
local Output = require('luatest.output.generic'):new_class()

-- Escapes string for XML attributes
function Output.xml_escape(str)
    return string.gsub(str, '.', {
        ['&'] = "&amp;",
        ['"'] = "&quot;",
        ["'"] = "&apos;",
        ['<'] = "&lt;",
        ['>'] = "&gt;",
    })
end

-- Escapes string for CData section
function Output.xml_c_data_escape(str)
    return string.gsub(str, ']]>', ']]&gt;')
end

function Output.node_status_xml(node)
    if node:is('error') then
        return table.concat(
            {'            <error type="', Output.xml_escape(node.message), '">\n',
             '                <![CDATA[', Output.xml_c_data_escape(node.trace),
             ']]></error>\n'})
    elseif node:is('fail') then
        return table.concat(
            {'            <failure type="', Output.xml_escape(node.message), '">\n',
             '                <![CDATA[', Output.xml_c_data_escape(node.trace),
             ']]></failure>\n'})
    elseif node:is('skip') then
        return table.concat({'            <skipped>', Output.xml_escape(node.message or ''),'</skipped>\n'})
    end
    return '            <passed/>\n' -- (not XSD-compliant! normally shouldn't get here)
end

function Output.mt:start_suite()
    self.output_file_name = assert(self.runner.output_file_name)
    -- open xml file early to deal with errors
    if string.sub(self.output_file_name,-4) ~= '.xml' then
        self.output_file_name = self.output_file_name..'.xml'
    end
    self.fd = io.open(self.output_file_name, "w")
    if self.fd == nil then
        error("Could not open file for writing: "..self.output_file_name)
    end

    print('# XML output to '..self.output_file_name)
    print('# Started on ' .. os.date(nil, self.result.start_time))
end

function Output.mt:start_group(group) -- luacheck: no unused
    print('# Starting group: ' .. group.name)
end

function Output.mt:start_test(test) -- luacheck: no unused
    print('# Starting test: ' .. test.name)
end

function Output.mt:update_status(node) -- luacheck: no unused
    if node:is('fail') or node:is('xsuccess') then
        print('#   Failure: ' .. node.message:gsub('\n', '\n#   '))
        -- print('# ' .. node.trace)
    elseif node:is('error') then
        print('#   Error: ' .. node.message:gsub('\n', '\n#   '))
        -- print('# ' .. node.trace)
    end
end

function Output.mt:end_suite()
    print('# ' .. self:status_line())

    -- XML file writing
    self.fd:write('<?xml version="1.0" encoding="UTF-8" ?>\n')
    self.fd:write('<testsuites>\n')
    self.fd:write(string.format(
        '    <testsuite name="luatest" id="00001" package="" hostname="localhost" tests="%d" timestamp="%s" ' ..
        'time="%0.3f" errors="%d" failures="%d" skipped="%d">\n',
        #self.result.tests.all - #self.result.tests.skip, os.date('%Y-%m-%dT%H:%M:%S', self.result.start_time),
        self.result.duration, #self.result.tests.error, #self.result.tests.fail + #self.result.tests.xsuccess,
        #self.result.tests.skip
    ))
    self.fd:write("        <properties>\n")
    self.fd:write(string.format('            <property name="Lua Version" value="%s"/>\n', _VERSION))
    self.fd:write(string.format('            <property name="luatest Version" value="%s"/>\n', ROCK_VERSION))
    -- XXX please include system name and version if possible
    self.fd:write("        </properties>\n")

    for _, node in ipairs(self.result.tests.all) do
        self.fd:write(string.format('        <testcase group="%s" name="%s" time="%0.3f">\n',
            node.group.name or '', node.name, node.duration))
        if not node:is('success') then
            self.fd:write(self.class.node_status_xml(node))
        end
        self.fd:write('        </testcase>\n')
    end

    -- Next two lines are needed to validate junit ANT xsd, but really not useful in general:
    self.fd:write('    <system-out/>\n')
    self.fd:write('    <system-err/>\n')

    self.fd:write('    </testsuite>\n')
    self.fd:write('</testsuites>\n')
    self.fd:close()
end

return Output
