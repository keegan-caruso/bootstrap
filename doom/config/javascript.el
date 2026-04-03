;;; config/javascript.el -*- lexical-binding: t; -*-

(add-to-list 'auto-mode-alist '("\\.jsx\\'" . rjsx-mode))
(add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))
(add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-ts-mode))

(defun kc/project-node-bin (program)
  (let ((candidate (expand-file-name (format "node_modules/.bin/%s" program) (kc/project-root))))
    (when (file-executable-p candidate)
      candidate)))

(defun kc/typescript-language-server-command ()
  (or (kc/project-node-bin "typescript-language-server")
      (executable-find "typescript-language-server")))

(after! eglot
  (dolist (mode '(typescript-mode typescript-ts-mode tsx-ts-mode js-mode js2-mode rjsx-mode))
    (add-to-list 'eglot-server-programs
                 `(,mode . (,(or (kc/typescript-language-server-command)
                                 "typescript-language-server")
                            "--stdio")))))

(after! apheleia
  (setf (alist-get 'js-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'js2-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'rjsx-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'typescript-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'typescript-ts-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'tsx-ts-mode apheleia-mode-alist) 'prettier)
  (add-hook 'js-mode-hook #'apheleia-mode)
  (add-hook 'js2-mode-hook #'apheleia-mode)
  (add-hook 'rjsx-mode-hook #'apheleia-mode)
  (add-hook 'typescript-mode-hook #'apheleia-mode)
  (add-hook 'typescript-ts-mode-hook #'apheleia-mode)
  (add-hook 'tsx-ts-mode-hook #'apheleia-mode))

(add-hook 'rjsx-mode-hook #'imenu-add-menubar-index)
(add-hook 'tsx-ts-mode-hook #'imenu-add-menubar-index)
(add-hook 'typescript-ts-mode-hook #'imenu-add-menubar-index)

(use-package! flymake-collection
  :hook ((js-mode . flymake-collection-eslint-setup)
         (js2-mode . flymake-collection-eslint-setup)
         (rjsx-mode . flymake-collection-eslint-setup)
         (typescript-mode . flymake-collection-eslint-setup)
         (typescript-ts-mode . flymake-collection-eslint-setup)
         (tsx-ts-mode . flymake-collection-eslint-setup)))
