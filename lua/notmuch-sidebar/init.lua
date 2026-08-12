local config = require("notmuch-sidebar.config")
local query = require("notmuch-sidebar.query")
local sidebar = require("notmuch-sidebar.sidebar")
local state = require("notmuch-sidebar.state")

local M = {}
local installed_keymaps = {}

local keymap_actions = {
	archive = { view = "archive", desc = "Mail: archive" },
	flagged = { view = "flagged", desc = "Mail: flagged" },
	junk = { view = "junk", desc = "Mail: junk" },
	sent = { view = "sent", desc = "Mail: sent" },
	trash = { view = "trash", desc = "Mail: trash" },
	unread = { view = "unread", desc = "Mail: unread" },
}

local function open_query(search)
	sidebar.focus_content_window()
	require("notmuch").search_terms(search)
end

local function clear_keymaps()
	for _, mapping in ipairs(installed_keymaps) do
		local current = vim.fn.maparg(mapping.lhs, "n", false, true)
		if type(current) == "table" and current.desc == mapping.desc then
			pcall(vim.keymap.del, "n", mapping.lhs)
		end
	end
	installed_keymaps = {}
end

local function set_keymap(lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, { desc = desc })
	table.insert(installed_keymaps, { lhs = lhs, desc = desc })
end

function M.open()
	sidebar.open(true)
end

function M.toggle()
	sidebar.toggle()
end

function M.refresh()
	sidebar.refresh()
end

function M.open_account(account)
	if type(account) == "number" then
		account = config.options.accounts[account]
	end
	if type(account) == "string" then
		account = query.account_by_root(account)
	end
	if not account then
		vim.notify("notmuch-sidebar: account not found", vim.log.levels.WARN)
		return
	end
	state.set_active(account.root, "inbox")
	open_query(query.folder_query(account, "inbox"))
end

function M.open_view(view)
	local account = state.current_account() or state.active_account()
	if not account then
		vim.notify("Open an account inbox before selecting a mailbox", vim.log.levels.WARN)
		return
	end
	local search = query.folder_query(account, view)
	if not search then
		vim.notify(("notmuch-sidebar: %s is disabled for this account"):format(view), vim.log.levels.WARN)
		return
	end
	state.set_active(account.root, view)
	open_query(search)
end

function M.setup(opts)
	config.setup(opts)
	clear_keymaps()
	local namespace = vim.api.nvim_create_namespace("notmuch_sidebar")
	vim.api.nvim_set_hl(0, "NotmuchSidebarNormal", { default = true, link = "Normal" })
	vim.api.nvim_set_hl(0, "NotmuchSidebarActive", { default = true, link = "CursorLine" })
	sidebar.setup({
		namespace = namespace,
		on_select = function(search, root, view)
			state.set_active(root, view)
			open_query(search)
		end,
	})

	if config.options.keymaps.toggle then
		set_keymap(config.options.keymaps.toggle, M.toggle, "Mail: sidebar")
	end
	for name, action in pairs(keymap_actions) do
		local lhs = config.options.keymaps[name]
		if lhs then
			set_keymap(lhs, function()
				M.open_view(action.view)
			end, action.desc)
		end
	end

	vim.api.nvim_create_user_command("NotmuchSidebar", M.open, { desc = "Open Notmuch sidebar", force = true })
	vim.api.nvim_create_user_command(
		"NotmuchSidebarToggle",
		M.toggle,
		{ desc = "Toggle Notmuch sidebar", force = true }
	)
	vim.api.nvim_create_user_command(
		"NotmuchSidebarRefresh",
		M.refresh,
		{ desc = "Refresh Notmuch sidebar", force = true }
	)

	local group = vim.api.nvim_create_augroup("NotmuchSidebar", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = { "mail", "notmuch-threads" },
		callback = function()
			if config.options.sidebar.auto_open then
				sidebar.open(false)
			else
				sidebar.refresh()
			end
			sidebar.highlight_current()
		end,
	})
	vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
		group = group,
		callback = sidebar.highlight_current,
	})
end

return M
