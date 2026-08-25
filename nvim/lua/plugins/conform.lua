-- LazyVim registers `fish_indent` for fish files out of the box. Fish isn't
-- installed here and isn't used, so conform's health check reports it as a
-- missing formatter. Drop the mapping instead of installing fish; if you ever
-- do start writing fish scripts, delete this file and `brew install fish`.
return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.fish = nil
      return opts
    end,
  },
}
