# Hexed.nvim

Easily edit binary data in NeoVim.

# Requirements

Luajit enabled NeoVim. (`ffi`)

# Installation

Any package manager should work

<details>
<summary>lazy.nvim</summary>

```lua
{
    "dmxk062/hexed.nvim",
    -- default options
    opts = {
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
}
```

</details>

# Usage

Use `:Hexed <file?>` to open a file or the current buffer.

To start NeoVim by editing a binary file, just use `nvim <file> +Hex`.

Editing and writing either the regular file or the hex view will update the underlying file on disk.
