return {
	"OXY2DEV/markview.nvim",
	lazy = false, -- already lazy-loaded internally, don't lazy-load
	dependencies = {
		"saghen/blink.cmp", -- callout/checkbox completions
	},
	config = function()
		require("markview").setup()
	end,
}
