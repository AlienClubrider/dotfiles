return {
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    keys = {
      { "<leader>g", function() require("neogit").open() end, desc = "Open Neogit" },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    event = "BufWinEnter",
    opts = {
      current_line_blame = true,
    },
  },
}
