local t = require('luatest')

local config_builder = require('luatest.cbuilder')
local utils = require('luatest.utils')

local DEFAULT_CONFIG = {
    credentials = {
        users = {
            client = {password = 'secret', roles = {'super'}},
            replicator = {password = 'secret', roles = {'replication'}},
        },
    },
    iproto = {
        advertise = {peer = {login = 'replicator'}},
        listen = {{uri = 'unix/:./{{ instance_name }}.iproto'}},
    },
    replication = {timeout = 0.1},
}

local function merge_config(base, diff)
    if type(base) ~= 'table' or type(diff) ~= 'table' then
        return diff
    end
    local result = table.copy(base)
    for k, v in pairs(diff) do
        result[k] = merge_config(result[k], v)
    end
    return result
end

local g = t.group()

g.test_default_config = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])
    t.assert_equals(config_builder:new():config(), DEFAULT_CONFIG)
    t.assert_equals(config_builder:new({}):config(), {})
end

g.test_set_global_option = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])
    local config = config_builder:new()
        :set_global_option('replication.timeout', 0.5)
        :set_global_option('console.enabled', false)
        :set_global_option('credentials.users.guest.privileges', {
            {permissions = {'read', 'write'}, spaces = {'src'}},
            {permissions = {'read', 'write'}, spaces = {'dest'}},
        })
        :config()
    t.assert_equals(config, merge_config(DEFAULT_CONFIG, {
        replication = {timeout = 0.5},
        console = {enabled = false},
        credentials = {
            users = {
                guest = {
                    privileges = {
                        {permissions = {'read', 'write'}, spaces = {'src'}},
                        {permissions = {'read', 'write'}, spaces = {'dest'}},
                    },
                },
            },
        },
    }))
    local builder = config_builder:new()
    t.assert_error_msg_contains(
        'Unexpected data type for a record: "string"',
        builder.set_global_option, builder, 'replication', 'bar')
    t.assert_error_msg_contains(
        'Expected "boolean", got "string"',
        builder.set_global_option, builder, 'replication.anon', 'bar')
end

g.test_add_instance = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])
    local config = config_builder:new()
        :add_instance('foo', {})
        :add_instance('bar', {
            replication = {anon = true},
        })
        :config()
    t.assert_equals(config, merge_config(DEFAULT_CONFIG, {
        groups = {
            ['group-001'] = {
                replicasets = {
                    ['replicaset-001'] = {
                        instances = {
                            foo = {},
                            bar = {replication = {anon = true}},
                        },
                    },
                },
            },
        },
    }))
    local builder = config_builder:new()
    t.assert_error_msg_contains(
        'Unexpected data type for a record: "string"',
        builder.add_instance, builder, 'foo', {replication = 'bar'})
    t.assert_error_msg_contains(
        'Expected "boolean", got "string"',
        builder.add_instance, builder, 'foo', {replication = {anon = 'bar'}})
end

g.test_set_instance_option = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])
    local config = config_builder:new()
        :add_instance('foo', {})
        :set_instance_option('foo', 'database.mode', 'rw')
        :add_instance('bar', {
            replication = {anon = true},
        })
        :set_instance_option('bar', 'replication.anon', false)
        :set_instance_option('bar', 'replication.election_mode', 'off')
        :config()
    t.assert_equals(config, merge_config(DEFAULT_CONFIG, {
        groups = {
            ['group-001'] = {
                replicasets = {
                    ['replicaset-001'] = {
                        instances = {
                            foo = {database = {mode = 'rw'}},
                            bar = {
                                replication = {
                                    anon = false,
                                    election_mode = 'off',
                                },
                            },
                        },
                    },
                },
            },
        },
    }))
    local builder = config_builder:new():add_instance('foo', {})
    t.assert_error_msg_contains(
        'Unexpected data type for a record: "string"',
        builder.set_instance_option, builder, 'foo', 'replication', 'bar')
    t.assert_error_msg_contains(
        'Expected "boolean", got "string"',
        builder.set_instance_option, builder, 'foo', 'replication.anon', 'bar')
end

g.test_set_instance_option_uses_existing_instance = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])

    local config_1 = config_builder:new()
        :use_replicaset('r-001')
        :add_instance('i-001', {})
        :set_instance_option('i-001', 'replication.timeout', 0.1)
        :config()

    local config_2 = config_builder:new(config_1)
        :set_instance_option('i-001', 'replication.timeout', 1000)
        :config()

    t.assert_equals(config_2, merge_config(config_1, {
        groups = {
            ['group-001'] = {
                replicasets = {
                    ['r-001'] = {
                        instances = {
                            ['i-001'] = {replication = {timeout = 1000}},
                        },
                    },
                },
            },
        },
    }))

    local builder = config_builder:new()
    t.assert_error_msg_contains(
        'Instance "missing" is not found in the configuration',
        builder.set_instance_option, builder, 'missing',
        'replication.timeout', 0.1)
end

g.test_instance_names_are_unique = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])

    local builder = config_builder:new()
        :use_group('g-001')
        :use_replicaset('r-001')
        :add_instance('duplicate', {})
        :use_group('g-002')
        :use_replicaset('r-002')


    t.assert_error_msg_contains(
        'Found instance with the same name "duplicate" in the ' ..
        'replicaset "r-001" in the group "g-001"',
        builder.add_instance, builder, 'duplicate', {}
    )
end

g.test_set_replicaset_option = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])
    local config = config_builder:new()
        :add_instance('foo', {})
        :set_replicaset_option('leader', 'foo')
        :set_replicaset_option('replication.failover', 'manual')
        :set_replicaset_option('replication.timeout', 0.5)
        :config()
    t.assert_equals(config, merge_config(DEFAULT_CONFIG, {
        groups = {
            ['group-001'] = {
                replicasets = {
                    ['replicaset-001'] = {
                        leader = 'foo',
                        replication = {
                            failover = 'manual',
                            timeout = 0.5,
                        },
                        instances = {foo = {}},
                    },
                },
            },
        },
    }))
    local builder = config_builder:new():add_instance('foo', {})
    t.assert_error_msg_contains(
        'Unexpected data type for a record: "string"',
        builder.set_replicaset_option, builder, 'replication', 'bar')
    t.assert_error_msg_contains(
        'Expected "boolean", got "string"',
        builder.set_replicaset_option, builder, 'replication.anon', 'bar')
end

g.test_custom_group_and_replicaset = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])
    local config = config_builder:new()
        :use_group('group-a')

        :use_replicaset('replicaset-x')
        :set_replicaset_option('replication.failover', 'manual')
        :set_replicaset_option('leader', 'instance-x1')
        :add_instance('instance-x1', {})
        :add_instance('instance-x2', {})
        :set_instance_option('instance-x1', 'memtx.memory', 100000000)

        :use_replicaset('replicaset-y')
        :set_replicaset_option('replication.failover', 'manual')
        :set_replicaset_option('leader', 'instance-y1')
        :add_instance('instance-y1', {})
        :add_instance('instance-y2', {})
        :set_instance_option('instance-y1', 'memtx.memory', 100000000)

        :use_group('group-b')

        :use_replicaset('replicaset-z')
        :set_replicaset_option('replication.failover', 'manual')
        :set_replicaset_option('leader', 'instance-z1')
        :add_instance('instance-z1', {})
        :add_instance('instance-z2', {})
        :set_instance_option('instance-z1', 'memtx.memory', 100000000)

        :config()

    t.assert_equals(config, merge_config(DEFAULT_CONFIG, {
        groups = {
            ['group-a'] = {
                replicasets = {
                    ['replicaset-x'] = {
                        leader = 'instance-x1',
                        replication = {failover = 'manual'},
                        instances = {
                            ['instance-x1'] = {memtx = {memory = 100000000}},
                            ['instance-x2'] = {},
                        },
                    },
                    ['replicaset-y'] = {
                        leader = 'instance-y1',
                        replication = {failover = 'manual'},
                        instances = {
                            ['instance-y1'] = {memtx = {memory = 100000000}},
                            ['instance-y2'] = {},
                        },
                    },
                },
            },
            ['group-b'] = {
                replicasets = {
                    ['replicaset-z'] = {
                        leader = 'instance-z1',
                        replication = {failover = 'manual'},
                        instances = {
                            ['instance-z1'] = {memtx = {memory = 100000000}},
                            ['instance-z2'] = {},
                        },
                    },
                },
            },
        },
    }))
end
