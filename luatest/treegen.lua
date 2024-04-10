--- Working tree generator.
--
-- Generates a tree of Lua files using provided templates and
-- filenames.
--
-- @usage
--
-- local t = require('luatest')
-- local treegen = require('luatest.treegen')
--
-- local g = t.group()
--
-- g.test_foo = function(g)
--     treegen.add_template('^.*$', 'test_script')
--     local dir = treegen.prepare_directory({'foo/bar.lua', 'main.lua'})
--     ...
-- end
--
-- @module luatest.treegen

local hooks = require('luatest.hooks')

local fio = require('fio')
local fun = require('fun')
local checks = require('checks')

local log = require('luatest.log')

local treegen = {
    _group = {}
}

local function find_template(group, script)
    for position, template_def in ipairs(group._treegen.templates) do
        if script:match(template_def.pattern) then
            return position, template_def.template
        end
    end
    error(("treegen: can't find a template for script %q"):format(script))
end

--- Write provided content into the given directory.
--
-- @string directory Directory where the content will be created.
-- @string filename File to write (possible nested path: /foo/bar/main.lua).
-- @string content The body to write.
-- @return string
function treegen.write_file(directory, filename, content)
    checks('string', 'string', 'string')
    local content_abspath = fio.pathjoin(directory, filename)
    local flags = {'O_CREAT', 'O_WRONLY', 'O_TRUNC'}
    local mode = tonumber('644', 8)

    local contentdir_abspath = fio.dirname(content_abspath)
    log.info('Creating a directory: %s', contentdir_abspath)
    fio.mktree(contentdir_abspath)

    log.info('Writing a content: %s', content_abspath)
    local fh = fio.open(content_abspath, flags, mode)
    fh:write(content)
    fh:close()
    return content_abspath
end

-- Generate a content that follows a template and write it at the
-- given path in the given directory.
--
-- @table group Group of tests.
-- @string directory Directory where the content will be created.
-- @string filename File to write (possible nested path: /foo/bar/main.lua).
-- @table replacements List of replacement templates.
-- @return string
local function gen_content(group, directory, filename, replacements)
    checks('table', 'string', 'string', 'table')
    local _, template = find_template(group, filename)
    replacements = fun.chain({filename = filename}, replacements):tomap()
    local body = template:gsub('<(.-)>', replacements)
    return treegen.write_file(directory, filename, body)
end

--- Initialize treegen module in the given group of tests.
--
-- @tab group Group of tests.
local function init(group)
    checks('table')
    group._treegen = {
        tempdirs = {},
        templates = {}
    }
    treegen._group = group
end

--- Remove all temporary directories created by the test
-- unless KEEP_DATA environment variable is set to a
-- non-empty value.
local function clean()
    if treegen._group._treegen == nil then
        return
    end

    local dirs = table.copy(treegen._group._treegen.tempdirs) or {}
    treegen._group._treegen.tempdirs = nil

    local keep_data = (os.getenv('KEEP_DATA') or '') ~= ''

    for _, dir in ipairs(dirs) do
        if keep_data then
            log.info('Left intact due to KEEP_DATA env var: %s', dir)
        else
            log.info('Recursively removing: %s', dir)
            fio.rmtree(dir)
        end
    end

    treegen._group._treegen.templates = nil
end

--- Save the template with the given pattern.
--
-- @string pattern File name template
-- @string template A content template for creating a file.
function treegen.add_template(pattern, template)
    checks('string', 'string')
    table.insert(treegen._group._treegen.templates, {
        pattern = pattern,
        template = template,
    })
end

--- Remove the template by pattern.
--
-- @string pattern File name template
function treegen.remove_template(pattern)
    checks('string')
    local is_found, position, _ = pcall(find_template, treegen._group, pattern)
    if is_found then
        table.remove(treegen._group._treegen.templates, position)
    end
end

--- Create a temporary directory with given contents.
--
-- The contents are generated using templates added by
-- treegen.add_template().
--
-- @usage
--
-- Example for {'foo/bar.lua', 'baz.lua'}:
--
-- /
-- + tmp/
--   + rfbWOJ/
--     + foo/
--     | + bar.lua
--     + baz.lua
--
-- The return value is '/tmp/rfbWOJ' for this example.
--
-- @tab contents List of bodies of the content to write.
-- @tab[opt] replacements List of replacement templates.
-- @return string
function treegen.prepare_directory(contents, replacements)
    checks('?table', '?table')
    replacements = replacements or {}

    local dir = fio.tempdir()

    -- fio.tempdir() follows the TMPDIR environment variable.
    -- If it ends with a slash, the return value contains a double
    -- slash in the middle: for example, if TMPDIR=/tmp/, the
    -- result is like `/tmp//rfbWOJ`.
    --
    -- It looks harmless on the first glance, but this directory
    -- path may be used later to form an URI for a Unix domain
    -- socket. As result the URI looks like
    -- `unix/:/tmp//rfbWOJ/instance-001.iproto`.
    --
    -- It confuses net_box.connect(): it reports EAI_NONAME error
    -- from getaddrinfo().
    --
    -- It seems, the reason is a peculiar of the URI parsing:
    --
    -- tarantool> uri.parse('unix/:/foo/bar.iproto')
    -- ---
    -- - host: unix/
    --   service: /foo/bar.iproto
    --   unix: /foo/bar.iproto
    -- ...
    --
    -- tarantool> uri.parse('unix/:/foo//bar.iproto')
    -- ---
    -- - host: unix
    --   path: /foo//bar.iproto
    -- ...
    --
    -- Let's normalize the path using fio.abspath(), which
    -- eliminates the double slashes.
    dir = fio.abspath(dir)

    table.insert(treegen._group._treegen.tempdirs, dir)

    for _, content in ipairs(contents) do
        gen_content(treegen._group, dir, content, replacements)
    end

    return dir
end

hooks.before_all_preloaded(init)
hooks.after_all_preloaded(clean)

return treegen
