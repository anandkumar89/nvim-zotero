local config = require("zotcite.config").get_config()

local M = {}

local zwarn = require("zotcite").zwarn

M.add_yaml_refs = function()
    local bigstr = vim.fn.join(vim.fn.getline(1, "$"))
    local rlist = vim.fn.uniq(vim.fn.sort(vim.fn.split(bigstr)))
    if rlist and type(rlist) == "table" and #rlist > 0 then
        local list2 = {}
        for _, v in pairs(rlist) do
            if v:find("^@.*#") then table.insert(list2, v) end
        end
        if #list2 > 0 then
            local refs = vim.fn.py3eval(
                "ZotCite.GetYamlRefs(['" .. table.concat(list2, "', '") .. "'])"
            )
            local rlines = vim.fn.split(refs, "\n")
            local lnum = vim.api.nvim_win_get_cursor(0)[1]
            vim.api.nvim_buf_set_lines(0, lnum, lnum, true, rlines)
        end
    end
end

M.ODTtoMarkdown = function(odt)
    require("zotcite.config").set_path()
    local mdf = vim.system({ config.python_path, "odt2md.py", odt }, { text = true }):wait()
    if mdf.code == 0 then
        vim.cmd("tabnew " .. mdf.stdout)
    else
        zwarn(mdf.stderr:gsub("\n", " "))
    end
end

M.view_document = function()
    local ext = "html"
    local fmt
    if vim.o.filetype == "quarto" then
        fmt = require("zotcite.get").yaml_field("format", vim.api.nvim_get_current_buf())
    else
        fmt = require("zotcite.get").yaml_field("output", vim.api.nvim_get_current_buf())
    end
    if type(fmt) == "table" then
        for k, _ in pairs(fmt) do
            ext = k
            break
        end
    elseif type(fmt) == "string" then
        ext = fmt
    end
    if ext == "html_document" or ext == "revealjs" then
        ext = "html"
    elseif ext == "pdf_document" or ext == "beamer" then
        ext = "pdf"
    elseif ext == "odf_document" then
        ext = "odt"
    end
    local doc = vim.fn.expand("%:p:r") .. "." .. ext
    if vim.fn.filereadable(doc) == 0 then
        zwarn('File "' .. doc .. '" not found.')
        return
    end
    M.open(doc)
end

M.check_bib = function()
    local bib =
        require("zotcite.get").yaml_field("bibliography", vim.api.nvim_get_current_buf())
    if not bib then return end

    local bibf = nil
    if type(bib) == "table" then
        if #bib == 0 then return end
        bibf = bib[1]
    elseif type(bib) == "string" then
        bibf = bib
    end
    if type(bibf) ~= "string" then
        zwarn('Invalid "bibliography" field: ' .. vim.inspect(bib))
        return
    end

    if bibf:find(".*zotcite.bib$") and vim.fn.filereadable(bibf) == 0 then
        -- Ensure that `quarto preview` will work
        vim.fn.writefile({}, bibf)
    end
end

M.open = function(fpath)
    if config.wait_attachment then
        local obj
        local em
        if config.open_cmd then
            obj = vim.system({ config.open_cmd, fpath }, { text = true }):wait()
            em = "Error running `" .. config.open_cmd .. ' "' .. fpath .. '"' .. "`"
        else
            obj = vim.ui.open(fpath):wait()
            em = 'Error running `vim.ui.open("' .. fpath .. '")`'
        end
        if obj.code ~= 0 then
            em = em .. ":\n  exit code: " .. tostring(obj.code)
            if obj.stdout and obj.stdout ~= "" then em = em .. "\n  " .. obj.stdout end
            if obj.stderr and obj.stderr ~= "" then em = em .. "\n  " .. obj.stderr end
            zwarn(em)
        end
        return
    end
    if config.open_cmd then
        vim.system({ config.open_cmd, fpath }, { text = true })
    else
        vim.ui.open(fpath)
    end
end

function M.showcb(items, callback)
	  if #items == 0 or #items > 9 then
		vim.notify("Quick select supports 1-9 items only", vim.log.levels.WARN)
		return
	  end

	  -- Create buffer
	  local buf = vim.api.nvim_create_buf(false, true)
	  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
	  
	  -- Prepare display lines
	  local lines = {}
	  for i, item in ipairs(items) do
		table.insert(lines, string.format("%d) %s", i, item))
	  end
	  table.insert(lines, "")
	  table.insert(lines, "x) Cancel")
	  
	  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	  
	  -- Calculate window size
	  local width = 0
	  for _, line in ipairs(lines) do
		width = math.max(width, #line)
	  end
	  width = math.min(width + 4, 80)
	  local height = #lines
	  
	  -- Center the window
	  local ui = vim.api.nvim_list_uis()[1]
	  local opts = {
		relative = 'editor',
		width = width,
		height = height,
		col = (ui.width - width) / 2,
		row = (ui.height - height) / 2,
		style = 'minimal',
		border = 'rounded',
		title = ' Select ',
		title_pos = 'center',
	  }
	  
	  local win = vim.api.nvim_open_win(buf, true, opts)
	  vim.api.nvim_win_set_option(win, 'cursorline', true)
	  
	  -- Set up key mappings
	  local function close_and_callback(choice)
		vim.api.nvim_win_close(win, true)
		if choice and callback then
		  callback(choice, items[choice])
		end
	  end
	  
	  -- Map number keys
	  for i = 1, #items do
		vim.api.nvim_buf_set_keymap(buf, 'n', tostring(i), '', {
		  nowait = true,
		  noremap = true,
		  silent = true,
		  callback = function() close_and_callback(i) end
		})
	  end
	  
	  -- Map cancel key
	  vim.api.nvim_buf_set_keymap(buf, 'n', 'x', '', {
		nowait = true,
		noremap = true,
		silent = true,
		callback = function() close_and_callback(nil) end
	  })
	  
	  -- Also close on <Esc>
	  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
		nowait = true,
		noremap = true,
		silent = true,
		callback = function() close_and_callback(nil) end
	  })
end

function M.show(items)
	  if #items == 0 or #items > 9 then
		vim.notify("Quick select supports 1-9 items only", vim.log.levels.WARN)
		return nil, nil
	  end

	  -- Create buffer
	  local buf = vim.api.nvim_create_buf(false, true)
	  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
	  
	  -- Prepare display lines
	  local lines = {}
	  for i, item in ipairs(items) do
		table.insert(lines, string.format("%d) %s", i, item))
	  end
	  table.insert(lines, "")
	  table.insert(lines, "x) Cancel")
	  
	  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	  
	  -- Calculate window size
	  local width = 0
	  for _, line in ipairs(lines) do
		width = math.max(width, #line)
	  end
	  width = math.min(width + 4, 80)
	  local height = #lines
	  
	  -- Center the window
	  local ui = vim.api.nvim_list_uis()[1]
	  local opts = {
		relative = 'editor',
		width = width,
		height = height,
		col = (ui.width - width) / 2,
		row = (ui.height - height) / 2,
		style = 'minimal',
		border = 'rounded',
		title = ' Select ',
		title_pos = 'center',
	  }
	  
	  local win = vim.api.nvim_open_win(buf, true, opts)
	  vim.api.nvim_win_set_option(win, 'cursorline', true)
	  
	  -- Variable to store the result
	  local choice = nil
	  local done = false
	  
	  -- Set up key mappings
	  local function close_with_choice(c)
		choice = c
		done = true
		vim.api.nvim_win_close(win, true)
	  end
	  
	  -- Map number keys
	  for i = 1, #items do
		vim.api.nvim_buf_set_keymap(buf, 'n', tostring(i), '', {
		  nowait = true,
		  noremap = true,
		  silent = true,
		  callback = function() close_with_choice(i) end
		})
	  end
	  
	  -- Map cancel keys
	  for _, key in ipairs({'x', '<Esc>'}) do
		vim.api.nvim_buf_set_keymap(buf, 'n', key, '', {
		  nowait = true,
		  noremap = true,
		  silent = true,
		  callback = function() close_with_choice(nil) end
		})
	  end
	  
	  -- Wait for input (blocking)
	  vim.fn.getchar()
	  
	  -- Return selection
	  if choice then
		return items[choice]
	  else
		return
	  end
end


return M
