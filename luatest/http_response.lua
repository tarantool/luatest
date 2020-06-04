--- Class to provide helper methods for HTTP responses
--
-- @classmod luatest.http_response

local json = require('json')

local HTTPResponse = require('luatest.class').new()

function HTTPResponse.mt:__index(method_name)
    if HTTPResponse.mt[method_name] then
        return HTTPResponse.mt[method_name]
    elseif HTTPResponse.getters[method_name] then
        return HTTPResponse.getters[method_name](self)
    end
end

--- Instance getter methods
--
-- @section

-- For backward compatibility this methods should be accessed
-- as object's fields (eg., `response.json.id`).
--
-- They are not assigned to object's fields on initialization
-- to be evaluated lazily and to be able to throw errors.
HTTPResponse.getters = {}

--- Parse json from body.
-- @usage response.json.id
function HTTPResponse.getters:json()
    self.json = json.decode(self.body)
    return self.json
end

--- Instance methods
-- @section

--- Check that status code is 2xx.
function HTTPResponse.mt:is_successful()
    return self.status >= 200 and self.status <= 299
end

return HTTPResponse
