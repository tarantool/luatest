--- Utils to define classes and their hierarchies.
-- Every class has `:new` method to create an instance of this class.
-- Every instance receives properties from class's `mt` field.
local Class = {mt = {}}
Class.mt.__index = Class.mt

--- Builds a class with optional superclass.
-- Both instance and class methods are inherited from superclass if given.
-- Otherwise default class methods are copied from Class.mt.
function Class.new(class, super)
    class = class or {}
    class.__index = class
    class.mt = {class = class}
    class.mt.__index = class.mt
    if super then
        class.super = super
        setmetatable(class, super)
        setmetatable(class.mt, super.mt)
    else
        class.super = Class.mt
        setmetatable(class, Class.mt)
    end
    return class
end

--- Create descendant class.
function Class.mt:new_class(class)
    return Class.new(class, self)
end

--- Build an instance of a class.
-- It sets metatable and calls instance's `initialize` method if it's available.
function Class.mt:new(...)
    return self:from({}, ...)
end

--- Initialize instance from given object.
function Class.mt:from(object, ...)
    setmetatable(object, self.mt)
    if object.initialize then object:initialize(...) end
    return object
end

return Class
