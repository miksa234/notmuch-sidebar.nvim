local config = require("notmuch-sidebar.config")
local query = require("notmuch-sidebar.query")

local M = {}

function M.set_active(root, view)
	vim.g.notmuch_sidebar_active_account = root
	vim.g.notmuch_sidebar_active_view = view
end

function M.active_account()
	return query.account_by_root(vim.g.notmuch_sidebar_active_account)
end

function M.active_view()
	return vim.g.notmuch_sidebar_active_view
end

function M.current_account(buf)
	local name = vim.api.nvim_buf_get_name(buf or 0)
	for _, account in ipairs(config.options.accounts) do
		if query.matches_account(name, account) then
			return account
		end
	end
end

return M
