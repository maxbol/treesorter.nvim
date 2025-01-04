local M = {}

M.find_node_ancestor = function(types, node)
	if not node then
		return nil
	end

	if vim.tbl_contains(types, node:type()) then
		return node
	end

	local parent = node:parent()

	return M.find_node_ancestor(types, parent)
end

M.find_top_node_containing = function(types, node)
	if not node then
		node = vim.treesitter.get_node()
	end

	local child_iter = M.iter_children_of_types(types, node)
	local first_child = child_iter()

	if first_child then
		return node
	end

	local parent = node:parent()

	if not parent then
		return nil
	end

	return M.find_top_node_containing(types, parent)
end

M.iter_children_of_types = function(types, node)
	if not node then
		return function()
			return nil
		end
	end

	local iter = node:iter_children()

	return function()
		while true do
			local child = iter()
			if not child then
				return nil
			end

			if vim.tbl_contains(types, child:type()) then
				return child
			end
		end
	end
end

M.get_first_child_by_type = function(node, child_type)
	if not node then
		return nil
	end

	local iter = M.iter_children_of_types({ child_type }, node)
	return iter()
end

M.node_to_lines = function(node)
	if not node then
		return nil
	end

	local start_row = node:start()
	local end_row = node:end_()
	return vim.api.nvim_buf_get_lines(0, start_row, end_row, false)
end

M.node_to_text = function(node)
	if not node then
		return nil
	end

	local start_row, start_col = node:start()
	local end_row, end_col = node:end_()
	return vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
end

M.node_to_string = function(node)
	local text = M.node_to_text(node)

	if not text then
		return nil
	end

	return table.concat(text, "\n")
end

M.get_node_name = function(node)
	if node:type() == "identifier" then
		return M.node_to_string(node)
	end

	local name_field = node:field("name")
	if #name_field > 0 then
		return M.get_node_name(name_field[1])
	end

	local declarator_field = node:field("declarator")
	if #declarator_field > 0 then
		return M.get_node_name(declarator_field[1])
	end

	error("Node type not supported: " .. node:type())
end

return M
