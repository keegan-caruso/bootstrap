;;; config/rust.el -*- lexical-binding: t; -*-

(defun kc/rust-language-server-command ()
  (cond
   ((executable-find "ra-multiplex")
    '("ra-multiplex"))
   ((executable-find "rust-analyzer")
    '("rust-analyzer"))))

(defun kc/project-cargo-build ()
  (interactive)
  (kc/project-vterm (format "%s cargo build" (kc/project-name)) "cargo build"))

(defun kc/project-cargo-check ()
  (interactive)
  (kc/project-vterm (format "%s cargo check" (kc/project-name)) "cargo check"))

(defun kc/project-cargo-clippy ()
  (interactive)
  (kc/project-vterm (format "%s cargo clippy" (kc/project-name)) "cargo clippy"))

(defun kc/project-cargo-test ()
  (interactive)
  (kc/project-vterm (format "%s cargo test" (kc/project-name)) "cargo test"))

(defun kc/project-cargo-nextest ()
  (interactive)
  (kc/project-vterm (format "%s cargo nextest" (kc/project-name)) "cargo nextest run"))

(defun kc/project-cargo-run ()
  (interactive)
  (kc/project-vterm (format "%s cargo run" (kc/project-name)) "cargo run"))

(defun kc/project-cargo-fmt ()
  (interactive)
  (kc/project-vterm (format "%s cargo fmt" (kc/project-name)) "cargo fmt"))

(after! vterm
  (map! :leader
        (:prefix ("o r" . "Rust")
         :desc "cargo build" "b" #'kc/project-cargo-build
         :desc "cargo check" "c" #'kc/project-cargo-check
         :desc "cargo clippy" "l" #'kc/project-cargo-clippy
         :desc "cargo test" "t" #'kc/project-cargo-test
         :desc "cargo nextest" "n" #'kc/project-cargo-nextest
         :desc "cargo run" "r" #'kc/project-cargo-run
         :desc "cargo fmt" "f" #'kc/project-cargo-fmt)))

(after! eglot
  (when-let ((rust-server (kc/rust-language-server-command)))
    (dolist (mode '(rust-mode rustic-mode rust-ts-mode))
      (add-to-list 'eglot-server-programs `(,mode . ,rust-server)))))

(after! apheleia
  (setf (alist-get 'rust-mode apheleia-mode-alist) 'rustfmt)
  (setf (alist-get 'rustic-mode apheleia-mode-alist) 'rustfmt)
  (setf (alist-get 'rust-ts-mode apheleia-mode-alist) 'rustfmt)
  (add-hook 'rust-mode-hook #'apheleia-mode)
  (add-hook 'rustic-mode-hook #'apheleia-mode)
  (add-hook 'rust-ts-mode-hook #'apheleia-mode))
