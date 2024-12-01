local M = {}

local api = vim.api

---@return integer?
local function get_cur_byte()
    local row, col = unpack(api.nvim_win_get_cursor(0))
    local line = api.nvim_buf_get_lines(0, row, row + 1, false)[1]
    local trimmed = line:gsub("^%x+:%s*", "")
    if #trimmed < #line then
        col = col - (#line - #trimmed)
    end
    if col < 0 then
        return
    end

end

function M.map(buf)
    local map = function(mode, lhs, rhs)
        vim.keymap.set(mode, lhs, rhs, { buffer = buf })
    end

    map("n", ">", function()
        get_cur_byte()
    end)
end

return M
