return {
  "ninetyfive-gg/ninetyfive.nvim",
  version = "*",
  config = function()
    require("ninetyfive").setup({
      enable_on_startup = true,
      debug = false,
      server = "wss://api.ninetyfive.gg",
      mappings = {
        enabled = true,
        accept = "<Tab>",
        accept_word = "<A-h>",
        accept_line = "<A-j>",
        reject = "<A-w>",
      },
      indexing = {
        mode = "ask",
        cache_consent = true,
      },
    })
  end,
}
