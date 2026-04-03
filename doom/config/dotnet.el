;;; config/dotnet.el -*- lexical-binding: t; -*-

(add-to-list 'auto-mode-alist '("\\.sln\\'" . conf-mode))
(add-to-list 'auto-mode-alist '("\\.slnx\\'" . conf-mode))
(add-to-list 'auto-mode-alist '("\\.csproj\\'" . nxml-mode))
(add-to-list 'auto-mode-alist '("\\.props\\'" . nxml-mode))
(add-to-list 'auto-mode-alist '("\\.targets\\'" . nxml-mode))
(add-to-list 'auto-mode-alist '("\\.runsettings\\'" . nxml-mode))
(add-to-list 'auto-mode-alist '("\\.nuspec\\'" . nxml-mode))

(defun kc/project-dotnet-target ()
  (let* ((root (kc/project-root))
         (solution (or (car (directory-files-recursively root "\\.slnx\\'"))
                       (car (directory-files-recursively root "\\.sln\\'"))))
         (project (car (directory-files-recursively root "\\.csproj\\'"))))
    (or solution project)))

(defun kc/project-dotnet-projects ()
  (directory-files-recursively (kc/project-root) "\\.csproj\\'"))

(defun kc/project-dotnet-project-target ()
  (let* ((projects (kc/project-dotnet-projects))
         (current-file (buffer-file-name)))
    (cond
     ((and current-file (string-suffix-p ".csproj" current-file) (file-exists-p current-file))
      current-file)
     ((null projects)
      (user-error "No .csproj file found in project"))
     ((= (length projects) 1)
      (car projects))
     (t
      (let* ((root (kc/project-root))
             (choices (mapcar (lambda (project)
                                (cons (file-relative-name project root) project))
                              projects))
             (selected (completing-read "Project: " (mapcar #'car choices) nil t)))
        (or (cdr (assoc selected choices))
            (user-error "Project selection failed")))))))

(defun kc/project-dotnet-command (subcommand)
  (if-let ((target (kc/project-dotnet-target)))
      (format "dotnet %s %s" subcommand (shell-quote-argument target))
    (format "dotnet %s" subcommand)))

(defun kc/project-dotnet-add-package ()
  (interactive)
  (let* ((project (kc/project-dotnet-project-target))
         (package (read-string "Package: "))
         (version (read-string "Version (blank for latest): "))
         (command (string-join
                   (delq nil
                         (list "dotnet add"
                               (shell-quote-argument project)
                               "package"
                               (shell-quote-argument package)
                               (unless (string-empty-p version)
                                 (format "--version %s" (shell-quote-argument version)))))
                   " ")))
    (kc/project-vterm (format "%s dotnet add package" (kc/project-name)) command)))

(defun kc/csharp-language-server-command ()
  (cond
   ((executable-find "dnx")
    '("dnx"
      "roslyn-language-server"
      "--yes"
      "--prerelease"
      "--"
      "--stdio"
      "--autoLoadProjects"))
   ((executable-find "csharp-ls")
    '("csharp-ls"))
   ((executable-find "omnisharp")
    '("omnisharp" "-lsp"))
   ((executable-find "OmniSharp")
    '("OmniSharp" "-lsp"))))

(defun kc/project-dotnet-build ()
  (interactive)
  (kc/project-vterm (format "%s dotnet build" (kc/project-name)) "dotnet build"))

(defun kc/project-dotnet-test ()
  (interactive)
  (kc/project-vterm (format "%s dotnet test" (kc/project-name)) "dotnet test"))

(defun kc/project-dotnet-run ()
  (interactive)
  (kc/project-vterm (format "%s dotnet run" (kc/project-name)) "dotnet run"))

(defun kc/project-dotnet-watch ()
  (interactive)
  (kc/project-vterm (format "%s dotnet watch" (kc/project-name)) "dotnet watch run"))

(defun kc/project-dotnet-restore ()
  (interactive)
  (kc/project-vterm (format "%s dotnet restore" (kc/project-name))
                    (kc/project-dotnet-command "restore")))

(defun kc/project-dotnet-clean ()
  (interactive)
  (kc/project-vterm (format "%s dotnet clean" (kc/project-name))
                    (kc/project-dotnet-command "clean")))

(defun kc/project-dotnet-format ()
  (interactive)
  (kc/project-vterm (format "%s dotnet format" (kc/project-name))
                    (kc/project-dotnet-command "format")))

(after! vterm
  (map! :leader
        (:prefix ("o d" . ".NET")
         :desc "dotnet add package" "a" #'kc/project-dotnet-add-package
         :desc "dotnet build" "b" #'kc/project-dotnet-build
         :desc "dotnet clean" "c" #'kc/project-dotnet-clean
         :desc "dotnet format" "f" #'kc/project-dotnet-format
         :desc "dotnet test" "t" #'kc/project-dotnet-test
         :desc "dotnet run" "r" #'kc/project-dotnet-run
         :desc "dotnet restore" "s" #'kc/project-dotnet-restore
         :desc "dotnet watch run" "w" #'kc/project-dotnet-watch)))

(after! eglot
  (when-let ((csharp-server (kc/csharp-language-server-command)))
    (dolist (mode '(csharp-mode csharp-ts-mode))
      (add-to-list 'eglot-server-programs `(,mode . ,csharp-server)))))
