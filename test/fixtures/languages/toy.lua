-- Toy language compiled to Lua, used to test luatest language modules.
--
-- A `.toy` file is Lua source with two differences:
--
--   * its first line must be `#toy`;
--   * the keyword `function` is spelled `fn`.
--
-- So a `.toy` file can't be loaded as plain Lua, and the "compiler" keeps
-- line numbers, which lets tests check the file name and line in traces.
--
-- Requiring the module installs its searcher into `package.loaders` (once
-- per process) and returns the language description luatest expects.

local EXTENSION = 'toy'

local function compile(source, path)
    if source:sub(1, 4) ~= '#toy' then
        return nil, ('%s: not a toy file: the first line must be #toy'):format(path)
    end
    -- Keep the newline after the header so that line numbers stay the same.
    local body = source:gsub('^[^\n]*', '', 1)
    body = body:gsub('%f[%w_]fn%f[^%w_]', 'function')
    return loadstring(body, '@' .. path)
end

-- Files are looked up relative to package.searchroot(), not the current
-- directory: a server started by luatest runs in its own working directory
-- and gets the search root with `-e package.setsearchroot(...)`.
local function search(name)
    local root = package.searchroot and package.searchroot() or '.'
    local templates = {
        root .. '/?.' .. EXTENSION,
        root .. '/?/init.' .. EXTENSION,
    }
    for template in package.path:gmatch('[^;]+') do
        if template:sub(-4) == '.lua' then
            table.insert(templates, template:sub(1, -5) .. '.' .. EXTENSION)
        end
    end
    return package.searchpath(name, table.concat(templates, ';'))
end

local function searcher(name)
    local path, err = search(name)
    if path == nil then
        return err
    end
    local file = assert(io.open(path))
    local source = file:read('*a')
    file:close()
    local chunk, compile_err = compile(source, path)
    if chunk == nil then
        error(("error loading module '%s' from file '%s':\n\t%s"):format(name, path, compile_err))
    end
    return chunk
end

local registry = debug.getregistry()
if registry.luatest_toy_searcher == nil then
    registry.luatest_toy_searcher = searcher
    table.insert(package.loaders, searcher)
end

return {extensions = {EXTENSION}}
