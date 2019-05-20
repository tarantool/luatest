package = 'luatest'
version = 'scm-0.1.0'
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
}
build = {
    type = 'builtin',
    modules = {}
}
