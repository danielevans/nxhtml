;;; web-vcs.el --- Download file trees from VCS web pages
;;
;; Author: Lennart Borgman (lennart O borgman A gmail O com)
;; Created: 2009-11-26 Thu
(defconst web-vcs:version "0.61") ;; Version:
;; Last-Updated: 2009-12-11 Fri
;; URL:
;; Keywords:
;; Compatibility:
;;
;; Features that might be required by this library:
;;
;;   None
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; Update file trees within Emacs from VCS systems using information
;; on their web pages.
;;
;; See the command `nxhtml-download'.
;;
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Change log:
;;
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

(eval-when-compile (require 'cl)) ;; assert

(defgroup web-vcs nil
  "Customization group for web-vcs."
  :group 'programming
  :group 'development)

(defcustom web-vcs-links-regexp
  `(
    (lp ;; Id
     ;; Comment:
     "http://www.launchpad.com/ uses this 2009-11-29 with Loggerhead 1.10 (generic?)"
     ;; Files URL regexp:
     ,(rx "href=\""
          (submatch (regexp ".*/download/[^\"]*"))
          "\"")
     ;; Dirs URL regexp:
     ,(rx "href=\""
          (submatch (regexp ".*%3A/[^\"]*/"))
          "\"")
     ;; File name URL part regexp:
     "\\([^\/]*\\)$"
     ;; Page revision regexp:
     ,(rx "for revision"
          (+ whitespace)
          "<span>"
          (submatch (+ digit))
          "</span>")
     ;; Release revision regexp:
     ,(rx "/"
          (submatch (+ digit))
          "\"" (+ (not (any ">"))) ">"
          (optional "Release ")
          (+ digit) "." (+ digit) "<")
     )
    )
  "Regexp patterns for matching links on a VCS web page.
The patterns are grouped by VCS web system type.

*Note: It is always sub match 1 from these patterns that are
       used."
  :type '(repeat
          (list
           (symbol :tag "VCS web system type specifier")
           (string :tag "Description")
           (regexp :tag "Files URL regexp")
           (regexp :tag "Dirs URL regexp")
           (regexp :tag "File name URL part regexp")
           (regexp :tag "Page revision regexp")
           (regexp :tag "Release revision regexp")
           ))
  :group 'web-vcs)

(defface web-vcs-gold
  '((((background dark)) (:background "gold" :foreground "black"))
    (t (:background "gold")))
  "Face for hi-lock mode."
  :group 'web-vcs)

(defface web-vcs-red
  '((((background dark)) (:background "red" :foreground "black"))
    (t (:background "red")))
  "Face for hi-lock mode."
  :group 'web-vcs)



;; (web-vcs-get-files-on-page 'lp "http://bazaar.launchpad.net/%7Enxhtml/nxhtml/main/files/head%3A/" t "c:/test/temp13/" t)
;; (web-vcs-get-files-on-page 'lp "http://bazaar.launchpad.net/%7Enxhtml/nxhtml/main/files/head%3A/util/" t "temp" t)
;; (web-vcs-get-files-on-page 'lp "http://bazaar.launchpad.net/%7Enxhtml/nxhtml/main/files/head%3A/alts/" t "temp" t)


;;;###autoload
(defun web-vcs-get-files-from-root (web-vcs url dl-dir)
  "Download a file tree from VCS system using the web interface.
Use WEB-VCS entry in variable `web-vcs-links-regexp' to download
files via http from URL to directory DL-DIR.

Show URL first and offer to visit the page.  That page will give
you information about version control system \(VCS) system used
etc."
  (unless (web-vcs-contains-moved-files dl-dir)
    (when (if (not (y-or-n-p (concat "Download files from \"" url "\".\n"
                                     "You can see on that page which files will be downloaded.\n\n"
                                     "Visit that page before downloading? ")))
              t
            (browse-url url)
            (if (y-or-n-p "Start downloading? ")
                t
              (message "Aborted")
              nil))
      (message "")
      (web-vcs-get-files-on-page web-vcs url t (file-name-as-directory dl-dir) nil))))

(defun web-vcs-get-missing-matching-files (web-vcs url dl-dir files-regexp)
  "Download missing files from VCS system using the web interface.
Use WEB-VCS entry in variable `web-vcs-links-regexp' to download
files via http from URL to directory DL-DIR.

Before downloading offer to visit the page from which the
downloading will be made.
"
  (let ((vcs-rec (or (assq web-vcs web-vcs-links-regexp)
                     (error "Does not know web-cvs %S" web-vcs))))
    (web-vcs-get-files-on-page-1 vcs-rec url dl-dir "" files-regexp 0 nil nil)
    ))

(defun web-vcs-get-files-on-page (web-vcs url recursive dl-dir test)
  "Download files listed by WEB-VCS on web page URL.
WEB-VCS is a specifier in `web-vcs-links-regexp'.

If RECURSIVE go into sub folders on the web page and download
files from them too.

Place the files under DL-DIR.

Before downloading check if the downloaded revision already is
the same as the one on the web page.  This is stored in the file
web-vcs-revision.txt.  After downloading update this file.

If TEST is non-nil then do not download, just list the files."
  (require 'hi-lock) ;; For faces
  (unless (string= dl-dir (file-name-as-directory (expand-file-name dl-dir)))
    (error "Download dir dl-dir=%S must be a full directory path" dl-dir))
  (catch 'command-level
    (when (web-vcs-contains-moved-files dl-dir)
      (throw 'command-level nil))
    (let ((vcs-rec (or (assq web-vcs web-vcs-links-regexp)
                       (error "Does not know web-cvs %S" web-vcs)))
          (start-time (current-time)))
      (unless (file-directory-p dl-dir)
        (if (yes-or-no-p (format "Directory %S does not exist, create it? " (expand-file-name dl-dir)))
            (mkdir dl-dir t)
          (message "Can't download then")
          (throw 'command-level nil)))
      (let ((old-win (selected-window)))
        (unless (eq (get-buffer "*Messages*") (window-buffer old-win))
          (switch-to-buffer-other-window "*Messages*"))
        (goto-char (point-max))
        (insert "\n")
        (insert (propertize (format "\n\nWeb-Vcs Download: %S\n" url) 'face 'web-vcs-gold))
        (insert "\n")
        (redisplay t)
        (set-window-point (selected-window) (point-max))
        (select-window old-win))
      (let* ((rev-file (expand-file-name "web-vcs-revision.txt" dl-dir))
             (rev-buf (find-file-noselect rev-file))
             ;; Fix-me: Per web vcs speficier.
             (old-rev-range (with-current-buffer rev-buf
                              (widen)
                              (goto-char (point-min))
                              (when (re-search-forward (format "%s:\\(.*\\)\n" web-vcs) nil t)
                                ;;(buffer-substring-no-properties (point-min) (line-end-position))
                                ;;(match-string 1)
                                (cons (match-beginning 1) (match-end 1))
                                )))
             (old-revision (when old-rev-range
                             (with-current-buffer rev-buf
                               (buffer-substring-no-properties (car old-rev-range)
                                                               (cdr old-rev-range)))))
             (dl-revision (web-vcs-get-revision-on-page vcs-rec url))
             ret
             moved)
        (when (and old-revision (string= old-revision dl-revision))
          (when (y-or-n-p (format "You already have revision %s.  Quit? " dl-revision))
            (message "Aborted")
            (kill-buffer rev-buf)
            (throw 'command-level nil)))
        ;; We do not have a revision number once we start download.
        (with-current-buffer rev-buf
          (when old-rev-range
            (delete-region (car old-rev-range) (cdr old-rev-range))
            (basic-save-buffer)))
        (setq ret (web-vcs-get-files-on-page-1
                   vcs-rec url
                   dl-dir
                   ""
                   nil
                   (if recursive 0 nil)
                   dl-revision test))
        (setq moved       (nth 1 ret))
        ;; Now we have a revision number again.
        (with-current-buffer rev-buf
          (when (= 0 (buffer-size))
            (insert "WEB VCS Revisions\n\n"))
          (goto-char (point-max))
          (unless (eolp) (insert "\n"))
          (insert (format "%s:%s\n" web-vcs dl-revision))
          (basic-save-buffer)
          (kill-buffer))
        (message "-----------------")
        (web-vcs-message-with-face 'web-vcs-gold "Web-Vcs Download Ready: %S" url)
        (web-vcs-message-with-face 'web-vcs-gold "  Time elapsed: %S"
                                   (web-vcs-nice-elapsed start-time (current-time)))
        (when (> moved 0)
          (web-vcs-message-with-face 'hi-yellow
                                     "  %i files updated (old versions renamed to *.moved)"
                                     moved))))))


(defun web-vcs-get-files-on-page-1 (vcs-rec url dl-root dl-relative file-mask recursive dl-revision test)
  "Download files listed by VCS-REC on web page URL.
VCS-REC should be an entry like the entries in the list
`web-vcs-links-regexp'.

If FILE-MASK is non nil then it should be a file path.  Only
files matching this path will be downloaded then.  Each part of
the path may be a regular expresion \(not containing /).

If RECURSIVE go into sub folders on the web page and download
files from them too.

Place the files under DL-DIR.

The revision on the page URL should match DL-REVISION if this is non-nil.

If TEST is non-nil then do not download, just list the files."
  (message "web-vcs-get-files-on-page-1 %s %s %s %s %s %s %s %s" vcs-rec url dl-root dl-relative file-mask recursive dl-revision test)
  (let* ((files-href-regexp  (nth 2 vcs-rec))
         (dirs-href-regexp   (nth 3 vcs-rec))
         (file-name-regexp   (nth 4 vcs-rec))
         (revision-regexp    (nth 5 vcs-rec))
         (dl-dir (file-name-as-directory (expand-file-name dl-relative dl-root)))
         (lst-dl-relative (web-vcs-file-name-as-list dl-relative))
         (lst-file-mask   (web-vcs-file-name-as-list file-mask))
         (url-buf (url-retrieve-synchronously url))
         this-page-revision
         files
         suburls
         (moved 0)
         (temp-file (expand-file-name "web-vcs-temp.tmp" dl-dir)))
    (with-current-buffer url-buf
      (goto-char (point-min))
      (unless (looking-at "HTTP/.* 200 OK\n")
        (switch-to-buffer url-buf)
        (error "Download error: %S" url))
      (unless (file-directory-p dl-dir)
        (make-directory dl-dir t))
      ;; Get revision number
      (setq this-page-revision (web-vcs-get-revision-from-url-buf vcs-rec url-buf url))
      (when dl-revision
        (unless (string= dl-revision this-page-revision)
          (web-vcs-message-with-face 'web-vcs-red "Revision on %S is %S, but should be %S"
                                     url this-page-revision dl-revision)
          (throw 'command-level nil)))
      ;; Find files
      (goto-char (point-min))
      (while (re-search-forward files-href-regexp nil t)
        (add-to-list 'files (match-string 1)))
      ;; Find subdirs
      (when recursive
        (goto-char (point-min))
        (while (re-search-forward dirs-href-regexp nil t)
          (let ((suburl (match-string 1))
                (lenurl (length url)))
            (when (and (> (length suburl) lenurl)
                       (string= (substring suburl 0 lenurl) url))
              (add-to-list 'suburls suburl)))))
      (kill-buffer))
    ;; Download files
    (dolist (file (reverse files))
      (let* ((file-url file)
             (file-name (progn
                          (when (string-match file-name-regexp file-url)
                            (match-string 1 file-url))))
             (lst-file-name (web-vcs-file-name-as-list file-name))
             (file-dl-name (expand-file-name file-name dl-dir))
             (file-rel-name (file-relative-name file-dl-name dl-root))
             temp-buf
             )
        (when (or (not file-mask)
                  (web-vcs-match-folderwise file-mask file-rel-name))
          (if test
              (progn
                (message "TEST file-url=%S" file-url)
                (message "TEST file-name=%S" file-name)
                (message "TEST file-dl-name=%S" file-dl-name)
                )
            (while (setq temp-buf (find-buffer-visiting temp-file))
              (set-buffer-modified-p nil)
              (kill-buffer temp-buf))
            ;; Use url-copy-file, this takes care of coding system.
            (url-copy-file file-url temp-file t t) ;; overwrite, keep time
            (let* (;; (new-buf (find-file-noselect temp-file))
                   ;; (new-src (with-current-buffer new-buf
                   ;;            (save-restriction
                   ;;              (widen)
                   ;;              (buffer-substring-no-properties (point-min) (point-max)))))
                   (time-after-url-copy (current-time))
                   (old-exists (file-exists-p file-dl-name))
                   (old-buf-open (find-buffer-visiting file-dl-name))
                   ;; (old-buf (or old-buf-open
                   ;;              (when old-exists
                   ;;                (let ((auto-mode-alist nil))
                   ;;                  (find-file-noselect file-dl-name)))))
                   ;; old-src
                   )
              (when old-buf-open
                (when (buffer-modified-p old-buf-open)
                  (save-excursion
                    (switch-to-buffer old-buf-open)
                    (when (y-or-n-p (format "Buffer %S is modified, save to make a backup? "
                                            file-dl-name))
                      (save-buffer)))))
              ;;(if (and old-src (string= new-src old-src))
              (if (and old-exists
                       (web-vcs-equal-files file-dl-name temp-file))
                  (web-vcs-message-with-face 'hi-green "File %S was ok" file-dl-name)
                (when old-exists
                  (let ((backup (concat file-dl-name ".moved")))
                    (when (file-exists-p backup)
                      (delete-file backup))
                    (rename-file file-dl-name backup)))
                (rename-file temp-file file-dl-name)
                (if old-exists
                    (web-vcs-message-with-face 'hi-yellow "Updated %S" file-dl-name)
                  (web-vcs-message-with-face 'hi-green "Downloaded %S" file-dl-name))
                (when old-buf-open
                  (with-current-buffer old-buf-open
                    (set-buffer-modified-p nil)
                    (revert-buffer))))
              (let* ((msg-win (get-buffer-window "*Messages*")))
                (with-current-buffer "*Messages*"
                  (set-window-point msg-win (point-max))))
              (redisplay t)
              ;; This is both for user and remote server load.  Do not remove this.
              (sit-for (- 1.0 (float-time (time-subtract (current-time) time-after-url-copy))))
              ;; (unless old-buf-open
              ;;   (when old-buf
              ;;     (kill-buffer old-buf)))
              )))
        (redisplay t)))
    ;; Download subdirs
    (when suburls
      (dolist (suburl (reverse suburls))
        (let* ((dl-sub-dir (substring suburl (length url)))
               (full-dl-sub-dir (file-name-as-directory
                                 (expand-file-name dl-sub-dir dl-dir)))
               (rel-dl-sub-dir (file-relative-name full-dl-sub-dir dl-root)))
          (when (or (not file-mask)
                    (web-vcs-match-folderwise file-mask rel-dl-sub-dir))
            (unless (web-vcs-contains-file dl-dir full-dl-sub-dir)
              (error "Subdir %S not in %S" dl-sub-dir dl-dir))
            (let* ((ret (web-vcs-get-files-on-page-1 vcs-rec
                                                     suburl
                                                     dl-root
                                                     rel-dl-sub-dir
                                                     file-mask
                                                     (1+ recursive)
                                                     this-page-revision
                                                     test)))
              (setq moved (+ moved (nth 1 ret)))
              )))))
    (list this-page-revision moved)
    ))


(defun web-vcs-get-revision-on-page (vcs-rec url)
  "Get revision number using VCS-REC on page URL.
VCS-REC should be an entry like the entries in the list
`web-vcs-links-regexp'."
  ;; url-insert-file-contents
  (let ((url-buf (url-retrieve-synchronously url)))
    (web-vcs-get-revision-from-url-buf vcs-rec url-buf url)))

(defun web-vcs-get-revision-from-url-buf (vcs-rec url-buf url)
  "Get revision number using VCS-REC.
VCS-REC should be an entry in the list `web-vcs-links-regexp'.
The buffer URL-BUF should contain the content on page URL."
  (let ((revision-regexp    (nth 5 vcs-rec)))
    ;; Get revision number
    (with-current-buffer url-buf
      (goto-char (point-min))
      (if (not (re-search-forward revision-regexp nil t))
          (progn
            (web-vcs-message-with-face 'web-vcs-red "Can't find revision number on %S" url)
            (throw 'command-level nil))
        (match-string 1)))))





;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Helpers

;;(web-vcs-file-name-as-list "/a/b/c.el")
;;(web-vcs-file-name-as-list "a/b/c.el")
;;(web-vcs-file-name-as-list "c:/a/b/c.el")
;;(web-vcs-file-name-as-list ".*/a/c/")
;;(web-vcs-file-name-as-list "[^/]*/a/c/") ;; Just avoid this.
(defun web-vcs-file-name-as-list (filename)
  "Split file name FILENAME into a list with file names."
  (let ((lst-name nil)
        (head filename)
        (old-head ""))
    (while (and (not (string= old-head head))
                (> (length head) 0))
      (let* ((file-head (directory-file-name head))
             (tail (file-name-nondirectory (directory-file-name head))))
        (setq old-head head)
        (setq head (file-name-directory file-head))
        ;; For an abs path the final tail is "", use root instead:
        (when (= 0 (length tail))
          (setq tail head))
        (setq lst-name (cons tail lst-name))))
    lst-name))

;;(web-vcs-match-folderwise ".*/util/mum.el" "top/util/mum.el")
;;(web-vcs-match-folderwise ".*/util/mu.el" "top/util/mum.el")
;;(web-vcs-match-folderwise ".*/ut/mum.el" "top/util/mum.el")
;;(web-vcs-match-folderwise ".*/ut../mum.el" "top/util/mum.el")
;;(web-vcs-match-folderwise ".*/ut../mum.el" "top/util")
;;(web-vcs-match-folderwise ".*/ut../mum.el" "top")
;;(web-vcs-match-folderwise "top/ut../mum.el" "top")
;;(web-vcs-match-folderwise "util/web-autoload-2.el" "util/nxhtml-company-mode/")
(defun web-vcs-match-folderwise (regex file)
  "Split REGEXP as a file path and match against FILE parts."
  ;;(message "folderwise %S %S" regex file)
  (let ((lst-regex (web-vcs-file-name-as-list regex))
        (lst-file  (web-vcs-file-name-as-list file)))
    (when (>= (length lst-regex) (length lst-file))
      (catch 'match
        (while lst-file
          (let ((head-file  (car lst-file))
                (head-regex (car lst-regex)))
            (unless (string-match-p (concat "^" head-regex "$") head-file)
              (throw 'match nil)))
          (setq lst-file  (cdr lst-file))
          (setq lst-regex (cdr lst-regex)))
        t))))

(defun web-vcs-contains-file (dir file)
  "Return t if DIR contain FILE."
  (assert (string= dir (file-name-as-directory (expand-file-name dir))) t)
  (assert (or (string= file (file-name-as-directory (expand-file-name file)))
              (string= file (expand-file-name file))) t)
  (let ((dir-len (length dir)))
    (assert (string= "/" (substring dir (1- dir-len))))
    (when (> (length file) dir-len)
      (string= dir (substring file 0 dir-len)))))

(defun web-vcs-nice-elapsed (start-time end-time)
  "Format elapsed time between START-TIME and END-TIME nicely.
Those times should have the same format as time returned by
`current-time'."
  (format-seconds "%h h %m m %z%s s" (float-time (time-subtract end-time start-time))))

;; (web-vcs-equal-files "web-vcs.el" "temp.tmp")
;; (web-vcs-equal-files "../.nosearch" "temp.tmp")
(defun web-vcs-equal-files (file-a file-b)
  "Return t if files FILE-A and FILE-B are equal."
  (let* ((cmd (if (eq system-type 'windows-nt)
                  (list "fc" nil nil nil
                        "/B" "/OFF"
                        (convert-standard-filename file-a)
                        (convert-standard-filename file-b))
                (list diff-command nil nil nil
                      "--binary" "-q" file-a file-b)))
         (ret (apply 'call-process cmd)))
    ;;(message "ret=%s, cmd=%S" ret cmd) (sit-for 2)
    (cond
     ((= 1 ret)
      nil)
     ((= 0 ret)
      t)
     (t
      (error "%S returned %d" cmd ret)))))

;; (web-vcs-message-with-face 'secondary-selection "I am saying: %s and %s" "Hi" "Farwell!")
(defun web-vcs-message-with-face (face format-string &rest args)
  "Display a colored message at the bottom of the string.
FACE is the face to use for the message.
FORMAT-STRING and ARGS are the same as for `message'.

Also put FACE on the message in *Messages* buffer."
  (with-current-buffer "*Messages*"
    (save-restriction
      (widen)
      (let* ((start (let ((here (point)))
                      (goto-char (point-max))
                      (prog1
                          (copy-marker
                           (if (bolp) (point-max)
                             (1+ (point-max))))
                        (goto-char here))))
             (msg-with-face (propertize (apply 'format format-string args)
                                        'face face)))
        ;; This is for the echo area:
        (message "%s" msg-with-face)
        ;; This is for the buffer:
        (when (< 0 (length msg-with-face))
          (goto-char (1- (point-max)))
          ;;(backward-char)
          ;;(unless (eolp) (goto-char (line-end-position)))
          (put-text-property start (point)
                             'face face))))))

;; (web-vcs-num-moved "c:/emacs/p/091105/EmacsW32/nxhtml/")
(defun web-vcs-num-moved (root)
  "Return nof files matching *.moved inside directory ROOT."
  (let* ((file-regexp ".*\\.moved$")
         (files (directory-files root t file-regexp))
         (subdirs (directory-files root t)))
    (dolist (subdir subdirs)
      (when (and (file-directory-p subdir)
                 (not (or (string= "/." (substring subdir -2))
                          (string= "/.." (substring subdir -3)))))
        (setq files (append files (web-vcs-rdir-get-files subdir file-regexp) nil))))
    (length files)))

;; Copy of rdir-get-files in ourcomment-util.el
(defun web-vcs-rdir-get-files (root file-regexp)
  (let ((files (directory-files root t file-regexp))
        (subdirs (directory-files root t)))
    (dolist (subdir subdirs)
      (when (and (file-directory-p subdir)
                 (not (or (string= "/." (substring subdir -2))
                          (string= "/.." (substring subdir -3)))))
        (setq files (append files (web-vcs-rdir-get-files subdir file-regexp) nil))))
    files))

(defun web-vcs-contains-moved-files (dl-dir)
  "Return t if there are *.moved files in DL-DIR."
  (let ((num-moved (web-vcs-num-moved dl-dir)))
    (when (> num-moved 0)
      (web-vcs-message-with-face 'font-lock-warning-face
                                 (concat "There are %d *.moved files (probably from prev download)\n"
                                         "in %S.\nPlease delete them first.")
                                 num-moved dl-dir)
      t)))





;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Specific

(defun web-vcs-set&save-option (symbol value)
  (customize-set-variable symbol value)
  (customize-set-value symbol value)
  (customize-mark-to-save symbol)
  (custom-save-all)
  (message "web-vcs: Saved option %s with value %s" symbol value))

(defvar web-vcs-nxhtml-base-url "http://bazaar.launchpad.net/%7Enxhtml/nxhtml/main/")

;; Fix-me: make gen for 'lp etc
(defun nxhtml-download-root-url (revision)
  (let* ((base-url web-vcs-nxhtml-base-url)
         (files-url (concat base-url "files/"))
         (rev-part (if revision (number-to-string revision) "head%3A/")))
    (concat files-url rev-part)))

(defun nxhtml-setup-auto-download ()
  "Set up to autoload nXhtml files from the web.
This will download some initial files and then download the rest
when you need them."
  (interactive)
  (when (condition-case nil
            (custom-file)
          (error nil))
    (web-vcs-set&save-option 'nxhtml-autoload-web t))
  (let* ((dl-dir (read-directory-name
                  "Download nXhtml to directory for auto-downloaded files: "))
         ;; Need some files:
         (web-vcs-el-src (or load-file-name
                             ;;(when (boundp 'bytecomp-filename) bytecomp-filename)
                             buffer-file-name))
         (web-vcs-el (expand-file-name (file-name-nondirectory web-vcs-el-src)
                                       dl-dir))
         (vcs 'lp)
         (base-url (nxhtml-download-root-url nil))
         )
    (unless (file-exists-p dl-dir)
      (if (y-or-n-p (format "Directory %S does not exist, create it? " dl-dir))
          (make-directory dl-dir t)
        (error "Aborted by user")))
    (unless (file-exists-p web-vcs-el)
      (copy-file web-vcs-el-src web-vcs-el))
    (catch 'command-level
      (unless (file-exists-p (expand-file-name "autostart.el" dl-dir))
        (web-vcs-get-missing-matching-files vcs base-url dl-dir "autostart.el"))
      (unless (file-exists-p (expand-file-name "nxhtml-loaddefs.el" dl-dir))
        (web-vcs-get-missing-matching-files vcs base-url dl-dir "nxhtml-loaddefs.el"))
      (unless (file-exists-p (expand-file-name "nxhtml-auto-helpers.el" dl-dir))
        (web-vcs-get-missing-matching-files vcs base-url dl-dir "nxhtml-auto-helpers.el"))
      (unless (file-exists-p (expand-file-name "web-autoload.el" dl-dir))
        (web-vcs-get-missing-matching-files vcs base-url dl-dir "web-autoload.el"))
      ;;(load (expand-file-name "etc/schema/schema-path-patch"
      (unless (file-exists-p (expand-file-name "etc/schema/schema-patch-patch.el" dl-dir))
        (web-vcs-get-missing-matching-files vcs base-url dl-dir "etc/schema/schema-patch-patch.el"))
      ;;(load (expand-file-name "nxhtml/nxhtml-autoload" nxhtml-install-dir)))
      (unless (file-exists-p (expand-file-name "nxhtml/nxhtml-autoload.el" dl-dir))
        (web-vcs-get-missing-matching-files vcs base-url dl-dir "nxhtml/nxhtml-autoload.el"))
      (load-file (expand-file-name "autostart.el" dl-dir))
    )))


;;(call-interactively 'nxhtml-download)
;;;###autoload
(defun nxhtml-download ()
  "Download or update nXhtml.
If you already have nXhtml installed you can update it with this
command.  Otherwise after downloading read the instructions in
README.txt in the download directory for setting up nXhtml.
\(This requires adding only one line to your .emacs, but you may
optionally also byte compile the files from the nXhtml menu.)

To learn more about nXhtml visit its home page at URL
`http://www.emacswiki.com/NxhtmlMode/'."
  (interactive)
  (let ((msg (concat "Downloading nXhtml through Launchpad web interface will take rather long\n"
                     "time (5-15 minutes) so you may want to do it in a separate Emacs session.\n\n"
                     "Do you want to download using this Emacs session? "
                     )))
    (if (not (y-or-n-p msg))
        (message "Aborted")
      (message "")
      (let* ((has-nxhtml (and (boundp 'nxhtml-install-dir)
                              nxhtml-install-dir))
             (dl-dir (or (when (and has-nxhtml
                                    (yes-or-no-p
                                     (format "Update current nXhtml files (%s)? "
                                             nxhtml-install-dir)))
                           nxhtml-install-dir)
                         (read-directory-name "Download nXhtml to directory: ")))
             ;; Fix-me: ask for latest revision or release, maybe also
             ;; rev number? Can't do that now because of the Emacs bug
             ;; that affects `nxhtml-get-release-revision'.
             (revision nil)
             (do-byte (when (and has-nxhtml
                                 (string= dl-dir nxhtml-install-dir))
                        (y-or-n-p "Do you want to byte compile the files after downloading? "))))
        ;; http://bazaar.launchpad.net/%7Enxhtml/nxhtml/main/files/322
        ;; http://bazaar.launchpad.net/%7Enxhtml/nxhtml/main/files/head%3A/"
        (nxhtml-download-1 dl-dir revision do-byte)))))


;; Fix-me: Does not work, Emacs Bug
;; Maybe use wget? http://gnuwin32.sourceforge.net/packages/wget.htm
;; http://emacsbugs.donarmstrong.com/cgi-bin/bugreport.cgi?bug=5103
;; (nxhtml-get-release-revision)
(defun nxhtml-get-release-revision ()
  "Get revision number for last release."
  (let* ((all-rev-url "http://code.launchpad.net/%7Enxhtml/nxhtml/main")
         (url-buf (url-retrieve-synchronously all-rev-url))
         (vcs-rec (or (assq 'lp web-vcs-links-regexp)
                      (error "Does not know web-cvs 'lp")))
         (rel-ver-regexp (nth 6 vcs-rec))
         )
    (message "%S" url-buf)
    (with-current-buffer url-buf
      (when (re-search-forward rel-ver-regexp nil t)
        (match-string 1)))))

(defun nxhtml-download-1 (dl-dir revision do-byte)
  "Download nXhtml to directory DL-DIR.
If REVISION is nil download latest revision, otherwise the
specified one.

If DO-BYTE is non-nil byte compile nXhtml after download."
  (let* ((base-url web-vcs-nxhtml-base-url)
         (files-url (concat base-url "files/"))
         ;;(revs-url  (concat base-url "changes/"))
         (rev-part (if revision (number-to-string revision) "head%3A/"))
         (full-root-url (concat files-url rev-part)))
    (when (web-vcs-get-files-from-root 'lp full-root-url dl-dir)
      (when do-byte
        (sit-for 10)
        (web-vcs-message-with-face 'hi-yellow "Will start byte compilation of nXhtml in 10 seconds")
        (sit-for 10)
        (nxhtmlmaint-start-byte-compilation)))))


(provide 'web-vcs)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; web-vcs.el ends here