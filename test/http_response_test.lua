local t = require('luatest')
local g = t.group()

local json = require('json')

local HTTPResponse = require('luatest.http_response')

g.test_is_successfull = function()
    local subject = function(http_status_code)
        return HTTPResponse:from({status = http_status_code}):is_successful()
    end
    t.assert_equals(subject(199), false)
    t.assert_equals(subject(100), false)
    t.assert_equals(subject(200), true)
    t.assert_equals(subject(201), true)
    t.assert_equals(subject(299), true)
    t.assert_equals(subject(300), false)
    t.assert_equals(subject(400), false)
    t.assert_equals(subject(500), false)
end

g.test_json = function()
    local subject = function(data)
        return HTTPResponse:from(data).json
    end
    local value = {field = 'value'}
    local json_value = json.encode(value)
    local invalid_json = json_value .. '!!!'
    t.assert_equals(subject({status = 200, body = json_value}), value)
    t.assert_equals(subject({status = 500, body = json_value}), value)

    local response = HTTPResponse:from({body = invalid_json})
    -- assert no error until .json is accessed and error stays on consecutive calls
    for _ = 1, 2 do
        t.assert_equals(response.body, invalid_json)
        t.assert_error_msg_contains('Expected the end but found invalid token', function() return response.json end)
    end
end
