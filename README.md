# treesorter.nvim

Simple POC of a plugin to sort code units using treesitter.



https://github.com/user-attachments/assets/8156fe67-8a12-4b68-a647-8012825dfeb5



## Installation

Using lazy.nvim:

```lua
return {
  "maxbol/treesorter.nvim",
  cmd = "TSort",
  config = function()
    require("treesorter").setup()
  end,
}
```

## Usage

To sort units of a certain type, use the `TSort` command. For example, to sort function definitions in a C file:

```vim
:TSort function_definition
```

This will result in all functions in the most narrow scope from the cursor position gets resorted in alphabetical order.

If you want to sort multiple types of nodes, simply add them additional arguments:

```vim
:TSort function_definition declaration
```

This will sort functions and variable declarations individually and keep them separate.

If instead you want to sort these node types as a single list of nodes, you can sort nodes of multiple types together using groups of types. Members of a single group are connected using a `+` sign:

```vim
:TSort function_definition+declaration method
```

You can use TSort in visual mode to only sort nodes within the selected range:

```vim
:'<,'>TSort function_definition
```

Usage with LUA:

```lua
require("treesorter").sort({"function_definition+declaration", "method"})
```
