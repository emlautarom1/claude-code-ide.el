;;; claude-code-ide-marginalia.el --- Marginalia annotations for claude-code-ide  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Yoav Orot
;; Keywords: ai, claude, marginalia, sessions

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

;; Optional integration that annotates the Claude Code IDE session picker with
;; `marginalia'.  Each candidate is a session's working directory tagged with
;; the `claude-session' completion category; this file registers a `marginalia'
;; annotator for that category which appends fixed-width columns -- the
;; session's name, age, run status and, when waiting, the reason -- laid out so
;; they line up across candidates the way `marginalia' aligns its own columns.
;;
;; It annotates whichever picker is active -- the plain `completing-read' front
;; end of `claude-code-ide-list-sessions' or the `consult' upgrade -- since both
;; tag their candidates with the `claude-session' category, and is the only
;; source of session annotations.
;;
;; This file adds no hard dependency: the `marginalia' hook below only activates
;; once `marginalia' is loaded, and `claude-code-ide' loads this file
;; automatically when `marginalia' is present, so no manual setup is needed.

;;; Code:

(require 'claude-code-ide)

;; `marginalia' is optional and referenced only inside the `with-eval-after-load'
;; block below; declare its variable so byte compilation stays clean when it is
;; not installed.
(defvar marginalia-annotators)

(defun claude-code-ide-marginalia--column (text width face)
  "Render TEXT as a fixed-WIDTH column, then propertize it with FACE.
TEXT is truncated with an ellipsis when it is too wide and padded with spaces
when too narrow.  A positive WIDTH left-justifies, a negative WIDTH
right-justifies.  This mirrors how `marginalia' lays out its own fixed-width
columns (its `:width' field option), so the session picker's columns line up
regardless of how long each entry is."
  (let* ((w (abs width))
         (col (if (< width 0)
                  (let ((s (truncate-string-to-width text w 0 nil "…")))
                    (concat (make-string (max 0 (- w (string-width s))) ?\s) s))
                (truncate-string-to-width text w 0 ?\s "…"))))
    (propertize col 'face face)))

(defun claude-code-ide-marginalia--annotate-session (directory)
  "Marginalia annotation for session DIRECTORY: name, age, status and reason.
These are rendered as fixed-width columns -- name, age, status, then any status
reason -- so the columns line up across candidates the way `marginalia' aligns
its own.  The leading space carries the `marginalia--align' text property so
`marginalia' aligns the whole block against the candidate.  The name uses
`marginalia-documentation', the age `marginalia-date' (matching how `marginalia'
faces file dates), and the status and its reason the status's run-status colour
from `claude-code-ide--run-status-faces'."
  (let* ((session (claude-code-ide--get-session directory))
         (name (or (and session (claude-code-ide--session-name session)) ""))
         (status (or (and session (claude-code-ide--session-status session)) "idle"))
         (reason (and session (claude-code-ide--session-status-reason session)))
         (age (claude-code-ide--format-status-age
               (claude-code-ide-session-run-status-since directory)))
         (status-face (or (cdr (assoc status claude-code-ide--run-status-faces)) 'shadow)))
    (concat (propertize " " 'marginalia--align t)
            (claude-code-ide-marginalia--column name 24 'marginalia-documentation)
            "  " (claude-code-ide-marginalia--column age -4 'marginalia-date)
            "  " (claude-code-ide-marginalia--column status 8 status-face)
            (when (and reason (not (string-empty-p reason)))
              (concat "  " (propertize reason 'face status-face))))))

;; Register the annotator for the `claude-session' completion category -- it is
;; the only source of session annotations, so no opt-in is offered.  This is
;; independent of `consult': it annotates whichever picker is active (the plain
;; `completing-read' one or the `consult' upgrade), both of which tag their
;; candidates with that category.
(with-eval-after-load 'marginalia
  (add-to-list 'marginalia-annotators
               '(claude-session claude-code-ide-marginalia--annotate-session
                                builtin none)))

(provide 'claude-code-ide-marginalia)
;;; claude-code-ide-marginalia.el ends here
