local M = {}

local function find_smallest_node_containing_oneof(needle, haystack)
  local parent = needle:parent()

  if not parent then
    return needle
  end

  for _, node in ipairs(haystack) do
    if needle:equal(node) then
      return parent
    end
  end

  return find_smallest_node_containing_oneof(parent, haystack)
end

M.compose_iterators = function(iterators)
  return function()
    for _, iter in ipairs(iterators) do
      local value = iter()
      if value then
        return value
      end
    end
    return nil
  end
end

M.find_container_from_query = function(query_iter, floor_node)
  local captured_nodes = {}
  while true do
    local node = query_iter()
    if not node then
      break
    end

    table.insert(captured_nodes, node)
  end

  -- First check the children of the floor node for matches to see if the floor node should be the container
  local child_it = floor_node:iter_children()
  while true do
    local child = child_it()
    if not child then
      break
    end
    for _, captured_node in ipairs(captured_nodes) do
      if child:equal(captured_node) then
        return floor_node
      end
    end
  end

  -- Then traverse up until the ceiling node checking for the container
  return find_smallest_node_containing_oneof(floor_node, captured_nodes)
end

M.find_root_node = function(bufnr, node)
  if not node then
    node = vim.treesitter.get_node({
      bufnr = bufnr,
      ignore_injections = false,
    })
  end
  local parent = node:parent()

  if not parent then
    return node
  end

  return M.find_root_node(bufnr, parent)
end

M.find_smallest_node_for_range = function(bufnr, range)
  local last_line = vim.api.nvim_buf_get_lines(bufnr or 0, range[2], range[2] + 1, true)
  if #last_line == 0 then
    error("Invalid range")
  end
  local end_col = #last_line[1]
  return vim.treesitter
    .get_parser(bufnr)
    :named_node_for_range({ range[1], 0, range[2], end_col }, { ignore_injections = false })
end

M.get_captures = function(bufnr, range)
  local node
  if range then
    node = M.find_smallest_node_for_range(bufnr, range)
  else
    node = M.find_root_node(bufnr)
  end

  local captures_set = {}
  local textobjects_query = M.get_textobjects_query(bufnr)

  if not textobjects_query then
    return {}
  end

  local query_it = textobjects_query:iter_captures(node, bufnr, 0)

  while true do
    local id = query_it()
    if not id then
      break
    end
    local name = textobjects_query.captures[id]
    if name ~= nil and name:find("_") ~= 1 then
      captures_set["@" .. name] = true
    end
  end

  local captures = {}
  for k, _ in pairs(captures_set) do
    captures[#captures + 1] = k
  end

  return captures
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

  local iter = node:iter_children()
  while true do
    local child = iter()
    if not child then
      break
    end

    local ok, child_name = pcall(M.get_node_name, child)
    if ok then
      return child_name
    end
  end

  error("Node type not supported: " .. node:type())
end

M.get_parent_filter = function(parent)
  return function(iter)
    return function()
      while true do
        local node = iter()
        if not node then
          return nil
        end

        if node:parent():equal(parent) then
          return node
        end
      end
    end
  end
end

M.get_query_node_iterator = function(iter)
  return function()
    local capture = { iter() }
    if not capture then
      return nil
    end

    return capture[2]
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

M.get_textobjects_query = function(bufnr)
  local filetype = vim.api.nvim_get_option_value("filetype", {
    buf = bufnr,
  })

  local ok, textobjects_query = pcall(vim.treesitter.query.get, filetype, "textobjects")

  if ok == false then
    textobjects_query = nil
  end

  return textobjects_query
end

M.get_types = function(bufnr, range)
  local node
  if range then
    node = M.find_smallest_node_for_range(bufnr, range)
  else
    node = M.find_root_node(bufnr)
  end
  local typeset = M.get_typeset(node)
  local types = {}

  for type, _ in pairs(typeset) do
    table.insert(types, type)
  end

  table.sort(types)

  return types
end

M.get_typeset = function(node, typeset)
  if not typeset then
    typeset = {}
  end

  local node_type = node:type()

  if not typeset[node_type] then
    typeset[node_type] = true
  end

  local iter = node:iter_children()
  while true do
    local child = iter()
    if not child then
      break
    end

    typeset = M.get_typeset(child, typeset)
  end

  return typeset
end

M.node_name_fields = {
  "name",
  "declarator",
  "path",
  "field",
}

M.node_name_types = {
  "identifier",
  "type_identifier",
  "name",
  "system_lib_string",
  "string_literal",
}

M.node_name_types = {
  "identifier",
  "system_lib_string",
  "string_literal",
}

M.node_to_string = function(node)
  local text = M.node_to_text(node)

  if not text then
    return nil
  end

  return table.concat(text, "\n")
end

M.node_to_text = function(node)
  if not node then
    return nil
  end

  local start_row, start_col = node:start()
  local end_row, end_col = node:end_()
  return vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
end

M.unpack_range_end_exlusive = function(range)
  if not range then
    return nil, nil
  end
  return range[1], range[2] + 1
end

return M
