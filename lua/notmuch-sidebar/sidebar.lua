local config = require("notmuch-sidebar.config")
local query = require("notmuch-sidebar.query")
local state = require("notmuch-sidebar.state")

local M = {}
local namespace
local on_select
local account_lines = {}
local content_window
local global_unread_line
local view_lines = {}
local count_error_notified = false
local refresh_id = 0

local function sidebar_buffer()
	return vim.fn.bufnr("NotmuchSidebar")
end

local function sidebar_window(buf)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			return win
		end
	end
end

local function remember_content_window()
	local win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(win) ~= sidebar_buffer() then
		content_window = win
	end
end

local function highlight(line, lines)
	if not line then
		return
	end
	vim.api.nvim_buf_set_extmark(sidebar_buffer(), namespace, line - 1, 0, {
		end_col = #lines[line],
		hl_group = "NotmuchSidebarActive",
		priority = 200,
	})
end

local function update_count(buf, line, search, format, id)
	vim.system({ "notmuch", "count", search }, { text = true }, function(result)
		vim.schedule(function()
			if id ~= refresh_id or not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			local count = result.code == 0 and tonumber(vim.trim(result.stdout))
			if count then
				count_error_notified = false
			elseif not count_error_notified then
				local message = result.stderr and result.stderr ~= "" and vim.trim(result.stderr)
					or "invalid count output"
				vim.notify("notmuch-sidebar: failed to count unread messages: " .. message, vim.log.levels.WARN)
				count_error_notified = true
			end

			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, line - 1, line, false, { format:format(count or "?") })
			vim.bo[buf].modifiable = false
		end)
	end)
end

function M.highlight_current()
	local buf = sidebar_buffer()
	if buf == -1 then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

	local current_buf = vim.api.nvim_get_current_buf()
	local ft = vim.bo[current_buf].filetype
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if ft == "notmuch-sidebar" then
		local account = state.active_account()
		if account then
			highlight(account_lines[account.root], lines)
			highlight(view_lines[state.active_view()], lines)
		elseif state.active_view() == "unread" then
			highlight(global_unread_line, lines)
		end
		return
	end
	if ft ~= "notmuch-threads" and ft ~= "mail" then
		return
	end

	local name = vim.api.nvim_buf_get_name(current_buf)
	local account = ft == "mail" and state.active_account() or state.current_account(current_buf)
	local view = ft == "mail" and state.active_view() or nil
	if account and ft == "notmuch-threads" then
		for _, candidate in ipairs(config.options.views) do
			local search = query.folder_query(account, candidate.key)
			if search and name:find(search, 1, true) then
				view = candidate.key
				state.set_active(account.root, view)
				break
			end
		end
	end

	if account then
		highlight(account_lines[account.root], lines)
		highlight(view_lines[view], lines)
	elseif name == query.global_unread_query() then
		highlight(global_unread_line, lines)
	end
end

function M.refresh()
	refresh_id = refresh_id + 1
	local id = refresh_id
	local buf = sidebar_buffer()
	if buf == -1 then
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, "NotmuchSidebar")
	end

	local lines, queries, line_account, line_global, line_view = {}, {}, {}, {}, {}
	account_lines, view_lines, global_unread_line = {}, {}, nil
	local account = state.active_account()

	if not account and config.options.unread.show_global_when_no_account then
		local search = query.global_unread_query()
		local label = "Unread (all accounts)"
		if config.options.unread.show_count then
			label = "Unread (all accounts: …)"
		end
		table.insert(lines, label)
		queries[#lines], line_global[#lines], line_view[#lines], global_unread_line = search, true, "unread", #lines
		if config.options.unread.show_count then
			update_count(buf, #lines, search, "Unread (all accounts: %s)", id)
		end
		table.insert(lines, string.rep("─", config.options.sidebar.width))
	end

	for _, candidate in ipairs(config.options.accounts) do
		table.insert(lines, candidate.name)
		account_lines[candidate.root] = #lines
		queries[#lines], line_account[#lines], line_view[#lines] =
			query.folder_query(candidate, "inbox"), candidate.root, "inbox"
	end

	if account then
		table.insert(lines, string.rep("─", config.options.sidebar.width))
		for _, view in ipairs(config.options.views) do
			local search = query.folder_query(account, view.key)
			if search then
				local label = view.label
				if view.key == "unread" and config.options.unread.show_count then
					label = "Unread (…)"
				end
				table.insert(lines, "  " .. label)
				queries[#lines], line_account[#lines], line_view[#lines], view_lines[view.key] =
					search, account.root, view.key, #lines
				if view.key == "unread" and config.options.unread.show_count then
					update_count(buf, #lines, search, "  Unread (%s)", id)
				end
			end
		end
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "notmuch-sidebar"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].undofile = false
	vim.keymap.set("n", "<CR>", function()
		local line = vim.fn.line(".")
		if queries[line] then
			on_select(queries[line], line_global[line] and nil or line_account[line], line_view[line])
		end
	end, { buffer = buf, desc = "Open mailbox" })
	vim.keymap.set("n", "q", M.close, { buffer = buf, desc = "Close sidebar" })
	vim.keymap.set("n", "r", M.refresh, { buffer = buf, desc = "Refresh sidebar" })
	M.highlight_current()
end

function M.open(focus)
	remember_content_window()
	M.refresh()
	local buf = sidebar_buffer()
	local win = sidebar_window(buf)
	if win then
		if focus then
			vim.api.nvim_set_current_win(win)
		end
		return
	end

	local command = config.options.sidebar.position == "right" and "botright" or "topleft"
	vim.cmd(("%s %dvnew"):format(command, config.options.sidebar.width))
	vim.api.nvim_win_set_buf(0, buf)
	vim.wo.number = false
	vim.wo.relativenumber = false
	vim.wo.signcolumn = "no"
	vim.wo.cursorline = false
	vim.wo.winfixwidth = true
	vim.wo.winhighlight = "Normal:NotmuchSidebarNormal,NormalNC:NotmuchSidebarNormal"
	vim.wo.wrap = false
	vim.wo.spell = false
	vim.wo.foldcolumn = "0"
	vim.wo.colorcolumn = ""
	vim.wo.statuscolumn = ""
	if not focus and content_window and vim.api.nvim_win_is_valid(content_window) then
		vim.api.nvim_set_current_win(content_window)
	end
end

function M.focus_content_window()
	if content_window and vim.api.nvim_win_is_valid(content_window) then
		vim.api.nvim_set_current_win(content_window)
		return true
	end

	local buf = sidebar_buffer()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) ~= buf then
			content_window = win
			vim.api.nvim_set_current_win(win)
			return true
		end
	end
	return false
end

function M.close()
	local buf = sidebar_buffer()
	local win = buf ~= -1 and sidebar_window(buf)
	if win then
		vim.api.nvim_win_close(win, true)
	end
end

function M.toggle()
	local buf = sidebar_buffer()
	local win = buf ~= -1 and sidebar_window(buf)
	if win then
		M.close()
	else
		M.open(true)
	end
end

function M.setup(opts)
	namespace = opts.namespace
	on_select = opts.on_select
end

return M
