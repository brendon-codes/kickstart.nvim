-- ============================================================
-- CUSTOM SETTINGS
-- ============================================================

local M = {}

local function use_single_float_border()
  if vim.fn.exists("&winborder") == 1 then
    vim.o.winborder = "single"
  end
end

use_single_float_border()

local function configure_soft_wrap()
  if vim.g.vscode then
    return
  end

  local soft_wrap_width = 120
  local no_neck_pain = require('no-neck-pain')
  local original_buffer_textwidth = {}
  local original_window_options = {}
  local soft_wrap_window_options = {
    breakindent = true,
    foldcolumn = '0',
    linebreak = true,
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    wrap = true,
  }

  local function is_valid_window(winid)
    return winid and vim.api.nvim_win_is_valid(winid)
  end

  local function set_soft_wrap_window_options(winid)
    if not is_valid_window(winid) then
      return
    end

    if not original_window_options[winid] then
      original_window_options[winid] = {}

      for option in pairs(soft_wrap_window_options) do
        original_window_options[winid][option] = vim.api.nvim_get_option_value(option, { win = winid })
      end
    end

    for option, value in pairs(soft_wrap_window_options) do
      vim.api.nvim_set_option_value(option, value, { win = winid, scope = 'local' })
    end
  end

  local function restore_window_options(winid, preserve_saved_options)
    local options = original_window_options[winid]

    if not options then
      return
    end

    if not preserve_saved_options then
      original_window_options[winid] = nil
    end

    if not is_valid_window(winid) then
      return
    end

    for option, value in pairs(options) do
      vim.api.nvim_set_option_value(option, value, { win = winid, scope = 'local' })
    end
  end

  local function restore_all_window_options(preserve_saved_options)
    local winids = vim.tbl_keys(original_window_options)

    for _, winid in ipairs(winids) do
      restore_window_options(winid, preserve_saved_options)
    end
  end

  local function enforce_soft_wrap_width()
    local state = _G.NoNeckPain and _G.NoNeckPain.state

    if not state or not state.enabled then
      return
    end

    local tab = state.tabs and state.tabs[state.active_tab]
    local wins = tab and tab.wins and tab.wins.main
    local current = wins and wins.curr
    local left = wins and wins.left
    local right = wins and wins.right

    if
      not is_valid_window(current)
      or not vim.b[vim.api.nvim_win_get_buf(current)].custom_soft_wrap_enabled
      or not is_valid_window(left)
      or not is_valid_window(right)
    then
      return
    end

    local total_width = vim.api.nvim_win_get_width(left)
      + vim.api.nvim_win_get_width(current)
      + vim.api.nvim_win_get_width(right)
    local padding_width = total_width - soft_wrap_width

    if padding_width < 2 then
      return
    end

    local left_width = math.floor(padding_width / 2)
    local right_width = padding_width - left_width

    -- Set the content window first, then balance both padding windows. Setting
    -- the padding last leaves the remaining center window at exactly 120 cells.
    pcall(vim.api.nvim_win_set_width, current, soft_wrap_width)
    pcall(vim.api.nvim_win_set_width, left, left_width)
    pcall(vim.api.nvim_win_set_width, right, right_width)
  end

  no_neck_pain.setup {
    width = soft_wrap_width,
    -- A one-cell minimum avoids creating two padding windows before the UI can
    -- also accommodate their split separators and a 120-cell center window.
    minSideBufferWidth = 1,
  }

  local function enable_soft_wrap_layout(bufnr)
    if
      not vim.api.nvim_buf_is_valid(bufnr)
      or not vim.b[bufnr].custom_soft_wrap_enabled
      or vim.api.nvim_get_current_buf() ~= bufnr
    then
      return
    end

    if original_buffer_textwidth[bufnr] == nil then
      original_buffer_textwidth[bufnr] = vim.api.nvim_get_option_value('textwidth', { buf = bufnr })
    end

    vim.api.nvim_set_option_value('textwidth', 0, { buf = bufnr })
    no_neck_pain.enable('custom_soft_wrap')
    vim.defer_fn(function()
      if
        vim.api.nvim_buf_is_valid(bufnr)
        and vim.api.nvim_get_current_buf() == bufnr
        and vim.b[bufnr].custom_soft_wrap_enabled
      then
        set_soft_wrap_window_options(vim.api.nvim_get_current_win())
        enforce_soft_wrap_width()
      end
    end, 30)
  end

  local function disable_soft_wrap_layout(preserve_saved_options)
    -- Leaving an opted-in buffer restores its window without discarding the
    -- snapshot, so revisiting the buffer can still restore the true baseline.
    restore_all_window_options(preserve_saved_options)

    local state = _G.NoNeckPain and _G.NoNeckPain.state
    if state and state.enabled then
      no_neck_pain.disable()
    end

    -- The plugin debounces enablement. Recheck once so a very quick buffer
    -- switch cannot leave a delayed enable active in a buffer that has not
    -- opted in to soft wrapping.
    vim.defer_fn(function()
      local bufnr = vim.api.nvim_get_current_buf()
      local current_state = _G.NoNeckPain and _G.NoNeckPain.state

      if
        vim.bo[bufnr].filetype ~= 'no-neck-pain'
        and not vim.b[bufnr].custom_soft_wrap_enabled
        and current_state
        and current_state.enabled
      then
        no_neck_pain.disable()
      end
    end, 30)
  end

  local function toggle_soft_wrap()
    local bufnr = vim.api.nvim_get_current_buf()

    if vim.b[bufnr].custom_soft_wrap_enabled then
      vim.b[bufnr].custom_soft_wrap_enabled = nil

      if original_buffer_textwidth[bufnr] ~= nil then
        vim.api.nvim_set_option_value('textwidth', original_buffer_textwidth[bufnr], { buf = bufnr })
        original_buffer_textwidth[bufnr] = nil
      end

      disable_soft_wrap_layout(false)
      vim.notify('Soft wrap disabled')
    else
      vim.b[bufnr].custom_soft_wrap_enabled = true
      enable_soft_wrap_layout(bufnr)
      vim.notify(string.format('Soft wrap enabled at %d columns', soft_wrap_width))
    end
  end

  -- Keep the legacy group name so reloading the config clears the old
  -- Markdown-only autocmds from an existing Neovim session.
  local group = vim.api.nvim_create_augroup('custom-markdown-soft-wrap', { clear = true })

  vim.api.nvim_create_user_command('SoftWrap', toggle_soft_wrap, {
    desc = 'Toggle centered 120-column soft wrapping for the current buffer',
    force = true,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    desc = 'Enable the centered layout only for buffers that opted in',
    callback = function()
      -- no-neck-pain creates a normal empty buffer before assigning its
      -- padding filetype. Reconcile on the next event-loop turn so those
      -- transient BufEnter events cannot disable the layout mid-creation.
      vim.schedule(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local filetype = vim.bo[bufnr].filetype

        if filetype == 'no-neck-pain' then
          return
        end

        if vim.b[bufnr].custom_soft_wrap_enabled then
          enable_soft_wrap_layout(bufnr)
        else
          disable_soft_wrap_layout(true)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    desc = 'Preserve the exact soft wrap width after resizing',
    callback = function()
      if vim.b.custom_soft_wrap_enabled then
        vim.defer_fn(enforce_soft_wrap_width, 30)
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufDelete', {
    group = group,
    desc = 'Forget saved options for deleted buffers',
    callback = function(event)
      original_buffer_textwidth[event.buf] = nil
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    desc = 'Forget saved options for closed windows',
    callback = function(event)
      original_window_options[tonumber(event.match)] = nil
    end,
  })
end

function M.lsp_servers(servers)
  servers.vtsls = {
    settings = {
      typescript = {
        tsserver = {
          experimental = {
            enableProjectDiagnostics = true,
          },
        },
      },
      vtsls = {
        autoUseWorkspaceTsdk = true,
      },
    },
  }
end

function M.general()
  -- ============================================================
  -- PERSONAL SETTINGS FROM ~/.config/nvim.bak/init.lua
  -- ============================================================

  vim.pack.add { 'https://github.com/projekt0n/github-nvim-theme' }
  vim.pack.add { 'https://github.com/shortcuts/no-neck-pain.nvim' }
  configure_soft_wrap()

  if vim.g.vscode then
    vim.cmd.colorscheme = ""
  else
    vim.cmd.colorscheme("github_dark_high_contrast")
    vim.opt.termguicolors = true
    vim.api.nvim_set_hl(0, "Normal", { bg = "#000000" })

    -- ============================================================
    -- FLOATING POPUP CONTRAST
    -- ============================================================
    local popup_bg = "#404040"
    local popup_fg = "#f2f2f2"
    local popup_border = "#c6c6c6"

    use_single_float_border()

    vim.api.nvim_set_hl(0, "NormalFloat", { bg = popup_bg, fg = popup_fg })
    vim.api.nvim_set_hl(0, "FloatBorder", { bg = popup_bg, fg = popup_border })
    vim.api.nvim_set_hl(0, "FloatTitle", { bg = popup_bg, fg = popup_fg })
    vim.api.nvim_set_hl(0, "Pmenu", { bg = popup_bg, fg = popup_fg })
    vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#1f6feb", fg = "#ffffff" })
    vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { bg = popup_bg, fg = popup_border })
    vim.api.nvim_set_hl(0, "BlinkCmpDocBorder", { bg = popup_bg, fg = popup_border })
    vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { bg = popup_bg, fg = popup_border })

    local hover = vim.lsp.handlers.hover
    local signature_help = vim.lsp.handlers.signature_help

    local popup_width = 65
    local popup_height = 18
    local popup_border_style = "single"

    local function popup_float_config(config)
      return vim.tbl_deep_extend("force", config or {}, {
        border = popup_border_style,
        width = popup_width,
        height = popup_height,
        max_width = popup_width,
        max_height = popup_height,
        wrap = true,
        wrap_at = popup_width,
      })
    end

    vim.diagnostic.config {
      float = vim.tbl_deep_extend("force", popup_float_config(), { source = "if_many" }),
    }

    local function force_float_size(winid)
      if winid and vim.api.nvim_win_is_valid(winid) then
        pcall(vim.api.nvim_win_set_config, winid, {
          width = popup_width,
          height = popup_height,
        })
      end
    end

    local close_floating_windows = function()
      local closed = false
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" then
          closed = pcall(vim.api.nvim_win_close, win, false) or closed
        end
      end
      return closed
    end

    local function trim_empty_lines(lines)
      local first = 1
      while first <= #lines and lines[first] == "" do
        first = first + 1
      end

      local last = #lines
      while last >= first and lines[last] == "" do
        last = last - 1
      end

      if first > last then
        return {}
      end

      return vim.list_slice(lines, first, last)
    end

    local function diagnostic_contains_cursor(diagnostic, lnum, col)
      local start_lnum = diagnostic.lnum or 0
      local end_lnum = diagnostic.end_lnum or start_lnum
      local start_col = diagnostic.col or 0
      local end_col = diagnostic.end_col or start_col

      if lnum < start_lnum or lnum > end_lnum then
        return false
      end

      if start_lnum == end_lnum then
        if start_col == end_col then
          return col == start_col
        end

        return col >= start_col and col < end_col
      end

      if lnum == start_lnum then
        return col >= start_col
      end

      if lnum == end_lnum then
        return col < end_col
      end

      return true
    end

    local function sort_diagnostics(diagnostics)
      table.sort(diagnostics, function(left, right)
        local left_severity = left.severity or math.huge
        local right_severity = right.severity or math.huge

        if left_severity ~= right_severity then
          return left_severity < right_severity
        end

        if (left.lnum or 0) ~= (right.lnum or 0) then
          return (left.lnum or 0) < (right.lnum or 0)
        end

        return (left.col or 0) < (right.col or 0)
      end)

      return diagnostics
    end

    local function exact_diagnostics_at_cursor(bufnr)
      local cursor = vim.api.nvim_win_get_cursor(0)
      local lnum = cursor[1] - 1
      local col = cursor[2]

      return sort_diagnostics(vim.tbl_filter(function(diagnostic)
        return diagnostic_contains_cursor(diagnostic, lnum, col)
      end, vim.diagnostic.get(bufnr)))
    end

    local function diagnostics_at_cursor(bufnr)
      local cursor = vim.api.nvim_win_get_cursor(0)
      local lnum = cursor[1] - 1
      local diagnostics = exact_diagnostics_at_cursor(bufnr)

      if #diagnostics > 0 then
        return diagnostics
      end

      return sort_diagnostics(vim.diagnostic.get(bufnr, { lnum = lnum }))
    end

    local function append_diagnostic_message(lines, prefix, message)
      local message_lines = vim.split(message or "", "\n", { plain = true })

      if #message_lines == 0 then
        table.insert(lines, prefix)
        return
      end

      table.insert(lines, prefix .. message_lines[1])

      for index = 2, #message_lines do
        table.insert(lines, "  " .. message_lines[index])
      end
    end

    local function compact_diagnostic_message(message)
      local max_chars = popup_width * 3
      local text = (message or ""):gsub("%s+", " ")

      if #text <= max_chars then
        return text
      end

      return vim.fn.strcharpart(text, 0, max_chars - 3) .. "..."
    end

    local function diagnostic_code_label(code)
      if code == nil or code == "" then
        return ""
      end

      return " `" .. tostring(code) .. "`"
    end

    local function diagnostic_lines(bufnr)
      local diagnostics = diagnostics_at_cursor(bufnr)
      local lines = {}

      for _, diagnostic in ipairs(diagnostics) do
        local severity = vim.diagnostic.severity[diagnostic.severity] or "Diagnostic"
        local source = diagnostic.source and (" [" .. diagnostic.source .. "]") or ""
        local code = diagnostic_code_label(diagnostic.code)
        local prefix = "- **" .. severity .. "**" .. source .. code .. ": "
        append_diagnostic_message(lines, prefix, compact_diagnostic_message(diagnostic.message))
      end

      return lines
    end

    local function source_range(bufnr)
      local cursor = vim.api.nvim_win_get_cursor(0)
      local lnum = cursor[1] - 1
      local diagnostics = exact_diagnostics_at_cursor(bufnr)
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local last_lnum = math.max(line_count - 1, 0)

      if #diagnostics == 0 then
        lnum = math.max(0, math.min(lnum, last_lnum))

        return lnum, lnum
      end

      local start_lnum = last_lnum
      local end_lnum = 0

      for _, diagnostic in ipairs(diagnostics) do
        local diagnostic_lnum = diagnostic.lnum or lnum
        start_lnum = math.min(start_lnum, diagnostic_lnum)
        end_lnum = math.max(end_lnum, diagnostic.end_lnum or diagnostic_lnum)
      end

      start_lnum = math.max(0, math.min(start_lnum, last_lnum))
      end_lnum = math.max(start_lnum, math.min(end_lnum, last_lnum))

      return start_lnum, end_lnum
    end

    local function source_context_lines(bufnr)
      local start_lnum, end_lnum = source_range(bufnr)
      local filetype = vim.bo[bufnr].filetype
      local lines = { "```" .. (filetype ~= "" and filetype or "") }
      local source_lines = vim.api.nvim_buf_get_lines(bufnr, start_lnum, end_lnum + 1, false)

      if #source_lines == 0 then
        table.insert(lines, "")
      else
        vim.list_extend(lines, source_lines)
      end

      table.insert(lines, "```")

      return lines
    end

    local function has_nonempty_line(lines)
      for _, line in ipairs(lines) do
        if line ~= "" then
          return true
        end
      end

      return false
    end

    local function hover_lines_from_result(result)
      if not result or not result.contents then
        return {}
      end

      if type(result.contents) == "table" and result.contents.kind == vim.lsp.protocol.MarkupKind.PlainText then
        local lines = vim.split(result.contents.value or "", "\n", { trimempty = true })

        if not has_nonempty_line(lines) then
          return {}
        end

        table.insert(lines, 1, "```")
        table.insert(lines, "```")

        return lines
      end

      local lines = trim_empty_lines(vim.lsp.util.convert_input_to_markdown_lines(result.contents))

      if not has_nonempty_line(lines) then
        return {}
      end

      return lines
    end

    local function append_section(lines, title, section_lines)
      if #section_lines == 0 then
        return
      end

      if #lines > 0 then
        table.insert(lines, "")
      end

      table.insert(lines, "## " .. title)
      table.insert(lines, "")
      vim.list_extend(lines, section_lines)
    end

    local function combined_popup_lines(bufnr, hover_results, clients)
      local lines = {}
      local diagnostics = diagnostic_lines(bufnr)
      local hover_sections = {}

      for _, client in ipairs(clients or {}) do
        local response = hover_results[client.id]
        local hover_lines = response and not response.err and hover_lines_from_result(response.result) or {}

        if #hover_lines > 0 then
          table.insert(hover_sections, {
            client = client,
            lines = hover_lines,
          })
        end
      end

      local hover_lines = {}

      for index, hover_section in ipairs(hover_sections) do
        if index > 1 then
          table.insert(hover_lines, "")
          table.insert(hover_lines, "---")
          table.insert(hover_lines, "")
        end

        if #hover_sections > 1 then
          table.insert(hover_lines, "### " .. (hover_section.client.name or ("client " .. hover_section.client.id)))
          table.insert(hover_lines, "")
        end

        vim.list_extend(hover_lines, hover_section.lines)
      end

      append_section(lines, "Diagnostics", diagnostics)
      append_section(lines, "Source", source_context_lines(bufnr))
      append_section(lines, "Hover", hover_lines)

      return lines
    end

    local function hover_clients(bufnr)
      local method = "textDocument/hover"

      return vim.lsp.get_clients { bufnr = bufnr, method = method }
    end

    local function popup_context_is_current(context)
      if not vim.api.nvim_buf_is_valid(context.bufnr) or not vim.api.nvim_win_is_valid(context.winid) then
        return false
      end

      if vim.api.nvim_get_current_win() ~= context.winid or vim.api.nvim_get_current_buf() ~= context.bufnr then
        return false
      end

      if vim.api.nvim_win_get_buf(context.winid) ~= context.bufnr then
        return false
      end

      local cursor = vim.api.nvim_win_get_cursor(context.winid)

      return cursor[1] == context.cursor[1]
        and cursor[2] == context.cursor[2]
        and vim.api.nvim_buf_get_changedtick(context.bufnr) == context.changedtick
    end

    local function open_combined_popup(context, config, hover_results, clients)
      if not popup_context_is_current(context) then
        return
      end

      local lines = combined_popup_lines(context.bufnr, hover_results or {}, clients)

      if #lines == 0 then
        return
      end

      close_floating_windows()

      local floating_bufnr, winid = vim.lsp.util.open_floating_preview(lines, "markdown", popup_float_config(vim.tbl_deep_extend("force", {
        focus = false,
      }, config or {})))
      force_float_size(winid)

      return floating_bufnr, winid
    end

    local function show_combined_popup(config)
      local bufnr = vim.api.nvim_get_current_buf()
      local winid = vim.api.nvim_get_current_win()
      local clients = hover_clients(bufnr)
      local context = {
        bufnr = bufnr,
        winid = winid,
        cursor = vim.api.nvim_win_get_cursor(winid),
        changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
      }

      close_floating_windows()

      if #clients == 0 then
        return open_combined_popup(context, config, {}, clients)
      end

      return vim.lsp.buf_request_all(bufnr, "textDocument/hover", function(client)
        return vim.lsp.util.make_position_params(winid, client.offset_encoding)
      end, function(results)
        open_combined_popup(context, config, results, clients)
      end)
    end

    local function set_combined_hover_keymap(bufnr)
      local opts = { desc = 'Show diagnostics, source, and hover documentation', silent = true }

      if bufnr then
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end

        opts.buffer = bufnr
        opts.desc = 'LSP: Show diagnostics, source, and hover documentation'
      end

      vim.keymap.set('n', 'K', function()
        show_combined_popup()
      end, opts)
    end

    local function set_combined_hover_keymaps_for_attached_clients()
      for _, client in ipairs(vim.lsp.get_clients()) do
        for bufnr in pairs(client.attached_buffers or {}) do
          set_combined_hover_keymap(bufnr)
        end
      end
    end

    set_combined_hover_keymap()

    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('custom-combined-hover', { clear = true }),
      callback = function(event)
        set_combined_hover_keymap(event.buf)
      end,
    })

    set_combined_hover_keymaps_for_attached_clients()

    vim.schedule(set_combined_hover_keymaps_for_attached_clients)

    vim.lsp.handlers["textDocument/hover"] = function(err, result, ctx, config)
      local floating_bufnr, winid = hover(err, result, ctx, popup_float_config(config))
      force_float_size(winid)

      return floating_bufnr, winid
    end
    vim.lsp.handlers["textDocument/signatureHelp"] = function(err, result, ctx, config)
      return signature_help(err, result, ctx, vim.tbl_deep_extend("force", config or {}, { border = "single" }))
    end

    vim.keymap.set('n', '<Esc>', function()
      if close_floating_windows() then
        return
      end

      vim.cmd.nohlsearch()
    end, { desc = 'Close floating window or clear search highlight', silent = true })
  end

  if vim.g.vscode then
    vim.keymap.set('n', 'u', "<Cmd>call VSCodeNotify('undo')<CR>")
  end

  vim.keymap.set('n', 'gj', 'g0', { noremap = true, silent = true })
  vim.keymap.set('n', 'gk', 'g$', { noremap = true, silent = true })

  vim.opt.mouse = ''
  vim.opt.whichwrap:append("<,>,h,l,[,]")
  vim.opt.ignorecase = true
  vim.opt.smartcase = true
  vim.opt.wildmode = 'longest:list'
  vim.opt.wildmenu = true
  vim.opt.wildoptions = 'pum'
  vim.opt.wildignorecase = false

  local replacing_vibetyper_newline = false

  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChangedP' }, {
    group = vim.api.nvim_create_augroup('custom-vibetyper-newline', { clear = true }),
    callback = function(event)
      if replacing_vibetyper_newline then
        return
      end

      local bufnr = event.buf

      if
        not vim.api.nvim_buf_is_valid(bufnr)
        or bufnr ~= vim.api.nvim_get_current_buf()
        or not vim.bo[bufnr].modifiable
        or vim.bo[bufnr].readonly
      then
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(0)
      local row = cursor[1] - 1
      local col = cursor[2]
      local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
      local line = lines[1]

      if not line or not line:find('@@nl', 1, true) then
        return
      end

      local normalized_line = line:gsub('@@nl ', '@@nl')
      local replacement_lines = vim.split(normalized_line, '@@nl', { plain = true, trimempty = false })
      local before_cursor = line:sub(1, col):gsub('@@nl ', '@@nl')
      local before_cursor_parts = vim.split(before_cursor, '@@nl', { plain = true, trimempty = false })
      local new_row = row + #before_cursor_parts - 1
      local new_col = #before_cursor_parts[#before_cursor_parts]

      vim.schedule(function()
        if
          replacing_vibetyper_newline
          or not vim.api.nvim_buf_is_valid(bufnr)
          or bufnr ~= vim.api.nvim_get_current_buf()
          or not vim.bo[bufnr].modifiable
          or vim.bo[bufnr].readonly
        then
          return
        end

        local current_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]

        if current_line ~= line then
          return
        end

        replacing_vibetyper_newline = true

        local ok = pcall(function()
          vim.api.nvim_buf_set_text(bufnr, row, 0, row, #line, replacement_lines)
          vim.api.nvim_win_set_cursor(0, { new_row + 1, new_col })
        end)

        replacing_vibetyper_newline = false

        if not ok then
          return
        end
      end)
    end,
  })

  -- ============================================================
  -- END PERSONAL SETTINGS FROM ~/.config/nvim.bak/init.lua
  -- ============================================================
end

function M.blink_cmdline()
  return {
    enabled = false,
  }
end

return M
