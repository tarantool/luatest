bootstrap: .rocks

.rocks: luatest-scm-1.rockspec
	tarantoolctl rocks make ./luatest-scm-1.rockspec
	tarantoolctl rocks install http 1.1.0
	tarantoolctl rocks install luacheck
	tarantoolctl rocks install ldoc --server=http://rocks.moonscript.org

.PHONY: lint
lint: bootstrap
	.rocks/bin/luacheck ./

.PHONY: test
test: bootstrap
	bin/luatest

.PHONY: doc
doc:
	.rocks/bin/ldoc -t luatest-scm-1 -p "luatest (scm-1)" --all .

.PHONY: clean
clean:
	rm -rf .rocks
