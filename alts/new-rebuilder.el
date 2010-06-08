;;; re-builder.el --- building Regexps with visual feedback

;; Copyright (C) 1999, 2000, 2001, 2002, 2003, 2004,
;;   2005, 2006, 2007, 2008, 2009, 2010 Free Software Foundation, Inc.

;; Author: Detlev Zundel <dzu@gnu.org>
;; Keywords: matching, lisp, tools

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; When I have to come up with regular expressions that are more
;; complex than simple string matchers, especially if they contain sub
;; expressions, I find myself spending quite some time in the
;; `development cycle'.  `re-builder' aims to shorten this time span
;; so I can get on with the more interesting bits.

;; With it you can have immediate visual feedback about how well the
;; regexp behaves to your expectations on the intended data.

;; When called up `re-builder' attaches itself to the current buffer
;; which becomes its target buffer, where all the matching is done.
;; The active window is split so you have a view on the data while
;; authoring the RE.  If the edited expression is valid the matches in
;; the target buffer are marked automatically with colored overlays
;; (for non-color displays see below) giving you feedback over the
;; extents of the matched (sub) expressions.  The (non-)validity is
;; shown only in the modeline without throwing the errors at you.  If
;; you want to know the reason why RE Builder considers it as invalid
;; call `reb-force-update' ("\C-c\C-u") which should reveal the error.

;; The target buffer can be changed with `reb-change-target-buffer'
;; ("\C-c\C-b").  Changing the target buffer automatically removes
;; the overlays from the old buffer and displays the new one in the
;; target window.

;; The `re-builder' keeps the focus while updating the matches in the
;; target buffer so corrections are easy to incorporate.  If you are
;; satisfied with the result you can paste the RE to the kill-ring
;; with `reb-copy' ("\C-c\C-w"), quit the `re-builder' ("\C-c\C-q")
;; and use it wherever you need it.

;; As the automatic updates can take some time on large buffers, they
;; can be limited by `reb-auto-match-limit' so that they should not
;; have a negative impact on the editing.  Setting it to nil makes
;; even the auto updates go all the way.  Forcing an update overrides
;; this limit allowing an easy way to see all matches.

;; Currently `re-builder' understands five different forms of input,
;; namely `read', `string', `rx', `sregex' and `lisp-re' syntax.  Read
;; syntax and string syntax are both delimited by `"'s and behave
;; according to their name.  With the `string' syntax there's no need
;; to escape the backslashes and double quotes simplifying the editing
;; somewhat.  The other three allow editing of symbolic regular
;; expressions supported by the packages of the same name.  (`lisp-re'
;; is a package by me and its support may go away as it is nearly the
;; same as the `sregex' package in Emacs)

;; Editing symbolic expressions is done through a major mode derived
;; from `emacs-lisp-mode' so you'll get all the good stuff like
;; automatic indentation and font-locking etc.

;; When editing a symbolic regular expression, only the first
;; expression in the RE Builder buffer is considered, which helps
;; limiting the extent of the expression like the `"'s do for the text
;; modes.  For the `sregex' syntax the function `sregex' is applied to
;; the evaluated expression read.  So you can use quoted arguments
;; with something like '("findme") or you can construct arguments to
;; your hearts delight with a valid ELisp expression.  (The compiled
;; string form will be copied by `reb-copy')  If you want to take
;; a glance at the corresponding string you can temporarily change the
;; input syntax.

;; Changing the input syntax is transparent (for the obvious exception
;; non-symbolic -> symbolic) so you can change your mind as often as
;; you like.

;; There is also a shortcut function for toggling the
;; `case-fold-search' variable in the target buffer with an immediate
;; update.


;; Q: But what if my display cannot show colored overlays?
;; A: Then the cursor will flash around the matched text making it stand
;;    out.

;; Q: But how can I then make out the sub-expressions?
;; A: Thats where the `sub-expression mode' comes in.  In it only the
;;    digit keys are assigned to perform an update that will flash the
;;    corresponding subexp only.


;;; Code:

;; On XEmacs, load the overlay compatibility library
(unless (fboundp 'make-overlay)
  (require 'overlay))

;; User customizable variables
(defgroup re-builder nil
  "Options for the RE Builder."
  :group 'lisp
  :prefix "reb-")

(defcustom reb-blink-delay 0.5
  "Seconds to blink cursor for next/previous match in RE Builder."
  :group 're-builder
  :type 'number)

(defcustom reb-mode-hook nil
  "Hooks to run on entering RE Builder mode."
  :group 're-builder
  :type 'hook)

(defcustom reb-re-syntax 'read
  "Syntax for the REs in the RE Builder.
Can either be `read', `string', `sregex', `lisp-re', `rx'."
  :group 're-builder
  :type '(choice (const :tag "Read syntax" read)
		 (const :tag "String syntax" string)
		 (const :tag "`sregex' syntax" sregex)
		 (const :tag "`lisp-re' syntax" lisp-re)
		 (const :tag "`rx' syntax" rx)))

(defcustom reb-auto-match-limit 200
  "Positive integer limiting the matches for RE Builder auto updates.
Set it to nil if you don't want limits here."
  :group 're-builder
  :type '(restricted-sexp :match-alternatives
			  (integerp 'nil)))


(defface reb-match-0
  '((((class color) (background light))
     :background "lightblue")
    (((class color) (background dark))
     :background "steelblue4")
    (t
     :inverse-video t))
  "Used for displaying the whole match."
  :group 're-builder)

(defface reb-match-1
  '((((class color) (background light))
     :background "aquamarine")
    (((class color) (background dark))
     :background "blue3")
    (t
     :inverse-video t))
  "Used for displaying the first matching subexpression."
  :group 're-builder)

(defface reb-match-2
  '((((class color) (background light))
     :background "springgreen")
    (((class color) (background dark))
     :background "chartreuse4")
    (t
     :inverse-video t))
  "Used for displaying the second matching subexpression."
  :group 're-builder)

(defface reb-match-3
  '((((min-colors 88) (class color) (background light))
     :background "yellow1")
    (((class color) (background light))
     :background "yellow")
    (((class color) (background dark))
     :background "sienna4")
    (t
     :inverse-video t))
  "Used for displaying the third matching subexpression."
  :group 're-builder)

;; Internal variables below
(defvar reb-mode nil
  "Enables the RE Builder minor mode.")

(defvar reb-target-buffer nil
  "Buffer to which the RE is applied to.")

(defvar reb-target-window nil
  "Window to which the RE is applied to.")

(defvar reb-regexp nil
  "Last regexp used by RE Builder.")

(defvar reb-regexp-src nil
  "Last input regexp used by RE Builder before processing it.
Except for Lisp syntax this is the same as `reb-regexp'.")

(defvar reb-overlays nil
  "List of overlays of the RE Builder.")

(defvar reb-window-config nil
  "Old window configuration.")

(defvar reb-subexp-mode nil
  "Indicates whether sub-exp mode is active.")

(defvar reb-subexp-displayed nil
  "Indicates which sub-exp is active.")

(defvar reb-mode-string ""
  "String in mode line for additional info.")

(defvar reb-valid-string ""
  "String in mode line showing validity of RE.")

(make-variable-buffer-local 'reb-overlays)
(make-variable-buffer-local 'reb-regexp)
(make-variable-buffer-local 'reb-regexp-src)

(defconst reb-buffer-name "*RE-Builder*"
  "Buffer name to use for the RE Builder.")

(defvar reb-buffer nil
  "Buffer to use for the RE Builder.")

;; Define the local "\C-c" keymap
(defvar reb-mode-map
  (let ((map (make-sparse-keymap))
	(menu-map (make-sparse-keymap)))
    (define-key map "\C-c\C-c" 'reb-toggle-case)
    (define-key map "\C-c\C-q" 'reb-quit)
    (define-key map "\C-c\C-w" 'reb-copy)
    (define-key map "\C-c\C-s" 'reb-next-match)
    (define-key map "\C-c\C-r" 'reb-prev-match)
    (define-key map "\C-c\C-i" 'reb-change-syntax)
    (define-key map "\C-c\C-e" 'reb-enter-subexp-mode)
    (define-key map "\C-c\C-b" 'reb-change-target-buffer)
    (define-key map "\C-c\C-u" 'reb-force-update)
    (define-key map [menu-bar reb-mode] (cons "Re-Builder" menu-map))
    (define-key menu-map [rq]
      '(menu-item "Quit" reb-quit
		  :help "Quit the RE Builder mode"))
    (define-key menu-map [div1] '(menu-item "--"))
    (define-key menu-map [rt]
      '(menu-item "Case sensitive" reb-toggle-case
		  :button (:toggle . case-fold-search)
		  :help "Toggle case sensitivity of searches for RE Builder target buffer"))
    (define-key menu-map [rb]
      '(menu-item "Change target buffer..." reb-change-target-buffer
		  :help "Change the target buffer and display it in the target window"))
    (define-key menu-map [rs]
      '(menu-item "Change syntax..." reb-change-syntax
		  :help "Change the syntax used by the RE Builder"))
    (define-key menu-map [div2] '(menu-item "--"))
    (define-key menu-map [re]
      '(menu-item "Enter subexpression mode" reb-enter-subexp-mode
		  :help "Enter the subexpression mode in the RE Builder"))
    (define-key menu-map [ru]
      '(menu-item "Force update" reb-force-update
		  :help "Force an update in the RE Builder target window without a match limit"))
    (define-key menu-map [rn]
      '(menu-item "Go to next match" reb-next-match
		  :help "Go to next match in the RE Builder target window"))
    (define-key menu-map [rp]
      '(menu-item "Go to previous match" reb-prev-match
		  :help "Go to previous match in the RE Builder target window"))
    (define-key menu-map [div3] '(menu-item "--"))
    (define-key menu-map [rc]
      '(menu-item "Copy current RE" reb-copy
		  :help "Copy current RE into the kill ring for later insertion"))
    map)
  "Keymap used by the RE Builder.")

(define-derived-mode reb-mode nil "RE Builder"
  "Major mode for interactively building Regular Expressions."
  (set (make-local-variable 'blink-matching-paren) nil)
  (reb-mode-common))

;; fix-me: not very useful as far as I can see. Is there anything I am
;; missing? What is actually useful?
(define-derived-mode reb-lisp-mode
  emacs-lisp-mode "RE Builder Lisp"
  "Major mode for interactively building symbolic Regular Expressions."
  (cond ((eq reb-re-syntax 'lisp-re)	; Pull in packages
	 (require 'lisp-re))		; as needed
	((eq reb-re-syntax 'sregex)	; sregex is not autoloaded
	 (require 'sregex))		; right now..
	((eq reb-re-syntax 'rx)		; rx-to-string is autoloaded
	 (require 'rx)))		; require rx anyway
  (reb-mode-common))

;; Use the same "\C-c" keymap as `reb-mode' and use font-locking from
;; `emacs-lisp-mode'
(define-key reb-lisp-mode-map "\C-c"
  (lookup-key reb-mode-map "\C-c"))

(defvar reb-subexp-mode-map
  (let ((m (make-keymap)))
    (suppress-keymap m)
    ;; Again share the "\C-c" keymap for the commands
    (define-key m "\C-c" (lookup-key reb-mode-map "\C-c"))
    (define-key m "q" 'reb-quit-subexp-mode)
    (dotimes (digit 10)
      (define-key m (int-to-string digit) 'reb-display-subexp))
    m)
  "Keymap used by the RE Builder for the subexpression mode.")

(defun reb-update-mode-line ()
  (with-current-buffer reb-buffer
    ;;(message "ruml reb-valid-string=%S" reb-valid-string)
    (setq mode-line-buffer-identification
          (append
           '(25 . ("%b" reb-mode-string))
           (list " "
                 (let ((len (length reb-valid-string)))
                   (if (zerop len)
                       (make-string 15 32)
                     (concat (propertize reb-valid-string 'face 'isearch-fail)
                             (make-string (max 0 (- 15 len)) 32)))))))
    ;;(message "mlbi=%S\n%S" mode-line-buffer-identification "" )
    ;;(with-output-to-string (backtrace))
    (force-mode-line-update)))

(defvar reb-need-target-update nil)
(defvar reb-need-regexp-update nil)

(defun reb-mode-common ()
  "Setup functions common to functions `reb-mode' and `reb-mode-lisp'."
  (setq	reb-mode-string  "")
  (setq reb-valid-string nil)
  ;; (setq mode-line-buffer-identification
  ;;                        '(25 . ("%b" reb-mode-string reb-valid-string)))
  (reb-update-modestring)
  ;;(add-hook 'after-change-functions 'reb-auto-update nil t)
  (add-hook 'after-change-functions 'reb-after-change nil t)
  (add-hook 'post-command-hook 'reb-post-command)
  (setq reb-need-regexp-update t)
  (reb-auto-update nil nil nil))

(defun reb-color-display-p ()
  "Return t if display is capable of displaying colors."
  (eq 'color
      ;; emacs/xemacs compatibility
      (if (fboundp 'frame-parameter)
	  (frame-parameter (selected-frame) 'display-type)
	(if (fboundp 'frame-property)
	    (frame-property (selected-frame) 'display-type)))))

(defsubst reb-lisp-syntax-p ()
  "Return non-nil if RE Builder uses a Lisp syntax."
  (memq reb-re-syntax '(lisp-re sregex rx)))

(defmacro reb-target-binding (symbol)
  "Return binding for SYMBOL in the RE Builder target buffer."
  `(with-current-buffer reb-target-buffer ,symbol))

(defun reb-insert-regexp ()
  "Insert current RE."
  (let ((re (or (reb-target-binding reb-regexp)
		(reb-empty-regexp))))
    (cond ((eq reb-re-syntax 'read)
           (print re (current-buffer)))
          ((eq reb-re-syntax 'string)
           (insert re))
          ((eq reb-re-syntax 'rx)
           (let* ((rec (rxx-parse-string re nil))
                  (form (when (car rec) (cdr rec))))
             (when form
               (insert (format "(and %S)" form)))))
          ;; For the other Lisp syntax we need the "source" of the
          ;; regexp - but we do not have it.
          ((reb-lisp-syntax-p)
           (insert (reb-empty-regexp)))
          (t (error "Unhandled syntax: %s" reb-re-syntax)))))

(defun reb-initialize-buffer (buffer)
  "Initialize buffer BUFFER as a RE Builder buffer."
  ;; Make the overlays go away if the buffer is reb buffer is killed.
  (with-current-buffer buffer
    (erase-buffer)
    (reb-insert-regexp)
    (goto-char (+ 2 (point-min)))
    (cond ((reb-lisp-syntax-p)
           (reb-lisp-mode))
          (t (reb-mode)))
    ;; The local hook might have killed
    (add-hook 'kill-buffer-hook 'reb-kill-buffer nil t)
    (reb-restart-font-lock)
    (reb-do-update)))

(defun reb-mode-buffer-p ()
  "Return non-nil if the current buffer is a RE Builder buffer."
  (memq major-mode '(reb-mode reb-lisp-mode)))

;;; This is to help people find this in Apropos.
;;;###autoload
(defalias 'regexp-builder 're-builder)

;;;###autoload
(defun re-builder ()
  "Construct a regexp interactively."
  (interactive)
  (if (and (string= (buffer-name) reb-buffer-name)
	   (reb-mode-buffer-p))
      (message "Already in the RE Builder")
    (when reb-target-buffer
      (reb-delete-overlays))
    (setq reb-target-buffer (current-buffer)
          reb-target-window (selected-window))
    (with-current-buffer reb-target-buffer
      (add-hook 'after-change-functions 'reb-after-change nil t))
    (let* ((old-reb-buffer-window (get-buffer-window reb-buffer-name))
           (old-reb-frame (when old-reb-buffer-window (window-frame old-reb-buffer-window))))
      (when old-reb-buffer-window
        (unless (eq old-reb-frame (selected-frame))
          (when (window-configuration-p reb-window-config)
            (with-selected-frame old-reb-frame
              (set-window-configuration reb-window-config)))
          (setq old-reb-buffer-window nil)))
      (select-window (or old-reb-buffer-window
                         (progn
                           (setq reb-window-config (current-window-configuration))
                           (split-window (selected-window) (- (window-height) 4))))))
    (setq reb-buffer (get-buffer-create reb-buffer-name))
    (switch-to-buffer reb-buffer)
    (reb-initialize-buffer reb-buffer)))

(defun reb-change-target-buffer (buf)
  "Change the target buffer and display it in the target window."
  (interactive "bSet target buffer to: ")

  (let ((buffer (get-buffer buf)))
    (if (not buffer)
        (error "No such buffer")
      (reb-delete-overlays)
      (when (buffer-live-p reb-target-buffer)
        (remove-hook 'after-change-functions 'reb-after-change t))
      (setq reb-target-buffer buffer)
      (with-current-buffer reb-target-buffer
        (add-hook 'after-change-functions 'reb-after-change nil t))
      (reb-do-update
       (if reb-subexp-mode reb-subexp-displayed nil))
      (reb-update-modestring))))

(defun reb-force-update ()
  "Force an update in the RE Builder target window without a match limit."
  (interactive)

  (let ((reb-auto-match-limit nil))
    (reb-update-overlays
     (if reb-subexp-mode reb-subexp-displayed nil))))

(defun reb-quit ()
  "Quit the RE Builder mode."
  (interactive)
  (setq reb-subexp-mode nil
	reb-subexp-displayed nil)
  (reb-delete-overlays)
  (when (buffer-live-p reb-buffer)
    (bury-buffer reb-buffer))
  (re-builder-unload-function)
  (set-window-configuration reb-window-config))

(defun reb-next-match ()
  "Go to next match in the RE Builder target window."
  (interactive)

  (reb-assert-buffer-in-window)
  (with-selected-window reb-target-window
    (when reb-regexp
      (if (not (re-search-forward reb-regexp (point-max) t))
          (message "No more matches")
        (reb-show-subexp
         (or (and reb-subexp-mode reb-subexp-displayed) 0)
         t)))))

(defun reb-prev-match ()
  "Go to previous match in the RE Builder target window."
  (interactive)

  (reb-assert-buffer-in-window)
  (with-selected-window reb-target-window
    (when reb-regexp
      (let ((p (point)))
        (goto-char (1- p))
        (if (re-search-backward reb-regexp (point-min) t)
            (reb-show-subexp
             (or (and reb-subexp-mode reb-subexp-displayed) 0)
             t)
          (goto-char p)
          (message "No more matches"))))))

(defun reb-toggle-case ()
  "Toggle case sensitivity of searches for RE Builder target buffer."
  (interactive)

  (with-current-buffer reb-target-buffer
    (setq case-fold-search (not case-fold-search)))
  (reb-update-modestring)
  (setq reb-need-regexp-update t)
  (reb-auto-update nil nil nil t))

(defun reb-copy ()
  "Copy current RE into the kill ring for later insertion."
  (interactive)

  (reb-update-regexp)
  (let ((re (with-output-to-string
	      (print (reb-target-binding reb-regexp)))))
    (if (not re)
        (message "No current valid regexp")
      (setq re (substring re 1 (1- (length re))))
      (setq re (replace-regexp-in-string "\n" "\\n" re nil t))
      (kill-new re)
      (message "Regexp copied to kill-ring"))))

;; The subexpression mode is not electric because the number of
;; matches should be seen rather than a prompt.
(defun reb-enter-subexp-mode ()
  "Enter the subexpression mode in the RE Builder."
  (interactive)
  (setq reb-subexp-mode t)
  (reb-update-modestring)
  (use-local-map reb-subexp-mode-map)
  (message "`0'-`9' to display subexpressions  `q' to quit subexp mode"))

(defun reb-show-subexp (subexp &optional pause)
  "Visually show limit of subexpression SUBEXP of recent search.
On color displays this just puts point to the end of the expression as
the match should already be marked by an overlay.
On other displays jump to the beginning and the end of it.
If the optional PAUSE is non-nil then pause at the end in any case."
  (with-selected-window reb-target-window
    (unless (reb-color-display-p)
      (goto-char (match-end subexp))
      (sit-for reb-blink-delay)
      (goto-char (match-beginning subexp))
      (sit-for reb-blink-delay))
    ;; Go to beginning because otherwise we will be jumping forward on
    ;; changes and restarts after syntax errors:
    (goto-char (match-beginning 0))
    (when (or (not (reb-color-display-p)) pause)
      (sit-for reb-blink-delay))))

(defun reb-quit-subexp-mode ()
  "Quit the subexpression mode in the RE Builder."
  (interactive)
  (setq reb-subexp-mode nil
	reb-subexp-displayed nil)
  (reb-update-modestring)
  (use-local-map reb-mode-map)
  (reb-do-update))

(defvar reb-change-syntax-hist nil)
(require 'rxx)

(defun reb-change-syntax (syntax)
  "Change RE Builder source syntax to SYNTAX."
  (interactive
   (list (intern
	  (completing-read "Select syntax: "
			   (mapcar (lambda (el) (cons (symbol-name el) 1))
				   '(read string lisp-re sregex rx))
			   nil t (symbol-name reb-re-syntax)
                           'reb-change-syntax-hist))))
  (if (memq syntax '(read string lisp-re sregex rx))
      (progn
        (setq reb-re-syntax syntax)
        (when (buffer-live-p reb-buffer)
          (reb-initialize-buffer reb-buffer)))
    (error "Invalid syntax: %s" syntax)))


;; Non-interactive functions below
(defun reb-do-update (&optional subexp)
  "Update matches in the RE Builder target window.
If SUBEXP is non-nil mark only the corresponding sub-expressions."
  (reb-assert-buffer-in-window)
  (reb-update-regexp)
  (reb-update-overlays subexp))

(defun reb-post-command ()
  "Update display `post-command-hook' if needed."
  (when reb-need-regexp-update
    (with-current-buffer reb-buffer
      (save-restriction
        (widen)
        (put-text-property (point-min) (point-max) 'fontified nil))))
  (when reb-need-target-update
    (reb-auto-update nil nil nil)))

(defun reb-after-change (beg end lenold)
  "Remember to update after changes in reb buffer."
  (setq reb-need-target-update t)
  (unless (eq reb-target-buffer (current-buffer))
    (setq reb-need-regexp-update t)))

(defun reb-auto-update (beg end lenold &optional force)
  "Called from `after-update-functions' to update the display.
BEG, END and LENOLD are passed in from the hook.
An actual update is only done if the regexp has changed or if the
optional fourth argument FORCE is non-nil."
  (let ((prev-valid reb-valid-string)
	(new-valid
         (when reb-need-regexp-update
           (condition-case err
               (reb-update-regexp)
             (error
              (error-message-string err))))))
    ;;(setq reb-valid-string new-valid)
    (unless (equal reb-valid-string prev-valid)
      (reb-update-mode-line))

    ;; Through the caching of the re a change invalidating the syntax
    ;; for symbolic expressions will not delete the overlays so we
    ;; catch it here
    (when (and (reb-lisp-syntax-p)
               new-valid)
      (reb-delete-overlays)))
  (reb-do-update)
  (setq reb-need-target-update nil))

(defun reb-delete-overlays ()
  "Delete all RE Builder overlays in the `reb-target-buffer' buffer."
  (when (buffer-live-p reb-target-buffer)
    (with-current-buffer reb-target-buffer
      (mapc 'delete-overlay reb-overlays)
      (setq reb-overlays nil))))

(defun reb-assert-buffer-in-window ()
  "Assert that `reb-target-buffer' is displayed in `reb-target-window'."

  (if (not (eq reb-target-buffer (window-buffer reb-target-window)))
      (set-window-buffer reb-target-window reb-target-buffer)))

(defun reb-update-modestring ()
  "Update the variable `reb-mode-string' displayed in the mode line."
  ;;(message "update-modde-string: reb-valid-string=%S" reb-valid-string)
  (setq reb-mode-string
	(concat
	 (if reb-subexp-mode
             (format " (subexp %s)" (or reb-subexp-displayed "-"))
	   "")
	 (if (not (reb-target-binding case-fold-search))
	     " Case"
	   "")))
  (reb-update-mode-line))

(defun reb-display-subexp (&optional subexp)
  "Highlight only subexpression SUBEXP in the RE Builder."
  (interactive)

  (setq reb-subexp-displayed
	(or subexp (string-to-number (format "%c" last-command-event))))
  (reb-update-modestring)
  (reb-do-update reb-subexp-displayed))

(defun reb-kill-buffer ()
  "When the RE Builder buffer is killed make sure no overlays stay around."
  (when (reb-mode-buffer-p)
    (reb-delete-overlays)))


;; The next functions are the interface between the regexp and
;; its textual representation in the RE Builder buffer.
;; They are the only functions concerned with the actual syntax
;; being used.
(defvar reb-read-error-positions nil)

(defun reb-mark-read-error (beg end)
  (setq reb-read-error-positions
        (cons (cons beg end)
              reb-read-error-positions)))

(defun reb-read-regexp ()
  "Read current regexp src from the RE Builder buffer.
Return it in raw source format, but trimmed except for 'string
format where the whole buffer is always returned.

Also check input format.  However do not check yet if the
resulting regexp is valid."
  (when (buffer-live-p reb-buffer)
    (with-current-buffer reb-buffer
      (set (make-local-variable 'reb-read-error-positions) nil)
      (save-excursion
        (cond ((eq reb-re-syntax 'read)
               (goto-char (point-min))
               (skip-chars-forward " \t\n")
               (let* ((start (point))
                      (form (condition-case err
                                (read (current-buffer))
                              (error (setq reb-valid-string (error-message-string err))
                                     (reb-mark-read-error start (point))
                                     (message "rvs=%S" reb-valid-string)
                                     nil))))
                 (if (not form)
                     (reb-mark-read-error start (point))
                   (if (not (stringp form))
                       (progn
                         (reb-mark-read-error start (point))
                         (setq reb-valid-string "Not a string"))
                     (skip-chars-forward " \t\n")
                     (if (eobp)
                         form
                       (setq start (point))
                       (goto-char (point-max))
                       (skip-chars-backward " \t\n")
                       (reb-mark-read-error start (point))
                       (setq reb-valid-string "Trailing garbage")
                       nil)))))
              ((eq reb-re-syntax 'string)
               (buffer-substring-no-properties (point-min) (point-max)))
              ((reb-lisp-syntax-p)
               (goto-char (point-min))
               (skip-chars-forward " \t\n")
               (if (memq (char-after) '(?\' ?\` ?\[))
                   (progn
                     (reb-mark-read-error (point) (1+ (point)))
                     (setq reb-valid-string "Bad char")
                     nil)
                 (let* ((start (point))
                        stop
                        (form (condition-case err
                                  (read (current-buffer))
                                (error (setq reb-valid-string (error-message-string err))
                                       (reb-mark-read-error start (point))
                                       nil))))
                   (when form
                     (setq stop (point))
                     (skip-chars-forward " \n\t")
                     (if (eobp)
                         (cons form (buffer-substring-no-properties start stop))
                       (reb-mark-read-error (point) (point-max))
                       (setq reb-valid-string "Trailing garbage")
                       nil)))))
              (t (error "reb-re-syntax=%s" reb-re-syntax)))))))

(defun reb-empty-regexp ()
  "Return empty RE for current syntax."
  (cond ((reb-lisp-syntax-p) "'()")
	(t "")))

(defun reb-cook-regexp (re)
  "Return RE after processing it according to `reb-re-syntax'.
The return value is a regexp in string format.  It may be
invalid."
  (cond ((eq reb-re-syntax 'lisp-re)
	 (when (fboundp 'lre-compile-string)
	   (lre-compile-string (eval (car re)))))
	((eq reb-re-syntax 'sregex)
	 (apply 'sregex (eval (car re))))
	((eq reb-re-syntax 'rx)
	 (rx-to-string (car re)))
	(t re)))

(defun reb-update-regexp ()
  "Update the regexp for the target buffer.
Return t if the (cooked) expression changed."
  (when reb-need-regexp-update
    (setq reb-valid-string nil)
    (let* ((re-src (reb-read-regexp))
           (re (unless reb-valid-string
                 (condition-case err
                     ;; Eval is used, there can be an error. Just catch it
                     ;; here.
                     (reb-cook-regexp re-src)
                   (error
                    ;;(setq reb-valid-string (format "re-src=%S => %s" re-src (error-message-string err)))
                    (setq reb-valid-string (error-message-string err))
                    (reb-update-modestring)
                    nil)))))
      ;;(message "update: re=%S" re)
      (when re
        (unless (stringp re)
          (unless reb-valid-string
            (setq reb-valid-string "*internal error, re is not a string*"))
          (setq re nil))
        (condition-case err
            (string-match-p re "")
          (error
           (setq reb-valid-string (error-message-string err))
           (setq re nil)))
        )
      (reb-update-modestring)
      (with-current-buffer reb-target-buffer
        ;; fix-me:
        (when (let ((oldre reb-regexp))
                (prog1
                    (not (equal oldre re))
                  (setq reb-regexp re)))
          ;; Only update the source re for the lisp formats
          (when (reb-lisp-syntax-p)
            (setq reb-regexp-src (cdr re-src))))))
    (setq reb-need-regexp-update nil)))


;; And now the real core of the whole thing
(defun reb-count-subexps (re)
  "Return number of sub-expressions in the regexp RE."

  (let ((i 0) (beg 0))
    (while (string-match "\\\\(" re beg)
      (setq i (1+ i)
	    beg (match-end 0)))
    i))

(defun reb-update-overlays (&optional subexp)
  "Switch to `reb-target-buffer' and mark all matches of `reb-regexp'.
If SUBEXP is non-nil mark only the corresponding sub-expressions."
  ;;(message "reb-update-overlays cb=%S" (current-buffer))
  (let* ((re (reb-target-binding reb-regexp))
	 (subexps (when re (reb-count-subexps re)))
	 (matches 0)
	 (submatches 0)
	 firstmatch
         (start-in-target (when (and (eq (current-buffer) reb-target-buffer)
                                     (window-live-p reb-target-window)
                                     (eq (selected-frame) (window-frame reb-target-window))
                                     (eq (window-buffer reb-target-window) reb-target-buffer)
                                     )
                            (window-start reb-target-window)))
         (point-in-target (when start-in-target (window-point reb-target-window)))
         here
         firstmatch-after-here)
    (with-current-buffer reb-target-buffer
      (setq here
            (if reb-target-window
                (with-selected-window reb-target-window (window-point))
              (point)))
      (reb-delete-overlays)
      ;;(message "reb-update-overlays cb=%S, re=%S" (current-buffer) re)
      (when re
        (goto-char (point-min))
        (while (and (not (eobp))
                    (re-search-forward re (point-max) t)
                    (or (not reb-auto-match-limit)
                        (< matches reb-auto-match-limit)))
          (when (and (= 0 (length (match-string 0)))
                     (not (eobp)))
            (forward-char 1))
          (let ((i 0)
                suffix max-suffix)
            (setq matches (1+ matches))
            (while (<= i subexps)
              (when (and (or (not subexp) (= subexp i))
                         (match-beginning i))
                (let ((overlay (make-overlay (match-beginning i)
                                             (match-end i)))
                      ;; When we have exceeded the number of provided faces,
                      ;; cycle thru them where `max-suffix' denotes the maximum
                      ;; suffix for `reb-match-*' that has been defined and
                      ;; `suffix' the suffix calculated for the current match.
                      (face
                       (cond
                        (max-suffix
                         (if (= suffix max-suffix)
                             (setq suffix 1)
                           (setq suffix (1+ suffix)))
                         (intern-soft (format "reb-match-%d" suffix)))
                        ((intern-soft (format "reb-match-%d" i)))
                        ((setq max-suffix (1- i))
                         (setq suffix 1)
                         ;; `reb-match-1' must exist.
                         'reb-match-1))))
                  (unless firstmatch (setq firstmatch (match-data)))
                  (unless firstmatch-after-here
                    (when (> (point) here)
                      (setq firstmatch-after-here (match-data))))
                  (setq reb-overlays (cons overlay reb-overlays)
                        submatches (1+ submatches))
                  (overlay-put overlay 'face face)
                  (overlay-put overlay 'priority i)))
              (setq i (1+ i)))))
        (let ((count (if subexp submatches matches)))
          (message "%s %smatch%s%s"
                   (if (= 0 count) "No" (int-to-string count))
                   (if subexp "subexpression " "")
                   (if (= 1 count) "" "es")
                   (if (and reb-auto-match-limit
                            (= reb-auto-match-limit count))
                       " (limit reached)" "")))))
    ;;(message "reb-update-overlays firstmatch=%S" firstmatch)
    (when firstmatch
      (store-match-data (or firstmatch-after-here firstmatch))
      (reb-show-subexp (or subexp 0)))
    ;;(message "reb-update-overlays start-in-target=%S" start-in-target)
    (when start-in-target
      (set-window-start reb-target-window start-in-target)
      (set-window-point reb-target-window point-in-target))
    ;;(message "reb-update-overlays EXIT")
    ))

;; The End
(defun re-builder-unload-function ()
  "Unload the RE Builder library."
  (remove-hook 'post-command-hook 'reb-post-command)
  (when (buffer-live-p reb-target-buffer)
    (remove-hook 'after-change-functions 'reb-after-change t))
  (when (buffer-live-p reb-buffer)
    (with-current-buffer reb-buffer
      ;;(remove-hook 'after-change-functions 'reb-auto-update t)
      (remove-hook 'after-change-functions 'reb-after-change t)
      (remove-hook 'kill-buffer-hook 'reb-kill-buffer t)
      (when (reb-mode-buffer-p)
	(reb-delete-overlays)
	(funcall (or (default-value 'major-mode) 'fundamental-mode)))))
  ;; continue standard unloading
  nil)

(defun reb-fontify-string-re (bound)
  (when nil ;; Enabling this hangs emacs (rather badly, but can be
            ;; stopped if with-local-quit is used.
    (catch 'found
      ;; The following loop is needed to continue searching after matches
      ;; that do not occur in strings.  The associated regexp matches one
      ;; of `\\\\' `\\(' `\\(?:' `\\|' `\\)'.  `\\\\' has been included to
      ;; avoid highlighting, for example, `\\(' in `\\\\('.
      (when (memq reb-re-syntax '(read string))
        (let ((n 0))
          (while (and (> 200 (setq n (1+ n)))
                      (re-search-forward
                       (if (eq reb-re-syntax 'read)
                           ;; Copied from font-lock.el
                           "\\(\\\\\\\\\\)\\(?:\\(\\\\\\\\\\)\\|\\((\\(?:\\?[0-9]*:\\)?\\|[|)]\\)\\)"
                         "\\(\\\\\\)\\(?:\\(\\\\\\)\\|\\((\\(?:\\?[0-9]*:\\)?\\|[|)]\\)\\)")
                       bound t))
            (unless (match-beginning 2)
              (let ((face (get-text-property (1- (point)) 'face)))
                (when (or (and (listp face)
                               (memq 'font-lock-string-face face))
                          (eq 'font-lock-string-face face)
                          t)
                  (throw 'found t))))))))))

(defface reb-regexp-grouping-backslash
  '((t :inherit font-lock-keyword-face :weight bold :underline t))
  "Font Lock mode face for backslashes in Lisp regexp grouping constructs."
  :group 're-builder)

(defface reb-regexp-grouping-construct
  '((t :inherit font-lock-keyword-face :weight bold :underline t))
  "Font Lock mode face used to highlight grouping constructs in Lisp regexps."
  :group 're-builder)

(defconst reb-string-font-lock-defaults
  (eval-when-compile
  '(((reb-fontify-string-re
      (1 'reb-regexp-grouping-backslash prepend)
      (3 'reb-regexp-grouping-construct prepend))
     (reb-mark-non-matching-parenthesis)
     (reb-font-lock-background-marker)
     (reb-font-lock-error-marker)
     )
    nil)))

(defsubst reb-while (limit counter where)
  (let ((count (symbol-value counter)))
    (if (= count limit)
        (progn
          (msgtrc "Reached (while limit=%s, where=%s)" limit where)
          nil)
      (set counter (1+ count)))))

(defun reb-mark-non-matching-parenthesis (bound)
  ;; We have a small string, check the whole of it, but wait until
  ;; everything else is fontified.
  (when (>= bound (point-max))
    (with-local-quit
      (with-silent-modifications
        (let ((here (point))
              left-pars
              (n-reb 0)
              faces-here
              )
          (goto-char (point-min))
          (while (and (reb-while 100 'n-reb "mark-par")
                      (not (eobp)))
            (skip-chars-forward "^()")
            (unless (eobp)
              (setq faces-here (get-text-property (point) 'face))
              ;; It is already fontified, use that info:
              (when (or (eq 'reb-regexp-grouping-construct faces-here)
                        (and (listp faces-here)
                             (memq 'reb-regexp-grouping-construct faces-here)))
                (cond ((eq (char-after) ?\()
                       (setq left-pars (cons (point) left-pars)))
                      ((eq (char-after) ?\))
                       (if left-pars
                           (setq left-pars (cdr left-pars))
                         (put-text-property (point) (1+ (point))
                                            'face 'font-lock-warning-face)))
                      (t (message "markpar: char-after=%s" (char-to-string (char-after))))))
              (unless (eobp) (forward-char))))
          (dolist (lp left-pars)
            (put-text-property lp (1+ lp)
                               'face 'font-lock-warning-face)))))))

(require 'rx)
;; Fix-me: add some completion
(defconst reb-rx-font-lock-keywords
  (let ((constituents (mapcar (lambda (rec) (symbol-name (car rec))) rx-constituents))
        (syntax (mapcar (lambda (rec) (symbol-name (car rec))) rx-syntax))
        (categories (mapcar (lambda (rec) (symbol-name (car rec))) rx-categories)))
    `(
      (reb-font-lock-error-marker)
      (,(concat "(category[[:space:]]+" (regexp-opt categories t) ")")
       (1 font-lock-variable-name-face))
      (,(concat "(syntax[[:space:]]+" (regexp-opt syntax t) ")")
       (1 font-lock-type-face))
      (,(concat "(" (regexp-opt constituents t))
       (1 font-lock-keyword-face))
      ;; (,(concat "(" (regexp-opt (list "rx-to-string") t) "[[:space:]]")
      ;;  (1 font-lock-warning-face))
      ;; (,(concat "(" (regexp-opt (list "rx") t) "[[:space:]]")
      ;;  (1 font-lock-warning-face))
      (,(concat "(category[[:space:]]+\\([a-z]+\\)")
       (1 font-lock-warning-face))
      (,(concat "(syntax[[:space:]]+\\([a-z]+\\)")
       (1 font-lock-warning-face))
      (,"(\\([a-z-]+\\)"
       (1 font-lock-warning-face))
      )))

(defun reb-font-lock-error-marker (limit)
  (when (eq limit (point-max))
    (with-local-quit
      (save-restriction
        (widen)
        (with-silent-modifications
          (dolist (rec reb-read-error-positions)
            (let ((beg (car rec))
                  (end (cdr rec)))
              (setq end (min end (point-max)))
              (when (> end beg)
                (put-text-property beg end 'face 'font-lock-warning-face)))))))))

(defun reb-font-lock-background-marker (limit)
  (when (eq reb-re-syntax 'string)
    (when (eq limit (point-max))
      (with-local-quit
        (save-restriction
          (widen)
          (let ((here (point))
                beg end
                old-face
                new-face
                (n 0)
                (bg-face 'secondary-selection))
            ;; Fix-me: no reason to jump around here.
            (goto-char (point-min))
            (setq beg (point))
            (with-silent-modifications
              (while (and (> 200 (setq n (1+ n)))
                          (not (eobp)))
                (setq old-face (get-text-property beg 'face))
                (setq end (or (next-single-property-change (point) 'face)
                              (point-max)))
                ;; This crashes Emacs
                (if (listp old-face)
                    (setq new-face (cons bg-face old-face))
                  (setq new-face (list bg-face old-face)))
                ;; so avoid it now:
                (setq new-face bg-face)
                (put-text-property beg end 'face new-face)
                (goto-char end)
                (setq beg (point)))
              (goto-char here))))))))

(defun reb-restart-font-lock ()
  "Restart `font-lock-mode' to fit current regexp format."
  (font-lock-mode 1) ;; fix-me
  (unless (eq (current-buffer) reb-buffer) (error "Not in %S" reb-buffer))
  (let ((font-lock-is-on font-lock-mode))
    (font-lock-mode -1)
    (kill-local-variable 'font-lock-set-defaults)
    (setq font-lock-defaults
          (cond
           ((memq reb-re-syntax '(read string))
            ;; Fix-me: should this be keywords? Anyway split it up for
            ;; read and string.
            reb-string-font-lock-defaults)
           ((eq reb-re-syntax 'rx)
            '(reb-rx-font-lock-keywords
              nil))
           (t nil)))
    (when font-lock-is-on (font-lock-mode 1))))

(provide 're-builder)

;; arch-tag: 5c5515ac-4085-4524-a421-033f44f032e7
;;; re-builder.el ends here
