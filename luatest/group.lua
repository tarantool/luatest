--- Tests group.
-- To add new example add function at key starting with `test`.
--
-- Group hooks run always when test group is changed.
-- So it may run multiple times when `--shuffle` option is used.
--
-- @classmod luatest.group
local Group = require('luatest.class').new()

local hooks = require('luatest.hooks')
local languages = require('luatest.languages')

-- Returns the capture of the first pattern matching the source of the
-- closest frame matched by any of the patterns.
local function find_closest_matching_frame(patterns)
    local level = 2
    while true do
        local info = debug.getinfo(level, 'S')
        if not info then
            return
        end
        local source = info.source
        for _, pattern in ipairs(patterns) do
            local capture = source:match(pattern)
            if capture then
                return capture
            end
        end
        level = level + 1
    end
end

--- Instance methods
-- @section methods

--- Add callback to run once before all tests in the group.
-- @function Group.mt.before_all
-- @param fn

--- Add callback to run once after all tests in the group.
-- @function Group.mt.after_all
-- @param fn

--- Add callback to run before each test in the group.
-- @function Group.mt.before_each
-- @param fn

--- Add callback to run after each test in the group.
-- @function Group.mt.after_each
-- @param fn

---
-- @string[opt] name Default name is inferred from caller filename when possible.
--  For `test/a/b/c_d_test.lua` it will be `a.b.c_d`. Files of active
--  languages (see @{luatest.languages}) work the same way:
--  `test/a/b/c_d_test.moon` gives `a.b.c_d` too.
-- @return Group instance
function Group.mt:initialize(name)
    if not name then
        local patterns = {'.*/test/(.+)_test%.lua'}
        local expected = {"'.*/test/.*_test.lua'"}
        for _, ext in ipairs(languages:extensions()) do
            if ext ~= 'lua' then
                table.insert(patterns, '.*/test/(.+)_test%.' .. ext:gsub('%-', '%%-') .. '$')
                table.insert(expected, ("'.*/test/.*_test.%s'"):format(ext))
            end
        end
        local test_filename = assert(
            find_closest_matching_frame(patterns),
            ("Can't derive test name from file name (it should match %s)"):format(
                table.concat(expected, ' or '))
        )
        name = test_filename:gsub('/', '.')
    end
    if name:find('/') then
        error('Group name must not contain `/`: ' .. name)
    end
    self.name = name
    hooks._define_group_hooks(self)
end

return Group
