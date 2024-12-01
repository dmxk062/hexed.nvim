local M = {}
local view = require("hexed.view")

local defaults = {
    highlights = {
        String  = "String",
        Null    = "NonText",
        Newline = "SpecialChar",
        Address = "Label",
        Byte    = "Identifier",
        Region  = "Visual",
        Char    = "Substitute",
    },
    command = "Hexed",
}

M.setup = function(opts)
    opts = opts or {}
    opts = vim.tbl_deep_extend("force", defaults, opts)

    vim.api.nvim_create_user_command(opts.command, function(args)
        local file = args.args == "" and vim.api.nvim_buf_get_name(0) or args.args

        view.edit_file(file)
    end, {
        complete = "file",
        nargs = "?",
    })

    for group, link in pairs(opts.highlights) do
        vim.api.nvim_set_hl(0, "Hexed" .. group, { link = link, default = true })
    end
end

return M
