bootstrap: .rocks

.rocks: luatest-scm-1.rockspec
	tarantoolctl rocks make ./luatest-scm-1.rockspec
	tarantoolctl rocks install http
	tarantoolctl rocks install https://raw.githubusercontent.com/mpeterv/luacheck/master/luacheck-dev-1.rockspec

.PHONY: lint
lint: bootstrap
	.rocks/bin/luacheck ./

.PHONY: test
test: bootstrap
	bin/luatest

.PHONY: clean
clean:
	rm -rf .rocks
