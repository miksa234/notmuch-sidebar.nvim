local M = {}

local view_keys = {
	archive = true,
	inbox = true,
	junk = true,
	sent = true,
	trash = true,
	unread = true,
}

local folder_keys = { "inbox", "archive", "sent", "trash", "junk" }

local function option_error(message)
	error("notmuch-sidebar: " .. message, 3)
end

local function non_empty_string(value)
	return type(value) == "string" and value ~= ""
end

local function validate_folder(account, key)
	local folders = account[key]
	if folders == nil or folders == false then
		return
	end
	if type(folders) ~= "table" or not vim.islist(folders) or vim.tbl_isempty(folders) then
		option_error(("account %q: %s must be false or a non-empty list of folder names"):format(account.name, key))
	end
	for _, folder in ipairs(folders) do
		if not non_empty_string(folder) then
			option_error(("account %q: %s folder names must be non-empty strings"):format(account.name, key))
		end
	end
end

M.defaults = {
	accounts = {},
	views = {
		{ key = "inbox", label = "Inbox" },
		{ key = "unread", label = "Unread" },
		{ key = "archive", label = "Archive" },
		{ key = "sent", label = "Sent" },
		{ key = "trash", label = "Trash" },
		{ key = "junk", label = "Junk" },
	},
	sidebar = {
		auto_open = true,
		position = "left",
		width = 22,
	},
	unread = {
		show_count = true,
		show_global_when_no_account = true,
	},
	keymaps = {
		toggle = "<leader>m",
		archive = "<leader>ma",
		sent = "<leader>ms",
		trash = "<leader>mt",
		junk = "<leader>mj",
		unread = "<leader>mu",
		flagged = "<leader>mf",
	},
}

function M.setup(opts)
	local options = vim.tbl_deep_extend("force", M.defaults, opts or {})
	if opts and opts.views then
		options.views = vim.deepcopy(opts.views)
	end

	if type(options.accounts) ~= "table" or not vim.islist(options.accounts) then
		option_error("accounts must be a list")
	end
	local roots = {}
	local names = {}

	for _, account in ipairs(options.accounts) do
		if type(account) ~= "table" then
			option_error("accounts must contain tables")
		end
		if not non_empty_string(account.name) then
			option_error("every account needs a non-empty name")
		end
		if not non_empty_string(account.root) then
			option_error(("account %q needs a non-empty root"):format(account.name))
		end
		if names[account.name] then
			option_error(("account name %q is duplicated"):format(account.name))
		end
		if roots[account.root] then
			option_error(("account root %q is duplicated"):format(account.root))
		end
		for root in pairs(roots) do
			local account_inside_root = account.root:sub(1, #root + 1) == root .. "/"
			local root_inside_account = root:sub(1, #account.root + 1) == account.root .. "/"
			if account_inside_root or root_inside_account then
				option_error(("account roots %q and %q overlap"):format(root, account.root))
			end
		end
		names[account.name] = true
		roots[account.root] = true
		for _, key in ipairs(folder_keys) do
			if key == "inbox" and account.inbox == false then
				option_error(("account %q: inbox cannot be disabled"):format(account.name))
			end
			validate_folder(account, key)
		end
	end

	if type(options.views) ~= "table" or not vim.islist(options.views) or vim.tbl_isempty(options.views) then
		option_error("views must be a non-empty list")
	end
	local configured_views = {}
	for _, view in ipairs(options.views) do
		if type(view) ~= "table" or not view_keys[view.key] then
			option_error("views may only use inbox, unread, archive, sent, trash, and junk")
		end
		if configured_views[view.key] then
			option_error(("view %q is duplicated"):format(view.key))
		end
		if not non_empty_string(view.label) then
			option_error(("view %q needs a non-empty label"):format(view.key))
		end
		configured_views[view.key] = true
	end

	if type(options.sidebar) ~= "table" then
		option_error("sidebar must be a table")
	end
	if options.sidebar.position ~= "left" and options.sidebar.position ~= "right" then
		option_error("sidebar.position must be left or right")
	end
	if type(options.sidebar.width) ~= "number" or options.sidebar.width < 1 or options.sidebar.width % 1 ~= 0 then
		option_error("sidebar.width must be a positive integer")
	end
	if type(options.sidebar.auto_open) ~= "boolean" then
		option_error("sidebar.auto_open must be a boolean")
	end
	if type(options.unread) ~= "table" then
		option_error("unread must be a table")
	end
	for key, value in pairs(options.unread) do
		if type(value) ~= "boolean" then
			option_error(("unread.%s must be a boolean"):format(key))
		end
	end
	if type(options.keymaps) ~= "table" then
		option_error("keymaps must be a table")
	end
	for key, value in pairs(options.keymaps) do
		if value ~= false and not non_empty_string(value) then
			option_error(("keymaps.%s must be a non-empty string or false"):format(key))
		end
	end

	M.options = options
end

return M
