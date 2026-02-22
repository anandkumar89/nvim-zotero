local config = require("zotcite.config").get_config()
local zwarn = require("zotcite").zwarn
local seek = require("zotcite.seek")

local offset = "0"
local pdfnote_data = {}
local sel_list = {}

local citation = {
    start_col = 0,
    end_col = 0,
}

local M = {}

local TranslateZPath = function(strg, citekey)
    local id, libDir, rest = strg:match("([^:]+):([^:]+):(.*)")

    if config.open_in_zotero and id and id:len() == 8 and id ~= "local" then
        local uri = ""
        if string.lower(strg):find("%.pdf$") then
            uri = "zotero://open-pdf/" .. libDir .. "/items/" .. id
            -- Check for page data
            if citekey and pdfnote_data.citekey and pdfnote_data.citekey:find("@" .. citekey) then
                if pdfnote_data.pg and pdfnote_data.pg ~= "" then
                    uri = uri .. "?page=" .. pdfnote_data.pg
                end
            end
        else
            uri = "zotero://select/" .. libDir .. "/items/" .. id
        end
        return uri
    end

    local fpath = strg
    if id and libDir and rest then
        fpath = rest
        if fpath:find("^storage:") then
            fpath = config.data_dir .. fpath:gsub("^storage:", "/storage/" .. id .. "/")
        elseif fpath:find("^attachments:") then
            if config.attach_dir == "" then
                zwarn("Attachments dir is not defined")
                fpath = ""
            else
                fpath = fpath:gsub("^attachments:", "/" .. config.attach_dir .. "/")
            end
        end
    end

    if fpath ~= "" and vim.fn.filereadable(fpath) == 0 then
        -- Search for the last colon to get the filename as a last resort
        local fallback = strg:match(".*:([^:]+)$")
        if fallback and vim.fn.filereadable(fallback) == 1 then
            return fallback
        end
        zwarn('Could not find "' .. fpath .. '"')
        fpath = ""
    end
    return fpath
end

local get_ref_data_prioritized = function(citekey)
    local repl = nil
    if (vim.o.filetype == "tex" or vim.o.filetype == "latex") and vim.fn.exists("*vimtex#bib#files") == 1 then
        local bib_files = vim.fn["vimtex#bib#files"]()
        if #bib_files > 0 then
            repl = vim.fn.py3eval('ZotCite.GetBibRefData("' .. citekey .. '", ' .. vim.fn.json_encode(bib_files) .. ')')
            if repl == vim.NIL then repl = nil end
        end
    end
    if not repl then
        repl = vim.fn.py3eval('ZotCite.GetRefData("' .. citekey .. '")')
        if repl == vim.NIL then repl = nil end
    end
    return repl
end

M.PDFPath = function(citekey, cb)
    local repl = nil
    local data = get_ref_data_prioritized(citekey)
    if data and data.attachment and #data.attachment > 0 then
        -- Check if first attachment exists
        local p = vim.fn.expand(data.attachment[1])
        if vim.fn.filereadable(p) == 1 then
            repl = data.attachment
        end
    end

    if not repl or #repl == 0 then
        repl = vim.fn.py3eval('ZotCite.GetAttachment("' .. citekey .. '")')
    end

    if #repl == 0 or repl[1] == "nOcItEkEy" or repl[1] == "nOaTtAChMeNt" then
        local msg = "No attachment found for " .. citekey
        if data and data.file then
            msg = msg .. ". BibTeX file field: " .. data.file .. ". Consider importing this to Zotero (File > Import)."
        end
        zwarn(msg)
        return
    end

    local results = {}
    for _, v in pairs(repl) do
        local path = TranslateZPath(v, citekey)
        if path ~= "" then
            local display = ""
            if v:find(":") then
                display = v:gsub(".*:", "") -- Get filename part
            else
                display = v
            end
            display = display:gsub(".*/", "") -- Basename
            table.insert(results, { display = display, path = path })
        end
    end

    if #results == 0 then
        zwarn("No readable attachments found")
        return
    elseif #results == 1 then
        return results[1].path
    else
        sel_list = {}
        local items = {}
        for _, res in ipairs(results) do
            table.insert(items, res.display)
            table.insert(sel_list, res.path)
        end

        local has_fzf, fzf = pcall(require, "fzf-lua")
        if has_fzf then
            vim.schedule(function()
                fzf.fzf_exec(items, {
                    prompt = "Select Attachment> ",
                    winopts = { height = 0.3, width = 0.5 },
                    actions = {
                        ['default'] = function(selected)
                            local choice = selected[1]
                            for i, item in ipairs(items) do
                                if item == choice then
                                    cb(nil, i)
                                    return
                                end
                            end
                        end
                    }
                })
            end)
        else
            vim.schedule(function() 
                vim.ui.select(items, { prompt = "Select attachment:" }, function(choice, idx)
                    for i, item in ipairs(items) do
                        if item == choice then
                            cb(nil, i)
                            return
                        end
                    end
                end) 
            end)
        end
    end
end

function findCiteAtCursorTex(line, cursorCol)
    -- returns \cite**{somestring} -> specific citekey under cursor or nil
    local searchStart = 1
    local col = cursorCol + 1 -- Lua 1-indexed

    while true do
        local startPos, endPos, match = line:find("(\\%a*cite%a*[^{]-%b{})", searchStart)
        if not match then return nil end
        
        if col >= startPos and col <= endPos then
            local content = match:match("{([^}]*)}")
            if not content then return nil end
            
            -- Find which key is under the cursor
            local relativeCol = col - startPos + 1
            local braceStart = match:find("{")
            local keysRelativeCol = relativeCol - braceStart
            
            local currentPos = 1
            for key in content:gmatch("([^,]+)") do
                local keyStart, keyEnd = content:find(key, currentPos, true)
                if keyStart <= keysRelativeCol and keysRelativeCol <= keyEnd then
                    return key:gsub("^%s*(.-)%s*$", "%1") -- trim
                end
                currentPos = keyEnd + 1
            end
            -- Fallback to first key if we are inside braces but not clearly on a key
            return content:match("([^,]+)"):gsub("^%s*(.-)%s*$", "%1")
        end
        searchStart = endPos + 1
    end
end

M.citation_key = function()
    local bbt = bbt or true -- assume by default that bbt is used, fix, TODO : read value from config
    if bbt then
		-- get filetype 
        local word = vim.fn.expand("<cWORD>")
		local ma   = ""
		if vim.o.filetype == "tex" or vim.o.filetype == "latex" then
			local buf = vim.api.nvim_get_current_buf()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local row, col = cursor[1], cursor[2]
			local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, true)[1]
			if not line then 
				vim.notify("No line found at cursor")
				return ""
			end
			local citestr = findCiteAtCursorTex(line, col)

			if not citestr then
				vim.notify("No citation found at cursor", vim.log.levels.WARN)
				return ""
			end

			local menu_options = {"All"}
			local keys = {}
			for key in citestr:gmatch("([^,]+)") do
				local key = key:gsub("^%s*(.-)%s*$", "%1")
				table.insert(keys, key)  -- Trim outer spaces, May need fix ? when no space after comma
				table.insert(menu_options, key)
			end

			if #keys == 0 then
				vim.notify("No citation key found in \\cite{}", vim.log.levels.WARN)
				return ""
			elseif #keys == 1 then
				ma = keys[1]
			else
				vim.ui.select(menu_options, {
					prompt = "Select citation key:",
				}, function(selected)
					if selected then
						ma = (selected == "All") and keys or selected
						-- Since this is async, we might need a different approach if we want to return a value.
						-- But for now, let's just picking the first one if it's called synchronously or 
						-- we could pass a callback to citation_key.
					end
				end)
				-- Fallback to first key if async select is used in sync context
				ma = keys[1]
			end
		else
			-- [@citekey], @citekey, [@citekey,p. 45], [@citekey; @citekey2, p. 45-50]
			ma  = word:match("%[?@(%w+)%]?")
		end

		return ma or "" -- returns empty string if not found, key or table if multiple keys(only in tex)
    else
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
        local pos = vim.api.nvim_win_get_cursor(0)[2]
        local found_i = false
        local i = pos + 1
        local k
        while i > 0 do
            k = line:sub(i, i)
            if k:find("@") then
                found_i = true
                i = i + 1
                break
            end
            if not k:find("[A-Za-z0-9_#%-]") then break end
            i = i - 1
        end
        if found_i then
            local j = i + 8
            k = line:sub(j, j)
            if k == "#" then
                local key = line:sub(i, j - 1)
                return key
            end
        end
    end
    return ""
end

M.yaml_ref = function()
    local wrd = M.citation_key() -- handle tables
    if wrd ~= "" then
        local repl = vim.fn.py3eval('ZotCite.GetYamlRefs(["' .. wrd .. '"])')
        repl = repl:gsub("^references:[\n\r]*", "")
        if repl == "" then
            zwarn("Citation key not found")
        else
            vim.schedule(function() vim.api.nvim_echo({ { repl } }, false, {}) end)
        end
    end
end

M.reference_data = function(btype)
    local wrd = M.citation_key() -- handle tables 
    if wrd ~= "" then
        local repl = get_ref_data_prioritized(wrd)
        if not repl then
            zwarn("Citation key not found")
            return
        end
        local source = repl.source_file and (" [Source: " .. repl.source_file .. "]") or " [Source: Zotero DB]"
        local title = (repl.title or "") .. source
        local info = {}
        if btype == "raw" then
            for k, v in pairs(repl) do
                table.insert(info, { k, "Title" })
                table.insert(info, { ": " .. vim.inspect(v):gsub("\n$", "") .. "\n" })
            end
        else
            if repl.alastnm then
                table.insert(info, { repl.alastnm .. " ", "Identifier" })
            end
            if repl.year then table.insert(info, { repl.year .. " ", "Number" }) end
            if repl.title then table.insert(info, { title, "Title" }) end
        end
        vim.schedule(function() vim.api.nvim_echo(info, false, {}) end)
    end
end

local finish_citation = function(citekey)
    local rownr = vim.api.nvim_win_get_cursor(0)[1] - 1
    local cite = "@" .. citekey
    vim.api.nvim_buf_set_text(
        0,
        rownr,
        citation.start_col,
        rownr,
        citation.end_col,
        { cite }
    )
    local colnr = citation.start_col + #cite
    vim.api.nvim_win_set_cursor(0, { rownr + 1, colnr })
    vim.api.nvim_feedkeys("a", "n", false)
    require("zotcite.config").hl_citations()
end

--  
M.citation = function()
    local argmt = ""
    local line = vim.api.nvim_get_current_line()
    local last = vim.api.nvim_win_get_cursor(0)[2]
    citation.start_col = last
    citation.end_col = last
    local c = line:sub(last, last):lower()
    if (c >= "a" and c <= "z") or c > "\127" then
        local first = last - 1
        while first > 0 and ((c >= "a" and c <= "z") or c > "\127") do
            first = first - 1
            c = line:sub(first, first):lower()
        end
        argmt = line:sub(first + 1, last):lower()
        citation.start_col = first
    end
    seek.refs(argmt, finish_citation)
end

M.abstract = function()
    local wrd = M.citation_key() -- handle tables
    if wrd ~= "" then
        local repl = get_ref_data_prioritized(wrd)
        if not repl then
            zwarn("Citation key not found")
            return
        end
        local source = repl.source_file and (" [Source: " .. repl.source_file .. "]") or " [Source: Zotero DB]"
        local title = (repl.title or "") .. source
        if repl.abstractNote then
            vim.api.nvim_put({ repl.abstractNote }, "l", true, true)
        else
            zwarn("No abstract found associated with article")
        end
    end
end

M.finish_annotations = function(citekey)
    local repl = vim.fn.py3eval(
        'ZotCite.GetAnnotations("' .. citekey .. '", ' .. offset .. ")"
    )
    if #repl == 0 then
        zwarn("No annotation found.")
    else
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, lnum, lnum, true, repl)
        require("zotcite.config").hl_citations()
    end
end

M.finish_annotations_selection = function(citekey)
    local raw_annotations = vim.fn.py3eval(
        'ZotCite.GetAnnotations("' .. citekey .. '", ' .. offset .. ")"
    )

    if #raw_annotations == 0 then
        zwarn("No annotation found.")
		return {}
    else
        local grouped_annotations = {}
        local current_group = {}
        local last_was_quote = false

        for _, line in ipairs(raw_annotations) do
            if line:sub(1, 1) == ">" then
                if #current_group > 0 and not last_was_quote then
                    table.insert(current_group, line)
                    table.insert(grouped_annotations, table.concat(current_group, "\n"))
                    current_group = {}
                else
                    if #current_group > 0 then
                        table.insert(
                            grouped_annotations,
                            table.concat(current_group, "\n")
                        )
                        current_group = {}
                    end
                    table.insert(current_group, line)
                end
                last_was_quote = true
            else
                if last_was_quote and #current_group > 0 then
                    table.insert(grouped_annotations, table.concat(current_group, "\n"))
                    current_group = {}
                end
                table.insert(current_group, line)
                last_was_quote = false
            end
        end

        if #current_group > 0 then
            table.insert(grouped_annotations, table.concat(current_group, "\n"))
        end
		return grouped_annotations
    end
end

M.annotations = function(ko, use_selection)
    local argmt
    if ko:find(" ") then
        ko = vim.fn.split(ko)
        argmt = ko[1]
        offset = ko[2]
    else
        argmt = ko
        offset = "0"
    end
    if use_selection then
        seek.refs(argmt, finish_annotations_selection)
    else
        seek.refs(argmt, finish_annotations)
    end
end

local finish_note = function(citekey)
    local repl = vim.fn.py3eval('ZotCite.GetNotes("' .. citekey .. '")')
    if repl == "" then
        zwarn("No note found.")
    else
        local lines = vim.fn.split(repl, "\n")
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, lnum, lnum, true, lines)
        require("zotcite.config").hl_citations()
    end
end

M.note = function(key) seek.refs(key, finish_note) end

local finish_pdfnote_2 = function(_, idx)
    local fpath = sel_list[idx]

    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local key = pdfnote_data.citekey
    local p = pdfnote_data.pg
    if vim.fn.filereadable(fpath) == 0 then
        zwarn('File not readable: "' .. fpath .. '"')
        return
    end

    -- Determine which PDF extractor to use
    local pdf_extractor = config.pdf_extractor or "pdfnotes.py"

    local notes = vim.system(
        { config.python_path, config.zotcite_home .. "/" .. pdf_extractor, fpath, key, p },
        { text = true }
    ):wait()
    if notes.code == 0 then
        vim.api.nvim_buf_set_lines(0, lnum, lnum, true, vim.fn.split(notes.stdout, "\n"))
        require("zotcite.config").hl_citations()
    elseif notes.code == 33 then
        zwarn('Failed to load "' .. fpath .. '" as a valid PDF document.')
    elseif notes.code == 34 then
        zwarn("No annotations found.")
    else
        zwarn(notes.stderr)
    end
end

local finish_pdfnote = function(citekey)
    local zotkey = citekey -- FIXME : move to citekey from zotkey, citekey below is different 
    local repl = get_ref_data_prioritized(zotkey)
    if not repl then
        zwarn("Citation key not found")
        return
    end
    local citekey = "@" .. zotkey .. "#" .. (repl["citekey"] or zotkey)
    local pg = "1"
    if repl.pages and repl.pages:find("[0-9]-") then pg = repl.pages end
    pdfnote_data = { citekey = citekey, pg = pg }

    local apath = M.PDFPath(zotkey, finish_pdfnote_2)
    if type(apath) == "string" then
        sel_list = { apath }
        finish_pdfnote_2(nil, 1)
    end
end

M.PDFNote = function(key) seek.refs(key, finish_pdfnote) end

M.yaml_field = function(field, bn)
	if vim.o.filetype == "tex" then
		return
	end
    local node = vim.treesitter.get_node({ bufnr = bn, pos = { 0, 0 } })
    if not node then
        zwarn("Error: Is treesitter enabled?")
        return nil
    end
    if node:type() ~= "minus_metadata" then return nil end

    -- FIXME: use treesitter to avoid dependence on PyYAML

    local lines = vim.api.nvim_buf_get_lines(bn, 0, -1, true)
    local nlines = #lines
    local ylines = {}
    local i = 2
    local line = ""
    local has_field = false
    while i < nlines do
        if lines[i]:find("^%s*%-%-%-%s*$") then break end
        if lines[i]:find(field .. ":") then has_field = true end
        line = lines[i]:gsub("\\", "\\\\")
        line = string.gsub(line, '"', '\\"')
        table.insert(ylines, line)
        i = i + 1
    end
    if #ylines == 0 then return nil end
    if not has_field then return nil end

    local value = vim.fn.py3eval(
        'ZotCite.GetYamlField("'
            .. field
            .. '", "'
            .. table.concat(ylines, "\002")
            .. '")'
    )
    if value == vim.NIL then return nil end

    return value
end

M.collection_name = function(bn)
    if bn == -1 then bn = vim.api.nvim_get_current_buf() end
    local newc = M.yaml_field("collection", bn)
    if not newc then return end

    if type(newc) == "table" then newc = table.concat(newc, "\002") end

    local buf = require("zotcite.config").has_buffer(bn)
    if buf then
        if
            not buf.zotcite_cllctn
            or (buf.zotcite_cllctn and buf.zotcite_cllctn ~= newc)
        then
            require("zotcite.config").set_collection(buf, newc)
            local repl = vim.fn.py3eval(
                'ZotCite.SetCollections("'
                    .. vim.fn.escape(vim.fn.expand("%:p"), "\\")
                    .. '", "'
                    .. newc
                    .. '")'
            )
            if repl ~= "" then zwarn(repl) end
        end
    end
end

M.zotero_info = function()
    local info = {}
    if config.zrunning then
        local pyinfo = vim.fn.py3eval("ZotCite.Info()")
        table.insert(info, { "Information from the Python module:\n", "Statement" })
        for k, v in pairs(pyinfo) do
            table.insert(info, { "  " .. k, "Title" }) -- FIXME: align output
            table.insert(info, { ": " .. tostring(v):gsub("\n", "") .. "\n" })
        end
    end
    if #config.log > 0 then
        table.insert(info, { "Know problems:\n", "Statement" })
        for _, v in pairs(config.log) do
            table.insert(info, { v .. "\n", "WarningMsg" })
        end
    end
    vim.schedule(function() vim.api.nvim_echo(info, false, {}) end)
end

local finish_open_attachment = function(_, idx)
    if idx then require("zotcite.utils").open(sel_list[idx]) end
end

M.open_attachment = function(citekey)
    if not citekey then
        citekey = M.citation_key() -- handle tables
    end
    if citekey ~= "" then
		local apath = M.PDFPath(citekey, finish_open_attachment)
		if type(apath) == "string" then require("zotcite.utils").open(apath) end
		vim.notify("Opening PDF: @" .. citekey )
        -- Clear pdfnote_data
        pdfnote_data = {}
	else
		vim.notify("Nothing to open", vim.log.levels.WARN)
	end
end

return M
