local config = require("notmuch-sidebar.config")

local M = {}

local function escape_term(value)
	return value:gsub("\\", "\\\\"):gsub('"', '\\"')
end

function M.account_by_root(root)
	for _, account in ipairs(config.options.accounts) do
		if account.root == root then
			return account
		end
	end
end

function M.folder_query(account, view)
	local root = escape_term(account.root)
	if view == "unread" or view == "flagged" then
		return ('path:"%s/**" and tag:%s'):format(root, view)
	end

	local override = account[view]
	if override == false then
		return nil
	end

	local defaults = {
		inbox = { "INBOX" },
		archive = { "Archive" },
		sent = { "Sent" },
		trash = { "Trash" },
		junk = { "Junk" },
	}
	local folders = override or defaults[view]
	if not folders then
		return nil
	end
	local queries = {}
	for _, folder in ipairs(folders) do
		table.insert(queries, ('path:"%s/%s/**"'):format(root, escape_term(folder)))
	end
	return #queries == 1 and queries[1] or "(" .. table.concat(queries, " or ") .. ")"
end

function M.matches_account(search, account)
	return search:find(('path:"%s/'):format(escape_term(account.root)), 1, true) ~= nil
end

function M.global_unread_query()
	return "tag:unread"
end

return M
