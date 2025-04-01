#!/usr/bin/env tarantool

local json = require('json')

local workdir = os.getenv('TARANTOOL_WORKDIR')
local listen = os.getenv('TARANTOOL_LISTEN')
local http_port = os.getenv('TARANTOOL_HTTP_PORT')

local httpd = require('http.server').new('0.0.0.0', http_port)

box.cfg({work_dir = workdir})
box.schema.user.grant('guest', 'super', nil, nil, {if_not_exists = true})
box.cfg({listen = listen})

httpd:route({path = '/ping', method = 'GET'}, function()
    return {status = 200, body = 'pong'}
end)

httpd:route({path = '/test', method = 'GET'}, function()
    local result = {
        workdir = workdir,
        listen = listen,
        http_port = http_port,
        value = os.getenv('custom_env'),
    }
    return {status = 200, body = json.encode(result)}
end)

httpd:route({path = '/echo', method = 'post'}, function(request)
    return {status = 200, body = json.encode({
        body = request:read(),
        request_headers = request.headers,
    })}
end)

httpd:route({path = '/test', method = 'post'}, function(request)
    return {status = 201, body = request:read()}
end)

httpd:start()
