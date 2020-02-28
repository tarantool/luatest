local t = require('luatest')
local g = t.group()

local Class = require('luatest.class')

g.test_new_class = function()
    local class = Class.new()
    function class.mt:get_a() return self.a end
    local instance = class:from({a = 123})
    t.assert_equals(getmetatable(instance), class.mt)
    t.assert_equals(instance.class, class)
    t.assert_equals(instance, {a = 123})
    t.assert_equals(instance:get_a(), 123)
end

g.test_inheritance = function()
    local Parent = Class.new()
    Parent.X = 'XX'
    function Parent:get_x() return self.X end
    function Parent.mt:get_a() return self.a end
    local Child = Parent:new_class()
    Child.Y = 'YY'
    function Child:get_y() return self.Y end
    function Child.mt:get_b() return self.b end

    t.assert_equals(Child.super, Parent)
    t.assert_equals(Child:get_x(), 'XX')
    t.assert_equals(Child:get_y(), 'YY')
    t.assert_equals(Parent:get_x(), 'XX')
    t.assert_equals(Parent.get_y, nil)

    local instance = Child:from({a = 123, b = 456})
    t.assert_equals(getmetatable(instance), Child.mt)
    t.assert_equals(instance.class, Child)
    t.assert_equals(instance, {a = 123, b = 456})
    t.assert_equals(instance:get_a(), 123)
    t.assert_equals(instance:get_b(), 456)
end

g.test_super = function()
    local Parent = Class.new()
    Parent.X = 'XX'
    function Parent:get_x() return self.X end
    function Parent.mt:get_a() return self.a end
    local Child = Parent:new_class({X = 'YY'})
    function Child:get_x() return Child.super.get_x(self) .. '!' end
    function Child.mt:get_a() return Child.super.mt.get_a(self) * 2 end

    local instance = Child:from({a = 123})
    t.assert_equals(Child:get_x(), 'YY!')
    t.assert_equals(instance:get_a(), 246)

    local Grandchild = Child:new_class({X = 'YY'})
    function Grandchild:get_x() return Grandchild.super.get_x(self) .. '?' end
    function Grandchild.mt:get_a() return Grandchild.super.mt.get_a(self) * 3 end
    instance = Grandchild:from({a = 2})
    t.assert_equals(Grandchild:get_x(), 'YY!?')
    t.assert_equals(instance:get_a(), 12)
end

g.test_new_and_from = function()
    local class = Class.new()
    function class.mt:initialize(a, b)
        self.a = a
        self.b = b
    end

    t.assert_equals(class:new(1, 2, 3), {a = 1, b = 2})
    t.assert_equals(class:new(3), {a = 3})

    local source = {a = 11, c = 33}
    local instance = class:from(source, 1, 2, 3)
    t.assert_equals(instance, {a = 1, b = 2, c = 33})
    t.assert_is(instance, source)
end
