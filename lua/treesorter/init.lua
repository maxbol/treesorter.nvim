local ts_utils = require("treesorter.ts_utils")

local M = {}

M.read_children = function(types)
  local container = ts_utils.find_top_node_containing(types)

  if not container then
    error("No node containing children of specified type exists in tree")
  end

  local child_iter = ts_utils.iter_children_of_types(types, container)
  local children = {}

  local to_pos = 0

  while true do
    local child = child_iter()
    if not child then
      break
    end

    if child:named() then
      local start = child:start()
      local end_ = child:end_()

      local prev_sibling = child:prev_sibling()

      if prev_sibling and prev_sibling:type() == "comment" then
        local prev_sibling_end = prev_sibling:end_()
        if prev_sibling_end + 1 == start then
          start = prev_sibling:start()
        end
      end

      local next_sibling = child:next_sibling()

      if next_sibling then
        local next_sibling_start = next_sibling:start()
        end_ = next_sibling_start - 1
      end

      table.insert(children, { start = start, end_ = end_, name = ts_utils.get_node_name(child) })

      if child:end_() + 1 > to_pos then
        to_pos = child:end_() + 1
      end
    end
  end

  table.sort(children, function(a, b)
    return a.name > b.name
  end)

  return children, to_pos
end

M.write_children = function(children, to_pos)
  for _, child in ipairs(children) do
    local start_row = child.start
    local end_row = child.end_

    local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)

    vim.api.nvim_buf_set_lines(0, to_pos, to_pos, false, lines)
  end
end

M.clear_children = function(children)
  table.sort(children, function(a, b)
    return a.end_ > b.end_
  end)

  for _, child in ipairs(children) do
    local start_row = child.start
    local end_row = child.end_

    vim.api.nvim_buf_set_lines(0, start_row, end_row + 1, false, {})
  end
end

M.reorder_children = function(types)
  local children, to_pos = M.read_children(types)
  M.write_children(children, to_pos)
  M.clear_children(children)
end

M.tsort = function(groups)
  for _, group in ipairs(groups) do
    local types = {}
    for type in group:gmatch("([^+]+)") do
      table.insert(types, type)
    end
    M.reorder_children(types)
  end
end

M.setup = function()
  vim.api.nvim_create_user_command("TSort", function(o)
    local groupstr = o.args
    local groups = {}
    for arg in groupstr:gmatch("%S+") do
      table.insert(groups, arg)
    end

    M.tsort(groups)
  end, { nargs = "*" })
end

return M
