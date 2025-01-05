local ts_utils = require("treesorter.ts_utils")

local M = {}

M.read_children = function(type_filter, bufnr, node, range_filter)
  local container = ts_utils.find_nearest_ancestor_containing(type_filter, bufnr, node)

  if not container then
    error("No node containing children of specified type exists in tree")
  end

  local child_iter = type_filter(container:iter_children())

  if range_filter then
    child_iter = range_filter(child_iter)
  end

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

      if range_filter then
        prev_sibling = range_filter(ts_utils.oneoff_iterator(prev_sibling))()
      end

      if prev_sibling and prev_sibling:type() == "comment" then
        local prev_sibling_end = prev_sibling:end_()
        if prev_sibling_end + 1 == start then
          start = prev_sibling:start()
        end
      end

      local next_sibling = child:next_sibling()

      if range_filter then
        next_sibling = range_filter(ts_utils.oneoff_iterator(next_sibling))()
      end

      if next_sibling then
        local next_sibling_start = next_sibling:start()
        end_ = next_sibling_start - 1
      end

      if end_ + 1 > to_pos then
        to_pos = end_ + 1
      end

      table.insert(children, { start = start, end_ = end_, name = ts_utils.get_node_name(child) })
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

M.reorder_children = function(type_filter, bufnr, node, range_filter)
  local children, to_pos = M.read_children(type_filter, bufnr, node, range_filter)
  print("children", vim.inspect(children))
  M.write_children(children, to_pos)
  M.clear_children(children)
end

M.sort = function(opts)
  local node, range_filter

  if opts.range then
    node = ts_utils.find_smallest_node_for_range(opts.bufnr, opts.range)
    range_filter = ts_utils.get_range_filter(opts.range)
  else
    node = vim.treesitter.get_node({
      bufnr = opts.bufnr,
      pos = opts.pos,
    })
  end

  for _, group in ipairs(opts.groups) do
    local types = {}
    for type in group:gmatch("([^+]+)") do
      table.insert(types, type)
    end
    M.reorder_children(ts_utils.get_type_filter(types), opts.bufnr, node, range_filter)
  end
end

M.setup = function()
  vim.api.nvim_create_user_command("TSort", function(o)
    local groupstr = o.args
    local groups = {}
    for arg in groupstr:gmatch("%S+") do
      table.insert(groups, arg)
    end

    local range

    if o.range == 2 then
      range = { o.line1 - 1, o.line2 - 1 }
    end

    M.sort({ groups = groups, range = range })
  end, {
    nargs = "*",
    range = "%",
    complete = function(arg_lead, cmd_line)
      local visual_mod = string.find(cmd_line, "'<,'>") == 1
      local range

      if visual_mod then
        range = { vim.api.nvim_buf_get_mark(0, "<")[1] - 1, vim.api.nvim_buf_get_mark(0, ">")[1] - 1 }
      end

      local all_types = ts_utils.get_types(nil, range)

      if not arg_lead then
        return all_types
      end

      local arg_part_idx = arg_lead:find("[^+]+$")

      local types = all_types

      if not arg_part_idx then
        for k, v in ipairs(types) do
          types[k] = arg_lead .. v
        end
        return types
      end

      local history_part = arg_lead:sub(1, arg_part_idx - 1)
      local arg_part = arg_lead:sub(arg_part_idx)

      types = vim.tbl_filter(function(type)
        return type:find(arg_part) == 1
      end, types)

      if #types == 1 and types[1] == arg_part then
        history_part = history_part .. arg_part .. "+"
        types = all_types
      end

      for k, type in ipairs(types) do
        types[k] = history_part .. type
      end

      return types
    end,
  })
end

return M
