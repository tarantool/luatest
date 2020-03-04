--- Tests group.
-- To add new example add function at key starting with `test`.
--
-- Group hooks run always when test group is changed.
-- So it may run multiple times when `--shuffle` option is used.
--
-- @classmod luatest.group
local Group = require('luatest.class').new()

local hooks = require('luatest.hooks')

local function find_closest_matching_frame(pattern)
    local level = 2
    while true do
        local info = debug.getinfo(level, 'S')
        if not info then
            return
        end
        local source = info.source
        if source:match(pattern) then
            return info
        end
        level = level + 1
    end
end

--- Instance methods
-- @section

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
--  For `test/a/b/c_d_test.lua` it will be `a.b.c_d`.
-- @return Group instance
function Group.mt:initialize(name)
    if not name then
        local pattern = '.*/test/(.+)_test%.lua'
        local info = assert(
            find_closest_matching_frame(pattern),
            "Can't derive test name from file name (it should match '.*/test/.*_test.lua')"
        )
        local test_filename = info.source:match(pattern)
        name = test_filename:gsub('/', '.')
    end
    if name:find('/') then
        error('Group name must not contain `/`: ' .. name)
    end
    self.name = name
    hooks.define_group_hooks(self)
end

return Group
