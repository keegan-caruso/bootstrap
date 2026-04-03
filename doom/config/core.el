;;; config/core.el -*- lexical-binding: t; -*-

(require 'subr-x)

(setq user-full-name "Keegan Caruso"
      doom-theme 'doom-one-light
      display-line-numbers-type 'relative)

(when (member "JetBrainsMono Nerd Font" (font-family-list))
  (setq doom-font (font-spec :family "JetBrainsMono Nerd Font" :size 14)
        doom-variable-pitch-font (font-spec :family "JetBrainsMono Nerd Font" :size 14)))

(setq confirm-kill-emacs nil
      completion-styles '(orderless basic)
      completion-category-defaults nil
      completion-category-overrides '((file (styles partial-completion))))

(setq tab-always-indent 'complete)
(setq auto-save-default t
      make-backup-files t
      create-lockfiles nil
      backup-by-copying t
      delete-old-versions t
      kept-new-versions 10
      kept-old-versions 3
      version-control t
      auto-save-timeout 20
      auto-save-interval 200)

(setq backup-directory-alist `(("." . ,(expand-file-name "backups/" doom-cache-dir)))
      auto-save-file-name-transforms `((".*" ,(expand-file-name "autosave/" doom-cache-dir) t)))

(recentf-mode 1)
(savehist-mode 1)
(save-place-mode 1)

(use-package! vertico
  :init
  (vertico-mode)
  :config
  (setq vertico-count 14
        vertico-cycle t
        vertico-resize t)
  (map! :map vertico-map
        "C-j" #'vertico-next
        "C-k" #'vertico-previous
        "C-l" #'vertico-exit
        "C-h" #'vertico-directory-up)
  (setq completion-in-region-function
        (if vertico-mode
            #'consult-completion-in-region
          completion-in-region-function))
  (after! vertico-directory
    (add-hook 'rfn-eshadow-update-overlay-hook #'vertico-directory-tidy)))

(defun kc/project-root ()
  (or (when-let ((project (project-current nil)))
        (project-root project))
      default-directory))

(defun kc/project-workflow-file ()
  (expand-file-name "agent-workflow.el" (kc/project-root)))

(defun kc/project-workflow-data ()
  (let ((file (kc/project-workflow-file)))
    (when (file-exists-p file)
      (condition-case err
          (with-temp-buffer
            (let ((read-eval nil))
              (insert-file-contents file)
              (goto-char (point-min))
              (let ((data (read (current-buffer))))
                (unless (listp data)
                  (user-error "Workflow file must contain an alist"))
                data)))
        (error
         (user-error "Failed to read %s: %s" file (error-message-string err)))))))

(defun kc/project-workflow-value (section key)
  (when-let ((section-data (alist-get section (kc/project-workflow-data))))
    (alist-get key section-data)))

(defun kc/project-command-default (key &optional fallback)
  (or (kc/project-workflow-value 'commands key) fallback))

(defun kc/project-agent-default (key &optional fallback)
  (or (kc/project-workflow-value 'agents key) fallback))

(defun kc/project-command-or-prompt (key prompt)
  (or (kc/project-command-default key)
      (read-shell-command prompt)))

(defun kc/project-fd ()
  (interactive)
  (let ((default-directory (kc/project-root))
        (consult-fd-args "fd --color=never --full-path --hidden --exclude .git ARG OPTS"))
    (consult-fd)))

(defun kc/project-git-grep ()
  (interactive)
  (let ((default-directory (kc/project-root)))
    (consult-git-grep)))

(setq org-directory (expand-file-name "~/org/")
      org-default-notes-file (expand-file-name "inbox.org" org-directory))

(defun kc/project-name ()
  (let* ((root (directory-file-name (kc/project-root)))
         (name (file-name-nondirectory root)))
    (if (string-empty-p name) "scratch" name)))

(defun kc/project-notes-file ()
  (expand-file-name (format "projects/%s.org" (kc/project-name)) org-directory))

(defun kc/ensure-project-notes-file ()
  (let ((file (kc/project-notes-file)))
    (make-directory (file-name-directory file) t)
    (unless (file-exists-p file)
      (with-temp-file file
        (insert (format "#+title: %s notes\n\n* Tasks\n\n* Findings\n\n* Scratch\n" (kc/project-name)))))
    file))

(defun kc/open-project-notes ()
  (interactive)
  (find-file (kc/ensure-project-notes-file)))

(defun kc/project-vterm (&optional name command)
  (interactive)
  (let ((default-directory (kc/project-root)))
    (vterm (format "*vterm: %s*" (or name (kc/project-name))))
    (when command
      (vterm-send-string command)
      (vterm-send-return))))

(defun kc/project-terminal ()
  (interactive)
  (kc/project-vterm))

(defun kc/project-codex ()
  (interactive)
  (kc/project-vterm (format "%s codex" (kc/project-name))
                    (kc/project-agent-default 'codex "codex")))

(defun kc/project-claude ()
  (interactive)
  (kc/project-vterm (format "%s claude" (kc/project-name))
                    (kc/project-agent-default 'claude "claude")))

(defun kc/project-test ()
  (interactive)
  (kc/project-vterm (format "%s test" (kc/project-name))
                    (kc/project-command-or-prompt 'test "Test command: ")))

(defun kc/project-build ()
  (interactive)
  (kc/project-vterm (format "%s build" (kc/project-name))
                    (kc/project-command-or-prompt 'build "Build command: ")))

(defun kc/project-run ()
  (interactive)
  (kc/project-vterm (format "%s run" (kc/project-name))
                    (kc/project-command-or-prompt 'run "Run command: ")))

(defun kc/project-lint ()
  (interactive)
  (kc/project-vterm (format "%s lint" (kc/project-name))
                    (kc/project-command-or-prompt 'lint "Lint command: ")))

(defun kc/project-git ()
  (interactive)
  (kc/project-vterm (format "%s git" (kc/project-name)) "git status"))

(defun kc/project-gh-copilot ()
  (interactive)
  (kc/project-vterm (format "%s gh copilot" (kc/project-name))
                    (kc/project-agent-default 'gh-copilot "gh copilot")))

(defun kc/open-file-reference-at-point ()
  (interactive)
  (let* ((raw (or (thing-at-point 'filename t)
                  (thing-at-point 'symbol t)
                  ""))
         (trimmed (string-trim raw))
         (pattern "\\`\\(.+?\\)\\(?::\\([0-9]+\\)\\)\\(?::\\([0-9]+\\)\\)?\\'"))
    (unless (and (not (string-empty-p trimmed))
                 (string-match pattern trimmed))
      (user-error "No file reference at point"))
    (let* ((path (match-string 1 trimmed))
           (line (match-string 2 trimmed))
           (column (match-string 3 trimmed))
           (project-path (expand-file-name path (kc/project-root)))
           (full-path (if (file-exists-p project-path)
                          project-path
                        (expand-file-name path default-directory))))
      (unless (file-exists-p full-path)
        (user-error "File not found: %s" path))
      (find-file full-path)
      (when line
        (goto-char (point-min))
        (forward-line (1- (string-to-number line))))
      (when column
        (move-to-column (1- (string-to-number column)))))))

(defun kc/buffer-relative-file-name ()
  (if-let ((file (buffer-file-name)))
      (file-relative-name file (kc/project-root))
    (user-error "Current buffer is not visiting a file")))

(defun kc/copy-file-path ()
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file
      (user-error "Current buffer is not visiting a file"))
    (kill-new file)
    (message "Copied file path: %s" file)))

(defun kc/copy-relative-file-path ()
  (interactive)
  (let ((file (kc/buffer-relative-file-name)))
    (kill-new file)
    (message "Copied relative path: %s" file)))

(defun kc/copy-file-line-reference ()
  (interactive)
  (let ((ref (format "%s:%d"
                     (kc/buffer-relative-file-name)
                     (line-number-at-pos))))
    (kill-new ref)
    (message "Copied file reference: %s" ref)))

(defun kc/current-symbol-name ()
  (when-let ((symbol (symbol-at-point)))
    (symbol-name symbol)))

(defun kc/current-context-reference ()
  (let ((file (when (buffer-file-name)
                (kc/buffer-relative-file-name)))
        (line (line-number-at-pos))
        (symbol (kc/current-symbol-name)))
    (string-join (delq nil (list file
                                 (when symbol (format "symbol=%s" symbol))
                                 (format "line=%d" line)))
                 " | ")))

(defun kc/capture-code-context ()
  (interactive)
  (kc/ensure-project-notes-file)
  (let ((org-capture-entry
         `("x" "Code context" entry
           (file+headline #'kc/project-notes-file "Findings")
           ,(format "* %s\nEntered: %%U\n%%?\n"
                    (kc/current-context-reference))
           :empty-lines 1)))
    (org-capture nil "x")))

(after! org
  (setq org-capture-templates
        '(("t" "Project TODO" entry
           (file+headline #'kc/project-notes-file "Tasks")
           "* TODO %?\nEntered: %U\n"
           :empty-lines 1)
          ("f" "Project finding" entry
           (file+headline #'kc/project-notes-file "Findings")
           "* %?\nEntered: %U\n"
           :empty-lines 1)
          ("s" "Project scratch" entry
           (file+headline #'kc/project-notes-file "Scratch")
           "* %?\nEntered: %U\n"
           :empty-lines 1)
          ("b" "Bug report" entry
           (file+headline #'kc/project-notes-file "Bug Reports")
           "* %?\nEntered: %U\n** Summary\n** Reproduction\n** Expected\n** Actual\n** Notes\n"
           :empty-lines 1)
          ("r" "Review note" entry
           (file+headline #'kc/project-notes-file "Review Notes")
           "* %?\nEntered: %U\n** Finding\n** Impact\n** Suggested change\n"
           :empty-lines 1)
          ("p" "Implementation plan" entry
           (file+headline #'kc/project-notes-file "Plans")
           "* %?\nEntered: %U\n** Goal\n** Constraints\n** Steps\n** Risks\n"
           :empty-lines 1)
          ("d" "Prompt draft" entry
           (file+headline #'kc/project-notes-file "Prompt Drafts")
           "* %?\nEntered: %U\n** Context\n** Ask\n** Constraints\n** Success criteria\n"
           :empty-lines 1)))
  (map! :leader
        :desc "Open project notes" "n p" #'kc/open-project-notes
        :desc "Capture project TODO" "n t" (cmd! (kc/ensure-project-notes-file) (org-capture nil "t"))
        :desc "Capture project finding" "n f" (cmd! (kc/ensure-project-notes-file) (org-capture nil "f"))
        :desc "Capture project scratch" "n s" (cmd! (kc/ensure-project-notes-file) (org-capture nil "s"))
        :desc "Capture bug report" "n b" (cmd! (kc/ensure-project-notes-file) (org-capture nil "b"))
        :desc "Capture review note" "n r" (cmd! (kc/ensure-project-notes-file) (org-capture nil "r"))
        :desc "Capture implementation plan" "n i" (cmd! (kc/ensure-project-notes-file) (org-capture nil "p"))
        :desc "Capture prompt draft" "n d" (cmd! (kc/ensure-project-notes-file) (org-capture nil "d"))
        :desc "Capture code context" "n x" #'kc/capture-code-context))

(after! vterm
  (setq vterm-shell (or (executable-find "zsh") shell-file-name)
        vterm-max-scrollback 10000)
  (map! :leader
        :desc "Open project terminal" "o t" #'kc/project-terminal
        :desc "Open project claude terminal" "o a" #'kc/project-claude
        :desc "Open project codex terminal" "o c" #'kc/project-codex
        :desc "Open project test terminal" "o T" #'kc/project-test
        :desc "Open project build terminal" "o b" #'kc/project-build
        :desc "Open project run terminal" "o R" #'kc/project-run
        :desc "Open project lint terminal" "o L" #'kc/project-lint
        :desc "Open project git terminal" "o g" #'kc/project-git
        :desc "Open project gh copilot terminal" "o C" #'kc/project-gh-copilot)
  (map! :map vterm-mode-map
        "C-c C-o" #'kc/open-file-reference-at-point))

(map! :leader
      :desc "Open file reference at point" "o ." #'kc/open-file-reference-at-point
      :desc "Copy file path" "c p" #'kc/copy-file-path
      :desc "Copy relative file path" "c r" #'kc/copy-relative-file-path
      :desc "Copy file line reference" "c l" #'kc/copy-file-line-reference)

(after! eglot
  (setq eglot-autoshutdown t
        eglot-sync-connect 1
        eglot-send-changes-idle-time 0.5)
  (map! :map eglot-mode-map
        :localleader
        "r" #'eglot-rename
        "a" #'eglot-code-actions
        "f" #'eglot-format
        "q" #'flymake-show-buffer-diagnostics))

(when (fboundp 'treesit-available-p)
  (setq treesit-font-lock-level 4))

(after! apheleia
  (setf (alist-get 'sh-mode apheleia-mode-alist) 'shfmt)
  (setf (alist-get 'markdown-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'gfm-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'yaml-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'yaml-ts-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'json-mode apheleia-mode-alist) 'prettier)
  (setf (alist-get 'json-ts-mode apheleia-mode-alist) 'prettier)
  (add-hook 'sh-mode-hook #'apheleia-mode)
  (add-hook 'markdown-mode-hook #'apheleia-mode)
  (add-hook 'gfm-mode-hook #'apheleia-mode)
  (add-hook 'yaml-mode-hook #'apheleia-mode)
  (add-hook 'yaml-ts-mode-hook #'apheleia-mode)
  (add-hook 'json-mode-hook #'apheleia-mode)
  (add-hook 'json-ts-mode-hook #'apheleia-mode))

(use-package! diff-hl
  :hook ((find-file . diff-hl-mode)
         (vc-dir-mode . diff-hl-dir-mode)
         (dired-mode . diff-hl-dired-mode))
  :config
  (diff-hl-flydiff-mode 1)
  (map! :leader
        :desc "Next hunk" "g n" #'diff-hl-next-hunk
        :desc "Previous hunk" "g p" #'diff-hl-previous-hunk
        :desc "Revert hunk" "g r" #'diff-hl-revert-hunk
        :desc "Stage hunk" "g s" #'diff-hl-stage-current-hunk
        :desc "Blame line" "g b" #'diff-hl-show-hunk
        :desc "Magit status" "g g" #'magit-status))

(after! magit
  (setq magit-save-repository-buffers 'dontask)
  (add-hook 'magit-pre-refresh-hook #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))

(use-package! flymake-shellcheck
  :hook (sh-mode . flymake-shellcheck-load))

(use-package! flymake-collection
  :hook ((markdown-mode . flymake-collection-markdownlint-cli2-setup)
         (gfm-mode . flymake-collection-markdownlint-cli2-setup)
         (yaml-mode . flymake-collection-yamllint-setup)
         (yaml-ts-mode . flymake-collection-yamllint-setup)))

(use-package! consult
  :bind (("C-s" . consult-line)
         ("C-x b" . consult-buffer)
         ("C-x C-r" . consult-recent-file)
         ("M-g g" . consult-goto-line)
         ("M-y" . consult-yank-pop)
         :map doom-leader-map
         ("b b" . consult-buffer)
         ("f f" . find-file)
         ("f d" . kc/project-fd)
         ("f r" . consult-recent-file)
         ("s G" . kc/project-git-grep)
         ("s g" . consult-ripgrep)
         ("s l" . consult-line)
         ("s i" . consult-imenu)
         ("s b" . consult-buffer)
         ("p f" . kc/project-fd)
         ("p g" . kc/project-git-grep)
         ("p s" . consult-ripgrep)
         ("p b" . consult-project-buffer)))

(use-package! orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))
