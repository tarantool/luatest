package = 'luatest'
version = 'scm-1'
source = {
    url = 'git://github.com/tarantool/luatest.git',
    branch = 'master',
}
description = {
    summary = 'Tool for testing tarantool applications',
    homepage = 'https://github.com/tarantool/luatest',
    license = 'MIT',
}
dependencies = {
    'lua >= 5.1',
    'checks >= 3.0.0',
}
external_dependencies = {
    TARANTOOL = {
        header = 'tarantool/module.h',
    },
}
build = {
    type = 'cmake',
    variables = {
        TARANTOOL_INSTALL_LUADIR = '$(LUADIR)',
        TARANTOOL_INSTALL_BINDIR = '$(BINDIR)',
        LUAROCKS = 'true',
    }
}
