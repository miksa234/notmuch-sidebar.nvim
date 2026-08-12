cache = true

std = "luajit"

codes = true

-- List of warnings: https://luacheck.readthedocs.io/en/stable/warnings.html
ignore = {
  "122", -- Indirectly setting a readonly global
}

read_globals = {
  "vim",
}
