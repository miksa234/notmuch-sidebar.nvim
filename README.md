# notmuch-sidebar.nvim

A Neomutt-inspired sidebar for
[notmuch.nvim](https://github.com/yousefakbar/notmuch.nvim).

## Requirements

- Neovim >= 0.10
- [notmuch.nvim](https://github.com/yousefakbar/notmuch.nvim)
- A working notmuch database

## Installation

```lua
{
  "miksa234/notmuch-sidebar.nvim",
  dependencies = { "yousefakbar/notmuch.nvim" },
}
```

## Example Configuration

```lua
local accounts = {
  { name = "Personal", root = "personal@example.com" },
  { name = "Work", root = "work@example.com" },
}

return {
  {
    "yousefakbar/notmuch.nvim",
    opts = {
      maildir_sync_cmd = "mbsync -a -q && notmuch new",
    },
    config = function(_, opts)
      require("notmuch").setup(opts)
    end,
  },
  {
    "miksa234/notmuch-sidebar.nvim",
    dependencies = { "yousefakbar/notmuch.nvim" },
    event = "VeryLazy",
    opts = { accounts = accounts },
    config = function(_, opts)
      require("notmuch-sidebar").setup(opts)
    end,
    keys = {
      {
        "<leader>m1",
        function()
          require("notmuch-sidebar").open_account("personal@example.com")
        end,
        desc = "Inbox: Personal",
      },
      {
        "<leader>m2",
        function()
          require("notmuch-sidebar").open_account("work@example.com")
        end,
        desc = "Inbox: Work",
      },
    },
  },
}
```

`name` is the sidebar label. `root` is the Maildir path used in notmuch
queries.

## Configuration

Defaults:

```lua
require("notmuch-sidebar").setup({
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
})
```

Override account folders when they differ from the defaults:

```lua
accounts = {
  {
    name = "Work",
    root = "work@example.com",
    inbox = { "Inbox", "Primary" },
    sent = { "Sent", "Sent Messages" },
    junk = { "Junk", "Spam" },
    trash = false,
  },
}
```

Inbox defaults to `{ "INBOX" }` and can contain one or more custom folder
names, but it cannot be disabled because account rows open the Inbox view.
Set any other account folder or keymap to `false` to disable it. Views support
`inbox`, `unread`, `archive`, `sent`, `trash`, and `junk`.

## Usage

Sidebar mappings:

- `<Enter>` opens an account or mailbox.
- `r` refreshes the sidebar and unread counts.
- `q` closes the sidebar.

Commands:

- `:NotmuchSidebar`
- `:NotmuchSidebarToggle`
- `:NotmuchSidebarRefresh`

Lua API:

- `open()`
- `toggle()`
- `refresh()`
- `open_account(root)`
- `open_view(view)`

Functions are available from `require("notmuch-sidebar")`.

The plugin uses one global sidebar. Opening it from another tab focuses its
existing tab; automatic refreshes do not change focus.

Unread counts update asynchronously. Count failures display `?` without
closing the sidebar.

## Highlights

- `NotmuchSidebarNormal` links to `Normal`.
- `NotmuchSidebarActive` links to `CursorLine`.

```lua
vim.api.nvim_set_hl(0, "NotmuchSidebarNormal", { bg = "#191724" })
vim.api.nvim_set_hl(0, "NotmuchSidebarActive", {
  fg = "#f6c177",
  bg = "#26233a",
  bold = true,
})
```

Apply overrides after loading your colorscheme.

## Testing

```sh
make lint
make test
```

## License

[MIT](LICENSE)
