;;; config/toml.el -*- lexical-binding: t; -*-

(defun kc/toml-mode ()
  (interactive)
  (cond
   ((fboundp 'toml-ts-mode)
    (toml-ts-mode))
   ((fboundp 'conf-toml-mode)
    (conf-toml-mode))
   ((fboundp 'toml-mode)
    (toml-mode))
   (conf-mode)))

(add-to-list 'auto-mode-alist '("\\.toml\\'" . kc/toml-mode))

(defun kc/taplo-language-server-command ()
  (when (executable-find "taplo")
    '("taplo" "lsp" "stdio")))

(after! eglot
  (when-let ((taplo-server (kc/taplo-language-server-command)))
    (dolist (mode '(toml-mode conf-toml-mode toml-ts-mode))
      (add-to-list 'eglot-server-programs `(,mode . ,taplo-server)))))

(after! apheleia
  (setf (alist-get 'toml-mode apheleia-mode-alist) '("taplo" "fmt" filepath))
  (setf (alist-get 'conf-toml-mode apheleia-mode-alist) '("taplo" "fmt" filepath))
  (setf (alist-get 'toml-ts-mode apheleia-mode-alist) '("taplo" "fmt" filepath))
  (add-hook 'toml-mode-hook #'apheleia-mode)
  (add-hook 'conf-toml-mode-hook #'apheleia-mode)
  (add-hook 'toml-ts-mode-hook #'apheleia-mode))
