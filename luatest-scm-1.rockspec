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
build = {
    type = 'none',
    install = {
        lua = {
            ['luarocks.test.luatest'] = 'luarocks/test/luatest.lua',
            ['luatest'] = 'luatest/init.lua',
            ['luatest.capture'] = 'luatest/capture.lua',
            ['luatest.capturing'] = 'luatest/capturing.lua',
            ['luatest.helpers'] = 'luatest/helpers.lua',
            ['luatest.hooks'] = 'luatest/hooks.lua',
            ['luatest.loader'] = 'luatest/loader.lua',
            ['luatest.luaunit'] = 'luatest/luaunit.lua',
            ['luatest.process'] = 'luatest/process.lua',
            ['luatest.runner'] = 'luatest/runner.lua',
            ['luatest.sandboxed_runner'] = 'luatest/sandboxed_runner.lua',
            ['luatest.server'] = 'luatest/server.lua',
            ['luatest.utils'] = 'luatest/utils.lua',
        },
        bin = {
            ['luatest'] = 'bin/luatest',
        },
    }
}
