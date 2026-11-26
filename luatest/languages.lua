--- Languages compiled to Lua.
--
-- luatest can run tests and helpers written in any language that compiles to
-- Lua (MoonScript, Fennel, Teal, YueScript, ...) through a *language module*.
-- luatest knows no concrete language: a language module is any Lua module
-- which, when required,
--
-- * installs a searcher for its files into `package.loaders` (once per
--   process, so requiring it again is harmless) and
-- * returns a table with `extensions`, a non-empty list of file extensions
--   without the dot, e.g. `{extensions = {'moon'}}`.
--
-- Requiring the module is the whole activation, so `tarantool -l <module>`
-- activates the language in a child process too.
--
-- Languages are activated with the `--language MODULE` CLI option or
-- `luatest.configure({languages = {'MODULE'}})`. Once active, a language
-- makes luatest discover `*_test.<ext>` files and pass `-l <module>` to the
-- servers it starts.
--
-- The module itself is the registry used by the runner. `languages.new()`
-- builds a separate one.
--
-- @module luatest.languages

local pp = require('luatest.pp')

local Registry = {}
Registry.__index = Registry

local LUA_EXTENSION = 'lua'

local function new()
    return setmetatable({
        _modules = {},
        _descriptions = {},
        _extensions = {LUA_EXTENSION},
        _known_extensions = {[LUA_EXTENSION] = true},
    }, Registry)
end

local function check_description(name, description)
    local extensions = type(description) == 'table' and description.extensions
    if type(extensions) ~= 'table' or #extensions == 0 then
        error(("Language module '%s' must return a table with a non-empty 'extensions' list, got: %s")
            :format(name, pp.tostring(description)), 0)
    end
    for _, ext in ipairs(extensions) do
        if type(ext) ~= 'string' or not ext:match('^[%w_%-]+$') then
            error(("Language module '%s' has an invalid extension %s " ..
                "(expected a name like 'moon', without the dot)")
                :format(name, pp.tostring(ext)), 0)
        end
    end
end

--- Activate languages.
--
-- Requires each language module, checks the table it returns and registers
-- its extensions. A module that is already active is skipped.
--
-- @param names Module name or a list of them; `nil` does nothing.
-- @return The table returned by the last module.
-- @raise If a module fails to load or returns a bad table. The error
--   names the module.
function Registry:use(names)
    if names == nil then
        return
    end
    if type(names) ~= 'table' then
        names = {names}
    end
    local description
    for _, name in ipairs(names) do
        if type(name) ~= 'string' then
            error(('Language module name must be a string, got: %s'):format(pp.tostring(name)), 0)
        end
        description = self._descriptions[name]
        if description == nil then
            local ok, res = pcall(require, name)
            if not ok then
                error(("Failed to load language module '%s': %s"):format(name, tostring(res)), 0)
            end
            check_description(name, res)
            description = res
            self._descriptions[name] = description
            table.insert(self._modules, name)
            for _, ext in ipairs(description.extensions) do
                if not self._known_extensions[ext] then
                    self._known_extensions[ext] = true
                    table.insert(self._extensions, ext)
                end
            end
        end
    end
    return description
end

--- Names of the active language modules, in the order of activation.
--
-- @return table
function Registry:modules()
    return table.copy(self._modules)
end

--- Active file extensions without the dot. The first one is always `lua`.
--
-- @return table
function Registry:extensions()
    return table.copy(self._extensions)
end

--- Strip an active extension from a path.
--
-- @string path
-- @return The path without the extension and the extension, or `nil` if
--   the path has no active extension.
function Registry:strip_extension(path)
    for _, ext in ipairs(self._extensions) do
        local suffix = '.' .. ext
        if #path > #suffix and path:sub(-#suffix) == suffix then
            return path:sub(1, -#suffix - 1), ext
        end
    end
    return nil
end

--- Find the file of a module written in Lua or an active language.
--
-- `package.search` is tried first. It does not ask `package.loaders`, so for
-- every other active extension `<ext>` the module is looked up along
-- `<root>/?.<ext>`, `<root>/?/init.<ext>`, where `<root>` is
-- `package.searchroot()`, and along every `package.path` template ending in
-- `.lua` with `.lua` replaced by `.<ext>`. A language module should resolve
-- files the same way so that what is found here is what it loads.
--
-- @string name Module name, e.g. `test.helper`.
-- @return Path of the module file or `nil`.
function Registry:search(name)
    local path = package.search(name)
    if path ~= nil then
        return path
    end
    local root = package.searchroot and package.searchroot() or '.'
    for _, ext in ipairs(self._extensions) do
        if ext ~= LUA_EXTENSION then
            local templates = {
                root .. '/?.' .. ext,
                root .. '/?/init.' .. ext,
            }
            for template in package.path:gmatch('[^;]+') do
                if template:sub(-4) == '.lua' then
                    table.insert(templates, template:sub(1, -5) .. '.' .. ext)
                end
            end
            path = package.searchpath(name, table.concat(templates, ';'))
            if path ~= nil then
                return path
            end
        end
    end
    return nil
end

local languages = new()

--- Build a new empty registry, separate from the one of the runner.
--
-- @function new
-- @return Registry with the methods of this module.
languages.new = new

return languages
