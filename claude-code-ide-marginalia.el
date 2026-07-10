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

;; `marginalia' is guaranteed loaded whenever this file is (it is required from
;; a `with-eval-after-load 'marginalia' hook), so its symbols are used directly
;; at runtime.  They are declared here so byte-compilation stays clean when
;; `marginalia' is absent from the compile-time load path.
(defvar marginalia-annotators)
(defvar marginalia-separator)
(declare-function marginalia--truncate "marginalia" (str width))

(defun claude-code-ide-marginalia--column (text width face)
  "Return TEXT as a fixed-WIDTH column propertized with FACE.
Delegates the layout to `marginalia--truncate', so it behaves exactly like
`marginalia's own `:width' columns: TEXT is padded with spaces or truncated
with the configured ellipsis (and given a `help-echo' with the full text) to
`abs WIDTH' columns, a positive WIDTH left-justifying and a negative WIDTH
right-justifying.  This keeps the session picker's columns aligned the way
every other `marginalia' annotation is."
  (propertize (marginalia--truncate text width) 'face face))

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
            marginalia-separator (claude-code-ide-marginalia--column age -4 'marginalia-date)
            marginalia-separator (claude-code-ide-marginalia--column status 8 status-face)
            (when (and reason (not (string-empty-p reason)))
              (concat marginalia-separator (propertize reason 'face status-face))))))

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
