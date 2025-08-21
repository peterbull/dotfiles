-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("i", "jk", "<ESC>", { noremap = true, silent = true })

-- Center view on cursor for half page jumps
vim.keymap.set("n", "<C-d>", "<C-d>zz", { noremap = true, silent = true })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { noremap = true, silent = true })

-- Molten
vim.keymap.set("n", "<leader>mi", ":MoltenInit<CR>", { silent = true, desc = "Initialize the plugin" })
vim.keymap.set("n", "<leader>rl", ":MoltenEvaluateOperator<CR>", { silent = true, desc = "run operator selection" })
vim.keymap.set("n", "<leader>rl", ":MoltenEvaluateLine<CR>", { silent = true, desc = "evaluate line" })
vim.keymap.set("n", "<leader>rr", ":MoltenReevaluateCell<CR>", { silent = true, desc = "re-evaluate cell" })
vim.keymap.set(
  "v",
  "<leader>r",
  ":<C-u>MoltenEvaluateVisual<CR>gv",
  { silent = true, desc = "evaluate visual selection" }
)

vim.keymap.set("n", "<leader>rd", ":MoltenDelete<CR>", { silent = true, desc = "molten delete cell" })
vim.keymap.set("n", "<leader>oh", ":MoltenHideOutput<CR>", { silent = true, desc = "hide output" })
vim.keymap.set("n", "<leader>os", ":noautocmd MoltenEnterOutput<CR>", { silent = true, desc = "show/enter output" })

-- Copilot keymaps
vim.keymap.set("n", "<leader>a", "", { desc = "+ai" })
vim.keymap.set({ "n", "v" }, "<leader>aa", function()
  return require("CopilotChat").toggle()
end, { desc = "Toggle Copilot Chat" })

-- LSPsaga keymaps
vim.keymap.set("n", "K", "<cmd>Lspsaga hover_doc")

vim.keymap.set({ "n", "v" }, "<leader>aq", function()
  local input = vim.fn.input("Quick Chat: ")
  if input ~= "" then
    require("CopilotChat").ask(input)
  end
end, { desc = "Quick Chat" })

-- Neo-tree yank file content
vim.api.nvim_create_autocmd("FileType", {
  pattern = "neo-tree",
  callback = function(event)
    -- Function to yank content
    local function yank_content(append)
      -- Get the neo-tree state directly from the renderer
      local state = require("neo-tree.sources.manager").get_state("filesystem")
      if not state then
        vim.notify("Failed to get neo-tree state", vim.log.levels.ERROR)
        return
      end

      local node = state.tree:get_node()
      if not node then
        vim.notify("No node selected", vim.log.levels.ERROR)
        return
      end

      if node.type == "file" then
        local filepath = node:get_id()
        local ok, content = pcall(function()
          local file = io.open(filepath, "r")
          if not file then
            return nil
          end
          local content = file:read("*all")
          file:close()
          return content
        end)

        if not ok or not content then
          vim.notify("Failed to read file: " .. filepath, vim.log.levels.ERROR)
          return
        end

        if content and content ~= "" then
          -- Remove trailing newline if present
          content = content:gsub("\n$", "")

          if append then
            -- Get current clipboard content and ensure it exists
            local current_content = vim.fn.getreg("+")
            if current_content and current_content ~= "" then
              content = current_content .. "\n" .. content
              vim.notify("Appended content from: " .. node.name, vim.log.levels.INFO)
            else
              vim.notify("No existing content to append to, yanking new content", vim.log.levels.WARN)
            end
          else
            vim.notify("Yanked content from: " .. node.name, vim.log.levels.INFO)
          end

          -- Set to both the unnamed register and system clipboard
          vim.fn.setreg('"', content)
          vim.fn.setreg("+", content)
        else
          vim.notify("File is empty: " .. node.name, vim.log.levels.WARN)
        end
      else
        vim.notify("Not a file", vim.log.levels.WARN)
      end
    end

    -- Regular yank
    vim.keymap.set("n", "<leader>Y", function()
      yank_content(false)
    end, { buffer = event.buf, desc = "Yank file content" })

    -- Append yank (using different leader key to avoid conflicts)
    vim.keymap.set("n", "<leader>A", function()
      yank_content(true)
    end, { buffer = event.buf, desc = "Append file content to clipboard" })
  end,
})
