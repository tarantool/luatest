include_files = {"**/*.lua", "*.rockspec", "*.luacheckrc"}
exclude_files = {"lua_modules", ".luarocks", ".rocks", "luatest/luaunit.lua"}

max_line_length = 120

new_globals = {
    package = {fields = {
        'search',
    }},
}

new_read_globals = {
    'box',
    os = {fields = {
        'environ',
    }},
    table = {fields = {
        'copy',
    }},
}
