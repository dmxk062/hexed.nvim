# Hexed.nvim

Easily edit binary data in neovim.

# Rationale

Especially when working with embedded systems or new, custom fileformats, being able to get a good look
at some binary data can be exceptionally useful.

For a while the standard (meaning only viable) way to edit binary files inside (neo)vim was `xxd`.
While it is quite fast and capable, it makes the process of writing to a file harder, 
as one cannot easily do changes on text and binary forms at the same time.
It also cannot interact with neovim internal state, e.g. folds or resizing on window size change

# Features

- Highlight bytes based on their likely meaning
- Synchronise plain text and hexdump views on a file
- Fold ranges of null bytes 

# Requirements

Luajit enabled neovim. (`ffi`)

# Installation

Any package manager should work

e.g. using lazy.nvim

```lua
{
    "dmxk062/hexed.nvim",
    -- default options
    opts = {
        highlights = {
            String  = "String",         -- ascii characters
            Null    = "NonText",        -- null bytes
            Newline = "SpecialChar",    -- newline characters(\n and \r)
            Address = "Label",          -- the addresses at the beginning of lines
            Byte    = "Identifier",     -- any other byte
            Region  = "Visual",         -- context are in preview buffer
            Char    = "Substitute",     -- character the cursor is on
        },
        command = "Hexed",              -- the command used to invoke hexed
    }
}
```

# Usage

Use `:Hexed <file?>` to open a file or the current buffer.

To start neovim by editing a binary file, just use `nvim <file> +Hex`.

Editing and writing either the regular file or the hex view will update the underlying file on disk.

# TODO

- Improve performance
- Allow reading files not on the local filesystem, e.g. via ssh
- add mappings for bitshifts, logical and, or etc
