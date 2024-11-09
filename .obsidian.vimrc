ettings
set clipboard=unnamed
set ignorecase
set smartcase
set incsearch
set hlsearch
set number
set relativenumber

" Map jk to escape
imap jk <Esc>
imap kj <Esc>

" LazyVim style leader key (space)
let mapleader=" "

" Buffer/Note Navigation (similar to LazyVim)
exmap quickSwitch obcommand quickswitcher:open
nmap <leader><leader> :quickSwitch
nmap <leader>ff :quickSwitch

" File Explorer (similar to Neo-tree)
exmap toggleLeftSidebar obcommand app:toggle-left-sidebar
nmap <leader>e :toggleLeftSidebar

" Save file
nmap <leader>w :w<CR>
nmap <C-s> :w<CR>

" Window Navigation
exmap focusRight obcommand workspace:next-tab
exmap focusLeft obcommand workspace:previous-tab
nmap <C-h> :focusLeft
nmap <C-l> :focusRight
nmap <leader>- :split<CR>
nmap <leader>| :vsplit<CR>

" Better window navigation
nmap <C-h> <C-w>h
nmap <C-j> <C-w>j
nmap <C-k> <C-w>k
nmap <C-l> <C-w>l

" Buffer navigation
exmap back obcommand app:go-back
exmap forward obcommand app:go-forward
nmap <leader>bp :back
nmap <leader>bn :forward

" Search
exmap searchInFiles obcommand global-search:open
nmap <leader>/ :nohl<CR>
nmap <leader>sg :searchInFiles

" LSP-like functionality
exmap followLink obcommand editor:follow-link
nmap gd :followLink
nmap gr :followLink

" File operations
exmap newNote obcommand file:new-note
nmap <leader>fn :newNote

" Toggle Terminal (if you have a terminal plugin)
exmap toggleTerminal obcommand terminal:toggle
nmap <leader>ft :toggleTerminal

" Diagnostics navigation (if you have linting plugins)
exmap nextError obcommand lint:next-error
exmap prevError obcommand lint:previous-error
nmap ]d :nextError
nmap [d :prevError

" Quick markdown formatting
nmap <leader>b ciw****<Left><Left>
nmap <leader>i ciw**<Left>
vmap <leader>b c****<Left><Left>
vmap <leader>i c**<Left>

" Better indenting
vmap < <gv
vmap > >gv

" Move Lines
nmap <A-j> :m .+1<CR>==
nmap <A-k> :m .-2<CR>==
vmap <A-j> :m '>+1<CR>gv=gv
vmap <A-k> :m '<-2<CR>gv=gv

" Quick pairs
imap '' ''<Left>
imap "" ""<Left>
imap () ()<Left>
imap [] []<Left>
imap {} {}<Left>
imap <> <><Left>

" LazyVim-style which-key equivalents
" Files
nmap <leader>ff :quickSwitch
nmap <leader>fn :newNote

" Search
nmap <leader>sg :searchInFiles
nmap <leader>sh :searchInFiles
nmap <leader>sw :searchInFiles

" Buffers
nmap <leader>bb :quickSwitch
nmap <leader>bd :close

" Windows
nmap <leader>ww <C-w>w
nmap <leader>wd :close
nmap <leader>wh <C-w>h
nmap <leader>wj <C-w>j
nmap <leader>wk <C-w>k
nmap <leader>wl <C-w>l

" Toggle options
exmap togglePreview obcommand markdown:toggle-preview
nmap <leader>tp :togglePreview

" Quick lists
nmap <leader>xl :toggleCheckbox

" Notes specific
exmap backlinks obcommand backlinks:open
nmap <leader>nb :backlinks

" Center search results
nmap n nzz
nmap N Nzz
nmap * *zz
nmap # #zz
nmap g* g*zz
nmap g# g#zz

" Quick commands
nmap ; :
vmap ; :

" Undo/Redo
nmap U :redo

" Fold/Unfold
exmap fold obcommand editor:fold-all
exmap unfold obcommand editor:unfold-all
nmap zM :fold
nmap zR :unfold

