.deps/docgen.nvim:
	git clone --depth 1 --branch v1.1.0 https://github.com/jamestrew/docgen.nvim $@

.PHONY: docgen
docgen: .deps/docgen.nvim
	nvim -l scripts/gendoc.lua
