return {
  -- {
  --   "navarasu/onedark.nvim",
  --   opts = {
  --     style = "cool",
  --   },
  -- },
  {
    "navarasu/onedark.nvim",
    opts = {
      colors = {
        -- You can customize colors if needed
        bright_orange = "#ff8800",
        green = "#98c379",
        blue = "#61afef",
        yellow = "#e5c07b",
        purple = "#c678dd",
      },
      code_style = {
        comments = "italic",
        keywords = "bold",
        functions = "bold",
        strings = "none",
        variables = "none",
      },
      highlights = {
        ["@keyword"] = { fg = "#c678dd", fmt = "bold" }, -- Purple bold
        ["@keyword.function"] = { fg = "#c678dd", fmt = "bold" }, -- Purple bold
        ["@function"] = { fg = "#61afef", fmt = "bold" }, -- Blue bold
        ["@function.builtin"] = { fg = "#61afef", fmt = "bold" }, -- Blue bold
        ["@variable"] = { fg = "#e06c75", fmt = "none" }, -- Red normal
        ["@parameter"] = { fg = "#e06c75", fmt = "none" }, -- Red normal
        ["@string"] = { fg = "#98c379", fmt = "none" }, -- Green normal
        ["@type"] = { fg = "#e5c07b", fmt = "bold" }, -- Yellow bold
        ["@comment"] = { fg = "#7f848e", fmt = "italic" }, -- Grey italic

        -- Additional common highlights
        Keyword = { fg = "#c678dd", fmt = "bold" },
        Function = { fg = "#61afef", fmt = "bold" },
        String = { fg = "#98c379", fmt = "none" },
        Variable = { fg = "#e06c75", fmt = "none" },
        Type = { fg = "#e5c07b", fmt = "bold" },
        Comment = { fg = "#7f848e", fmt = "italic" },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "onedark",
    },
  },
}
