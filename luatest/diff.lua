local yaml = require('yaml')
local uri = require('uri')

-- diff_match_patch expects bit32
if not rawget(_G, 'bit32') then
    _G.bit32 = require('bit')
end

local diff_match_patch = require('luatest.vendor.diff_match_patch')

diff_match_patch.settings({
    Diff_Timeout = 0,
    Patch_Margin = 1e9,
})

local M = {}

-- Maximum number of distinct line IDs that can be encoded as single-byte chars.
local MAX_LINE_ID = 0x100

local function encode_line_id(id)
    if id >= MAX_LINE_ID then
        return nil
    end

    return string.char(id)
end

local function decode_line_id(encoded)
    return encoded:byte(1)
end

-- Recursively normalize a value into something that:
-- * is safe and stable for YAML encoding;
-- * produces meaningful diffs for values that provide informative tostring();
-- * does NOT produce noisy diffs for opaque userdata/cdata (newproxy, ffi types, etc).
local function normalize_for_yaml(value)
    local t = type(value)

    if t == 'table' then
        local entries = {}
        for k, v in pairs(value) do
            local nk = normalize_for_yaml(k)
            if nk == nil then
                -- YAML keys must be representable; fallback to tostring.
                nk = tostring(k)
            end
            table.insert(entries, {key = nk, value = v})
        end
        table.sort(entries, function(a, b)
            if type(a.key) == 'number' and type(b.key) == 'number' then
                return a.key < b.key
            end
            return tostring(a.key) < tostring(b.key)
        end)

        local res = {}
        for _, entry in ipairs(entries) do
            res[entry.key] = normalize_for_yaml(entry.value)
        end
        return res
    end

    if t == 'cdata' or t == 'userdata' then
        local ok, s = pcall(tostring, value)
        if ok and type(s) == 'string' then
            return s
        end

        return '<unknown cdata/userdata>'
    end

    if t == 'function' or t == 'thread' then
        return '<' .. t .. '>'
    end

    -- other primitive types.
    return value
end

-- Encode a Lua value as YAML after normalizing it to a diff-friendly form.
local function encode_yaml(value)
    local ok, encoded = pcall(yaml.encode, normalize_for_yaml(value))
    if ok then
        return encoded
    end
end

-- Convert a supported Lua value into a textual form suitable for diffing.
--
-- * Tables are serialized to YAML with recursive normalization.
-- * Strings are used as-is.
-- * Numbers / booleans are converted via tostring().
-- * Top-level opaque userdata/cdata disable diffing when tostring() fails (return nil).
local function as_yaml(value)
    local t = type(value)

    if t == 'cdata' or t == 'userdata' then
        local ok, s = pcall(tostring, value)
        if ok and type(s) == 'string' then
            return s
        end

        return nil
    end

    if t == 'string' then
        return value
    end

    local encoded = encode_yaml(value)
    if encoded ~= nil then
        return encoded
    end

    local ok, s = pcall(tostring, value)
    if ok and type(s) == 'string' then
        return s
    end
end

-- Map two multiline texts to compact "char sequences" and shared line table.
-- Returns nil if the number of unique lines exceeds MAX_LINE_ID.
local function lines_to_chars(text1, text2)
    local line_array = {}
    local line_hash = {}

    local function add_line(line)
        local id = line_hash[line]
        if id == nil then
            id = #line_array + 1
            local encoded = encode_line_id(id)
            if encoded == nil then
                return nil
            end
            line_array[id] = line
            line_hash[line] = id
        end

        return encode_line_id(id)
    end

    local function munge(text)
        local tokens = {}
        local start = 1

        while true do
            local newline_pos = text:find('\n', start, true)
            if newline_pos == nil then
                local tail = text:sub(start)
                if tail ~= '' then
                    local token = add_line(tail)
                    if token == nil then
                        return nil
                    end
                    table.insert(tokens, token)
                end
                break
            end

            local token = add_line(text:sub(start, newline_pos))
            if token == nil then
                return nil
            end
            table.insert(tokens, token)
            start = newline_pos + 1
        end

        return table.concat(tokens)
    end

    local chars1 = munge(text1)
    if chars1 == nil then
        return nil
    end

    local chars2 = munge(text2)
    if chars2 == nil then
        return nil
    end

    return chars1, chars2, line_array
end

-- Expand a "char sequence" produced by lines_to_chars back into full text.
local function chars_to_lines(text, line_array)
    local out = {}

    for i = 1, #text do
        local id = decode_line_id(text:sub(i, i))
        local line = line_array[id]
        if line == nil then
            return nil
        end
        table.insert(out, line)
    end

    return table.concat(out)
end

-- Compute line-based diff using diff_match_patch, falling back to nil on failure.
local function diff_by_lines(text1, text2)
    local chars1, chars2, line_array = lines_to_chars(text1, text2)
    if chars1 == nil then
        return nil
    end

    local diffs = diff_match_patch.diff_main(chars1, chars2, false)
    diff_match_patch.diff_cleanupSemantic(diffs)

    for i, diff in ipairs(diffs) do
        local text = chars_to_lines(diff[2], line_array)
        if text == nil then
            return nil
        end
        diffs[i][2] = text
    end

    return diffs
end

-- Normalize patch text from diff_match_patch: unescape it, drop junk lines,
-- and ensure it is valid, readable unified diff.
local function prettify_patch(patch_text)
    -- patch_toText() escapes non-ascii symbols using URL escaping. Convert it
    -- back to preserve the original values in unified diff output.
    patch_text = uri.unescape(patch_text)

    local out = {}
    local last_sign = nil

    for line in (patch_text .. '\n'):gmatch('(.-)\n') do
        if line ~= '' and line ~= ' ' then
            local first = line:sub(1, 1)

            if first == '+' or first == '-' then
                last_sign = first
            elseif first == '@' or first == ' ' then
                last_sign = nil
            elseif last_sign ~= nil then
                line = last_sign .. line
            else
                line = ' ' .. line
            end

            table.insert(out, line)
        end
    end

    return table.concat(out, '\n')
end

--- Build unified diff for expected and actual values serialized to YAML.
-- Tries line-based diff first, falls back to char-based.
-- Returns nil when values can't be serialized or there is no diff.
function M.build_unified_diff(expected, actual)
    local expected_text = as_yaml(expected)
    local actual_text = as_yaml(actual)

    if expected_text == nil or actual_text == nil then
        return nil
    end

    local diffs = diff_by_lines(expected_text, actual_text)

    if diffs == nil then
        return nil
    end

    local patches = diff_match_patch.patch_make(expected_text,
                                                actual_text, diffs)
    local patch_text = diff_match_patch.patch_toText(patches)

    if patch_text == '' then
        return nil
    end

    return prettify_patch(patch_text)
end

return M
