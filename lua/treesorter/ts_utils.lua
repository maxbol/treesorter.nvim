local M = {}

M.node_name_types = {
  "identifier",
  "system_lib_string",
  "string_literal",
}

M.node_name_fields = {
  "name",
  "declarator",
  "path",
}

M.find_top_node = function(node)
  if not node then
    node = vim.treesitter.get_node()
  end

  local parent = node:parent()

  if not parent then
    return node
  end

  return M.find_top_node(parent)
end

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

M.find_nearest_ancestor_containing = function(type_filter, bufnr, node)
  local child_iter = type_filter(node:iter_children())
  local first_child = child_iter()

  if first_child then
    return node
  end

  local parent = node:parent()

  if not parent then
    return nil
  end

  return M.find_nearest_ancestor_containing(type_filter, bufnr, parent)
end

M.get_type_filter = function(types)
  return function(iter)
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
end

M.get_range_filter = function(range)
  return function(iter)
    return function()
      while true do
        local child = iter()
        if not child then
          return nil
        end

        local start_row = child:start()
        local end_row = child:end_()

        if start_row >= range[1] and end_row <= range[2] then
          return child
        end
      end
    end
  end
end

M.get_first_child_by_type = function(node, child_type)
  if not node then
    return nil
  end

  local iter = M.get_type_filter({ child_type })(node:iter_children())
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
  for _, literal_type in ipairs(M.node_name_types) do
    if node:type() == literal_type then
      return M.node_to_string(node)
    end
  end

  for _, field_name in ipairs(M.node_name_fields) do
    local field = node:field(field_name)
    if #field > 0 then
      return M.get_node_name(field[1])
    end
  end

  error("Node type not supported: " .. node:type())
end

M.get_typeset = function(node, types)
  if not types then
    types = {}
  end
  if not node then
    node = M.find_top_node()
  end

  local node_type = node:type()

  if not types[node_type] then
    types[node_type] = true
  end

  local iter = node:iter_children()
  while true do
    local child = iter()
    if not child then
      break
    end

    types = M.get_typeset(child, types)
  end

  return types
end

M.get_types = function()
  local typeset = M.get_typeset()
  local types = {}

  for type, _ in pairs(typeset) do
    table.insert(types, type)
  end

  return types
end

return M
