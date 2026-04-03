;;; config/python.el -*- lexical-binding: t; -*-

(defun kc/python-language-server-command ()
  (cond
   ((executable-find "ty")
    '("ty" "server"))
   ((executable-find "uvx")
    '("uvx" "ty" "server"))))

(defun kc/project-uv-sync ()
  (interactive)
  (kc/project-vterm (format "%s uv sync" (kc/project-name)) "uv sync"))

(defun kc/project-uv-run-python ()
  (interactive)
  (kc/project-vterm (format "%s uv run python" (kc/project-name)) "uv run python"))

(defun kc/project-ruff-check ()
  (interactive)
  (kc/project-vterm (format "%s ruff check" (kc/project-name)) "ruff check"))

(defun kc/project-ruff-format ()
  (interactive)
  (kc/project-vterm (format "%s ruff format" (kc/project-name)) "ruff format ."))

(defun kc/project-ty-check ()
  (interactive)
  (kc/project-vterm (format "%s ty check" (kc/project-name)) "ty check"))

(after! vterm
  (map! :leader
        (:prefix ("o p" . "Python")
         :desc "uv sync" "s" #'kc/project-uv-sync
         :desc "uv run python" "r" #'kc/project-uv-run-python
         :desc "ruff check" "c" #'kc/project-ruff-check
         :desc "ruff format" "f" #'kc/project-ruff-format
         :desc "ty check" "t" #'kc/project-ty-check)))

(after! eglot
  (when-let ((python-server (kc/python-language-server-command)))
    (dolist (mode '(python-mode python-ts-mode))
      (add-to-list 'eglot-server-programs `(,mode . ,python-server)))))

(after! apheleia
  (setf (alist-get 'python-mode apheleia-mode-alist) '("ruff" "format" filepath))
  (setf (alist-get 'python-ts-mode apheleia-mode-alist) '("ruff" "format" filepath))
  (add-hook 'python-mode-hook #'apheleia-mode)
  (add-hook 'python-ts-mode-hook #'apheleia-mode))
