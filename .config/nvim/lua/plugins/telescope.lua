return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "debugloop/telescope-undo.nvim",
      config = function()
        require("telescope").load_extension("undo")
      end,
    },
    keys = {
      { "<C-space>", "<cmd>Telescope buffers show_all_buffers=true<cr>", desc = "Switch Buffer" },
      { "<leader><space>", "<cmd>Telescope buffers show_all_buffers=true<cr>", desc = "Switch Buffer" },
      { "<leader>p", "<cmd>Telescope find_files<cr>", desc = "Find Files (root dir)" },
      { "<leader>;", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Find in buffer" },
      { "<leader>su", "<cmd>Telescope undo<cr>", desc = "Undo history" },
      {
        "<leader>gb",
        function()
          require("telescope.builtin").git_branches({
            on_complete = {
              function(selection)
                -- Open diffview comparing with selected branch
                vim.cmd("DiffviewOpen " .. selection.value)
              end,
            },
          })
        end,
        desc = "Git Branches (with Diff)",
      },
      {
        "<leader>o",
        function()
          require("telescope.builtin").lsp_document_symbols({
            symbols = {
              "Class",
              "Function",
              "Method",
              "Constant",
              "Constructor",
              "Interface",
              "Module",
              "Struct",
              "Trait",
              "Field",
              "Property",
              "Variable",
            },
          })
        end,
        { desc = "Goto symbol" },
      },
    },
    opts = {
      pickers = {
        git_commits = {
          mappings = {
            i = {
              ["<C-d>"] = function() -- show diffview for the selected commit
                -- Open in diffview
                local entry = require("telescope.actions.state").get_selected_entry()
                -- close Telescope window properly prior to switching windows
                require("telescope.actions").close(vim.api.nvim_get_current_buf())
                vim.cmd(("DiffviewOpen %s^!"):format(entry.value))
              end,
            },
          },
        },
        git_bcommits = {
          mappings = {
            i = {
              ["<C-d>"] = function() -- show diffview for the selected commit of current buffer
                -- Open in diffview
                local entry = require("telescope.actions.state").get_selected_entry()
                -- close Telescope window properly prior to switching windows
                require("telescope.actions").close(vim.api.nvim_get_current_buf())
                vim.cmd(("DiffviewOpen %s^!"):format(entry.value))
              end,
            },
          },
        },
        git_branches = {
          mappings = {
            i = {
              ["<C-d>"] = function() -- show diffview comparing the selected branch with the current branch
                -- Open in diffview
                local entry = require("telescope.actions.state").get_selected_entry()
                -- close Telescope window properly prior to switching windows
                require("telescope.actions").close(vim.api.nvim_get_current_buf())
                vim.cmd(("DiffviewOpen %s.."):format(entry.value))
              end,
            },
          },
        },
        buffers = {
          initial_mode = "normal",
          show_all_buffers = true,
          sort_mru = true,
          mappings = {
            i = {
              ["<C-d>"] = function(...)
                require("telescope.actions").delete_buffer(...)
              end,
            },
            n = {
              ["v"] = function(...)
                require("telescope.actions").file_vsplit(...)
              end,
              ["s"] = function(...)
                require("telescope.actions").file_split(...)
              end,
              ["d"] = function(...)
                require("telescope.actions").delete_buffer(...)
              end,
              ["c"] = function(...)
                require("telescope.actions").delete_buffer(...)
              end,
              ["<C-j>"] = function(...)
                require("telescope.actions").move_selection_next(...)
              end,
              ["<C-k>"] = function(...)
                require("telescope.actions").move_selection_previous(...)
              end,
            },
          },
        },
      },
      defaults = {
        mappings = {
          i = {
            ["<C-n>"] = function(...)
              require("telescope.actions").move_selection_next(...)
            end,
            ["<C-j>"] = function(...)
              require("telescope.actions").move_selection_next(...)
            end,
            ["<C-p>"] = function(...)
              require("telescope.actions").move_selection_previous(...)
            end,
            ["<C-k>"] = function(...)
              require("telescope.actions").move_selection_previous(...)
            end,
            ["<C-n>"] = function(...)
              return require("telescope.actions").preview_scrolling_down(...)
            end,
            ["<C-p>"] = function(...)
              return require("telescope.actions").preview_scrolling_up(...)
            end,
          },
          n = {
            ["v"] = function(...)
              require("telescope.actions").file_vsplit(...)
            end,
            ["s"] = function(...)
              require("telescope.actions").file_split(...)
            end,
            ["<C-n>"] = function(...)
              return require("telescope.actions").preview_scrolling_down(...)
            end,
            ["<C-p>"] = function(...)
              return require("telescope.actions").preview_scrolling_up(...)
            end,
          },
        },
      },
    },
  },
}
