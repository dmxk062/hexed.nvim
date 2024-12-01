local M = {}

local api = vim.api
local ffi = require("ffi")
local strbuffer = require("string.buffer")

---@class hexed_bufdata
---@field path string
---@field augroup integer
---@field buf integer
---@field win integer
---@field view_buf integer
---@field view_win integer
---@field width integer
---@field elems_per_line integer
---@field data_len integer?
---@field cached_text string[]?
---@field cached_hls string[]?
---@field do_reread boolean

---@type table<integer, hexed_bufdata>
local bufdata = {}

local diagns = api.nvim_create_namespace("HexedDiagnostic")
local hlns = api.nvim_create_namespace("HexedHighlights")

ffi.cdef [[
typedef struct FILE FILE;
FILE* fopen(const char* fname, const char* mode);
size_t fread(void* ptr, size_t sz, size_t nmemb, FILE* stream);
int fclose(FILE* stream);
int fseek(FILE* stream, long offset, int whence);
]]

local bufsize = 4096

local function update_winwidth(buf)
    local width = api.nvim_win_get_width(bufdata[buf].win)
    bufdata[buf].width = width
    bufdata[buf].elems_per_line = math.max(math.min(16, math.floor((width - 40) / 5)), 2)
end

local function parse_file(buf)
    local data = bufdata[buf]
    local stream = ffi.C.fopen(data.path, "rb")
    if stream == nil then
        vim.notify("Hexed: Failed to open for reading: " .. data.path)
        return
    end
    local buffer = ffi.new("uint8_t[?]", bufsize)
    ffi.C.fseek(stream, 0, 0)

    local text = {}
    local hls = {}
    while true do
        local num_read = tonumber(ffi.C.fread(buffer, 1, bufsize, stream))
        if num_read == 0 then
            break
        end

        for i = 0, num_read - 1 do
            local byte = buffer[i]
            local hl

            if byte == 0 then
                hl = "HexedNull"
            elseif byte >= 32 and byte < 127 then
                hl = "HexedString"
            elseif byte == 0x0A or byte == 0x0D then
                hl = "HexedNewline"
            else
                hl = "HexedByte"
            end

            table.insert(text, string.format("%02X", byte))
            table.insert(hls, hl)
        end
    end

    bufdata[buf].cached_text = text
    bufdata[buf].cached_hls = hls
    ffi.C.fclose(stream)
end

local function do_draw_buf(buf)
    local data = bufdata[buf]
    if not data.cached_text or data.do_reread then
        parse_file(buf)
        data = bufdata[buf]
    end

    api.nvim_buf_clear_namespace(buf, hlns, 0, -1)
    api.nvim_buf_set_lines(buf, 0, -1, false, {})

    -- one ABCD shows two bytes
    local num_elems = data.elems_per_line
    local num_bytes = num_elems * 2

    local addr = 0
    local text = data.cached_text
    local cur_txt = { "00000000:" }
    local text_len = #text
    local lines = {}


    for i = 1, text_len, 2 do
        if i == text_len then
            table.insert(cur_txt, text[i])
            break
        end
        table.insert(cur_txt, (text[i] .. text[i + 1]))

        -- next line
        if (i + 1) % num_bytes == 0 then
            addr = addr + num_bytes

            table.insert(lines, table.concat(cur_txt, " "))
            cur_txt = { string.format("%08X:", addr) }
        end
    end
    if #cur_txt > 1 then
        table.insert(lines, table.concat(cur_txt, " "))
    end

    local hl_elems = data.cached_hls
    local hl_start = 10
    local hl_end = hl_start
    local hl_cur
    local hl_cur_line = {}
    local hls = {}

    for i, hl in ipairs(hl_elems) do
        if not hl_cur then
            hl_cur = hl
        end
        if hl == hl_cur then
            hl_end = hl_end + (i % 2 == 0 and 3 or 2)
        else
            table.insert(hl_cur_line, { hl_cur, hl_start, hl_end })
            hl_cur = hl
            hl_start = hl_end
            hl_end = hl_start + (i % 2 == 0 and 3 or 2)
        end

        if i == text_len then
            table.insert(hl_cur_line, { hl, hl_start, hl_end })
        elseif i % num_bytes == 0 then
            table.insert(hl_cur_line, { hl_cur, hl_start, -1 })
            table.insert(hls, hl_cur_line)
            hl_cur_line = {}
            hl_start = 10
            hl_end = hl_start
            hl_cur = nil
        end
    end

    if #hl_cur_line > 0 then
        table.insert(hls, hl_cur_line)
    end

    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for i, hlline in ipairs(hls) do
        for _, hl in ipairs(hlline) do
            api.nvim_buf_add_highlight(buf, hlns, hl[1], i - 1, hl[2], hl[3])
        end
    end

    api.nvim_buf_clear_namespace(buf, diagns, 0, -1)
    vim.bo[buf].modified = false
end

local function mirror_cursor_movement(buf)
    local data = bufdata[buf]
    local row, col = unpack(api.nvim_win_get_cursor(data.win))

    local bytes_per_line = data.elems_per_line * 2
    local start_byte = (row - 1) * bytes_per_line
    local end_byte = start_byte + bytes_per_line

    local idx = col - 11
    local index
    if idx < 0 then
        index = 0
    else
        idx = idx + 1
        local block = math.floor(idx / 5)
        local off = idx % 5
        local lower = math.floor(off / 2)

        index = (2 * block) + lower
    end

    local bindex = index + start_byte + 1
    start_byte = start_byte + 1
    end_byte = end_byte + 1

    local start_row, start_col, end_row, end_col, cursor_row, cursor_col

    -- HACK: so i can use byte2line
    api.nvim_buf_call(data.view_buf, function()
        cursor_row = vim.fn.byte2line(bindex)
        start_row = vim.fn.byte2line(start_byte)
        end_row = vim.fn.byte2line(end_byte)
        cursor_col = bindex - vim.fn.line2byte(cursor_row)

        start_col = start_byte - vim.fn.line2byte(start_row)
        end_col = end_byte - vim.fn.line2byte(end_row)
        if end_row == -1 then
            end_row = api.nvim_buf_line_count(data.view_buf)
        end
    end)

    api.nvim_win_set_cursor(data.view_win, { cursor_row, cursor_col })
    api.nvim_buf_clear_namespace(data.view_buf, hlns, 0, -1)

    if start_row == end_row then
        api.nvim_buf_add_highlight(data.view_buf, hlns, "HexedRegion", start_row - 1, start_col, end_col)
    else
        api.nvim_buf_add_highlight(data.view_buf, hlns, "HexedRegion", start_row - 1, start_col, -1)
        for i = start_row, end_row - 2 do
            api.nvim_buf_add_highlight(data.view_buf, hlns, "HexedRegion", i, 0, -1)
        end
        api.nvim_buf_add_highlight(data.view_buf, hlns, "HexedRegion", end_row - 1, 0, end_col)
    end

    api.nvim_buf_add_highlight(data.view_buf, hlns, "HexedChar", cursor_row - 1, cursor_col, cursor_col + 1)
end

local function parse_buf_and_write(buf)
    local data = bufdata[buf]
    local buffer = strbuffer.new(bufsize)
    local cbuffer = ffi.new("uint8_t[?]", bufsize)
    local wpointer = 0
    local errors = {}

    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)

    for i, line in ipairs(lines) do
        local data = line:gsub("^%x+:%s*", ""):gsub("%s*", "")
        for j = 1, #data, 2 do
            local txt = data:sub(j, j + 1)
            local num = tonumber(txt, 16)
            if not num then
                table.insert(errors, {
                    message = "Invalid base 16 integer: " .. txt,
                    lnum = i - 1,
                    col = 0
                })
                goto continue
            end
            if wpointer == bufsize then
                buffer:putcdata(cbuffer, bufsize)
                wpointer = 0
            end
            cbuffer[wpointer] = num
            wpointer = wpointer + 1
            ::continue::
        end
    end

    if #errors > 0 then
        vim.diagnostic.set(diagns, buf, errors)
        return false
    end

    buffer:putcdata(cbuffer, wpointer)

    local file = io.open(data.path, "wb")
    if not file then
        vim.notify("Hexed: Failed to open for writing: " .. data.path)
        return false
    end
    file:write(buffer:tostring())
    file:close()
    return true
end

function M.edit_file(file)
    local cur_bufnum = api.nvim_get_current_buf()
    if bufdata[cur_bufnum] then
        return
    end

    if not vim.uv.fs_access(file, "R") then
        vim.notify("Hexed: Cannot open file " .. file .. " as readable, aborting", vim.log.levels.ERROR)
        return
    end

    local st, err = vim.uv.fs_stat(file)
    if not st or err then
        vim.notify("Hexed: failed to stat() " .. file, vim.log.levels.ERROR)
        return
    end

    if st.type ~= "file" then
        vim.notify("Hexed: Not a regular file: " .. file, vim.log.levels.ERROR)
        return
    end

    local buf = api.nvim_create_buf(true, false)
    local win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)

    local view_buf = vim.fn.bufnr(file, true)
    local view_win = api.nvim_open_win(view_buf, false, {
        split = "right",
        win = win,
    })
    vim.wo[view_win][0].list = true

    local augroup = api.nvim_create_augroup("BinedBuf" .. buf, { clear = true })
    bufdata[buf] = {
        augroup = augroup,
        buf = buf,
        win = win,
        width = 0,
        elems_per_line = 0,
        path = file,
        do_reread = false,
        view_buf = view_buf,
        view_win = view_win
    }



    vim.bo[buf].buftype = "acwrite"
    vim.bo[buf].filetype = "hexed"
    api.nvim_buf_set_name(buf, file .. ":hex")
    update_winwidth(buf)

    local aucmd = api.nvim_create_autocmd
    aucmd("WinResized", {
        group = augroup,
        buffer = buf,
        callback = function()
            if not vim.bo[buf].modified then
                update_winwidth(buf)
                do_draw_buf(buf)
            end
        end
    })
    aucmd("CursorMoved", {
        group = augroup,
        buffer = buf,
        callback = function()
            mirror_cursor_movement(buf)
        end,
    })
    aucmd("BufWritePost", {
        group = augroup,
        buffer = view_buf,
        callback = function()
            bufdata[buf].do_reread = true
            do_draw_buf(buf)
        end
    })
    aucmd("BufWriteCmd", {
        group = augroup,
        buffer = buf,
        callback = function()
            if parse_buf_and_write(buf) then
                bufdata[buf].do_reread = true
                vim.cmd("e #" .. view_buf)
                do_draw_buf(buf)
                vim.bo[buf].modified = false
            end
        end
    })
    aucmd("BufDelete", {
        group = augroup,
        buffer = buf,
        callback = function()
            api.nvim_del_augroup_by_id(augroup)
        end
    })

    do_draw_buf(buf)
end

return M
