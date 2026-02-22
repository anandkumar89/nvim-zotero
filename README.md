# Zotcite

Zotero 8 + Neovim integration for researchers.

A powerful Neovim plugin designed to bring Zotero's library management directly into your TeX, Markdown, and Quarto workflows. Fully optimized for Zotero 8 with native citekey support and advanced PDF reader integration.

## 🚀 Key Features

- **Zotero 8 Native Support**: Automatically recognizes and prioritizes Zotero's internal `Citation Key` field. No dependency on Better BibTeX required.
- **Smart Citation Prioritization**: 
    - **Local `.bib` Files**: Integrates with **Vimtex** to search local bibliography files first.
    - **Zotero Database**: Transparently falls back to the main Zotero database if a key is not found locally.
- **Enhanced Search Picker (`Zseek`)**:
    - **Floating UI**: Uses `fzf-lua` (recommended) or `Telescope` for a fast, searchable interface.
    - **Bulk Actions & Scratch Buffer**: Select multiple entries and press `<C-n>` (Notes) or `<C-a>` (Annotations) to collate their contents into a Markdown-formatted scratch buffer.
    - **Grouped Annotations**: If a citation has multiple PDF attachments, annotations are clearly grouped by filename in the scratch buffer.
    - **Clickable Links**: Scratch buffers include `[Zotero Link]` elements that open the exact item in Zotero.
    - **Cite Insertion**: Select multiple entries and press `<C-x>` to insert citekeys directly into your buffer.
    - **Metadata Preview**: The metadata preview is visible by default and can be toggled via `<C-i>`.
- **Advanced Zotero Reader Integration**:
    - **Zotero-First Opening**: Pressing `<leader>zo` on a citation opens the PDF directly in Zotero's reader.
    - **Page Parameters**: Automatically appends `?page=PNUM` to open the cited page directly.
    - **Attachment Selection**: If multiple PDFs are associated with a citation, a clear picker displays full filenames for easy selection.
- **Direct Citation Access**:
    - Placing your cursor on a `@citekey` and pressing `<leader>za` or `<leader>zn` bypasses the picker and opens the scratch buffer directly.

## 🛠 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'anandkumar89/nvim-zotero',
    branch = 'myzot',
    dependencies = {
        'nvim-lua/plenary.nvim',
        'ibhagwan/fzf-lua', -- for picker
    },
    config = function()
        require('zotcite').setup({
            -- Minimal configuration
            open_in_zotero = true, -- Open PDFs in Zotero reader by default
        })
    end
}
```

## ⌨️ Default Keymaps

| Keymap | Mode | Action |
| :--- | :--- | :--- |
| `<leader>zs` | Normal | Open **Zseek** search (Search by Author/Year/Title) |
| `<leader>zo` | Normal | Open PDF in Zotero (or default viewer) |
| `<leader>zi` | Normal | Echo Reference Info (Metadata + Citekey) |
| `<leader>za` | Normal | Open PDF Annotations in Scratch Buffer (Directly if on citation) |
| `<leader>zn` | Normal | Open Zotero Notes in Scratch Buffer (Directly if on citation) |
| `<leader>zy` | Normal | Insert YAML Metadata (Markdown/Quarto) |

### Inside Zseek Picker:

| Keymap | Action |
| :--- | :--- |
| `<CR>` | Open associated PDF |
| `<C-o>` | Open associated PDF |
| `<C-i>` | Toggle Metadata Preview |
| `<C-n>` | Open Notes in Scratch Buffer (Bulk Action) |
| `<C-a>` | Open Annotations in Scratch Buffer (Bulk Action) |
| `<C-x>` | Insert Citekey(s) into buffer |

## ⚙️ Configuration

```lua
require('zotcite').setup({
    hl_cite_key = true,
    sort_key = "dateModified",
    open_in_zotero = true, -- prioritize zotero:// URIs
    filetypes = { "markdown", "tex", "latex", "quarto", "pandoc" },
    python_path = "python3", -- path to python with sqlite3 support
})
```

## 📜 Requirements

- Neovim >= 0.9.0
- Python 3 with `sqlite3` and `PyYAML`
- Zotero (Desktop app)
- (Optional) [fzf-lua](https://github.com/ibhagwan/fzf-lua) for the best picker experience.

## 🤝 Contributing

This is a personalized fork of `zotcite` optimized for a modern Zotero 8 research workflow. PRs and issues are welcome!
