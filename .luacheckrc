include_files = {"**/*.lua", "*.rockspec", "*.luacheckrc"}
exclude_files = {"lua_modules", ".luarocks", ".rocks", "luatest/luaunit.lua"}

max_line_length = 120

std = {
    read_globals = {
        '_G',
        'arg',
        'assert',
        'box',
        'collectgarbage',
        'debug',
        'dofile',
        'error',
        'getmetatable',
        'io',
        'ipairs',
        'loadstring',
        'math',
        'next',
        'os',
        'package',
        'pairs',
        'pcall',
        'print',
        'rawget',
        'rawset',
        'require',
        'select',
        'setfenv',
        'setmetatable',
        'string',
        'table',
        'tonumber',
        'tonumber64',
        'tostring',
        'type',
        'unpack',
        'xpcall',
    },
}
