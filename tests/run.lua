local failures = {}
local tests_run = 0

local function test(name, fn)
	tests_run = tests_run + 1
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		print("ok - " .. name)
	else
		table.insert(failures, name .. "\n" .. err)
	end
end

local function eq(actual, expected)
	assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. " ~= " .. vim.inspect(expected))
end

local searches = {}
local search_windows = {}
local system_requests = {}
local content_window

vim.system = function(command, options, callback)
	table.insert(system_requests, { command = command, options = options, callback = callback })
	return {}
end

package.preload["notmuch"] = function()
	return {
		search_terms = function(search)
			table.insert(searches, search)
			table.insert(search_windows, vim.api.nvim_get_current_win())
		end,
	}
end

local sidebar = require("notmuch-sidebar")
local config = require("notmuch-sidebar.config")
local query = require("notmuch-sidebar.query")
local state = require("notmuch-sidebar.state")

local function complete_count(request, code, stdout, stderr)
	request.callback({ code = code, stdout = stdout or "", stderr = stderr or "" })
	vim.wait(20)
end

local function sidebar_buffer()
	return vim.fn.bufnr("NotmuchSidebar")
end

local function sidebar_window()
	local buf = sidebar_buffer()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			return win
		end
	end
	error("sidebar window not found")
end

local function sidebar_lines()
	return vim.api.nvim_buf_get_lines(sidebar_buffer(), 0, -1, false)
end

local setup_options = {
	accounts = {
		{ name = "Personal", root = "personal" },
		{
			name = "Work",
			root = "work",
			archive = false,
			sent = { "Sent", "Sent Messages" },
			junk = { "Spam" },
		},
	},
	sidebar = { auto_open = false, width = 16 },
}

sidebar.setup(setup_options)

test("builds default and overridden folder queries", function()
	local personal = query.account_by_root("personal")
	local work = query.account_by_root("work")

	eq(query.folder_query(personal, "inbox"), 'path:"personal/INBOX/**"')
	eq(query.folder_query(personal, "unread"), 'path:"personal/**" and tag:unread')
	eq(query.folder_query(work, "archive"), nil)
	eq(query.folder_query(work, "sent"), '(path:"work/Sent/**" or path:"work/Sent Messages/**")')
	eq(query.folder_query(work, "junk"), 'path:"work/Spam/**"')
	eq(query.folder_query({ root = 'quoted"\\root' }, "inbox"), 'path:"quoted\\"\\\\root/INBOX/**"')
	eq(query.folder_query({ root = "custom", inbox = { "Primary" } }, "inbox"), 'path:"custom/Primary/**"')
	eq(
		query.folder_query({ root = "custom", inbox = { "Primary", 'Other "Inbox"' } }, "inbox"),
		'(path:"custom/Primary/**" or path:"custom/Other \\"Inbox\\"/**")'
	)
end)

test("validates configuration during setup", function()
	local active_width = config.options.sidebar.width
	local invalid_options = {
		{ accounts = {}, sidebar = { width = 0 } },
		{ accounts = {}, views = { { key = "custom", label = "Custom" } } },
		{ accounts = { { name = "A", root = "mail" }, { name = "B", root = "mail/work" } } },
		{ accounts = { { name = "A", root = "mail", inbox = false } } },
	}
	for _, options in ipairs(invalid_options) do
		local ok, err = pcall(config.setup, options)
		assert(not ok and tostring(err):find("notmuch%-sidebar:"), "expected a contextual configuration error")
		eq(config.options.sidebar.width, active_width)
	end
end)

test("matches accounts only in path queries", function()
	local buf = vim.api.nvim_create_buf(false, true)
	state.set_active("work", "inbox")
	vim.api.nvim_buf_set_name(buf, "unrelated-personal-message")
	eq(state.current_account(buf), nil)
	vim.api.nvim_buf_set_name(buf, 'notmuch://path:"personal/INBOX/**"')
	eq(state.current_account(buf).root, "personal")
	eq(state.active_account().root, "work")
	eq(state.active_view(), "inbox")
	vim.api.nvim_buf_delete(buf, { force = true })
end)

test("tracks selected account and view", function()
	state.set_active("personal", "unread")
	eq(state.active_account().root, "personal")
	eq(state.active_view(), "unread")

	state.set_active(nil, "unread")
	eq(state.active_account(), nil)
	eq(state.active_view(), "unread")
end)

test("registers user commands", function()
	eq(vim.fn.exists(":NotmuchSidebar"), 2)
	eq(vim.fn.exists(":NotmuchSidebarToggle"), 2)
	eq(vim.fn.exists(":NotmuchSidebarRefresh"), 2)
end)

test("registers default mailbox mappings", function()
	local mappings = vim.api.nvim_get_keymap("n")
	local defaults = {
		"<leader>m",
		"<leader>ma",
		"<leader>ms",
		"<leader>mt",
		"<leader>mj",
		"<leader>mu",
		"<leader>mf",
	}
	for _, lhs in ipairs(defaults) do
		local expanded = lhs:gsub("<leader>", vim.g.mapleader or "\\")
		local mapped_keys = vim.tbl_map(function(map)
			return map.lhs
		end, mappings)
		local found = vim.tbl_contains(mapped_keys, expanded)
		assert(found, "missing mapping: " .. lhs)
	end
end)

test("renders global unread and account rows", function()
	state.set_active(nil, nil)
	content_window = vim.api.nvim_get_current_win()
	sidebar.open()
	local buf = sidebar_buffer()
	eq(vim.bo[buf].filetype, "notmuch-sidebar")
	eq(sidebar_lines(), {
		"Unread (all accounts: …)",
		string.rep("─", 16),
		"Personal",
		"Work",
	})
	local request = system_requests[#system_requests]
	eq(request.command, { "notmuch", "count", "tag:unread" })
	complete_count(request, 0, "9\n")
	eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "Unread (all accounts: 9)")
end)

test("configures the sidebar buffer and window", function()
	local buf = sidebar_buffer()
	local win = sidebar_window()
	eq(vim.fn.buflisted(buf), 0)
	eq(vim.bo[buf].buftype, "nofile")
	eq(vim.bo[buf].bufhidden, "hide")
	eq(vim.bo[buf].swapfile, false)
	eq(vim.wo[win].wrap, false)
	eq(vim.wo[win].spell, false)
	eq(vim.wo[win].winhighlight, "Normal:NotmuchSidebarNormal,NormalNC:NotmuchSidebarNormal")
end)

test("opens global unread from the sidebar", function()
	local win = sidebar_window()
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)
	vim.wait(20)
	eq(searches[#searches], "tag:unread")
	eq(state.active_account(), nil)
	eq(state.active_view(), "unread")
	eq(search_windows[#search_windows], content_window)
end)

test("opens an account inbox in the content window", function()
	state.set_active(nil, nil)
	sidebar.refresh()
	local win = sidebar_window()
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_cursor(win, { 3, 0 })
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)
	vim.wait(20)
	eq(searches[#searches], 'path:"personal/INBOX/**"')
	eq(search_windows[#search_windows], content_window)
	eq(state.active_account().root, "personal")
	eq(state.active_view(), "inbox")
	assert(vim.api.nvim_win_is_valid(win), "sidebar window should remain visible")
end)

test("routes public mailbox APIs away from the sidebar", function()
	local win = sidebar_window()
	vim.api.nvim_set_current_win(win)

	sidebar.open_account("personal")
	eq(searches[#searches], 'path:"personal/INBOX/**"')
	eq(search_windows[#search_windows], content_window)

	vim.api.nvim_set_current_win(win)
	sidebar.open_view("unread")
	eq(searches[#searches], 'path:"personal/**" and tag:unread')
	eq(search_windows[#search_windows], content_window)
	assert(vim.api.nvim_win_is_valid(win), "sidebar window should remain visible")
end)

test("renders selected account folders and unread message count", function()
	state.set_active("personal", "unread")
	sidebar.refresh()
	local buf = sidebar_buffer()
	local lines = sidebar_lines()
	eq(lines[1], "Personal")
	eq(lines[2], "Work")
	eq(lines[4], "  Inbox")
	eq(lines[5], "  Unread (…)")
	eq(lines[6], "  Archive")
	complete_count(system_requests[#system_requests], 0, "3\n")
	eq(vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1], "  Unread (3)")
end)

test("retains active highlights when refreshed from the sidebar", function()
	state.set_active("personal", "unread")
	local buf = sidebar_buffer()
	local win = sidebar_window()
	vim.api.nvim_set_current_win(win)
	sidebar.refresh()
	local namespace = vim.api.nvim_create_namespace("notmuch_sidebar")
	local marks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {})
	assert(#marks >= 2, "account and view highlights should remain active")
end)

test("hides and rejects disabled folders", function()
	sidebar.open_account("work")
	local search_count = #searches
	sidebar.open_view("archive")
	eq(#searches, search_count)

	sidebar.refresh()
	local lines = sidebar_lines()
	assert(not vim.tbl_contains(lines, "  Archive"), "disabled archive should not be rendered")
end)

test("keeps the sidebar usable when unread counting fails", function()
	state.set_active("personal", "unread")
	sidebar.refresh()
	complete_count(system_requests[#system_requests], 1, "", "count failed\n")
	local lines = sidebar_lines()
	assert(vim.tbl_contains(lines, "  Unread (?)"), "failed counts should use a placeholder")
end)

test("ignores stale unread count results", function()
	state.set_active("personal", "unread")
	sidebar.refresh()
	local stale_request = system_requests[#system_requests]
	state.set_active("work", "unread")
	sidebar.refresh()
	complete_count(stale_request, 0, "99\n")

	local lines = sidebar_lines()
	assert(vim.tbl_contains(lines, "  Unread (…)"), "stale count should not update the current account")
	assert(not vim.tbl_contains(lines, "  Unread (99)"), "stale count was rendered")
end)

test("keeps the global sidebar in its original tab during background refresh", function()
	local sidebar_ui = require("notmuch-sidebar.sidebar")
	local buf = sidebar_buffer()
	local sidebar_tab
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			sidebar_tab = vim.api.nvim_win_get_tabpage(win)
		end
	end

	vim.cmd("tabnew")
	local extra_tab = vim.api.nvim_get_current_tabpage()
	sidebar_ui.open(false)
	eq(vim.api.nvim_get_current_tabpage(), extra_tab)
	sidebar_ui.open(true)
	eq(vim.api.nvim_get_current_tabpage(), sidebar_tab)

	vim.api.nvim_set_current_tabpage(extra_tab)
	vim.cmd("tabclose")
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(sidebar_tab)) do
		if vim.api.nvim_win_get_buf(win) ~= buf then
			vim.api.nvim_set_current_win(win)
			sidebar_ui.open(false)
			break
		end
	end
end)

test("supports repeated setup and removes old plugin mappings", function()
	sidebar.setup(vim.tbl_deep_extend("force", setup_options, {
		keymaps = { toggle = "<leader>x", archive = false },
	}))
	eq(vim.fn.maparg("<leader>m", "n"), "")
	assert(vim.fn.maparg("<leader>x", "n") ~= "", "replacement toggle mapping should exist")
	eq(vim.fn.maparg("<leader>ma", "n"), "")
	sidebar.setup(setup_options)
end)

if #failures > 0 then
	error(table.concat(failures, "\n\n"))
end

print(("%d tests passed"):format(tests_run))
