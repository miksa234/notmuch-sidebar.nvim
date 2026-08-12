.PHONY: lint test clean

lint:
	luacheck lua tests

test:
	nvim --headless -u tests/minimal.lua -c "lua dofile('tests/run.lua')" -c qa

clean:
	rm -rf .cache .tmp doc/tags
