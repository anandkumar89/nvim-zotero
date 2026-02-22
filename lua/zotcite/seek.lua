local fzf_lua = require("fzf-lua")
local config = require("zotcite.config").get_config()
local ns = vim.api.nvim_create_namespace("ZSeekPreview")

local M = {}
local use_fzf = true		-- read from configurations

if not use_fzf then 			-- use telescope if not fzf_lua
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local sorters = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")
	local entry_display = require("telescope.pickers.entry_display")
end

-- Conversion from zotero.sqlite to bib types
local _zbt = {
        artwork             = 'Misc',
        audioRecording      = "Audio",
        blogPost            = "Blog",
        book                = "Book",
        bookSection         = "Book Sec",
        case                = "Misc",
        computerProgram     = "Code",
        conferencePaper     = "Proc",
        dictionaryEntry     = "Misc",
        document            = "Docu",
        email               = "Email",
        encyclopediaArticle = "Encyclopedia",
        film                = "Misc",
        forumPost           = "Misc",
        hearing             = "Misc",
        instantMessage      = "Misc",
        interview           = "Misc",
        journalArticle      = "Article",
        letter              = "Misc",
        magazineArticle     = "Magaz",
        newspaperArticle    = "News",
        note                = "Note",
        podcast             = "Misc",
        presentation        = "PPT",
        radioBroadcast      = "Misc",
        statute             = "Misc",
        thesis              = "Thesis",
        tvBroadcast         = "Misc",
        videoRecording      = "Video"
	}

local get_match = function(key)
    local citeptrn = key:gsub(" .*", "")
    local refs = vim.fn.py3eval(
        'ZotCite.GetMatch("'
            .. citeptrn
            .. '", "'
            .. vim.fn.escape(vim.fn.expand("%:p"), "\\")
            .. '", True)'
    )
    if #refs == 0 then
        vim.schedule(
            function() vim.api.nvim_echo({ { "No matches found." } }, false, {}) end
        )
    end
    return refs
end

M.print = function(ref)
    local msg = {
        { ref.value.alastnm, "Identifier" },
        { " " },
        { ref.value.year, "Number" },
        { " " },
        { ref.value.title, "Title" },
    }
    vim.schedule(function() vim.api.nvim_echo(msg, false, {}) end)
end

local format_preview = function(v)
    local alist = {}
    local authors
    if v.author then
        if #v.author > 5 then
            authors = v.author[1][1] .. ", " .. v.author[1][2] .. " and others"
        else
            for _, n in pairs(v.author) do
                table.insert(alist, n[1] .. ", " .. n[2])
            end
            authors = table.concat(alist, "; ")
        end
    else
        authors = "?"
    end
    local year = v.year or "????"
    local title = v.title or "????"
    local ptitle = v.publicationTitle or "????"
	local citekey = v.cite or ""
    local txt
    local hl = {{ g = "Key", s = 0, e = #citekey }}
    table.insert(hl, { g = "Identifier",    s = hl[1].e + 1, e = hl[1].e + 1 + #authors })
	table.insert(hl, { g = "Number", s = hl[2].e + 1, e = hl[2].e + 1 + #year })
    table.insert(hl, { g = "Title",  s = hl[3].e + 1, e = hl[3].e + 1 + #title })
    if v.etype == "journalArticle" then
        txt = string.format(
            "%s %s %s %s. %s.\n\n%s\n",
			citekey,
            authors,
            year,
            title,
            ptitle,
            v.abstract or "No abstract available."
        )
        table.insert(hl, { g = "Include", s = hl[4].e + 2, e = hl[4].e + 2 + #ptitle })
    elseif v.etype == "bookSection" then
        txt = string.format(
            "%s %s %s %s. In: %s.\n\n%s\n",
			citekey,
            authors,
            year,
            title,
            ptitle,
            v.abstract or ""
        )
        table.insert(hl, { g = "Include", s = hl[5].e + 6, e = hl[5].e + 6 + #ptitle })
    else
        txt = string.format("%s %s %s %s.\n\n%s\n", citekey, authors, year, title, v.abstract or "")
    end
    return txt, hl
end

---------------------------- fzf begin 
fopts = {
	['--header']    = "<C-o>: Notes | <CR>: Sioyek | <C-a> : Annotation | <C-x> : Cite",
	['--delimiter'] = '\t',
	['--with-nth']  = '2',
	['--ansi']      = true,
	['--no-sort']   = "",
	['--multi']     = "",
	['--preview-window']   = "wrap:hidden"
}

bibdata = {}
fzf_query   = ""

annotation_picker = function(citekey, picker)
	if citekey then
		local grouped_annotations = require("zotcite.get").finish_annotations_selection(citekey)
		if next(grouped_annotations) == nil then return end
		local ent = vim.tbl_map(function(line)
			return "modified " .. line:gsub("(%[.-%])", "\27[34m%1\27[0m", 1)
		end, grouped_annotations)
		fzf_lua.fzf_exec(ent, {
			prompt = "> ",
			fzf_opts = {
				['--ansi'] = true,
				["--wrap"] = "",
				["--multi"] = "",
			},
			actions = {
				['ctrl-y'] = function(selected)
					-- copy selected to clipboard 
					vim.fn.setreg("+", selected[1])
					picker()
				end,
				['default'] = function(selected)
					-- insert all of multiple selections  
					local line = vim.api.nvim_win_get_cursor(0)[1]
					for _, v in pairs(selected) do
						vim.api.nvim_buf_set_lines(0, line, line, false, {v})
						line = line + 1
					end
				end,
			},
		})
	end
end

-- fzf-lua configuration
fzf_picker = function(data, pref)
	local entries, previewtext = data.lines or {}, data.preview or {}
	local exact = pref.exact ~= nil and pref.exact or true

	fzf_lua.fzf_exec(entries, {
			prompt = pref.prompt or "grep > ",
			exec_empty_query = true,
			winopts = {
				preview = {
					hidden = true,
					wrap = true,
				},
			},
			fzf_opts = fopts,
			previewer = {
				_ctor = function()
					local base = require 'fzf-lua.previewer.builtin'.buffer_or_file
					local previewer = base:extend()
					function previewer:populate_preview_buf(selection)
						local citekey = selection:match("([^\t]+)")
						local text = previewtext[citekey]
						local tmpbuf = self:get_tmp_buffer()
						vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(text[1], '\n'))
						for _, h in pairs(text[2]) do
							if vim.fn.has("nvim-0.11") == 1 then
								vim.hl.range(tmpbuf, ns, h.g, { 0, h.s }, { 0, h.e }, {})
							else
								vim.api.nvim_buf_add_highlight(tmpbuf, -1, h.g, 0, h.s, h.e)
							end
						end
						self:set_preview_buf(tmpbuf)
					end
				return previewer
				end,
			},
			actions = {
				['default'] = function(selected, opts)
					print(opts.last_query)
					local citekey = selected[1]:match("([^\t]+)")
					print("Default action for: " .. citekey)
					if citekey then
						require("zotcite.get").open_attachment(citekey)
					end
				end,
				['ctrl-o'] = function(selected, opts)
					local citekey = selected[1]:match("([^\t]+)")
					if citekey and pref.cb then
						pref.cb(citekey)
					end
				end,
				['ctrl-a'] = function (selected, opts)
					local citekey = selected[1]:match("([^\t]+)")
					annotation_picker(citekey, fzf_picker)
				end,
				-- -- Open loclist with selected references in formatted sense : @citekey Year Title
				-- -- Has keymaps to open in Sioyek or copy citekeys or open annotations or corresponding notes
				-- ['ctrl-q'] = function (selected, opts)
				-- 	local winnr = vim.api.nvim_get_current_win()
				-- 	local items = {}
				-- 	for _, sel in pairs(selected) do
				-- 		items.insert({
				-- 			text = sel,
				-- 			filename = vim.fn.expand("%:p"),
				-- 			lnum = 1,
				-- 			col = 1,
				-- 		})
				-- 	end
				-- 	vim.fn.setloclist(winnr, items, 'r', { 
				-- 		title = 'Zotero References', 
				-- 		context = {citation_list = true} 
				-- 	})
				-- 	vim.cmd("lopen")
				-- end,
				['ctrl-x'] = function(selected, opts)
					local citekeys = {}
					for _, sel in pairs(selected) do
						local ckey = sel:match("([^\t]+)")
						if ckey then
							table.insert(citekeys, ckey)
						end
					end
					if #citekeys > 0 then
						local text = table.concat(citekeys, ", ")
						vim.api.nvim_put({ text }, "c", true, true)
					end
				end,
			},
	})
end

--- Use telescope or fzf to find and select a reference
---@param key string Pattern to search
---@param cb function Callback function
M.refs = function(key, cb)
    local mtchs = get_match(key)
    local references = {}
    local awidth = 2
    local awlim = vim.o.columns - 140
    if awlim < 20 then awlim = 20 end
    if awlim > 60 then awlim = 60 end
    for _, v in pairs(mtchs) do
        if #v.alastnm > awidth then awidth = #v.alastnm end
        table.insert(references, {
            display = v.alastnm .. " " .. v.year .. " " .. v.title,
            etype = _zbt[v.etype] or v.etype,
            sort_key = v[config.sort_key] or "0000-00-00 0000",
            publicationTitle = v.publicationTitle
                or v.bookTitle
                or v.proceedingsTitle
                or v.conferenceName
                or v.programTitle
                or v.blogTitle
                or v.code
                or v.dictionaryTitle
                or v.encyclopediaTitle
                or v.forumTitle
                or v.websiteTitle
                or v.seriesTitle,
            author = v.author
                or v.artist
                or v.performer
                or v.director
                or v.composer
                or v.sponsor
                or v.contributor
                or v.interviewee
                or v.cartographer
                or v.inventor
                or v.podcaster
                or v.presenter
                or v.programmer
                or v.recipient
                or v.editor
                or v.seriesEditor
                or v.translator,
            alastnm = v.alastnm,
            year = v.year,
            title = v.title,
            abstract = v.abstractNote,
            key = v.zotkey,
            cite = v.citekey,
        })
    end
    if awidth > awlim then awidth = awlim end
    table.sort(references, function(a, b) return (a.sort_key > b.sort_key) end)


	if use_fzf then
		local entries = {}
		local previewtext = {}

		-- Define ANSI color codes
		local red    = "\27[31m"
		local green  = "\27[32m"
		local yellow = "\27[33m"
		local reset  = "\27[0m"

		for i, ref in ipairs(references) do
			entries[i] = string.format(
			  "%s\t%s"..red.." %-4s"..reset..green.." %s"..reset.." [%s]",
			  ref.cite, ref.alastnm, ref.year, ref.title, ref.etype
			)
			local text, hl = format_preview(ref)
			previewtext[ref.cite] = { text, hl }
		end
		bibdata = {lines = entries, preview = previewtext}



		fzf_picker(bibdata, {exact=true, prompt="grep >", cb=cb})

	else
		pickers
			.new({}, {
				prompt_title = "Search pattern",
				results_title = "Zotero references",
				finder = finders.new_table({
					results = references,
					entry_maker = function(entry)
						local displayer = entry_display.create({
							separator = " ",
							items = {
								{ width = awidth }, -- Author
								{ width = 4 }, -- Year
								{ remaining = true }, -- Title
							},
						})
						return {
							value = entry,
							display = function(e)
								return displayer({
									{ e.value.alastnm, "Identifier" },
									{ e.value.year, "Number" },
									{ e.value.title, "Title" },
								})
							end,
							ordinal = entry.display,
						}
					end,
				}),
				sorter = sorters.generic_sorter({}),
				previewer = previewers.new_buffer_previewer({
					define_preview = function(self, entry, _)
						local bufnr = self.state.bufnr
						local preview_text, hl = format_preview(entry.value)
						vim.api.nvim_buf_set_lines(
							bufnr,
							0,
							-1,
							false,
							vim.split(preview_text, "\n")
						)
						for _, h in pairs(hl) do
							if vim.fn.has("nvim-0.11") == 1 then
								vim.hl.range(bufnr, ns, h.g, { 0, h.s }, { 0, h.e }, {})
							else
								vim.api.nvim_buf_add_highlight(bufnr, -1, h.g, 0, h.s, h.e)
							end
						end
					end,
				}),
				attach_mappings = function(prompt_bufnr, map)
					map("i", "<C-o>", function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						-- Handle the selected reference here
						cb(selection)
					end)
					map("i", "<CR>", function()
						local selection = action_state.get_selected_entry()
						-- actions.close(prompt_bufnr)
						print(selection.value)
						require("zotcite.get").open_attachment(selection.value.cite)
					end)
					map("i", "<C-x>", function()
						local picker = action_state.get_current_picker(prompt_bufnr)
						local selections = picker:get_multi_selection()
						if vim.tbl_isempty(selections) then
							selections = { action_state.get_selected_entry() }
						end
						actions.close(prompt_bufnr)
						local citekeys = {}
						for _, entry in ipairs(selections) do
							table.insert(citekeys, entry.value.cite)
						end
						if #citekeys > 0 then
							local text = table.concat(citekeys, ", ")
							vim.api.nvim_put({ text }, "c", true, true)
						end
					end)
					return true
				end,
		}):find()
	end

end

--  text wrapping in the preview window
vim.api.nvim_create_autocmd("User", {
    pattern = "TelescopePreviewerLoaded",
    callback = function()
        vim.wo.wrap = true
        vim.wo.linebreak = true
    end,
})

return M
