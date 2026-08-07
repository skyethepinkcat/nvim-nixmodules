-- scripts/gendoc.lua
vim.opt.rtp:prepend(".deps/docgen.nvim")
vim.opt.rtp:prepend(".")  -- add your plugin to rtp if needed (e.g. for @eval)

require("docgen").run({
  name = "nixmodules",
  files = {
    "./lua/nixmodules/init.lua",
  },
})
