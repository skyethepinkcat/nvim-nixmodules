--- @class nixmodules
--- @field config nixmodules.config
local M = {}

--- @class nixmodules.config
--- @field output string? The flake output path to use.
--- @field nix_path string The path to the nix binary. Defaults to `nix`.
--- @field flake string The path to the nix flake. Defaults to `.`.
--- @field jq_path string The path to the jq executable. Defaults to `jq`.
--- @field command_timeout integer MS to wait until killing nix eval. Defaults to 1 minute since nix
--  commands can take a long time.
M.config = {}

---Setup with opts.
---@param opts table?
---@return nixmodules
function M.setup(opts)
	M.config = assert(vim.tbl_deep_extend("keep", opts or {}, {
		output = nil,
		nix_path = "nix",
		flake = ".",
		jq_path = "jq",
		command_timeout = 1000 * 60, -- One minute timeout by default
	}))
	return M
end

---Debug function, outputs a table as a string.
---@return string
---@diagnostic disable-next-line: unused-function
local function dump(o)
	if type(o) == "table" then
		local s = "{ "
		for k, v in pairs(o) do
			if type(k) ~= "number" then
				k = '"' .. k .. '"'
			end
			s = s .. "[" .. k .. "] = " .. dump(v) .. ","
		end
		return s .. "} "
	else
		return tostring(o)
	end
end

local api = vim.api

local ts = vim.treesitter

--- @param path string
local function add_dot(path)
	if path == "" then
		return path
	end
	return path .. "."
end

--- @param node TSNode
--- @return string[]
local function print_node(node)
	if node:type() == "binding" then
		local attrpath = node:field("attrpath")[1]
		if attrpath ~= nil then
			return { ts.get_node_text(attrpath, 0, {}) }
		end
	end
	return {}
end

--- Check if this node is parseable.
--- @param node TSNode
--- @param dest TSNode
--- @return boolean
local function check_parseable(node, dest)
	local invalid_types = { "list_expression" }
	if vim.tbl_contains(invalid_types, node:type()) then
		return false
	end

	local body_types = { "let_expression", "function_expression" }
	if vim.tbl_contains(body_types, node:type()) then
		local child = assert(node:child_with_descendant(dest))
		local body = node:field("body")

		if body == nil or body[1] == nil then
			return false
		end

		-- If we aren't in the body of a function or let expression, its not possible to go
		-- deeper
		if not child:equal(body[1]) then
			return false
		end
	end
	return true
end

--- Turns recurses through a list of nodes and turns them into a single nix attrset path.
--- @param root TSNode
--- @param dest TSNode
--- @param fullPath string[]
--- @return string[]
local function concat_nodes(root, dest, fullPath)
	-- Check if we reach a type we can't parse, and exit if so.
	if not check_parseable(root, dest) then
		return fullPath
	elseif root:id() == dest:id() then
		return vim.list_extend(fullPath, print_node(root))
	else
		return concat_nodes(assert(root:child_with_descendant(dest)), dest, vim.list_extend(fullPath, print_node(root)))
	end
end

--- Return the option or config path under the cursor as a list of strings.
--- @return string[]
function M.get_option_path()
	local cur = api.nvim_win_get_cursor(0)
	local node = assert(ts.get_node(cur))
	local root = node:tree():root()

	-- TODO Needs to consider non-config paths
	local path = concat_nodes(root, node, {})

	-- Reasonable "top level" paths we don't have to edit.
	local top_level_paths = {"options", "config", "imports"}

	if vim.tbl_contains(top_level_paths, path[1]) then
		return path
	else
		-- Slap config onto the top level.
		return vim.list_extend({"config"}, path)
	end
end

--- Prints the config path under the cursor with vim.notify
function M.print_config_path()
	local path = M.get_option_path()
	vim.notify(table.concat(path, "."))
end

--- Prints the config path under the cursor and copies to the clipboard.
function M.copy_config_path()
	local path = table.concat(M.get_option_path(), ".")
	vim.notify("Copied: " .. path)
	vim.fn.setreg("+", path)
end

---Takes a given flake output and an option apply string and returns the result of nix eval. Returns
---SystemCompleted and a boolean indicating whether the output is JSON.
---@param flake_output string
---@param apply string?
---@return vim.SystemCompleted, boolean
function M.nix_eval(flake_output, apply)
	local apply_command = {}
	if apply ~= nil and apply ~= "" then
		apply_command = { "--apply", apply }
	end

	local result = vim.system(
		vim.list_extend({
			M.config.nix_path,
			"eval",
			string.format("%s#%s", M.config.flake, flake_output),
			"--json",
		}, apply_command),
		{ text = true, timeout = M.config.command_timeout }
	):wait()

	if result.code ~= 0 then
		-- See https://github.com/NixOS/nix/issues/11576
		vim.notify("Unable to evaluate as JSON, trying regular eval...", vim.log.levels.WARN)
		return vim.system(
					vim.list_extend({
						M.config.nix_path,
						"eval",
						string.format("%s#%s", M.config.flake, flake_output),
						apply_command,
					}, apply_command),
					{ text = true, timeout = M.config.command_timeout }
				):wait(),
				false
	end
	return result, true
end

---Sets the flake output to use, prompting the user if parameter is nil.
---@param setting string?
---@return string
function M.set_output(setting)
	if setting == nil then
		vim.ui.input({ prompt = "Enter the nix output to use.", scope = "project" }, function(input)
			M.output = input
		end)
	else
		M.output = setting
	end
	return M.output
end

---Generates a dynamic floating window configuration.
---@return table
local function window_config()
	local WIDTH_RATIO = 0.5
	local HEIGHT_RATIO = 0.8
	local win_w = vim.api.nvim_win_get_width(0)
	local win_h = vim.api.nvim_win_get_height(0)
	local window_w = win_w * WIDTH_RATIO
	local window_h = win_h * HEIGHT_RATIO
	local window_w_int = math.floor(window_w)
	local window_h_int = math.floor(window_h)
	local center_x = (win_w - window_w) / 2
	local center_y = (win_h - window_h) / 2
	return {
		border = "rounded",
		relative = "win",
		row = center_y,
		col = center_x,
		width = window_w_int,
		height = window_h_int,
	}
end

---Evaluates a config path under the cursor and prints to a floating buffer.
--	If possible, it will give formatted json, but otherwise it falls back to regular eval output.
function M.eval_config()
	if M.output == nil then
		M.set_output(nil)
	end
	if M.output ~= nil then
		local option_path = M.get_option_path()
		if #option_path <= 1 then
			vim.notify("Cowardly refusing to evaluate a shallow option path.", vim.log.levels.WARN)
			return
		end
		local result, json =
				M.nix_eval(string.format(M.output), string.format("(x: x.%s)", table.concat(option_path, ".")))
		if result.code == 0 then
			local buf = vim.api.nvim_create_buf(false, true)
			local lines
			if json then
				lines =
						assert(vim.system({ M.config.jq_path, "." }, { text = true, stdin = result.stdout }):wait().stdout)
			else
				lines = assert(result.stdout)
			end
			vim.api.nvim_open_win(buf, true, window_config())

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(lines, "\n"))
			vim.api.nvim_set_option_value("filetype", "json", { buf = buf })
			vim.api.nvim_set_option_value("readonly", true, { buf = buf })
			vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
			vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		else
			vim.notify(string.format("Unable to evaluate:\n%s", result.stderr), vim.log.levels.ERROR)
		end
	end
end

return M
