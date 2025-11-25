local yaml = require('yaml')
local msgpack = require('msgpack')
local uri = require('uri')

-- Optional Tarantool-specific types.
local decimal = require('decimal')
local datetime = require('datetime')
local uuid = require('uuid')
local ffi = require('ffi')

-- varbinary is available only since Tarantool 3.0.0.
-- For older versions we provide a fallback stub.
local has_varbinary, varbinary = pcall(require, 'varbinary')
if not has_varbinary then
    varbinary = {
        is = function()
            return false
        end
    }
end

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

-- Classify known cdata/userdata types into semantic kinds.
local function classify_cdata(v)
    local t = type(v)

    if t ~= 'cdata' and t ~= 'userdata' then
        return nil
    end

    if decimal.is_decimal(v) then
        return 'decimal'
    end

    if datetime.is_datetime(v) then
        return 'datetime'
    end

    if uuid.is_uuid(v) then
        return 'uuid'
    end

    if varbinary.is(v) then
        return 'varbinary'
    end

    return nil
end

-- Recursively normalize a value into something that:
-- * is safe and stable for YAML encoding;
-- * produces meaningful diffs for "semantic" types (decimal/datetime/uuid/varbinary);
-- * does NOT produce noisy diffs for opaque userdata/cdata (newproxy, ffi types, etc).
local function normalize_for_yaml(value)
    local t = type(value)

    if t == 'table' then
        local res = {}
        for k, v in pairs(value) do
            local nk = normalize_for_yaml(k)
            if nk == nil then
                -- YAML keys must be representable; fallback to tostring.
                nk = tostring(k)
            end
            res[nk] = normalize_for_yaml(v)
        end
        return res
    end

    if t == 'cdata' or t == 'userdata' then
        local kind = classify_cdata(value)
        if kind ~= nil then
            local ok, s = pcall(tostring, value)
            if ok and type(s) == 'string' then
                return s
            end
            return '<' .. kind .. '>'
        end

        if t == 'userdata' then
            return '<userdata>'
        end

        if ffi ~= nil then
            local ok, ctype = pcall(ffi.typeof, value)
            if ok then
                -- Stable placeholder: includes type, but not the pointer or content.
                return '<cdata:' .. tostring(ctype) .. '>'
            end
        end

        return '<cdata>'
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

-- Try to decode a string as msgpack and then encode the result to YAML.
-- Returns nil if decoding or encoding fails.
local function msgpack_to_yaml(value)
    if type(value) ~= 'string' then
        return nil
    end

    local ok, decoded = pcall(msgpack.decode, value)
    if not ok or type(decoded) ~= 'table' then
        return nil
    end

    return encode_yaml(decoded)
end

-- Convert a supported Lua value into a textual form suitable for diffing.
--
-- * Tables are serialized to YAML with recursive normalization.
-- * Strings are used as-is, or interpreted as msgpack and then YAML when possible.
-- * Numbers / booleans are converted via tostring().
-- * Top-level decimal/datetime/uuid/varbinary are converted via tostring().
-- * Top-level opaque userdata/cdata disable diffing (return nil).
local function as_yaml(value)
    local t = type(value)

    if t == 'cdata' or t == 'userdata' then
        local kind = classify_cdata(value)
        if kind ~= nil then
            local ok, s = pcall(tostring, value)
            if ok and type(s) == 'string' then
                return s
            end
            return '<' .. kind .. '>'
        end

        return nil
    end

    if t == 'string' then
        return msgpack_to_yaml(value) or encode_yaml(value)
    end

    local encoded = encode_yaml(value)
    if encoded ~= nil then
        return encoded
    end

    local ok, packed = pcall(msgpack.encode, value)
    if ok then
        local decoded_yaml = msgpack_to_yaml(packed)
        if decoded_yaml ~= nil then
            return decoded_yaml
        end

        return encode_yaml(packed)
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

    for line in (patch_text .. '\n'):gmatch('(.-)\n') do
        if line ~= '' and line ~= ' ' then
            local first = line:sub(1, 1)

            if first ~= '@' and first ~= '+'
               and first ~= '-' and first ~= ' ' then
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
    local used_line_diff = true

    if diffs == nil then
        diffs = diff_match_patch.diff_main(expected_text, actual_text)
        used_line_diff = false
    end

    if not used_line_diff then
        diff_match_patch.diff_cleanupSemantic(diffs)
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
