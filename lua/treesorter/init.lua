local ts_utils = require("treesorter.ts_utils")

local M = {}

M.build_type_query = function(bufnr, types)
  if #types == 0 then
    return nil
  end
  local filetype = vim.api.nvim_get_option_value("filetype", {
    buf = bufnr,
  })
  local query = "["
  for _, type in ipairs(types) do
    query = query .. "(" .. type .. ")"
  end
  query = query .. "] @_typequery"
  return vim.treesitter.query.parse(filetype, query)
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

M.get_query_iterator = function(types_query, captures, ceil_node, textobjects_query, range_filter, opts)
  local query_iter

  if types_query ~= nil then
    query_iter = M.get_type_query_iterator(types_query, ceil_node, opts)
  end

  if #captures > 0 then
    local filtered_to_iter = M.get_textobject_query_iterator(captures, textobjects_query, ceil_node, opts)
    if not query_iter then
      query_iter = filtered_to_iter
    else
      query_iter = ts_utils.compose_iterators({ query_iter, filtered_to_iter })
    end
  end

  if not query_iter then
    error(
      "Group contains neither a textobjects or type query iterator, this is very strange and should definitely not happen"
    )
  end

  if range_filter then
    query_iter = range_filter(query_iter)
  end

  return query_iter
end

M.get_textobject_query_iterator = function(captures, textobjects_query, ceil_node, opts)
  if not textobjects_query then
    error("You need to activate Treesitter textobjects to use captures in your sortgroup")
  end
  local start, end_ = ts_utils.unpack_range_end_exlusive(opts.range)
  local to_iter = textobjects_query:iter_captures(ceil_node, opts.bufnr, start or 0, end_)
  return ts_utils.get_query_node_iterator(function()
    while true do
      local capture = { to_iter() }
      if not capture[1] then
        return nil
      end

      if vim.tbl_contains(captures, textobjects_query.captures[capture[1]]) then
        return unpack(capture)
      end
    end
  end)
end

M.get_type_query_iterator = function(types_query, ceil_node, opts)
  local start, end_ = ts_utils.unpack_range_end_exlusive(opts.range)
  return ts_utils.get_query_node_iterator(types_query:iter_captures(ceil_node, opts.bufnr, start or 0, end_))
end

M.read_children = function(node_iter, range)
  local children = {}

  local to_pos = 0

  while true do
    local node = node_iter()
    if not node then
      break
    end

    if node:named() then
      local start = node:start()
      local end_ = node:end_()

      -- Include preceding extra node superflous to grammar (typically a comment)
      local prev_sibling = node:prev_named_sibling()

      if range and prev_sibling and (prev_sibling:start() < range[1] or prev_sibling:end_() > range[2]) then
        prev_sibling = nil
      end

      if prev_sibling and prev_sibling:extra() then
        local prev_sibling_end = prev_sibling:end_()
        if prev_sibling_end + 1 == start then
          start = prev_sibling:start()
        end
      end

      -- Extend the range of the node to the beginning of next sibling if it exists and is in range,
      -- this makes sures padding around text objects is maintained when sorting
      local next_sibling = node:next_named_sibling()

      if range and next_sibling and (next_sibling:start() < range[1] or next_sibling:end_() > range[2]) then
        next_sibling = nil
      end

      if next_sibling then
        local next_sibling_start = next_sibling:start()
        end_ = next_sibling_start - 1
      end

      if end_ + 1 > to_pos then
        to_pos = end_ + 1
      end

      table.insert(children, { start = start, end_ = end_, name = ts_utils.get_node_name(node) })
    end
  end

  table.sort(children, function(a, b)
    return a.name > b.name
  end)

  return children, to_pos
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

    local bufnr = vim.api.nvim_win_get_buf(0)
    local textobjects_query = ts_utils.get_textobjects_query(bufnr)

    M.sort({
      groups = groups,
      range = range,
      bufnr = vim.api.nvim_win_get_buf(0),
      textobjects_query = textobjects_query,
    })
  end, {
    nargs = "*",
    range = "%",
    complete = function(arg_lead, cmd_line)
      local visual_mod = string.find(cmd_line, "'<,'>") == 1
      local range

      if visual_mod then
        range = { vim.api.nvim_buf_get_mark(0, "<")[1] - 1, vim.api.nvim_buf_get_mark(0, ">")[1] - 1 }
      end

      local bufnr = vim.api.nvim_win_get_buf(0)

      local all_completions = {}
      local all_captures = ts_utils.get_captures(bufnr, range)
      local all_types = ts_utils.get_types(bufnr, range)

      for i = 1, #all_captures do
        all_completions[#all_completions + 1] = all_captures[i]
      end

      for i = 1, #all_types do
        all_completions[#all_completions + 1] = all_types[i]
      end

      if not arg_lead then
        return all_types
      end

      local arg_part_idx = arg_lead:find("[^+]+$")

      local completions = all_completions

      if not arg_part_idx then
        for k, v in ipairs(completions) do
          completions[k] = arg_lead .. v
        end
        return completions
      end

      local history_part = arg_lead:sub(1, arg_part_idx - 1)
      local arg_part = arg_lead:sub(arg_part_idx)

      completions = vim.tbl_filter(function(type)
        return type:find(arg_part) == 1
      end, completions)

      if #completions == 1 and completions[1] == arg_part then
        history_part = history_part .. arg_part .. "+"
        completions = all_completions
      end

      for k, type in ipairs(completions) do
        completions[k] = history_part .. type
      end

      return completions
    end,
  })
end

M.sort = function(opts)
  local ok, floor_node, ceil_node, range_filter

  if opts.range then
    floor_node = ts_utils.find_smallest_node_for_range(opts.bufnr, opts.range)
    ceil_node = floor_node
    range_filter = ts_utils.get_range_filter(opts.range)
  else
    floor_node = vim.treesitter.get_node({
      bufnr = opts.bufnr,
      pos = opts.pos,
      ignore_injections = false,
    })
    ceil_node = ts_utils.find_root_node(opts.bufnr, floor_node)
  end

  for _, group in ipairs(opts.groups) do
    local types = {}
    local captures = {}

    for type in group:gmatch("([^+]+)") do
      if type:find("@") == 1 then
        table.insert(captures, type:sub(2))
      else
        table.insert(types, type)
      end
    end

    local types_query = M.build_type_query(opts.bufnr, types)

    local query_iter =
      M.get_query_iterator(types_query, captures, ceil_node, opts.textobjects_query, range_filter, opts)

    local container = ts_utils.find_container_from_query(query_iter, floor_node)

    local parent_filter = ts_utils.get_parent_filter(container)

    -- Refresh iterator since it's been exhausted, and wrap it in parent filter
    query_iter =
      parent_filter(M.get_query_iterator(types_query, captures, ceil_node, opts.textobjects_query, range_filter, opts))

    local children, to_pos
    ok, children, to_pos = pcall(M.read_children, query_iter, opts.range)

    if ok == false then
      print(children)
      break
    end

    M.write_children(children, to_pos)
    M.clear_children(children)
  end
end

M.write_children = function(children, to_pos)
  for _, child in ipairs(children) do
    local start_row = child.start
    local end_row = child.end_

    local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)

    vim.api.nvim_buf_set_lines(0, to_pos, to_pos, false, lines)
  end
end

return M
