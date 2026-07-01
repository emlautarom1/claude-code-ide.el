;;; claude-code-ide-consult.el --- Consult integration for claude-code-ide  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Yoav Orot
;; Keywords: ai, claude, consult, sessions

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Optional integration that surfaces live Claude Code IDE sessions in
;; `consult-buffer' (narrow with `c'), ordered by run status (blocked first,
;; then idle, then working) and -- when `marginalia' is loaded -- annotated
;; with each session's status and how long it has held it.  Previewing a
;; candidate shows its Claude Code buffer in the side window.
;;
;; Loading this file also upgrades `claude-code-ide-list-sessions' itself to a
;; `consult'-based picker with the same live preview, replacing its default
;; `completing-read' front end (which stays the fallback when `consult' is not
;; loaded).
;;
;; This file adds no hard dependency: the `consult' and `marginalia' hooks
;; below only activate once those packages are loaded.  Require it from your
;; configuration, e.g.:
;;
;;   (with-eval-after-load 'consult
;;     (require 'claude-code-ide-consult))

;;; Code:

(require 'claude-code-ide)

;; `consult' and `marginalia' are optional and referenced only inside the
;; `with-eval-after-load' blocks below; declare their symbols so byte
;; compilation stays clean when they are not installed.
(defvar consult-buffer-sources)
(defvar marginalia-annotators)
(declare-function consult-buffer "consult" (&optional sources))
(declare-function consult--read "consult" (table &rest options))

(defun claude-code-ide-consult--session-buffer (dir)
  "Return the live session buffer for display directory DIR, or nil."
  (when dir
    (get-buffer (funcall claude-code-ide-buffer-name-function
                         (claude-code-ide--session-dir-key dir)))))

(defun claude-code-ide-consult--session-dirs ()
  "Return working directories of live Claude Code IDE sessions.
Ordered by run status (blocked, then idle, then working)."
  (claude-code-ide--cleanup-dead-processes)
  (let (dirs)
    (maphash
     (lambda (directory _process)
       (when (get-buffer (funcall claude-code-ide-buffer-name-function directory))
         (push (abbreviate-file-name directory) dirs)))
     claude-code-ide--processes)
    ;; `sort' on a list is stable, so same-status sessions keep their order.
    (sort (nreverse dirs)
          (lambda (a b)
            (< (claude-code-ide--run-status-rank a)
               (claude-code-ide--run-status-rank b))))))

(defun claude-code-ide-consult--show-session (buf)
  "Show session buffer BUF the way `claude-code-ide-switch-to-buffer' would.
Focus its window if already shown, else display it in the side window."
  (if-let* ((win (get-buffer-window buf)))
      (select-window win)
    (claude-code-ide--display-buffer-in-side-window buf)))

(defun claude-code-ide-consult--session-state ()
  "Consult state: preview a session by switching to its Claude Code buffer.

The buffer that was current when the picker opened is remembered up front.
Previewing a candidate switches to its Claude Code buffer; aborting restores
focus to the original buffer, while selecting a session leaves focus in it.

Consult runs each preview inside the original window and re-selects it
afterwards, so the `select-window' here only takes hold permanently once the
minibuffer exits on selection."
  (let (orig-win orig-buf)
    (lambda (action dir)
      (let ((buf (claude-code-ide-consult--session-buffer dir)))
        (pcase action
          ('setup
           (setq orig-win (selected-window)
                 orig-buf (current-buffer)))
          ;; DIR nil resets the preview (also fires just before an abort):
          ;; return focus to where we started.
          ('preview
           (if buf
               (claude-code-ide-consult--show-session buf)
             (when (window-live-p orig-win)
               (select-window orig-win)
               (when (buffer-live-p orig-buf)
                 (set-window-buffer orig-win orig-buf)))))
          ('return
           (when buf
             (claude-code-ide-consult--show-session buf)
             ;; Guarantee focus lands in the session regardless of
             ;; `claude-code-ide-focus-on-open'.
             (when-let* ((win (get-buffer-window buf)))
               (select-window win)))))))))

(defun claude-code-ide-consult--preview-only-state ()
  "Consult state that previews sessions but does not commit focus on selection."
  (let ((state (claude-code-ide-consult--session-state)))
    (lambda (action dir)
      ;; Delegate setup/preview/exit; the caller owns the final display.
      (unless (eq action 'return)
        (funcall state action dir)))))

(defun claude-code-ide-consult--annotate (cand)
  "Annotate Claude session directory CAND with its run status and elapsed time.
The leading space carries the `marginalia--align' text property so `marginalia'
aligns the status column to a common offset across candidates of differing
width, the same way its built-in field annotators do."
  (let* ((status (or (claude-code-ide-session-run-status cand) "idle"))
         (face (or (cdr (assoc status claude-code-ide--run-status-faces)) 'shadow))
         (age (claude-code-ide--format-status-age
               (claude-code-ide-session-run-status-since cand))))
    (concat (propertize " " 'marginalia--align t)
            " "
            (propertize (format "%-8s" status) 'face face)
            " "
            (propertize (format "%-6s" age) 'face 'marginalia-date))))

(defvar claude-code-ide-consult-source
  `( :name "Claude"
     :narrow ?c
     :category claude-session
     :face consult-file
     :history file-name-history
     :state ,#'claude-code-ide-consult--session-state
     :items ,#'claude-code-ide-consult--session-dirs
     :hidden t)             ; surfaced in `consult-buffer' by narrowing with `c'
  "Consult source listing Claude Code IDE sessions by directory.")

(defun claude-code-ide-consult--read-session (sessions)
  "Pick a Claude session from SESSIONS with `consult--read' and live preview.
SESSIONS is the sorted ((DISPLAY . DIR) ...) alist; returns the chosen DISPLAY.
The candidates are the session directories -- annotated by `marginalia' with
each session's run status and elapsed time -- and previewed in the side window
as you move between them.  Serves as `claude-code-ide-session-read-function'."
  (consult--read
   (mapcar #'car sessions)
   :prompt "Switch to: "
   :category 'claude-session
   :require-match t
   :sort nil                 ; SESSIONS is already ordered by run status
   :history 'file-name-history
   :state (claude-code-ide-consult--preview-only-state)))

(with-eval-after-load 'consult
  (add-to-list 'consult-buffer-sources 'claude-code-ide-consult-source 'append)
  ;; Route `claude-code-ide-list-sessions' through `consult' so the standalone
  ;; picker gains the same preview as the `consult-buffer' source.
  (setq claude-code-ide-session-read-function
        #'claude-code-ide-consult--read-session))

(with-eval-after-load 'marginalia
  (add-to-list 'marginalia-annotators
               '(claude-session claude-code-ide-consult--annotate builtin none)))

(provide 'claude-code-ide-consult)
;;; claude-code-ide-consult.el ends here
