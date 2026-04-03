;;; ~/.doom.d/init.el -*- lexical-binding: t; -*-

(doom!
 :input

 :completion
 vertico

 :ui
 doom
 hl-todo
 modeline
 nav-flash
 ophints
 (popup +defaults)
 vc-gutter
 vi-tilde-fringe
 window-select
 workspaces

 :editor
 evil
 file-templates
 fold
 format
 snippets
 word-wrap

 :emacs
 dired
 electric
 undo
 vc

 :checkers
 syntax

 :tools
 eval
 lookup
 (lsp +eglot)
 magit
 tree-sitter

 :lang
 csharp
 emacs-lisp
 (javascript +tree-sitter)
 json
 markdown
 org
 (rust +lsp)
 sh
 yaml

 :term
 vterm

 :config
 (default +bindings +smartparens))
