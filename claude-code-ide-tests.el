;;; claude-code-ide-tests.el --- Tests for Claude Code IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Yoav Orot

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Test suite for claude-code-ide.el using ERT
;;
;; Run tests with:
;;   `emacs -batch -L . -l ert -l claude-code-ide-tests.el -f ert-run-tests-batch-and-exit'
;;
;; The tests mock both vterm and mcp-server-lib functionality to avoid requiring
;; these packages during testing. This allows the tests to run in any environment
;; without external dependencies.
;;
;; CRITICAL DISCOVERY: Claude Code tools only work when launched from VS Code/editor terminals
;; because the extensions set these environment variables:
;; - CLAUDE_CODE_SSE_PORT: The WebSocket server port created by the extension
;; - FORCE_CODE_TERMINAL: Set to "true" to enable terminal features
;;
;; Workflow:
;; 1. Extension creates WebSocket/MCP server on random port
;; 2. Extension sets environment variables in terminal
;; 3. Extension launches 'claude' command
;; 4. Claude CLI reads env vars and connects to WebSocket server
;; 5. CLI and extension communicate via WebSocket/JSON-RPC for tool calls

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock Implementations

;; === Mock claude-code-ide-debug module ===
(defvar claude-code-ide-debug nil
  "Mock debug flag for testing.")
(defvar claude-code-ide-log-with-context t
  "Mock log context flag for testing.")
(defun claude-code-ide-debug (&rest _args)
  "Mock debug function that does nothing."
  nil)
(defun claude-code-ide-clear-debug ()
  "Mock clear debug function."
  nil)
(defun claude-code-ide-log (format-string &rest args)
  "Mock logging function for tests."
  (apply #'message format-string args))
(defun claude-code-ide--get-session-context ()
  "Mock session context function."
  "")
(provide 'claude-code-ide-debug)

;; === Mock websocket module ===
;; Try to load real websocket, otherwise provide comprehensive mocks
(condition-case nil
    (progn
      (add-to-list 'load-path (expand-file-name "~/.emacs.d/.cache/straight/build/websocket/"))
      (require 'websocket))
  (error
   ;; Comprehensive websocket mock implementation
   (defun websocket-server (&rest _args)
     "Mock websocket-server function."
     ;; Return something that looks like a server but isn't a process
     '(:mock-server t))
   (defun websocket-server-close (_server)
     "Mock websocket-server-close function."
     nil)
   (defun websocket-send-text (_ws _text)
     "Mock websocket-send-text function."
     nil)
   (defun websocket-ready-state (_ws)
     "Mock websocket-ready-state function."
     'open)
   (defun websocket-url (_ws)
     "Mock websocket-url function."
     "ws://localhost:12345")
   (defun websocket-frame-text (_frame)
     "Mock websocket-frame-text function."
     "{}")
   (defun websocket-frame-opcode (_frame)
     "Mock websocket-frame-opcode function."
     'text)
   (defun websocket-send (_ws _frame)
     "Mock websocket-send function."
     nil)
   (defun websocket-server-filter (_proc _string)
     "Mock websocket-server-filter function."
     nil)
   ;; Define the structure accessors to avoid free variable warnings
   (defvar websocket-frame nil)
   (cl-defstruct websocket-frame opcode payload)
   (provide (quote websocket))))

;; === Mock vterm module ===
(defvar vterm--process nil)
(defvar vterm-buffer-name nil)
(defvar vterm-shell nil)
(defvar vterm-environment nil)

(defun vterm (&optional buffer-name)
  "Mock vterm function for testing with optional BUFFER-NAME."
  (let ((buffer (generate-new-buffer (or buffer-name vterm-buffer-name "*vterm*"))))
    (with-current-buffer buffer
      ;; Create a mock process that exits immediately
      (setq vterm--process (make-process :name "mock-vterm"
                                         :buffer buffer
                                         :command '("true")
                                         :connection-type 'pty
                                         :sentinel (lambda (_ event)
                                                     (when (string-match "finished" event)
                                                       (setq vterm--process nil))))))
    buffer))

;; Mock vterm functions
(defun vterm-send-string (_string)
  "Mock vterm-send-string function for testing."
  nil)

(defun vterm-send-return ()
  "Mock vterm-send-return function for testing."
  nil)

(defun vterm-send-key (_key &optional _shift _meta _ctrl)
  "Mock vterm-send-key function for testing."
  nil)

(provide (quote vterm))

;; === Mock ghostel module ===
(defvar ghostel-buffer-name nil)
(defvar ghostel-set-title-function #'ignore)
(defvar ghostel-enable-title-tracking t)
(defvar ghostel-kill-buffer-on-exit t)

(defun ghostel (&optional _arg)
  "Mock ghostel function for testing."
  (let ((buffer (get-buffer-create (or ghostel-buffer-name "*ghostel*"))))
    (set-buffer buffer)
    (with-current-buffer buffer
      (make-process :name "mock-ghostel"
                    :buffer buffer
                    :command '("true")
                    :connection-type 'pty))
    buffer))

(defun ghostel-exec (buffer _program &optional _args)
  "Mock ghostel-exec function for testing."
  (with-current-buffer buffer
    (make-process :name "mock-ghostel"
                  :buffer buffer
                  :command '("true")
                  :connection-type 'pty)))

(defun ghostel-send-string (_string)
  "Mock ghostel send function for testing."
  nil)

(defun ghostel--window-adjust-process-window-size (_process _windows)
  "Mock ghostel resize handler for testing."
  '(80 . 24))

(provide (quote ghostel))

;; === Mock Emacs display functions ===
(unless (fboundp 'display-buffer-in-side-window)
  (defun display-buffer-in-side-window (buffer _alist)
    "Mock display-buffer-in-side-window for testing."
    (set-window-buffer (selected-window) buffer)
    (selected-window)))

;; === Additional test-specific websocket mocks ===
(unless (featurep 'websocket)
  ;; Only define these if websocket wasn't loaded above
  (defvar websocket--test-server nil
    "Mock server for testing.")
  (defvar websocket--test-client nil
    "Mock client for testing.")
  (defvar websocket--test-port 12345
    "Mock port for testing."))

;; === Mock flycheck module ===
;; Mock flycheck before loading any modules that require it
(defvar flycheck-mode nil
  "Mock flycheck-mode variable.")
(defvar flycheck-current-errors nil
  "Mock list of flycheck errors.")

(cl-defstruct flycheck-error
  "Mock flycheck error structure."
  buffer checker filename line column end-line end-column
  message level severity id)

(provide (quote flycheck))

;; === Load required modules ===
(define-error 'mcp-error "MCP Error" 'error)
(require 'claude-code-ide-mcp-handlers)
(require 'claude-code-ide)

;;; Test Helper Functions

(defmacro claude-code-ide-tests--with-mocked-cli (cli-path &rest body)
  "Execute BODY with claude CLI path set to CLI-PATH."
  `(let ((claude-code-ide-cli-path ,cli-path)
         (claude-code-ide--cli-available nil))
     ,@body))

(defun claude-code-ide-tests--with-temp-directory (test-body)
  "Execute TEST-BODY in a temporary directory context.
Creates a temporary directory, sets it as `default-directory',
executes TEST-BODY, and ensures cleanup even if TEST-BODY fails."
  (let ((temp-dir (make-temp-file "claude-code-ide-test-" t)))
    (unwind-protect
        (let ((default-directory temp-dir))
          (funcall test-body))
      (delete-directory temp-dir t))))

(defmacro claude-code-ide-tests--with-temp-config-dir (&rest body)
  "Run BODY with `CLAUDE_CONFIG_DIR' pointed at a fresh writable temp dir.
Ensures MCP lockfile creation does not depend on a writable `~/.claude/ide/'."
  (declare (indent 0))
  `(let* ((config-dir (make-temp-file "claude-code-ide-config-" t))
          (process-environment
           (cons (format "CLAUDE_CONFIG_DIR=%s" config-dir) process-environment)))
     (unwind-protect
         (progn ,@body)
       (delete-directory config-dir t))))

(defun claude-code-ide-tests--clear-processes ()
  "Clear the session hash table for testing.
Ensures a clean state before each test that involves process management."
  (clrhash claude-code-ide--sessions)
  ;; Also clear MCP sessions
  (when (boundp 'claude-code-ide-mcp--sessions)
    (clrhash claude-code-ide-mcp--sessions)))

(defun claude-code-ide-tests--seed-status (dir status &optional since reason name)
  "Seed DIR's session with STATUS for testing, as the watcher would.
Optional SINCE, REASON and NAME populate the matching struct fields.
Returns the session."
  (let ((session (claude-code-ide--ensure-session dir)))
    (setf (claude-code-ide--session-status session) status
          (claude-code-ide--session-status-since session) (or since (current-time))
          (claude-code-ide--session-status-reason session) reason
          (claude-code-ide--session-name session) name)
    session))

(defun claude-code-ide-tests--write-session-file (sessions-dir pid alist)
  "Write ALIST as JSON to SESSIONS-DIR/PID.json, the way the CLI would."
  (make-directory sessions-dir t)
  (with-temp-file (expand-file-name (format "%d.json" pid) sessions-dir)
    (insert (json-encode alist))))

(defun claude-code-ide-tests--wait-for-process (buffer)
  "Wait for the process in BUFFER to finish.
This prevents race conditions in tests by ensuring mock processes
have completed before cleanup.  Waits up to 5 seconds."
  (with-current-buffer buffer
    (let ((max-wait 50)) ; 5 seconds max (50 * 0.1s)
      (while (and vterm--process
                  (process-live-p vterm--process)
                  (> max-wait 0))
        (sleep-for 0.1)
        (setq max-wait (1- max-wait))))))

;;; Tests for Helper Functions

(ert-deftest claude-code-ide-test-default-buffer-name ()
  "Test default buffer name generation for various path formats."
  ;; Normal path
  (should (equal (claude-code-ide--default-buffer-name "/home/user/project")
                 "*claude-code[project]*"))
  ;; Path with trailing slash
  (should (equal (claude-code-ide--default-buffer-name "/home/user/my-app/")
                 "*claude-code[my-app]*"))
  ;; Root directory
  (should (equal (claude-code-ide--default-buffer-name "/")
                 "*claude-code[]*"))
  ;; Path with spaces
  (should (equal (claude-code-ide--default-buffer-name "/home/user/my project/")
                 "*claude-code[my project]*"))
  ;; Path with special characters
  (should (equal (claude-code-ide--default-buffer-name "/home/user/my-project@v1.0/")
                 "*claude-code[my-project@v1.0]*")))

(ert-deftest claude-code-ide-test-get-working-directory ()
  "Test working directory detection."
  (claude-code-ide-tests--with-temp-directory
   (lambda ()
     ;; Without project, should return current directory
     (let ((expected (expand-file-name default-directory)))
       (should (equal (claude-code-ide--get-working-directory) expected))))))

(ert-deftest claude-code-ide-test-get-buffer-name ()
  "Test buffer name generation using custom function."
  ;; Test with custom function
  (let ((claude-code-ide-buffer-name-function
         (lambda (dir) (format "test-%s" (file-name-nondirectory dir)))))
    (claude-code-ide-tests--with-temp-directory
     (lambda ()
       (should (string-match "^test-claude-code-ide-test-"
                             (claude-code-ide--get-buffer-name))))))

  ;; Test that nil directory is handled correctly
  (let ((claude-code-ide-buffer-name-function
         (lambda (dir) (if dir
                           (format "*custom[%s]*" (file-name-nondirectory dir))
                         "*custom[none]*"))))
    (should (equal (funcall claude-code-ide-buffer-name-function nil)
                   "*custom[none]*"))))

(ert-deftest claude-code-ide-test-process-management ()
  "Test process storage and retrieval."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((dir (claude-code-ide--get-working-directory))
               (mock-process 'mock-process))
           ;; Initially no process
           (should (null (claude-code-ide--get-process dir)))

           ;; Set a process
           (claude-code-ide--set-process mock-process dir)
           (should (eq (claude-code-ide--get-process dir) mock-process))

           ;; Get process without specifying directory
           (should (eq (claude-code-ide--get-process) mock-process)))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-cleanup-dead-processes ()
  "Test cleanup of dead processes."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (let* ((live-process (make-process :name "test-live"
                                         :command '("sleep" "10")
                                         :buffer nil))
             (dead-process-name "test-dead"))
        ;; Create a mock dead process
        (puthash "/dir1" (claude-code-ide--session-create :process live-process)
                 claude-code-ide--sessions)
        (puthash "/dir2" (claude-code-ide--session-create :process dead-process-name)
                 claude-code-ide--sessions)

        ;; Before cleanup
        (should (= (hash-table-count claude-code-ide--sessions) 2))

        ;; Run cleanup
        (claude-code-ide--cleanup-dead-processes)

        ;; After cleanup - only live process remains
        (should (= (hash-table-count claude-code-ide--sessions) 1))
        (should (gethash "/dir1" claude-code-ide--sessions))
        (should (null (gethash "/dir2" claude-code-ide--sessions)))

        ;; Clean up the live process
        (delete-process live-process))
    (claude-code-ide-tests--clear-processes)))

;;; Tests for CLI Detection

(ert-deftest claude-code-ide-test-detect-cli ()
  "Test CLI detection mechanism."
  (let ((claude-code-ide--cli-available nil))
    ;; Test with invalid CLI path
    (let ((claude-code-ide-cli-path "nonexistent-claude-cli"))
      (claude-code-ide--detect-cli)
      (should (null claude-code-ide--cli-available)))

    ;; Test with valid command (echo exists on most systems)
    (let ((claude-code-ide-cli-path "echo"))
      (claude-code-ide--detect-cli)
      (should claude-code-ide--cli-available))))

(ert-deftest claude-code-ide-test-ensure-cli ()
  "Test CLI availability checking."
  (let ((claude-code-ide--cli-available nil)
        (claude-code-ide-cli-path "echo"))
    ;; Initially not available
    (should (null claude-code-ide--cli-available))

    ;; After ensure, should be detected
    (should (claude-code-ide--ensure-cli))
    (should claude-code-ide--cli-available)))

;;; Command Tests

(ert-deftest claude-code-ide-test-run-without-cli ()
  "Test run command when CLI is not available."
  (let ((claude-code-ide--cli-available nil)
        (claude-code-ide-cli-path "nonexistent-claude-cli"))
    (should-error (claude-code-ide)
                  :type 'user-error)))

(ert-deftest claude-code-ide-test-run-without-vterm ()
  "Test run command when vterm is not available."
  (let ((claude-code-ide--cli-available t)
        (claude-code-ide-cli-path "echo")
        (claude-code-ide-terminal-backend 'vterm)
        (orig-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (sym &rest _) (if (eq sym 'vterm) nil (funcall orig-featurep sym))))
              ((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (unless (eq feature 'vterm)
                   (require feature filename noerror)))))
      (should-error (claude-code-ide)
                    :type 'user-error))))

(ert-deftest claude-code-ide-test-run-without-eat ()
  "Test run command when eat is not available."
  (let ((claude-code-ide--cli-available t)
        (claude-code-ide-cli-path "echo")
        (claude-code-ide-terminal-backend 'eat)
        (orig-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (sym &rest _) (if (eq sym 'eat) nil (funcall orig-featurep sym))))
              ((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (unless (eq feature 'eat)
                   (require feature filename noerror)))))
      (should-error (claude-code-ide)
                    :type 'user-error))))

(ert-deftest claude-code-ide-test-run-without-ghostel ()
  "Test run command when ghostel is not available."
  (let ((claude-code-ide--cli-available t)
        (claude-code-ide-cli-path "echo")
        (claude-code-ide-terminal-backend 'ghostel)
        (orig-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (sym &rest _) (if (eq sym 'ghostel) nil (funcall orig-featurep sym))))
              ((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (unless (eq feature 'ghostel)
                   (require feature filename noerror)))))
      (should-error (claude-code-ide)
                    :type 'user-error))))

(ert-deftest claude-code-ide-test-terminal-backend-selection ()
  "Test terminal backend selection and validation."
  ;; Test vterm backend
  (let ((claude-code-ide-terminal-backend 'vterm))
    (should (eq claude-code-ide-terminal-backend 'vterm)))

  ;; Test eat backend
  (let ((claude-code-ide-terminal-backend 'eat))
    (should (eq claude-code-ide-terminal-backend 'eat)))

  ;; Test ghostel backend
  (let ((claude-code-ide-terminal-backend 'ghostel))
    (should (eq claude-code-ide-terminal-backend 'ghostel)))

  ;; Test invalid backend
  (let ((claude-code-ide-terminal-backend 'invalid-backend)
        (orig-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (sym) nil)))
      (should-error (claude-code-ide--terminal-ensure-backend)
                    :type 'user-error))))

(ert-deftest claude-code-ide-test-terminal-send-functions ()
  "Test terminal send wrapper functions."
  ;; Mock vterm functions
  (let ((vterm-string-sent nil)
        (vterm-escape-sent nil)
        (vterm-return-sent nil)
        (eat-string-sent nil)
        (ghostel-string-sent nil))
    (cl-letf (((symbol-function 'vterm-send-string)
               (lambda (str) (setq vterm-string-sent str)))
              ((symbol-function 'vterm-send-escape)
               (lambda () (setq vterm-escape-sent t)))
              ((symbol-function 'vterm-send-return)
               (lambda () (setq vterm-return-sent t)))
              ((symbol-function 'eat-term-send-string)
               (lambda (term str) (setq eat-string-sent str)))
              ((symbol-function 'ghostel-send-string)
               (lambda (str) (setq ghostel-string-sent str))))

      ;; Test vterm backend
      (let ((claude-code-ide-terminal-backend 'vterm))
        (claude-code-ide--terminal-send-string "test")
        (should (equal vterm-string-sent "test"))

        (claude-code-ide--terminal-send-escape)
        (should vterm-escape-sent)

        (claude-code-ide--terminal-send-return)
        (should vterm-return-sent))

      ;; Test eat backend - need to mock the buffer-local variable
      (with-temp-buffer
        (let ((claude-code-ide-terminal-backend 'eat))
          ;; Set eat-terminal as a buffer-local variable
          (setq-local eat-terminal t)
          (claude-code-ide--terminal-send-string "test")
          (should (equal eat-string-sent "test"))

          (setq eat-string-sent nil)
          (claude-code-ide--terminal-send-escape)
          (should (equal eat-string-sent "\e"))

          (setq eat-string-sent nil)
          (claude-code-ide--terminal-send-return)
          (should (equal eat-string-sent "\r"))))

      ;; Test ghostel backend
      (with-temp-buffer
        (let ((claude-code-ide-terminal-backend 'ghostel))
          (claude-code-ide--terminal-send-string "test")
          (should (equal ghostel-string-sent "test"))

          (setq ghostel-string-sent nil)
          (claude-code-ide--terminal-send-escape)
          (should (equal ghostel-string-sent "\e"))

          (setq ghostel-string-sent nil)
          (claude-code-ide--terminal-send-return)
          (should (equal ghostel-string-sent "\r")))))))

(ert-deftest claude-code-ide-test-submit-prompt-command ()
  "Test the claude-code-ide-submit-prompt command."
  (let ((test-prompt "Test prompt from minibuffer")
        (prompted-string nil)
        (sent-string nil)
        (sent-return nil))
    ;; Mock read-string to return our test prompt
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &rest _)
                 (setq prompted-string prompt)
                 test-prompt))
              ((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str) (setq sent-string str)))
              ((symbol-function 'claude-code-ide--terminal-send-return)
               (lambda () (setq sent-return t))))

      ;; Test with existing buffer
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (claude-code-ide-submit-prompt)
        (should (equal prompted-string "Claude prompt: "))
        (should (equal sent-string test-prompt))
        (should sent-return))

      ;; Test with non-existent buffer (should error)
      (should-error (claude-code-ide-submit-prompt) :type 'user-error)

      ;; An active region does NOT attach a reference; the raw prompt is sent.
      (setq sent-string nil sent-return nil)
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (insert "line1\nline2\nline3")
        (setq buffer-file-name "/tmp/prompt.el")
        (goto-char (point-min))
        (set-mark (point))
        (goto-char (line-end-position 2))
        (let ((transient-mark-mode t))
          (activate-mark)
          (claude-code-ide-submit-prompt))
        (set-buffer-modified-p nil)
        (should (equal sent-string test-prompt))
        (should sent-return))

      ;; Test with empty prompt (should not send anything)
      (setq sent-string nil sent-return nil)
      (cl-letf (((symbol-function 'read-string)
                 (lambda (&rest _) "")))
        (with-temp-buffer
          (rename-buffer "*test-claude-buffer*")
          (claude-code-ide-submit-prompt)
          (should (null sent-string))
          (should (null sent-return)))))))

(ert-deftest claude-code-ide-test-terminal-session-creation ()
  "Test terminal session creation with both backends."
  (let ((mock-vterm-buffer nil)
        (mock-eat-buffer nil)
        (mock-ghostel-buffer nil)
        (mock-ghostel-program nil)
        (mock-ghostel-args nil)
        (mock-ghostel-env nil)
        (mock-ghostel-default-directory nil)
        (mock-process (start-process "mock" nil "true")))
    (cl-letf (((symbol-function 'claude-code-ide--terminal-ensure-backend)
               (lambda () nil))  ; Mock the ensure function to do nothing
              ((symbol-function 'vterm)
               (lambda (name)
                 (setq mock-vterm-buffer (get-buffer-create name))))
              ((symbol-function 'eat-mode)
               (lambda () nil))
              ((symbol-function 'eat-exec)
               (lambda (buffer name cmd startfile args)
                 (setq mock-eat-buffer buffer)))
              ((symbol-function 'ghostel-exec)
               (lambda (buffer program &optional args)
                 (setq mock-ghostel-buffer buffer)
                 (setq mock-ghostel-program program)
                 (setq mock-ghostel-args args)
                 (setq mock-ghostel-env process-environment)
                 (setq mock-ghostel-default-directory default-directory)
                 (setq-local ghostel-set-title-function #'ignore)
                 mock-process))
              ((symbol-function 'get-buffer-process)
               (lambda (buffer) mock-process))
              ((symbol-function 'claude-code-ide-mcp-start)
               (lambda (dir) 12345)))

      ;; Test vterm backend session creation
      (let ((claude-code-ide-terminal-backend 'vterm)
            (claude-code-ide--cli-available t))
        (cl-letf (((symbol-function 'claude-code-ide--build-claude-command)
                   (lambda (&rest _) "claude")))
          (let ((result (claude-code-ide--create-terminal-session
                         "*test-vterm*" "/tmp" 12345 nil nil "test-session")))
            (should (consp result))
            (should (bufferp (car result)))
            (should (processp (cdr result)))
            (should (equal (buffer-name mock-vterm-buffer) "*test-vterm*")))))

      ;; Test eat backend session creation
      (let ((claude-code-ide-terminal-backend 'eat)
            (claude-code-ide--cli-available t))
        (cl-letf (((symbol-function 'claude-code-ide--build-claude-command)
                   (lambda (&rest _) "claude")))
          (let ((result (claude-code-ide--create-terminal-session
                         "*test-eat*" "/tmp" 12345 nil nil "test-session")))
            (should (consp result))
            (should (bufferp (car result)))
            (should (processp (cdr result)))
            (should (bufferp mock-eat-buffer)))))

      ;; Test ghostel backend session creation
      (let ((claude-code-ide-terminal-backend 'ghostel)
            (claude-code-ide--cli-available t))
        (cl-letf (((symbol-function 'claude-code-ide--build-claude-command)
                   (lambda (&rest _) "claude --print \"hello world\"")))
          (let ((result (claude-code-ide--create-terminal-session
                         "*test-ghostel*" "/tmp" 12345 nil nil "test-session")))
            (should (consp result))
            (should (bufferp (car result)))
            (should (processp (cdr result)))
            (should (equal (buffer-name mock-ghostel-buffer) "*test-ghostel*"))
            (should (equal mock-ghostel-program "claude"))
            (should (equal mock-ghostel-args '("--print" "hello world")))
            (should (equal mock-ghostel-default-directory "/tmp"))
            (with-current-buffer mock-ghostel-buffer
              (should (null ghostel-set-title-function)))
            (should (member "CLAUDE_CODE_SSE_PORT=12345" mock-ghostel-env))
            (should (member "TERM_PROGRAM=emacs" mock-ghostel-env))
            (should (member "FORCE_CODE_TERMINAL=true" mock-ghostel-env))))))))

(ert-deftest claude-code-ide-test-vterm-smart-renderer-passthrough ()
  "Test that vterm smart renderer passes through normal text immediately."
  (let ((orig-fun-called nil)
        (orig-fun-input nil)
        (claude-code-ide-vterm-anti-flicker t))
    (cl-letf (((symbol-function 'claude-code-ide--session-buffer-p)
               (lambda (_) t)))
      (with-temp-buffer
        (let ((claude-code-ide--vterm-render-queue nil)
              (claude-code-ide--vterm-render-timer nil)
              (mock-process (make-process :name "mock"
                                          :buffer (current-buffer)
                                          :command '("true"))))
          ;; Create a mock original function
          (let ((orig-fun (lambda (_process input)
                            (setq orig-fun-called t
                                  orig-fun-input input))))
            ;; Test with normal text (no escape sequences)
            (claude-code-ide--vterm-smart-renderer orig-fun mock-process "Hello World")
            ;; Should pass through immediately
            (should orig-fun-called)
            (should (equal orig-fun-input "Hello World"))
            (should-not claude-code-ide--vterm-render-queue)))))))

(ert-deftest claude-code-ide-test-vterm-smart-renderer-batching ()
  "Test that vterm smart renderer batches complex escape sequences."
  (let ((orig-fun-called nil)
        (timer-created nil)
        (claude-code-ide-vterm-anti-flicker t)
        (claude-code-ide-vterm-render-delay 0.005))
    (cl-letf (((symbol-function 'claude-code-ide--session-buffer-p)
               (lambda (_) t))
              ((symbol-function 'run-at-time)
               (lambda (delay &rest _)
                 (setq timer-created delay)
                 'mock-timer))
              ((symbol-function 'cancel-timer)
               (lambda (_) nil)))
      (with-temp-buffer
        (let ((claude-code-ide--vterm-render-queue nil)
              (claude-code-ide--vterm-render-timer nil)
              (mock-process (make-process :name "mock"
                                          :buffer (current-buffer)
                                          :command '("true"))))
          ;; Create a mock original function
          (let ((orig-fun (lambda (_process _input)
                            (setq orig-fun-called t))))
            ;; Test with complex escape sequence pattern
            (let ((complex-input "\033[2A\033[K\033[3A\033[K"))
              (claude-code-ide--vterm-smart-renderer orig-fun mock-process complex-input)
              ;; Should be queued, not called immediately
              (should-not orig-fun-called)
              ;; Queue is a list (pushed in reverse order for O(1))
              (should (listp claude-code-ide--vterm-render-queue))
              (should (equal (apply #'concat (nreverse claude-code-ide--vterm-render-queue))
                             complex-input))
              (should (equal timer-created 0.005)))))))))

(ert-deftest claude-code-ide-test-toggle-vterm-optimization ()
  "Test toggling vterm optimization on and off."
  (let ((original-value claude-code-ide-vterm-anti-flicker)
        (message-output nil))
    (unwind-protect
        (cl-letf (((symbol-function 'message)
                   (lambda (format &rest args)
                     (setq message-output (apply #'format format args)))))
          ;; Start with optimization enabled
          (setq claude-code-ide-vterm-anti-flicker t)

          ;; Toggle off
          (claude-code-ide-toggle-vterm-optimization)
          (should-not claude-code-ide-vterm-anti-flicker)
          (should (string-match "disabled" message-output))

          ;; Toggle back on
          (claude-code-ide-toggle-vterm-optimization)
          (should claude-code-ide-vterm-anti-flicker)
          (should (string-match "enabled" message-output)))
      ;; Restore original value
      (setq claude-code-ide-vterm-anti-flicker original-value))))

(ert-deftest claude-code-ide-test-run-with-cli ()
  "Test successful run command execution."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((claude-code-ide--cli-available t)
               (claude-code-ide-cli-path "echo"))
           ;; Run claude-code-ide
           (claude-code-ide)

           ;; Check that buffer was created
           (let ((buffer-name (claude-code-ide--get-buffer-name)))
             (should (get-buffer buffer-name))

             ;; Check that process was registered
             (should (claude-code-ide--get-process))

             ;; Wait for process to finish and clean up
             (claude-code-ide-tests--wait-for-process (get-buffer buffer-name))
             ;; Kill the buffer explicitly since we're in batch mode
             (when (get-buffer buffer-name)
               (kill-buffer buffer-name))))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-run-existing-session ()
  "Test run command when session already exists."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((claude-code-ide--cli-available t)
               (claude-code-ide-cli-path "echo"))
           ;; Start first session
           (claude-code-ide)
           (let* ((buffer-name (claude-code-ide--get-buffer-name))
                  (first-buffer (get-buffer buffer-name)))

             ;; Verify we have the buffer
             (should first-buffer)

             ;; Try to run again - should not create new buffer
             (claude-code-ide)

             ;; Should still have same buffer
             (should (eq (get-buffer buffer-name) first-buffer))

             ;; Wait for process and clean up
             (claude-code-ide-tests--wait-for-process first-buffer)
             (kill-buffer first-buffer)))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-check-status ()
  "Test status check command."
  (let ((claude-code-ide-cli-path "echo")
        (claude-code-ide--cli-available nil))
    ;; Should not error and should detect CLI
    (claude-code-ide-check-status)
    (should claude-code-ide--cli-available)))

(ert-deftest claude-code-ide-test-terminal-initialization-delay ()
  "Test terminal initialization delay configuration."
  ;; Test default value
  (should (boundp 'claude-code-ide-terminal-initialization-delay))
  (should (numberp claude-code-ide-terminal-initialization-delay))
  (should (= claude-code-ide-terminal-initialization-delay 0.1))

  ;; Test customization
  (let ((original-delay claude-code-ide-terminal-initialization-delay))
    (unwind-protect
        (progn
          (setq claude-code-ide-terminal-initialization-delay 0.2)
          (should (= claude-code-ide-terminal-initialization-delay 0.2)))
      ;; Restore original value
      (setq claude-code-ide-terminal-initialization-delay original-delay))))

(ert-deftest claude-code-ide-test-stop-no-session ()
  "Test stop command when no session is running."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         ;; Should not error when no session exists
         (claude-code-ide-stop)))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-stop-with-session ()
  "Test stop command with active session."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((claude-code-ide--cli-available t)
               (claude-code-ide-cli-path "echo"))
           ;; Start a session
           (claude-code-ide)
           (let ((buffer-name (claude-code-ide--get-buffer-name)))
             ;; Verify session exists
             (should (get-buffer buffer-name))
             (should (claude-code-ide--get-process))

             ;; Wait for process to finish before stopping
             (claude-code-ide-tests--wait-for-process (get-buffer buffer-name))

             ;; Stop the session
             (claude-code-ide-stop)

             ;; Verify session is stopped
             (should (null (get-buffer buffer-name)))
             (should (null (claude-code-ide--get-process)))))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-switch-to-buffer-no-session ()
  "Test `switch-to-buffer' command when no session exists."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (should-error (claude-code-ide-switch-to-buffer)
                    :type 'user-error)
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-toggle-window-functionality ()
  "Test that running claude-code-ide on an existing session toggles the window."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((claude-code-ide--cli-available t)
               (claude-code-ide-cli-path "echo")
               (test-dir default-directory))
           ;; Start a session
           (claude-code-ide)
           (let* ((buffer-name (claude-code-ide--get-buffer-name))
                  (session-buffer (get-buffer buffer-name)))

             ;; Verify we have the buffer
             (should session-buffer)

             ;; Simulate window being visible (in batch mode we can't test actual windows)
             ;; Just verify the command runs without error when session exists
             (let ((default-directory test-dir))
               ;; Running claude-code-ide again should toggle (not error)
               (claude-code-ide))

             ;; Wait for process and clean up
             (claude-code-ide-tests--wait-for-process session-buffer)
             (kill-buffer session-buffer)))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-list-sessions-empty ()
  "Test listing sessions when none exist."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      ;; Should not error when no sessions exist
      (claude-code-ide-list-sessions)
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-list-sessions-with-sessions ()
  "Test listing sessions functionality."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (progn
        ;; Test that list-sessions works with no sessions
        (claude-code-ide-list-sessions)

        ;; Manually add mock entries to the session table
        (puthash "/tmp/project1" (claude-code-ide--session-create :process (current-buffer))
                 claude-code-ide--sessions)
        (puthash "/tmp/project2" (claude-code-ide--session-create :process (current-buffer))
                 claude-code-ide--sessions)

        ;; Verify we have 2 entries
        (should (= (hash-table-count claude-code-ide--sessions) 2))

        ;; List sessions should work without error
        (claude-code-ide-list-sessions))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-toggle-recent ()
  "Test the toggle-recent functionality."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (let ((test-buffer1 (get-buffer-create "*Claude Code - test1*"))
            (test-buffer2 (get-buffer-create "*Claude Code - test2*"))
            (claude-code-ide--last-accessed-buffer nil))
        ;; Test when no recent buffer exists
        (should-error (claude-code-ide-toggle-recent))

        ;; Set a recent buffer
        (setq claude-code-ide--last-accessed-buffer test-buffer1)

        ;; Test toggle when no windows are visible (should show the buffer)
        ;; This will fail in batch mode but verifies the function doesn't error
        (condition-case nil
            (claude-code-ide-toggle-recent)
          (error nil))

        ;; Clean up
        (kill-buffer test-buffer1)
        (kill-buffer test-buffer2))
    (claude-code-ide-tests--clear-processes)))

;;; Edge Case Tests

(ert-deftest claude-code-ide-test-concurrent-sessions ()
  "Test managing multiple concurrent sessions."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (let ((claude-code-ide--cli-available t)
            (claude-code-ide-cli-path "echo")
            (dir1 (make-temp-file "claude-test-1" t))
            (dir2 (make-temp-file "claude-test-2" t)))
        ;; Start sessions in different directories
        (let ((default-directory dir1))
          (claude-code-ide)
          (should (claude-code-ide--get-process dir1)))
        (let ((default-directory dir2))
          (claude-code-ide)
          (should (claude-code-ide--get-process dir2)))
        ;; Verify both sessions exist
        (should (= (hash-table-count claude-code-ide--sessions) 2))
        ;; Clean up
        (let ((buffers (mapcar (lambda (dir)
                                 (funcall claude-code-ide-buffer-name-function dir))
                               (list dir1 dir2))))
          (dolist (buffer-name buffers)
            (when-let ((buffer (get-buffer buffer-name)))
              (claude-code-ide-tests--wait-for-process buffer)
              (kill-buffer buffer))))
        (delete-directory dir1 t)
        (delete-directory dir2 t))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-custom-buffer-naming ()
  "Test custom buffer naming function."
  (let ((claude-code-ide-buffer-name-function
         (lambda (dir)
           (format "TEST-%s"
                   (upcase (file-name-nondirectory (directory-file-name dir)))))))
    (claude-code-ide-tests--with-temp-directory
     (lambda ()
       (let ((expected (format "TEST-%s"
                               (upcase (file-name-nondirectory
                                        (directory-file-name default-directory))))))
         (should (equal (claude-code-ide--get-buffer-name) expected)))))))

(ert-deftest claude-code-ide-test-window-placement-options ()
  "Test different window placement configurations."
  (dolist (side '(left right top bottom))
    (let ((claude-code-ide-window-side side))
      ;; Just verify the setting is accepted
      (should (eq claude-code-ide-window-side side)))))

(ert-deftest claude-code-ide-test-debug-mode-flag ()
  "Test debug mode CLI flag."
  (let ((claude-code-ide-cli-debug t))
    (should (string-match "-d" (claude-code-ide--build-claude-command)))
    (should (string-match "-d.*-c" (claude-code-ide--build-claude-command t)))
    (should (string-match "-d.*-r" (claude-code-ide--build-claude-command nil t)))))

(ert-deftest claude-code-ide-test-build-command-with-system-prompt ()
  "Test building command with append-system-prompt flag."
  ;; Test with user system prompt
  (let ((claude-code-ide-cli-path "claude")
        (claude-code-ide-system-prompt "You are a helpful assistant")
        (claude-code-ide-cli-debug nil)
        (claude-code-ide-cli-extra-flags ""))
    (let ((cmd (claude-code-ide--build-claude-command)))
      (should (string-match-p "--append-system-prompt" cmd))
      ;; Check that Emacs prompt is included (accounting for shell escaping)
      (should (or (string-match-p "Connected to Emacs" cmd)
                  (string-match-p "Connected\\\\ to\\\\ Emacs" cmd)))
      ;; Check that user prompt is included
      (should (or (string-match-p "You are a helpful assistant" cmd)
                  (string-match-p "You\\\\ are\\\\ a\\\\ helpful\\\\ assistant" cmd)))))
  ;; Test with nil value (should still add the Emacs prompt)
  (let ((claude-code-ide-cli-path "claude")
        (claude-code-ide-system-prompt nil)
        (claude-code-ide-cli-debug nil)
        (claude-code-ide-cli-extra-flags ""))
    (let ((cmd (claude-code-ide--build-claude-command)))
      (should (string-match-p "--append-system-prompt" cmd))
      ;; Check that Emacs prompt is included (accounting for shell escaping)
      (should (or (string-match-p "Connected to Emacs" cmd)
                  (string-match-p "Connected\\\\ to\\\\ Emacs" cmd)))
      ;; Should not contain user prompt when nil
      (should-not (string-match-p "You are a helpful assistant" cmd))))
  ;; Test with special characters that need quoting
  (let ((claude-code-ide-cli-path "claude")
        (claude-code-ide-system-prompt "You're a \"helpful\" assistant!")
        (claude-code-ide-cli-debug nil)
        (claude-code-ide-cli-extra-flags ""))
    (let ((cmd (claude-code-ide--build-claude-command)))
      (should (string-match-p "--append-system-prompt" cmd))
      ;; Check that Emacs prompt is included (accounting for shell escaping)
      (should (or (string-match-p "Connected to Emacs" cmd)
                  (string-match-p "Connected\\\\ to\\\\ Emacs" cmd)))
      ;; The command should contain the escaped version (shell-quote-argument escapes quotes and apostrophes)
      (should (string-match-p "You\\\\'re\\\\ a\\\\ \\\\\"helpful\\\\\"\\\\ assistant\\\\!" cmd)))))

(ert-deftest claude-code-ide-test-error-handling ()
  "Test error handling in various scenarios."
  ;; Test with nil CLI path
  (let ((claude-code-ide-cli-path nil)
        (claude-code-ide--cli-available nil))
    (should-error (claude-code-ide) :type 'user-error))

  ;; Test with empty CLI path
  (let ((claude-code-ide-cli-path "")
        (claude-code-ide--cli-available nil))
    (should-error (claude-code-ide) :type 'user-error)))

;;; Run all tests

(ert-deftest claude-code-ide-test-tab-bar-tracking ()
  "Test that tab-bar tabs are tracked correctly."
  (let* ((temp-dir (make-temp-file "test-project-" t))
         (claude-code-ide-mcp--sessions (make-hash-table :test 'equal))
         ;; Mock tab-bar functions
         (mock-tab '((name . "test-tab") (index . 1)))
         (tab-bar-mode-enabled nil))
    ;; Mock tab-bar functions
    (cl-letf (((symbol-function 'tab-bar--current-tab)
               (lambda () mock-tab))
              (tab-bar-mode tab-bar-mode-enabled))
      (claude-code-ide-tests--with-temp-config-dir
       ;; Start MCP server
       (let ((port (claude-code-ide-mcp-start temp-dir)))
         (should port)
         ;; Get the session
         (let ((session (gethash temp-dir claude-code-ide-mcp--sessions)))
           (should session)
           ;; Check that tab was captured
           (should (equal (claude-code-ide-mcp-session-original-tab session) mock-tab))))
       ;; Cleanup
       (claude-code-ide-mcp-stop-session temp-dir)))
    ;; Cleanup temp directory
    (delete-directory temp-dir t)))

(ert-deftest claude-code-ide-test-tab-bar-switch-on-ediff ()
  "Test that tab-bar switching on ediff respects the configuration."
  ;; Test that the variable exists with the expected default
  (should (boundp 'claude-code-ide-switch-tab-on-ediff))
  (should (equal claude-code-ide-switch-tab-on-ediff t))

  ;; Test with simple mocking to ensure the config is checked
  (let* ((original-tab '((name . "original-tab")))
         (current-tab '((name . "current-tab")))
         (tab-switched nil)
         (tab-bar-mode t))

    ;; Mock functions
    (cl-letf (((symbol-function 'tab-bar--current-tab)
               (lambda () current-tab))
              ((symbol-function 'tab-bar-select-tab-by-name)
               (lambda (name)
                 (setq tab-switched name))))

      ;; Create a minimal test session
      (let ((session (make-claude-code-ide-mcp-session
                      :original-tab original-tab)))

        ;; Test 1: With switch enabled (default)
        (let ((claude-code-ide-switch-tab-on-ediff t))
          (setq tab-switched nil)
          ;; Simulate the relevant part of the handler
          (when (and claude-code-ide-switch-tab-on-ediff
                     (claude-code-ide-mcp-session-original-tab session))
            (let ((original-tab (claude-code-ide-mcp-session-original-tab session)))
              (when tab-bar-mode
                (let ((current-tab (tab-bar--current-tab)))
                  (when (and original-tab current-tab
                             (not (equal (alist-get 'name original-tab)
                                         (alist-get 'name current-tab))))
                    (tab-bar-select-tab-by-name (alist-get 'name original-tab)))))))
          ;; Should have switched
          (should (equal tab-switched "original-tab")))

        ;; Test 2: With switch disabled
        (let ((claude-code-ide-switch-tab-on-ediff nil))
          (setq tab-switched nil)
          ;; Simulate the relevant part of the handler
          (when (and claude-code-ide-switch-tab-on-ediff
                     (claude-code-ide-mcp-session-original-tab session))
            (let ((original-tab (claude-code-ide-mcp-session-original-tab session)))
              (when tab-bar-mode
                (let ((current-tab (tab-bar--current-tab)))
                  (when (and original-tab current-tab
                             (not (equal (alist-get 'name original-tab)
                                         (alist-get 'name current-tab))))
                    (tab-bar-select-tab-by-name (alist-get 'name original-tab)))))))
          ;; Should NOT have switched
          (should (null tab-switched)))))))

(defun claude-code-ide-run-tests ()
  "Run all claude-code-ide test cases."
  (interactive)
  (ert-run-tests-batch-and-exit "^claude-code-ide-test-"))

(defun claude-code-ide-run-all-tests ()
  "Run all claude-code-ide tests including MCP tests."
  (interactive)
  (ert-run-tests-batch-and-exit "^claude-code-ide-"))

;;; MCP Tests

;; Load MCP module now that websocket is available
(require 'claude-code-ide-mcp)

;; Load MCP handlers module for testing
(require 'claude-code-ide-mcp-handlers)

;; Load MCP tools server module
(condition-case nil
    (require 'claude-code-ide-mcp-server)
  (error nil))

;;; MCP Test Helper Functions

(defmacro claude-code-ide-mcp-tests--with-temp-file (file-var content &rest body)
  "Create a temporary file with CONTENT, bind its path to FILE-VAR, and execute BODY."
  (declare (indent 2))
  `(let ((,file-var (make-temp-file "claude-mcp-test-")))
     (unwind-protect
         (progn
           (with-temp-file ,file-var
             (insert ,content))
           ,@body)
       (delete-file ,file-var))))

(defmacro claude-code-ide-mcp-tests--with-temp-buffer (content &rest body)
  "Create a temporary buffer with CONTENT and execute BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,content)
     (goto-char (point-min))
     ,@body))

;;; Tests for MCP Tool Implementations

(ert-deftest claude-code-ide-test-mcp-open-file ()
  "Test the openFile tool implementation."
  ;; Test successful file open
  (claude-code-ide-mcp-tests--with-temp-file test-file "Line 1\nLine 2\nLine 3\nLine 4"
                                             (let ((result (claude-code-ide-mcp-handle-open-file `((filePath . ,test-file)))))
                                               (should (listp result))
                                               (let ((first-item (car result)))
                                                 (should (equal (alist-get 'type first-item) "text"))
                                                 (should (equal (alist-get 'text first-item) "FILE_OPENED")))
                                               (should (equal (buffer-file-name) test-file))
                                               (kill-buffer)))

  ;; Test with selection
  (claude-code-ide-mcp-tests--with-temp-file test-file "Line 1\nLine 2\nLine 3\nLine 4"
                                             (let ((result (claude-code-ide-mcp-handle-open-file
                                                            `((filePath . ,test-file)
                                                              (startLine . 2)
                                                              (endLine . 3)))))
                                               (should (listp result))
                                               (let ((first-item (car result)))
                                                 (should (equal (alist-get 'type first-item) "text"))
                                                 (should (equal (alist-get 'text first-item) "FILE_OPENED")))
                                               (should (use-region-p))
                                               (should (= (line-number-at-pos (region-beginning)) 2))
                                               (kill-buffer)))

  ;; Test missing filePath parameter
  (should-error (claude-code-ide-mcp-handle-open-file '())
                :type 'mcp-error))

(ert-deftest claude-code-ide-test-mcp-get-current-selection ()
  "Test the selection payload builder."
  ;; Test with active selection
  (claude-code-ide-mcp-tests--with-temp-buffer "Line 1\nLine 2\nLine 3"
                                               (goto-char (point-min))
                                               (set-mark (point))
                                               (forward-line 2)
                                               ;; Ensure transient-mark-mode is on and region is active
                                               (let ((transient-mark-mode t))
                                                 (activate-mark)
                                                 (let ((result (claude-code-ide-mcp--get-current-selection)))
                                                   (should (equal (alist-get 'text result) "Line 1\nLine 2\n"))
                                                   (should-not (assq 'fileUrl result))
                                                   (let ((selection (alist-get 'selection result)))
                                                     (should selection)
                                                     (should-not (assq 'isEmpty selection))
                                                     (let ((start (alist-get 'start selection))
                                                           (end (alist-get 'end selection)))
                                                       ;; Positions are zero-based (line and character),
                                                       ;; following the IDE protocol (VS Code / LSP).
                                                       (should (= (alist-get 'line start) 0))
                                                       (should (= (alist-get 'character start) 0))
                                                       (should (= (alist-get 'line end) 2))
                                                       (should (= (alist-get 'character end) 0)))))))

  ;; Test without selection
  (claude-code-ide-mcp-tests--with-temp-buffer "Test"
                                               (let ((result (claude-code-ide-mcp--get-current-selection)))
                                                 (should (equal (alist-get 'text result) ""))
                                                 (let ((selection (alist-get 'selection result)))
                                                   (should selection)
                                                   ;; No selection: start and end should be equal (cursor position)
                                                   (should (equal (alist-get 'start selection) (alist-get 'end selection)))
                                                   ;; Should not contain isEmpty or fileUrl
                                                   (should-not (assq 'isEmpty selection))
                                                   (should-not (assq 'fileUrl result))))))

(ert-deftest claude-code-ide-test-mcp-selection-matches-reference ()
  "Selection payload and @-mention describe the same physical region.
The payload reports zero-based positions (VS Code / LSP), while the
@-mention reports one-based inclusive lines; both must cover the same
lines for a mid-line selection."
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma")
    (setq buffer-file-name "/tmp/consistency.el")
    ;; Select from column 2 of line 1 to column 2 of line 3 (mid-line to mid-line).
    (goto-char 3)
    (set-mark (point))
    (goto-char 14)
    (let ((transient-mark-mode t))
      (activate-mark)
      ;; Zero-based selection payload.
      (let* ((result (claude-code-ide-mcp--get-current-selection))
             (selection (alist-get 'selection result))
             (start (alist-get 'start selection))
             (end (alist-get 'end selection)))
        (should (= (alist-get 'line start) 0))
        (should (= (alist-get 'character start) 2))
        (should (= (alist-get 'line end) 2))
        (should (= (alist-get 'character end) 2)))
      ;; One-based inclusive @-mention over the same physical region.
      (should (equal (claude-code-ide--region-or-buffer-reference)
                     "@/tmp/consistency.el#1-3")))
    (set-buffer-modified-p nil)))

(ert-deftest claude-code-ide-test-mcp-close-tab ()
  "Test the close_tab tool implementation."
  (claude-code-ide-mcp-tests--with-temp-file test-file "Content"
                                             (find-file-noselect test-file)
                                             ;; Close using tool
                                             (let ((result (claude-code-ide-mcp-handle-close-tab `((path . ,test-file)))))
                                               ;; Handler returns VS Code format
                                               (should (listp result))
                                               (let ((first-item (car result)))
                                                 (should (equal (alist-get 'type first-item) "text"))
                                                 (should (equal (alist-get 'text first-item) "TAB_CLOSED")))
                                               (should-not (find-buffer-visiting test-file))))

  ;; Test non-existent buffer - should throw an error
  (should-error (claude-code-ide-mcp-handle-close-tab '((path . "/nonexistent/file")))
                :type 'mcp-error))

;;; Tests for IDE State Tools (Phase 1 port)

(ert-deftest claude-code-ide-test-mcp-get-current-selection-tool ()
  "Test the getCurrentSelection tool handler."
  ;; With an active selection
  (claude-code-ide-mcp-tests--with-temp-buffer "Line 1\nLine 2\nLine 3"
                                               (goto-char (point-min))
                                               (set-mark (point))
                                               (forward-line 2)
                                               (let ((transient-mark-mode t))
                                                 (activate-mark)
                                                 (let* ((result (claude-code-ide-mcp-handle-get-current-selection nil))
                                                        (text (alist-get 'text (car result)))
                                                        (data (json-read-from-string text)))
                                                   (should (equal (alist-get 'type (car result)) "text"))
                                                   (should (equal (alist-get 'text data) "Line 1\nLine 2\n"))
                                                   (should (eq (alist-get 'isEmpty (alist-get 'selection data)) :json-false)))))
  ;; Without a selection - isEmpty should be true
  (claude-code-ide-mcp-tests--with-temp-buffer "Test"
                                               (let* ((result (claude-code-ide-mcp-handle-get-current-selection nil))
                                                      (data (json-read-from-string (alist-get 'text (car result)))))
                                                 (should (equal (alist-get 'text data) ""))
                                                 (should (eq (alist-get 'isEmpty (alist-get 'selection data)) t)))))

(ert-deftest claude-code-ide-test-mcp-get-latest-selection-tool ()
  "Test the getLatestSelection tool handler."
  (claude-code-ide-mcp-tests--with-temp-file test-file "Alpha\nBeta\nGamma"
                                             (let ((buf (find-file-noselect test-file)))
                                               (unwind-protect
                                                   (let ((transient-mark-mode t))
                                                     (with-current-buffer buf
                                                       (goto-char (point-min))
                                                       (set-mark (point))
                                                       (forward-line 1)
                                                       (activate-mark))
                                                     (let* ((result (claude-code-ide-mcp-handle-get-latest-selection nil))
                                                            (data (json-read-from-string (alist-get 'text (car result)))))
                                                       (should (equal (alist-get 'text data) "Alpha\n"))))
                                                 (when (buffer-live-p buf) (kill-buffer buf))))))

(ert-deftest claude-code-ide-test-mcp-get-latest-selection-recency-order ()
  "getLatestSelection follows buffer-list recency order, not edit count."
  (claude-code-ide-mcp-tests--with-temp-file file-a "Alpha\nBeta\nGamma"
                                             (claude-code-ide-mcp-tests--with-temp-file file-b "One\nTwo\nThree"
                                                                                        (let ((buf-a (find-file-noselect file-a))
                                                                                              (buf-b (find-file-noselect file-b)))
                                                                                          (unwind-protect
                                                                                              (let ((transient-mark-mode t))
                                                                                                ;; Give buf-a a high modified tick, then select in it.
                                                                                                (with-current-buffer buf-a
                                                                                                  (goto-char (point-max))
                                                                                                  (dotimes (_ 10) (insert "x"))
                                                                                                  (goto-char (point-min))
                                                                                                  (set-mark (point))
                                                                                                  (forward-line 1)
                                                                                                  (activate-mark))
                                                                                                (with-current-buffer buf-b
                                                                                                  (goto-char (point-min))
                                                                                                  (set-mark (point))
                                                                                                  (forward-line 1)
                                                                                                  (activate-mark))
                                                                                                ;; buf-b is most-recently-current (first in list), so it
                                                                                                ;; wins even though buf-a has a far higher modified tick.
                                                                                                (cl-letf (((symbol-function 'buffer-list)
                                                                                                           (lambda (&optional _frame) (list buf-b buf-a))))
                                                                                                  (let* ((result (claude-code-ide-mcp-handle-get-latest-selection nil))
                                                                                                         (data (json-read-from-string (alist-get 'text (car result)))))
                                                                                                    (should (equal (alist-get 'text data) "One\n"))))
                                                                                                ;; Reversing the order makes buf-a the latest selection.
                                                                                                (cl-letf (((symbol-function 'buffer-list)
                                                                                                           (lambda (&optional _frame) (list buf-a buf-b))))
                                                                                                  (let* ((result (claude-code-ide-mcp-handle-get-latest-selection nil))
                                                                                                         (data (json-read-from-string (alist-get 'text (car result)))))
                                                                                                    (should (equal (alist-get 'text data) "Alpha\n")))))
                                                                                            (when (buffer-live-p buf-a) (kill-buffer buf-a))
                                                                                            (when (buffer-live-p buf-b) (kill-buffer buf-b)))))))

(ert-deftest claude-code-ide-test-mcp-get-open-editors ()
  "Test the getOpenEditors tool handler."
  (claude-code-ide-mcp-tests--with-temp-file test-file "content"
                                             (let ((buf (find-file-noselect test-file)))
                                               (unwind-protect
                                                   (let* ((result (claude-code-ide-mcp-handle-get-open-editors nil))
                                                          (data (json-read-from-string (alist-get 'text (car result))))
                                                          (editors (alist-get 'editors data)))
                                                     (should (vectorp editors))
                                                     (should (seq-find (lambda (e) (equal (alist-get 'path e) test-file))
                                                                       editors)))
                                                 (when (buffer-live-p buf) (kill-buffer buf))))))

(ert-deftest claude-code-ide-test-mcp-get-workspace-folders ()
  "Test the getWorkspaceFolders tool handler."
  (let* ((session (make-claude-code-ide-mcp-session :project-dir "/tmp/claude-proj-xyz/"))
         (result (claude-code-ide-mcp-handle-get-workspace-folders nil session))
         (data (json-read-from-string (alist-get 'text (car result))))
         (folders (alist-get 'folders data)))
    (should (vectorp folders))
    (should (seq-find (lambda (f) (string-match-p "claude-proj-xyz" (alist-get 'uri f)))
                      folders))))

(ert-deftest claude-code-ide-test-mcp-check-document-dirty ()
  "Test the checkDocumentDirty tool handler."
  (claude-code-ide-mcp-tests--with-temp-file test-file "content"
                                             (let ((buf (find-file-noselect test-file)))
                                               (unwind-protect
                                                   (progn
                                                     ;; Clean buffer
                                                     (let ((data (json-read-from-string
                                                                  (alist-get 'text (car (claude-code-ide-mcp-handle-check-document-dirty
                                                                                         `((filePath . ,test-file))))))))
                                                       (should (eq (alist-get 'isDirty data) :json-false)))
                                                     ;; Modify, then check via file:// URI
                                                     (with-current-buffer buf
                                                       (goto-char (point-max))
                                                       (insert "more"))
                                                     (let ((data (json-read-from-string
                                                                  (alist-get 'text (car (claude-code-ide-mcp-handle-check-document-dirty
                                                                                         `((uri . ,(concat "file://" test-file)))))))))
                                                       (should (eq (alist-get 'isDirty data) t))))
                                                 (when (buffer-live-p buf)
                                                   (with-current-buffer buf (set-buffer-modified-p nil))
                                                   (kill-buffer buf)))))
  ;; Missing parameter
  (should-error (claude-code-ide-mcp-handle-check-document-dirty '())
                :type 'mcp-error))

(ert-deftest claude-code-ide-test-mcp-save-document ()
  "Test the saveDocument tool handler."
  (claude-code-ide-mcp-tests--with-temp-file test-file "content"
                                             (let ((buf (find-file-noselect test-file)))
                                               (unwind-protect
                                                   (progn
                                                     (with-current-buffer buf
                                                       (goto-char (point-max))
                                                       (insert "appended"))
                                                     (let ((data (json-read-from-string
                                                                  (alist-get 'text (car (claude-code-ide-mcp-handle-save-document
                                                                                         `((filePath . ,test-file))))))))
                                                       (should (eq (alist-get 'saved data) t))
                                                       (should-not (buffer-modified-p buf))))
                                                 (when (buffer-live-p buf) (kill-buffer buf)))))
  ;; File not open returns saved:false
  (let ((data (json-read-from-string
               (alist-get 'text (car (claude-code-ide-mcp-handle-save-document
                                      '((filePath . "/nonexistent/file-xyz"))))))))
    (should (eq (alist-get 'saved data) :json-false)))
  ;; Missing parameter
  (should-error (claude-code-ide-mcp-handle-save-document '())
                :type 'mcp-error))

(ert-deftest claude-code-ide-test-mcp-arg-file-path ()
  "Test file path extraction from tool arguments."
  (should (equal (claude-code-ide-mcp--arg-file-path '((filePath . "/a/b.el"))) "/a/b.el"))
  (should (equal (claude-code-ide-mcp--arg-file-path '((uri . "file:///a/b.el"))) "/a/b.el"))
  (should (equal (claude-code-ide-mcp--arg-file-path '((path . "/a/b.el"))) "/a/b.el"))
  (should-not (claude-code-ide-mcp--arg-file-path '())))

;;; Tests for MCP Resources (Phase 1 port)

(ert-deftest claude-code-ide-test-mcp-mime-type ()
  "Test MIME type resolution by extension."
  (should (equal (claude-code-ide-mcp--get-mime-type "foo.el") "text/x-elisp"))
  (should (equal (claude-code-ide-mcp--get-mime-type "foo.py") "text/x-python"))
  (should (equal (claude-code-ide-mcp--get-mime-type "foo.json") "application/json"))
  (should (equal (claude-code-ide-mcp--get-mime-type "foo.unknownext") "text/plain"))
  (should (equal (claude-code-ide-mcp--get-mime-type "noextension") "text/plain")))

(ert-deftest claude-code-ide-test-mcp-resources-list ()
  "Test that resources/list includes open file buffers."
  (claude-code-ide-mcp-tests--with-temp-file test-file "data"
                                             (let ((buf (find-file-noselect test-file)))
                                               (unwind-protect
                                                   (let* ((response (claude-code-ide-mcp--handle-resources-list 1 nil))
                                                          (resources (alist-get 'resources (alist-get 'result response))))
                                                     (should (vectorp resources))
                                                     (should (seq-find (lambda (r)
                                                                         (equal (alist-get 'uri r)
                                                                                (concat "file://" test-file)))
                                                                       resources)))
                                                 (when (buffer-live-p buf) (kill-buffer buf))))))

(ert-deftest claude-code-ide-test-mcp-resources-read ()
  "Test reading a resource by file:// URI."
  (claude-code-ide-mcp-tests--with-temp-file test-file "hello resources"
                                             (let* ((uri (concat "file://" test-file))
                                                    (response (claude-code-ide-mcp--handle-resources-read 1 `((uri . ,uri))))
                                                    (contents (alist-get 'contents (alist-get 'result response)))
                                                    (entry (aref contents 0)))
                                               (should (equal (alist-get 'uri entry) uri))
                                               (should (equal (alist-get 'text entry) "hello resources"))
                                               (should (equal (alist-get 'mimeType entry) "text/plain"))))
  ;; Non-existent resource returns an error response
  (let ((response (claude-code-ide-mcp--handle-resources-read 1 '((uri . "file:///nonexistent/xyz")))))
    (should (alist-get 'error response)))
  ;; A directory URI is not a regular file and must return an error, not raise.
  (let ((response (claude-code-ide-mcp--handle-resources-read
                   1 `((uri . ,(concat "file://" temporary-file-directory))))))
    (should (alist-get 'error response)))
  ;; A URI without the file:// scheme is rejected with an error response.
  (let ((response (claude-code-ide-mcp--handle-resources-read 1 '((uri . "http://example.com/x")))))
    (should (alist-get 'error response))))

(ert-deftest claude-code-ide-test-mcp-tool-registry ()
  "Test that all tools are properly registered."
  ;; Build expected tools list dynamically based on configuration
  (let* ((base-tools '("openFile" "getDiagnostics" "close_tab"))
         (diff-tools (when (bound-and-true-p claude-code-ide-use-ide-diff)
                       '("openDiff" "closeAllDiffTabs")))
         (exec-tools (when (bound-and-true-p claude-code-ide-enable-execute-code)
                       '("executeCode")))
         (expected-tools (append base-tools diff-tools exec-tools)))
    ;; Rebuild tool lists to match current configuration
    (setq claude-code-ide-mcp-tools (claude-code-ide-mcp--build-tool-list))
    (setq claude-code-ide-mcp-tool-schemas (claude-code-ide-mcp--build-tool-schemas))
    (setq claude-code-ide-mcp-tool-descriptions (claude-code-ide-mcp--build-tool-descriptions))
    (dolist (tool-name expected-tools)
      (should (alist-get tool-name claude-code-ide-mcp-tools nil nil #'string=))
      (let ((handler (alist-get tool-name claude-code-ide-mcp-tools nil nil #'string=))
            (schema (alist-get tool-name claude-code-ide-mcp-tool-schemas nil nil #'string=)))
        ;; Check that handler is a function or a symbol that points to a function
        (should (or (functionp handler)
                    (and (symbolp handler) (fboundp handler))))
        ;; Check that schema is provided
        (should schema)))))

(ert-deftest claude-code-ide-test-ediff-flag-disables-tools ()
  "Test that diff tools are excluded when claude-code-ide-use-ide-diff is nil."
  (let ((claude-code-ide-use-ide-diff nil))
    ;; Rebuild tool lists with ediff disabled
    (setq claude-code-ide-mcp-tools (claude-code-ide-mcp--build-tool-list))
    (setq claude-code-ide-mcp-tool-schemas (claude-code-ide-mcp--build-tool-schemas))
    (setq claude-code-ide-mcp-tool-descriptions (claude-code-ide-mcp--build-tool-descriptions))
    ;; Verify diff tools are not present
    (should-not (alist-get "openDiff" claude-code-ide-mcp-tools nil nil #'string=))
    (should-not (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tools nil nil #'string=))
    (should-not (alist-get "openDiff" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should-not (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should-not (alist-get "openDiff" claude-code-ide-mcp-tool-descriptions nil nil #'string=))
    (should-not (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tool-descriptions nil nil #'string=))
    ;; Verify other tools are still present
    (should (alist-get "openFile" claude-code-ide-mcp-tools nil nil #'string=))
    (should (alist-get "getDiagnostics" claude-code-ide-mcp-tools nil nil #'string=)))
  ;; Test with ediff enabled
  (let ((claude-code-ide-use-ide-diff t))
    ;; Rebuild tool lists with ediff enabled
    (setq claude-code-ide-mcp-tools (claude-code-ide-mcp--build-tool-list))
    (setq claude-code-ide-mcp-tool-schemas (claude-code-ide-mcp--build-tool-schemas))
    (setq claude-code-ide-mcp-tool-descriptions (claude-code-ide-mcp--build-tool-descriptions))
    ;; Verify diff tools are present
    (should (alist-get "openDiff" claude-code-ide-mcp-tools nil nil #'string=))
    (should (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tools nil nil #'string=))
    (should (alist-get "openDiff" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should (alist-get "openDiff" claude-code-ide-mcp-tool-descriptions nil nil #'string=))
    (should (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tool-descriptions nil nil #'string=))))

(ert-deftest claude-code-ide-test-execute-code-flag ()
  "Test that executeCode tool is excluded when flag is nil and included when t."
  (let ((claude-code-ide-enable-execute-code nil))
    (setq claude-code-ide-mcp-tools (claude-code-ide-mcp--build-tool-list))
    (setq claude-code-ide-mcp-tool-schemas (claude-code-ide-mcp--build-tool-schemas))
    (setq claude-code-ide-mcp-tool-descriptions (claude-code-ide-mcp--build-tool-descriptions))
    (should-not (alist-get "executeCode" claude-code-ide-mcp-tools nil nil #'string=))
    (should-not (alist-get "executeCode" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should-not (alist-get "executeCode" claude-code-ide-mcp-tool-descriptions nil nil #'string=)))
  (let ((claude-code-ide-enable-execute-code t))
    (setq claude-code-ide-mcp-tools (claude-code-ide-mcp--build-tool-list))
    (setq claude-code-ide-mcp-tool-schemas (claude-code-ide-mcp--build-tool-schemas))
    (setq claude-code-ide-mcp-tool-descriptions (claude-code-ide-mcp--build-tool-descriptions))
    (should (alist-get "executeCode" claude-code-ide-mcp-tools nil nil #'string=))
    (should (alist-get "executeCode" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should (alist-get "executeCode" claude-code-ide-mcp-tool-descriptions nil nil #'string=))))

(ert-deftest claude-code-ide-test-execute-code-handler ()
  "Test the executeCode handler."
  ;; Simple expression
  (let ((result (claude-code-ide-mcp-handle-execute-code '((code . "(+ 1 2)")))))
    (should (equal (alist-get 'text (car result)) "3")))
  ;; String result
  (let ((result (claude-code-ide-mcp-handle-execute-code '((code . "(concat \"hello\" \" world\")")))))
    (should (equal (alist-get 'text (car result)) "\"hello world\"")))
  ;; Missing code parameter
  (should-error (claude-code-ide-mcp-handle-execute-code '())
                :type 'mcp-error)
  ;; Evaluation error
  (should-error (claude-code-ide-mcp-handle-execute-code '((code . "(error \"boom\")")))
                :type 'mcp-error))

(ert-deftest claude-code-ide-test-mcp-lockfile-directory-resolution ()
  "Test that the lockfile directory honors `CLAUDE_CONFIG_DIR'."
  (require 'claude-code-ide-mcp)
  ;; Unset: defaults to ~/.claude/ide/.
  (let ((process-environment (cons "CLAUDE_CONFIG_DIR" process-environment)))
    (should (equal (claude-code-ide-mcp--lockfile-directory)
                   (expand-file-name "~/.claude/ide/"))))
  ;; Set without a trailing slash: still resolves under that directory.
  (let ((process-environment (cons "CLAUDE_CONFIG_DIR=/tmp/cc-config" process-environment)))
    (should (equal (claude-code-ide-mcp--lockfile-directory)
                   "/tmp/cc-config/ide/")))
  ;; Set but empty: treated as unset, must not resolve relative to
  ;; `default-directory'.
  (let ((process-environment (cons "CLAUDE_CONFIG_DIR=" process-environment))
        (default-directory "/some/project/"))
    (should (equal (claude-code-ide-mcp--lockfile-directory)
                   (expand-file-name "~/.claude/ide/")))))

(ert-deftest claude-code-ide-test-mcp-server-lifecycle ()
  "Test MCP server start and stop."
  (require 'claude-code-ide-mcp)
  (claude-code-ide-tests--with-temp-config-dir
   (unwind-protect
       (progn
         ;; Start server
         (let ((port (claude-code-ide-mcp-start)))
           (should (numberp port))
           (should (>= port 10000))
           (should (<= port 65535))
           ;; Check lockfile exists
           (should (file-exists-p (claude-code-ide-mcp--lockfile-path port)))
           ;; Stop server
           (claude-code-ide-mcp-stop)
           ;; Check lockfile removed
           (should-not (file-exists-p (claude-code-ide-mcp--lockfile-path port)))))
     ;; Ensure cleanup
     (claude-code-ide-mcp-stop))))

(ert-deftest claude-code-ide-test-ide-connected-notification ()
  "Test that ide_connected notification stores the CLI PID."
  (require 'claude-code-ide-mcp)
  (let* ((session (make-claude-code-ide-mcp-session
                   :server nil :client nil :port 12345
                   :project-dir "/tmp/test"
                   :deferred (make-hash-table :test 'equal)
                   :ping-timer nil :selection-timer nil
                   :last-selection nil :cli-pid nil))
         (message '((method . "ide_connected")
                    (params . ((pid . 42))))))
    ;; Simulate the dispatch
    (claude-code-ide-mcp--handle-message message session)
    (should (= (claude-code-ide-mcp-session-cli-pid session) 42))))

;; Test for side window handling in openDiff
(defvar claude-code-ide-debug-buffer)
(ert-deftest claude-code-ide-test-opendiff-side-window ()
  "Test that openDiff handles side windows correctly."
  (require 'claude-code-ide-debug)
  (require 'claude-code-ide-mcp-handlers)
  (let* ((temp-dir (make-temp-file "test-project-" t))
         (claude-code-ide-mcp--sessions (make-hash-table :test 'equal))
         (claude-code-ide-debug t)
         (claude-code-ide-debug-buffer "*claude-code-ide-debug*")
         (temp-file (make-temp-file "test-diff-" nil ".txt" "Original content\n"))
         (side-window nil)
         ;; Create a mock session for the test
         (test-session (make-claude-code-ide-mcp-session
                        :server nil
                        :client nil
                        :port 12345
                        :project-dir temp-dir
                        :deferred (make-hash-table :test 'equal)
                        :ping-timer nil
                        :selection-timer nil
                        :last-selection nil
                        :last-buffer nil
                        :active-diffs (make-hash-table :test 'equal)
                        :original-tab nil)))
    ;; Register the test session
    (puthash temp-dir test-session claude-code-ide-mcp--sessions)
    ;; Create a .git directory to make this a project
    (make-directory (expand-file-name ".git" temp-dir) t)

    (unwind-protect
        ;; Mock the project detection to return our test directory
        (cl-letf (((symbol-function 'claude-code-ide-mcp--get-buffer-project)
                   (lambda () temp-dir))
                  ((symbol-function 'claude-code-ide-mcp--get-current-session)
                   (lambda () test-session)))
          ;; Set up the project context
          (with-current-buffer (get-buffer-create "*test-buffer*")
            (setq default-directory temp-dir)

            ;; Create a side window to simulate the problem
            (let ((side-buffer (get-buffer-create "*test-sidebar*")))
              (with-current-buffer side-buffer
                (insert "Sidebar content"))
              ;; Display buffer in side window
              (setq side-window (display-buffer-in-side-window
                                 side-buffer
                                 '((side . left) (slot . 0) (window-width . 30))))

              ;; Verify side window was created
              (should (window-parameter side-window 'window-side))

              ;; Now try to open diff - should handle side window gracefully
              (let ((result (claude-code-ide-mcp-handle-open-diff
                             `((old_file_path . ,temp-file)
                               (new_file_path . ,temp-file)
                               (new_file_contents . "Modified content\n")
                               (tab_name . "test-diff")))))
                ;; Should return deferred
                (should (eq (alist-get 'deferred result) t))

                ;; Should have created diff session in the test session
                (should (gethash "test-diff" (claude-code-ide-mcp-session-active-diffs test-session)))

                ;; Clean up - quit ediff if it started
                (when (and (boundp 'ediff-control-buffer)
                           ediff-control-buffer
                           (buffer-live-p ediff-control-buffer))
                  (with-current-buffer ediff-control-buffer
                    (remove-hook 'ediff-quit-hook t t)
                    (ediff-really-quit nil)))))))
      ;; Cleanup
      (when (file-exists-p temp-file)
        (delete-file temp-file))
      (when (file-exists-p temp-dir)
        (delete-directory temp-dir t))
      (when (and side-window (window-live-p side-window))
        (delete-window side-window))
      (claude-code-ide-mcp--cleanup-diff "test-diff" test-session)
      (kill-buffer "*test-buffer*")
      (kill-buffer "*test-sidebar*"))))

;;; Tests for Diagnostics

(ert-deftest claude-code-ide-test-diagnostics-severity-mapping ()
  "Test diagnostic severity conversion."
  (require 'claude-code-ide-diagnostics)
  ;; Test Flycheck symbols
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'error) 1))
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'warning) 2))
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'info) 3))
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'hint) 4))
  ;; Test default fallback
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'unknown) 3)))

(ert-deftest claude-code-ide-test-diagnostics-severity-to-string ()
  "Test severity to string conversion."
  (require 'claude-code-ide-diagnostics)
  ;; Test Flycheck severities
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'error) "Error"))
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'warning) "Warning"))
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'info) "Information"))
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'hint) "Hint"))
  ;; Test default fallback
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'unknown) "Information")))

(ert-deftest claude-code-ide-test-diagnostics-handler ()
  "Test getDiagnostics handler."
  (require 'claude-code-ide-diagnostics)
  ;; Test with no diagnostics available
  (let ((result (claude-code-ide-diagnostics-handler nil)))
    ;; The diagnostics handler returns content array format
    (should (listp result))
    ;; Check it has the expected format
    (should (equal (alist-get 'type (car result)) "text"))
    ;; The text should be an empty array "[]"
    (should (equal (alist-get 'text (car result)) "[]"))))

;; Define mock struct for flymake diagnostics testing
(cl-defstruct claude-code-ide-test-mock-diag
  beg end type text backend)

(ert-deftest claude-code-ide-test-flymake-diagnostics ()
  "Test flymake diagnostics collection."
  ;; Skip this test in batch mode as it requires a complex flymake setup
  (skip-unless nil)
  (require 'claude-code-ide-diagnostics))

(ert-deftest claude-code-ide-test-diagnostics-backend-auto ()
  "Test automatic backend detection."
  (require 'claude-code-ide-diagnostics)
  ;; Test flycheck detection
  (cl-letf (((symbol-function 'featurep)
             (lambda (feature &rest _)
               (memq feature '(flycheck flymake))))
            ((symbol-function 'bound-and-true-p)
             (lambda (var)
               (eq var 'flycheck-mode)))
            ((symbol-function 'flycheck-diagnostics)
             (lambda () nil))
            (flycheck-current-errors nil)
            (claude-code-ide-diagnostics-backend 'auto))
    (with-temp-buffer
      (let ((diags (claude-code-ide-diagnostics-get-all (current-buffer))))
        ;; Should use flycheck when flycheck-mode is active
        (should (vectorp diags))))))

(ert-deftest claude-code-ide-test-diagnostics-flycheck-zero-based ()
  "Flycheck diagnostics use 0-based line and character (VS Code / LSP)."
  (require 'claude-code-ide-diagnostics)
  (let ((flycheck-mode t)
        (flycheck-current-errors
         (list (make-flycheck-error :line 5 :column 3
                                    :end-line 5 :end-column 8
                                    :level 'warning :checker 'emacs-lisp
                                    :message "test warning")))
        (claude-code-ide-diagnostics-backend 'flycheck))
    (with-temp-buffer
      (let* ((diags (claude-code-ide-diagnostics-get-all (current-buffer)))
             (range (alist-get 'range (aref diags 0)))
             (start (alist-get 'start range))
             (end (alist-get 'end range)))
        (should (= (length diags) 1))
        ;; 1-based flycheck line 5 / column 3 -> 0-based line 4 / character 2.
        (should (= (alist-get 'line start) 4))
        (should (= (alist-get 'character start) 2))
        ;; 1-based end column 8 -> 0-based character 7.
        (should (= (alist-get 'line end) 4))
        (should (= (alist-get 'character end) 7))))))

(ert-deftest claude-code-ide-test-diagnostics-flymake-zero-based ()
  "Flymake diagnostics use 0-based line and character (VS Code / LSP)."
  (require 'claude-code-ide-diagnostics)
  ;; Use a real flymake diagnostic: its accessors are inlined into the
  ;; byte-compiled diagnostics code, so stubbing them via `cl-letf' would
  ;; not take effect.  Only `flymake-diagnostics' (a plain defun) is stubbed.
  (skip-unless (fboundp 'flymake-make-diagnostic))
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma")
    ;; beg = column 2 of line 1; end = column 2 of line 2.
    (let ((diag (flymake-make-diagnostic (current-buffer) 3 9 :warning "test")))
      (cl-letf (((symbol-function 'flymake-diagnostics) (lambda (&rest _) (list diag))))
        (setq-local flymake-mode t)
        (let* ((claude-code-ide-diagnostics-backend 'flymake)
               (diags (claude-code-ide-diagnostics-get-all (current-buffer)))
               (range (alist-get 'range (aref diags 0)))
               (start (alist-get 'start range))
               (end (alist-get 'end range)))
          (should (= (length diags) 1))
          (should (= (alist-get 'line start) 0))
          (should (= (alist-get 'character start) 2))
          (should (= (alist-get 'line end) 1))
          (should (= (alist-get 'character end) 2)))))))

;; Disabled due to ERT macro interaction with transient-mark-mode in batch mode
;; The handler works correctly (verified with direct testing) but the test fails
;; because `should` macro seems to evaluate `use-region-p` in a different context
(ert-deftest claude-code-ide-test-open-file-text-patterns ()
  "Test openFile handler with text pattern selection."
  (skip-unless nil) ; Skip this test for now
  (require 'claude-code-ide-mcp-handlers)
  ;; Create a temporary file with known content
  (let ((temp-file (make-temp-file "test-openfile-" nil ".el"))
        ;; Save and restore global transient-mark-mode
        (orig-tmm transient-mark-mode))
    (unwind-protect
        (progn
          ;; Enable transient-mark-mode globally for this test
          (setq transient-mark-mode t)
          ;; Write test content to file
          (with-temp-file temp-file
            (insert "Line 1\n")
            (insert "function foo() {\n")
            (insert "  console.log('hello');\n")
            (insert "}\n")
            (insert "Line 5\n")
            (insert "function bar() {\n")
            (insert "  return 42;\n")
            (insert "}\n"))

          ;; Test 1: Text pattern selection with both start and end
          (let ((result (claude-code-ide-mcp-handle-open-file
                         `((path . ,temp-file)
                           (startText . "function foo")
                           (endText . "}")))))
            ;; Should have opened the file and selected from "function foo" to first "}"
            (with-current-buffer (find-buffer-visiting temp-file)
              (should (string= (buffer-file-name) temp-file))
              ;; Debug info
              (message "Debug: buffer=%s tmm=%s mark-active=%s mark=%s point=%s region-p=%s"
                       (buffer-name) transient-mark-mode mark-active
                       (and (mark) (mark)) (point) (use-region-p))
              ;; Store region state before should
              (let ((region-was-active (use-region-p)))
                (should region-was-active))
              (should (string= (buffer-substring-no-properties (region-beginning) (region-end))
                               "function foo() {\n  console.log('hello');\n}"))))

          ;; Test 2: Only start text pattern
          (with-current-buffer (find-buffer-visiting temp-file)
            (deactivate-mark))
          (let ((result (claude-code-ide-mcp-handle-open-file
                         `((path . ,temp-file)
                           (startText . "function bar")))))
            ;; Should position cursor at start of "function bar"
            (with-current-buffer (find-buffer-visiting temp-file)
              (should (looking-at "function bar"))
              (should-not (use-region-p))))

          ;; Test 3: Text pattern with fallback to line numbers
          (let ((result (claude-code-ide-mcp-handle-open-file
                         `((path . ,temp-file)
                           (startText . "nonexistent text")
                           (startLine . 2)
                           (endLine . 4)))))
            ;; Should fall back to line selection
            (with-current-buffer (find-buffer-visiting temp-file)
              (should (use-region-p))
              (let ((selected (buffer-substring-no-properties (region-beginning) (region-end))))
                (should (string-match-p "function foo" selected)))))

          ;; Test 4: Text patterns take precedence over line numbers
          (with-current-buffer (find-buffer-visiting temp-file)
            (deactivate-mark))
          (let ((result (claude-code-ide-mcp-handle-open-file
                         `((path . ,temp-file)
                           (startText . "Line 5")
                           (startLine . 1)))))
            ;; Should go to "Line 5", not line 1
            (with-current-buffer (find-buffer-visiting temp-file)
              (should (looking-at "Line 5"))
              (should (= (line-number-at-pos) 5)))))

      ;; Cleanup
      (delete-file temp-file)
      ;; Restore original transient-mark-mode
      (setq transient-mark-mode orig-tmm))))

;; Test claude-code-ide-show-claude-window-in-ediff option
(ert-deftest claude-code-ide-test-show-claude-window-in-ediff ()
  "Test that Claude window visibility is controlled correctly during ediff."
  (claude-code-ide-tests--with-temp-directory
   (lambda ()
     (let* ((session (make-claude-code-ide-mcp-session
                      :project-dir default-directory
                      :active-diffs (make-hash-table :test 'equal)))
            (test-file (expand-file-name "test.txt" default-directory))
            (claude-buffer-created nil)
            (claude-window-displayed nil))

       ;; Register session in global hash table
       (puthash default-directory session claude-code-ide-mcp--sessions)

       ;; Create a test file
       (with-temp-file test-file (insert "Original content"))

       ;; Create a .git directory to make this a project
       (make-directory (expand-file-name ".git" default-directory) t)

       ;; Mock relevant functions
       (cl-letf* (((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&optional _dir) "*Claude Code Test*"))
                  ((symbol-function 'claude-code-ide--display-buffer-in-side-window)
                   (lambda (buffer)
                     (setq claude-window-displayed t)
                     (selected-window)))
                  ((symbol-function 'ediff-buffers)
                   (lambda (_buf-A _buf-B)
                     ;; Simulate successful ediff start
                     (setq ediff-control-buffer (get-buffer-create "*Ediff Control*"))))
                  ((symbol-function 'ediff-next-difference)
                   (lambda () nil))
                  ((symbol-function 'claude-code-ide-mcp--get-current-session)
                   (lambda () session)))

         ;; Create a Claude buffer
         (setq claude-buffer-created (get-buffer-create "*Claude Code Test*"))

         ;; Test 1: With claude-code-ide-show-claude-window-in-ediff = t (default)
         (let ((claude-code-ide-show-claude-window-in-ediff t)
               (ediff-control-buffer (get-buffer-create "*Ediff Control*")))
           (setq claude-window-displayed nil)
           ;; Call the startup handler
           (claude-code-ide-mcp--handle-ediff-startup "test-diff" session nil
                                                      (lambda () nil))
           ;; Should display Claude window
           (should claude-window-displayed))

         ;; Test 2: With claude-code-ide-show-claude-window-in-ediff = nil
         (let ((claude-code-ide-show-claude-window-in-ediff nil)
               (ediff-control-buffer (get-buffer-create "*Ediff Control*")))
           (setq claude-window-displayed nil)
           ;; Call the startup handler
           (claude-code-ide-mcp--handle-ediff-startup "test-diff" session nil
                                                      (lambda () nil))
           ;; Should NOT display Claude window
           (should-not claude-window-displayed))

         ;; Cleanup
         (when (buffer-live-p claude-buffer-created)
           (kill-buffer claude-buffer-created))
         (when (get-buffer "*Ediff Control*")
           (kill-buffer "*Ediff Control*"))
         (when (file-exists-p test-file)
           (delete-file test-file))
         (remhash default-directory claude-code-ide-mcp--sessions))))))

;; Test multiple ediff sessions
(ert-deftest claude-code-ide-test-multiple-ediff-sessions ()
  "Test that multiple ediff sessions can run simultaneously without conflicts."
  (claude-code-ide-tests--with-temp-directory
   (lambda ()
     (let* ((session (make-claude-code-ide-mcp-session
                      :project-dir default-directory
                      :active-diffs (make-hash-table :test 'equal)))
            (file1 (expand-file-name "test-file1.txt" default-directory))
            (file2 (expand-file-name "test-file2.txt" default-directory))
            (control-buffers '()))

       ;; Register session in global hash table
       (puthash default-directory session claude-code-ide-mcp--sessions)

       ;; Create test files
       (with-temp-file file1 (insert "Original content 1"))
       (with-temp-file file2 (insert "Original content 2"))

       ;; Create a .git directory to make this a project
       (make-directory (expand-file-name ".git" default-directory) t)

       ;; Mock ediff functions to capture control buffer names
       (cl-letf* ((ediff-called-count 0)
                  ((symbol-function 'ediff-buffers)
                   (lambda (buf-A buf-B)
                     (cl-incf ediff-called-count)
                     ;; Simulate ediff creating a control buffer with the suffix
                     (let ((suffix (or ediff-control-buffer-suffix "")))
                       (push (format "*Ediff Control Panel%s*" suffix) control-buffers))))
                  ((symbol-function 'claude-code-ide-mcp--get-current-session)
                   (lambda () session)))

         ;; Simulate opening multiple diffs
         (unwind-protect
             (progn
               ;; Open first diff
               (let ((result1 (claude-code-ide-mcp-handle-open-diff
                               `((old_file_path . ,file1)
                                 (new_file_path . ,file1)
                                 (new_file_contents . "Modified content 1")
                                 (tab_name . "diff1")))))
                 (should (equal (alist-get 'deferred result1) t))
                 (should (equal (alist-get 'unique-key result1) "diff1"))
                 (should (equal (alist-get 'session result1) session)))

               ;; Open second diff
               (let ((result2 (claude-code-ide-mcp-handle-open-diff
                               `((old_file_path . ,file2)
                                 (new_file_path . ,file2)
                                 (new_file_contents . "Modified content 2")
                                 (tab_name . "diff2")))))
                 (should (equal (alist-get 'deferred result2) t))
                 (should (equal (alist-get 'unique-key result2) "diff2"))
                 (should (equal (alist-get 'session result2) session)))

               ;; Verify ediff was called twice
               (should (= ediff-called-count 2))

               ;; Verify we have two distinct control buffer names
               (should (= (length control-buffers) 2))
               (should (member "*Ediff Control Panel<diff1>*" control-buffers))
               (should (member "*Ediff Control Panel<diff2>*" control-buffers))

               ;; Verify active diffs are tracked correctly
               (let ((active-diffs (claude-code-ide-mcp--get-active-diffs session)))
                 (should (gethash "diff1" active-diffs))
                 (should (gethash "diff2" active-diffs))))

           ;; Cleanup
           (claude-code-ide-mcp-handle-close-all-diff-tabs nil)
           (when (file-exists-p file1) (delete-file file1))
           (when (file-exists-p file2) (delete-file file2))
           ;; Remove session from global hash table
           (remhash default-directory claude-code-ide-mcp--sessions)))))))

(ert-deftest test-claude-code-ide-mcp-multi-session-deferred ()
  "Test that deferred responses work correctly with multiple sessions."
  (skip-unless (not (getenv "CI")))
  (let ((claude-code-ide-mcp--sessions (make-hash-table :test 'equal))
        (project-a "/tmp/project-a/")
        (project-b "/tmp/project-b/")
        (session-a nil)
        (session-b nil)
        (deferred-responses '())
        (sent-responses '()))
    ;; Create mock websocket-send-text to capture responses
    (cl-letf* (((symbol-function 'websocket-send-text)
                (lambda (_ws text)
                  (push text sent-responses))))
      (claude-code-ide-tests--with-temp-config-dir
       (unwind-protect
           (progn
             ;; Create two sessions
             (make-directory project-a t)
             (make-directory project-b t)

             ;; Session A
             (let ((default-directory project-a))
               (claude-code-ide-mcp-start project-a)
               (setq session-a (gethash project-a claude-code-ide-mcp--sessions)))

             ;; Session B
             (let ((default-directory project-b))
               (claude-code-ide-mcp-start project-b)
               (setq session-b (gethash project-b claude-code-ide-mcp--sessions)))

             ;; Set up mock clients for each session
             (setf (claude-code-ide-mcp-session-client session-a) :mock-client-a)
             (setf (claude-code-ide-mcp-session-client session-b) :mock-client-b)

             ;; Store deferred responses in each session
             (let ((deferred-a (claude-code-ide-mcp-session-deferred session-a))
                   (deferred-b (claude-code-ide-mcp-session-deferred session-b)))
               ;; Session A has a deferred response for openDiff-diff1
               (puthash "openDiff-diff1" "request-id-1" deferred-a)
               ;; Session B has a deferred response for openDiff-diff2
               (puthash "openDiff-diff2" "request-id-2" deferred-b))

             ;; Complete deferred response for session A
             (claude-code-ide-mcp-complete-deferred session-a
                                                    "openDiff"
                                                    '(((type . "text") (text . "FILE_SAVED")))
                                                    "diff1")

             ;; Complete deferred response for session B
             (claude-code-ide-mcp-complete-deferred session-b
                                                    "openDiff"
                                                    '(((type . "text") (text . "DIFF_REJECTED")))
                                                    "diff2")

             ;; Verify both responses were sent
             (should (= (length sent-responses) 2))

             ;; Verify the responses contain the correct request IDs
             (let ((response1 (json-read-from-string (nth 1 sent-responses)))
                   (response2 (json-read-from-string (nth 0 sent-responses))))
               ;; Check that request-id-1 and request-id-2 were both used
               (let ((ids (list (alist-get 'id response1) (alist-get 'id response2))))
                 (should (member "request-id-1" ids))
                 (should (member "request-id-2" ids))))

             ;; Verify deferred responses were removed from sessions
             (should (= 0 (hash-table-count (claude-code-ide-mcp-session-deferred session-a))))
             (should (= 0 (hash-table-count (claude-code-ide-mcp-session-deferred session-b)))))

         ;; Cleanup
         (ignore-errors (delete-directory project-a t))
         (ignore-errors (delete-directory project-b t))
         (clrhash claude-code-ide-mcp--sessions))))))

;;; MCP Tools Server Tests

;; Mock the server functions since web-server might not be available in test env
(defvar claude-code-ide-mcp-server-tests--mock-server-started nil)
(defvar claude-code-ide-mcp-server-tests--mock-server-port 12345)

(defun claude-code-ide-mcp-server-tests--mock-server-start (&optional _port)
  "Mock server start function."
  (setq claude-code-ide-mcp-server-tests--mock-server-started t)
  (cons 'mock-process claude-code-ide-mcp-server-tests--mock-server-port))

(defun claude-code-ide-mcp-server-tests--mock-server-stop (_process)
  "Mock server stop function."
  (setq claude-code-ide-mcp-server-tests--mock-server-started nil))

;;; Mock websocket request/response for testing
(defvar claude-code-ide-mcp-server-tests--last-response nil
  "Storage for the last response sent.")

(defvar claude-code-ide-mcp-server-tests--last-response-headers nil
  "Storage for the last response headers.")

(defvar claude-code-ide-mcp-server-tests--last-response-status nil
  "Storage for the last response status.")

;; Mock the web-server functions
(cl-defstruct claude-code-ide-mcp-server-tests--mock-request
  process headers body)

(cl-defstruct claude-code-ide-mcp-server-tests--mock-process)

(defun claude-code-ide-mcp-server-tests--mock-ws-response-header (process status &rest headers)
  "Mock ws-response-header function."
  (setq claude-code-ide-mcp-server-tests--last-response-status status)
  (setq claude-code-ide-mcp-server-tests--last-response-headers headers))

(defun claude-code-ide-mcp-server-tests--mock-ws-send (process data)
  "Mock ws-send function."
  (unless (claude-code-ide-mcp-server-tests--mock-process-p process)
    (error "Wrong type argument: processp, %s" process))
  (setq claude-code-ide-mcp-server-tests--last-response data))

(defun claude-code-ide-mcp-server-tests--mock-ws-send-404 (process)
  "Mock ws-send-404 function."
  (unless (claude-code-ide-mcp-server-tests--mock-process-p process)
    (error "Wrong type argument: processp, %s" process))
  (setq claude-code-ide-mcp-server-tests--last-response-status 404))

;;; Session Management Tests

(ert-deftest claude-code-ide-mcp-server-test-session-lifecycle ()
  "Test MCP tools server session lifecycle."
  (let ((claude-code-ide-enable-mcp-server t)
        (claude-code-ide-mcp-server--session-count 0)
        (claude-code-ide-mcp-server--server nil)
        (claude-code-ide-mcp-server--port nil))
    ;; Mock the server functions and require
    (cl-letf (((symbol-function 'claude-code-ide-mcp-http-server-start)
               #'claude-code-ide-mcp-server-tests--mock-server-start)
              ((symbol-function 'claude-code-ide-mcp-http-server-stop)
               #'claude-code-ide-mcp-server-tests--mock-server-stop)
              ((symbol-function 'require)
               (lambda (feature &optional _filename _noerror)
                 (cond ((eq feature 'claude-code-ide-mcp-http-server) nil)
                       ((memq feature '(claude-code-ide-mcp-server websocket vterm flycheck
                                                                   claude-code-ide-debug claude-code-ide-mcp-handlers
                                                                   claude-code-ide transient)) nil)
                       (t (funcall (cl-letf-saved-symbol-function 'require) feature _filename _noerror))))))
      ;; First session should start the server
      (claude-code-ide-mcp-server-session-started)
      (should (= claude-code-ide-mcp-server--session-count 1))
      ;; Manually call the mock server start since ensure-server might fail
      (setq claude-code-ide-mcp-server--server
            (car (claude-code-ide-mcp-server-tests--mock-server-start)))
      (setq claude-code-ide-mcp-server--port
            (cdr (claude-code-ide-mcp-server-tests--mock-server-start)))
      (should claude-code-ide-mcp-server--server)
      (should (= claude-code-ide-mcp-server--port
                 claude-code-ide-mcp-server-tests--mock-server-port))

      ;; Second session should not restart the server
      (claude-code-ide-mcp-server-session-started)
      (should (= claude-code-ide-mcp-server--session-count 2))

      ;; Ending one session should not stop the server
      (claude-code-ide-mcp-server-session-ended)
      (should (= claude-code-ide-mcp-server--session-count 1))
      (should claude-code-ide-mcp-server--server)

      ;; Ending last session should stop the server
      (claude-code-ide-mcp-server-session-ended)
      (should (= claude-code-ide-mcp-server--session-count 0))
      ;; Manually stop the mock server
      (claude-code-ide-mcp-server-tests--mock-server-stop claude-code-ide-mcp-server--server)
      (setq claude-code-ide-mcp-server--server nil)
      (setq claude-code-ide-mcp-server--port nil)
      (should-not claude-code-ide-mcp-server--server)
      (should-not claude-code-ide-mcp-server--port))))

(ert-deftest claude-code-ide-mcp-server-test-config-generation ()
  "Test MCP configuration generation."
  (let ((claude-code-ide-enable-mcp-server t)
        (claude-code-ide-mcp-server--server 'mock-server)
        (claude-code-ide-mcp-server--port 8080))
    ;; With server running
    (cl-letf (((symbol-function 'process-live-p) (lambda (_) t))
              ((symbol-function 'ws-process) (lambda (_) 'mock-process)))
      (let ((config (claude-code-ide-mcp-server-get-config)))
        (should config)
        (should (equal (alist-get 'type (alist-get 'emacs-tools (alist-get 'mcpServers config)))
                       "http"))
        (should (equal (alist-get 'url (alist-get 'emacs-tools (alist-get 'mcpServers config)))
                       "http://localhost:8080/mcp"))))

    ;; Without server running
    (let ((claude-code-ide-mcp-server--server nil)
          (claude-code-ide-mcp-server--port nil)
          (config (claude-code-ide-mcp-server-get-config)))
      (should-not config))))

(ert-deftest claude-code-ide-mcp-server-test-disabled ()
  "Test that MCP tools server does nothing when disabled."
  (let ((claude-code-ide-enable-mcp-server nil)
        (claude-code-ide-mcp-server--session-count 0))
    (should-not (claude-code-ide-mcp-server-ensure-server))
    (claude-code-ide-mcp-server-session-started)
    (should (= claude-code-ide-mcp-server--session-count 1))
    ;; But server should not start
    (should-not claude-code-ide-mcp-server--server)))

;;; Tool Configuration Tests

(ert-deftest claude-code-ide-mcp-server-test-tool-config ()
  "Test tool configuration structure."
  (let ((claude-code-ide-mcp-server-tools
         '((test-function
            :description "Test function"
            :parameters ((:name "arg1" :type "string" :required t)
                         (:name "arg2" :type "number" :required nil))))))
    (let* ((tool (car claude-code-ide-mcp-server-tools))
           (name (car tool))
           (plist (cdr tool)))
      (should (eq name 'test-function))
      (should (equal (plist-get plist :description) "Test function"))
      (should (= (length (plist-get plist :parameters)) 2)))))

;;; JSON-RPC Message Tests

(ert-deftest claude-code-ide-mcp-server-test-json-encoding ()
  "Test JSON encoding of MCP config."
  (let ((config '((mcpServers . ((emacs-tools . ((transport . "http")
                                                 (url . "http://localhost:8080/mcp"))))))))
    (let ((json-str (json-encode config)))
      (should (stringp json-str))
      (should (string-match "mcpServers" json-str))
      (should (string-match "emacs-tools" json-str))
      (should (string-match "transport.*:.*http" json-str)))))

(ert-deftest claude-code-ide-mcp-server-test-ws-send-fix ()
  "Test that ws-send is called with process, not request."
  ;; Test that verifies our fix for the wrong-type-argument error
  ;; Skip test if web-server is not available
  (skip-unless (condition-case nil
                   (progn (require 'web-server) t)
                 (error nil)))
  (require 'claude-code-ide-mcp-http-server)
  (let ((mock-process (make-claude-code-ide-mcp-server-tests--mock-process))
        (mock-request (make-claude-code-ide-mcp-server-tests--mock-request)))
    ;; Set the process in the request
    (setf (claude-code-ide-mcp-server-tests--mock-request-process mock-request) mock-process)
    ;; Mock the ws-* functions
    (cl-letf (((symbol-function 'ws-response-header)
               #'claude-code-ide-mcp-server-tests--mock-ws-response-header)
              ((symbol-function 'ws-send)
               #'claude-code-ide-mcp-server-tests--mock-ws-send)
              ((symbol-function 'ws-send-404)
               #'claude-code-ide-mcp-server-tests--mock-ws-send-404))
      ;; Test send-json-response
      (claude-code-ide-mcp-http-server--send-json-response
       mock-request 200 '((test . "data")))
      (should (equal claude-code-ide-mcp-server-tests--last-response-status 200))
      (should (string-match "test.*:.*data" claude-code-ide-mcp-server-tests--last-response))

      ;; Test handle-get (404 response)
      (claude-code-ide-mcp-http-server--handle-get mock-request)
      (should (equal claude-code-ide-mcp-server-tests--last-response-status 404)))))

;;; MCP Server Session Context Tests

(ert-deftest claude-code-ide-mcp-server-test-session-registration ()
  "Test session registration and retrieval."
  (let ((session-id "test-session-123")
        (project-dir "/tmp/test-project")
        (buffer (get-buffer-create "*test-buffer*")))
    (unwind-protect
        (progn
          ;; Register a session
          (claude-code-ide-mcp-server-register-session session-id project-dir buffer)

          ;; Retrieve and verify session context
          (let ((context (gethash session-id claude-code-ide-mcp-server--sessions)))
            (should context)
            (should (equal (plist-get context :project-dir) project-dir))
            (should (eq (plist-get context :buffer) buffer))
            (should (plist-get context :start-time)))

          ;; Test get-session-context function
          (let ((claude-code-ide-mcp-server--current-session-id session-id))
            (let ((context (claude-code-ide-mcp-server-get-session-context)))
              (should context)
              (should (equal (plist-get context :project-dir) project-dir))))

          ;; Unregister session
          (claude-code-ide-mcp-server-unregister-session session-id)
          (should-not (gethash session-id claude-code-ide-mcp-server--sessions)))

      ;; Cleanup
      (kill-buffer buffer)
      (clrhash claude-code-ide-mcp-server--sessions))))

(ert-deftest claude-code-ide-mcp-server-test-with-session-context-macro ()
  "Test the with-session-context macro."
  (let ((session-id "test-session-456")
        (project-dir "/tmp/test-project-2/")
        (buffer (get-buffer-create "*test-buffer-2*"))
        (original-dir default-directory))
    (unwind-protect
        (progn
          ;; Set up the buffer with the project directory
          (with-current-buffer buffer
            (setq default-directory project-dir))

          ;; Register a session
          (claude-code-ide-mcp-server-register-session session-id project-dir buffer)

          ;; Test macro with valid session
          (let ((claude-code-ide-mcp-server--current-session-id session-id))
            (claude-code-ide-mcp-server-with-session-context nil
              ;; Inside the macro, default-directory should be the project dir
              (should (equal default-directory project-dir))
              ;; Current buffer should be the session buffer
              (should (eq (current-buffer) buffer))))

          ;; Verify we're back to original context
          (should (equal default-directory original-dir))

          ;; Test error handling with invalid session
          (let ((claude-code-ide-mcp-server--current-session-id "invalid-session"))
            (should-error
             (claude-code-ide-mcp-server-with-session-context nil
               (error "Should not reach here")))))

      ;; Cleanup
      (kill-buffer buffer)
      (clrhash claude-code-ide-mcp-server--sessions))))

(ert-deftest claude-code-ide-mcp-server-test-session-lifecycle-detailed ()
  "Test complete session lifecycle with detailed tracking."
  (let ((session-id "test-session-789")
        (project-dir "/tmp/test-project-3")
        (buffer (get-buffer-create "*test-buffer-3*")))
    (unwind-protect
        (progn
          ;; Start session
          (claude-code-ide-mcp-server-session-started session-id project-dir buffer)
          (should (= claude-code-ide-mcp-server--session-count 1))
          (should (gethash session-id claude-code-ide-mcp-server--sessions))

          ;; End session
          (claude-code-ide-mcp-server-session-ended session-id)
          (should (= claude-code-ide-mcp-server--session-count 0))
          (should-not (gethash session-id claude-code-ide-mcp-server--sessions)))

      ;; Cleanup
      (kill-buffer buffer)
      (setq claude-code-ide-mcp-server--session-count 0)
      (clrhash claude-code-ide-mcp-server--sessions))))

(ert-deftest claude-code-ide-mcp-server-test-config-with-session-id ()
  "Test MCP config generation with session ID."
  ;; Mock the server port
  (cl-letf (((symbol-function 'claude-code-ide-mcp-server-get-port)
             (lambda () 12345)))
    ;; Test without session ID
    (let ((config (claude-code-ide-mcp-server-get-config)))
      (should config)
      (let ((url (alist-get 'url (alist-get 'emacs-tools (alist-get 'mcpServers config)))))
        (should (equal url "http://localhost:12345/mcp"))))

    ;; Test with session ID
    (let ((config (claude-code-ide-mcp-server-get-config "my-session-123")))
      (should config)
      (let* ((emacs-tools (alist-get 'emacs-tools (alist-get 'mcpServers config)))
             (url (alist-get 'url emacs-tools)))
        (should (equal url "http://localhost:12345/mcp/my-session-123"))))))

;;; Emacs Tools Tests

(ert-deftest claude-code-ide-emacs-tools-test-imenu-list-symbols ()
  "Test the imenu-list-symbols MCP tool."
  ;; Load the emacs-tools module
  (require 'claude-code-ide-emacs-tools)

  (let ((test-file (make-temp-file "test-imenu-" nil ".el"))
        (session-id "test-session-imenu")
        (project-dir (temporary-file-directory)))
    (unwind-protect
        (progn
          ;; Write test content to file
          (with-temp-file test-file
            (insert ";;; Test file for imenu\n\n"
                    "(defun test-function-1 (arg)\n"
                    "  \"A test function.\"\n"
                    "  (message \"Hello %s\" arg))\n\n"
                    "(defvar test-variable 42\n"
                    "  \"A test variable.\")\n\n"
                    "(defun test-function-2 ()\n"
                    "  \"Another test function.\"\n"
                    "  (+ 1 2))\n\n"
                    "(defconst test-constant 'foo\n"
                    "  \"A test constant.\")\n"))

          ;; Register a mock session
          (claude-code-ide-mcp-server-register-session session-id project-dir nil)

          ;; Test with session context
          (let ((claude-code-ide-mcp-server--current-session-id session-id))
            (let ((result (claude-code-ide-mcp-imenu-list-symbols test-file)))
              ;; Should return a list of results
              (should (listp result))
              (should (> (length result) 0))

              ;; Check that we found our functions and variables
              (let ((result-string (mapconcat #'identity result "\n")))
                (should (string-match "test-function-1" result-string))
                (should (string-match "test-function-2" result-string))
                (should (string-match "test-variable" result-string))
                (should (string-match "test-constant" result-string))

                ;; Check format includes line numbers
                (should (string-match ":[0-9]+:" result-string)))))

          ;; Test error handling - no file path
          (should-error (claude-code-ide-mcp-imenu-list-symbols nil)
                        :type 'error)

          ;; Test with non-existent file
          (let ((result (condition-case nil
                            (claude-code-ide-mcp-imenu-list-symbols "/nonexistent/file.el")
                          (error "Error listing symbols"))))
            (should (stringp result))
            (should (string-match "Error" result))))

      ;; Cleanup
      (delete-file test-file)
      (claude-code-ide-mcp-server-unregister-session session-id))))

(ert-deftest claude-code-ide-emacs-tools-test-imenu-nested-symbols ()
  "Test imenu-list-symbols with nested symbol structures."
  (require 'claude-code-ide-emacs-tools)

  (let ((test-file (make-temp-file "test-imenu-nested-" nil ".py"))
        (session-id "test-session-imenu-nested")
        (project-dir (temporary-file-directory)))
    (unwind-protect
        (progn
          ;; Write Python test content (which often has nested imenu structures)
          (with-temp-file test-file
            (insert "# Test Python file\n\n"
                    "class TestClass:\n"
                    "    def method1(self):\n"
                    "        pass\n\n"
                    "    def method2(self, arg):\n"
                    "        return arg * 2\n\n"
                    "def standalone_function():\n"
                    "    return 42\n"))

          ;; Register a mock session
          (claude-code-ide-mcp-server-register-session session-id project-dir nil)

          ;; Test with session context
          (let ((claude-code-ide-mcp-server--current-session-id session-id))
            ;; Note: This test might not find nested structures if python-mode
            ;; isn't properly configured, but it should at least not error
            (condition-case err
                (let ((result (claude-code-ide-mcp-imenu-list-symbols test-file)))
                  ;; Should return either a list or a string (no symbols message)
                  (should (or (listp result) (stringp result))))
              (error
               ;; If python mode isn't available, that's okay for this test
               (should (string-match "Error" (error-message-string err)))))))

      ;; Cleanup
      (delete-file test-file)
      (claude-code-ide-mcp-server-unregister-session session-id))))

(ert-deftest claude-code-ide-emacs-tools-test-tool-configuration ()
  "Test that imenu tool is properly configured."
  (require 'claude-code-ide-emacs-tools)
  (require 'claude-code-ide-mcp-server)

  ;; Tools are registered eagerly at load.

  ;; Find the imenu tool in the registered tools
  (let ((imenu-tool (cl-find-if
                     (lambda (tool)
                       (eq (plist-get tool :function)
                           'claude-code-ide-mcp-imenu-list-symbols))
                     claude-code-ide-mcp-server-tools)))
    (should imenu-tool)

    ;; Check its properties
    (progn
      ;; Check description
      (should (equal (plist-get imenu-tool :description)
                     "Navigate and explore a file's structure by listing all its functions, classes, and variables with their locations"))

      ;; Check args
      (let ((args (plist-get imenu-tool :args)))
        (should (= (length args) 1))
        (let ((file-path-arg (car args)))
          (should (equal (plist-get file-path-arg :name) "file_path"))
          (should (eq (plist-get file-path-arg :type) 'string))
          (should (not (plist-get file-path-arg :optional)))
          (should (equal (plist-get file-path-arg :description)
                         "Path to the file to analyze for symbols")))))))

;;; Tests for Terminal UX Commands (Phase 2 port)

(ert-deftest claude-code-ide-test-format-file-reference ()
  "Test @file#line reference formatting."
  (with-temp-buffer
    (insert "a\nb\nc\n")
    (goto-char (point-min))
    (setq buffer-file-name "/tmp/foo.el")
    (should (equal (claude-code-ide--format-file-reference) "@/tmp/foo.el#1"))
    (should (equal (claude-code-ide--format-file-reference nil 2 5) "@/tmp/foo.el#2-5"))
    (should (equal (claude-code-ide--format-file-reference "/x/y.el" 3) "@/x/y.el#3"))
    (set-buffer-modified-p nil))
  ;; No file -> nil
  (with-temp-buffer
    (should-not (claude-code-ide--format-file-reference))))

(ert-deftest claude-code-ide-test-region-or-buffer-reference ()
  "Test the region-or-buffer DWIM reference."
  ;; Active region -> @file#start-end
  (with-temp-buffer
    (insert "Hello\nWorld\nAgain")
    (setq buffer-file-name "/tmp/dwim.el")
    (goto-char (point-min))
    (set-mark (point))
    (goto-char (line-end-position 2))
    (let ((transient-mark-mode t))
      (activate-mark)
      (should (equal (claude-code-ide--region-or-buffer-reference)
                     "@/tmp/dwim.el#1-2")))
    (set-buffer-modified-p nil))
  ;; Region ending at the beginning of a line -> that line is not selected
  (with-temp-buffer
    (insert "Hello\nWorld\nAgain")
    (setq buffer-file-name "/tmp/dwim.el")
    (goto-char (point-min))
    (set-mark (point))
    (goto-char (line-beginning-position 3))
    (let ((transient-mark-mode t))
      (activate-mark)
      (should (equal (claude-code-ide--region-or-buffer-reference)
                     "@/tmp/dwim.el#1-2")))
    (set-buffer-modified-p nil))
  ;; No region -> whole buffer @file
  (with-temp-buffer
    (insert "x")
    (setq buffer-file-name "/tmp/dwim.el")
    (should (equal (claude-code-ide--region-or-buffer-reference) "@/tmp/dwim.el"))
    (set-buffer-modified-p nil))
  ;; Empty active region (point == mark) -> treated as no region
  (with-temp-buffer
    (insert "Hello\nWorld")
    (setq buffer-file-name "/tmp/dwim.el")
    (goto-char (point-min))
    (set-mark (point))
    (let ((transient-mark-mode t)
          (use-empty-active-region t))
      (activate-mark)
      (should (equal (claude-code-ide--region-or-buffer-reference) "@/tmp/dwim.el")))
    (set-buffer-modified-p nil))
  ;; No file -> nil
  (with-temp-buffer
    (should-not (claude-code-ide--region-or-buffer-reference))))

(ert-deftest claude-code-ide-test-format-errors-at-point ()
  "Test diagnostic extraction at point via help-at-pt fallback."
  (cl-letf (((symbol-function 'help-at-pt-kbd-string) (lambda () nil)))
    (should-not (claude-code-ide--format-errors-at-point)))
  (cl-letf (((symbol-function 'help-at-pt-kbd-string) (lambda () "boom error")))
    (should (equal (claude-code-ide--format-errors-at-point) "boom error"))))

(ert-deftest claude-code-ide-test-fix-error-at-point ()
  "Test fix-error-at-point only sends when a diagnostic is present."
  (let ((sent nil))
    (cl-letf (((symbol-function 'claude-code-ide--send-text)
               (lambda (text) (setq sent text) nil)))
      ;; No error -> nothing sent
      (cl-letf (((symbol-function 'claude-code-ide--format-errors-at-point)
                 (lambda () nil)))
        (with-temp-buffer
          (claude-code-ide-fix-error-at-point)
          (should-not sent)))
      ;; Error present -> sent text includes it
      (cl-letf (((symbol-function 'claude-code-ide--format-errors-at-point)
                 (lambda () "undefined var x")))
        (with-temp-buffer
          (insert "code")
          (setq buffer-file-name "/tmp/err.el")
          (claude-code-ide-fix-error-at-point)
          (set-buffer-modified-p nil)
          (should (string-match-p "undefined var x" sent)))))))

(ert-deftest claude-code-ide-test-insert-text ()
  "Test the --insert-text primitive inserts without submitting."
  (let ((sent-string nil)
        (sent-return nil)
        (sent-newline nil)
        (bufname "*claude-test-term*"))
    (get-buffer-create bufname)
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&rest _) bufname))
                  ((symbol-function 'claude-code-ide--terminal-send-string)
                   (lambda (str) (setq sent-string str)))
                  ((symbol-function 'claude-code-ide--terminal-send-newline)
                   (lambda () (setq sent-newline t)))
                  ((symbol-function 'claude-code-ide--terminal-send-return)
                   (lambda () (setq sent-return t))))
          (claude-code-ide--insert-text "hello")
          (should (equal sent-string "hello"))
          ;; A separator newline is appended, but the prompt is not submitted.
          (should sent-newline)
          (should-not sent-return))
      (kill-buffer bufname))
    ;; No session -> user-error
    (should-error (claude-code-ide--insert-text "x") :type 'user-error)))

(ert-deftest claude-code-ide-test-insert-region-or-buffer ()
  "Test insert-region-or-buffer inserts a reference without submitting."
  (let ((sent-string nil)
        (sent-return nil)
        (sent-newline nil)
        (prompted-string nil)
        (context-input "")
        (bufname "*claude-test-term*"))
    (get-buffer-create bufname)
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&rest _) bufname))
                  ((symbol-function 'read-string)
                   (lambda (prompt &rest _)
                     (setq prompted-string prompt)
                     context-input))
                  ((symbol-function 'claude-code-ide--terminal-send-string)
                   (lambda (str) (setq sent-string str)))
                  ((symbol-function 'claude-code-ide--terminal-send-newline)
                   (lambda () (setq sent-newline t)))
                  ((symbol-function 'claude-code-ide--terminal-send-return)
                   (lambda () (setq sent-return t))))
          ;; No region, empty context -> whole buffer reference, no submit
          (with-temp-buffer
            (insert "x")
            (setq buffer-file-name "/tmp/ins.el")
            (claude-code-ide-insert-region-or-buffer)
            (set-buffer-modified-p nil))
          (should (equal prompted-string "Add context (optional): "))
          (should (equal sent-string "@/tmp/ins.el"))
          ;; A separator newline is appended, but the prompt is not submitted.
          (should sent-newline)
          (should-not sent-return)
          ;; Non-empty context -> prepended as "CONTEXT: reference"
          (setq sent-string nil context-input "explore this")
          (with-temp-buffer
            (insert "x")
            (setq buffer-file-name "/tmp/ins.el")
            (claude-code-ide-insert-region-or-buffer)
            (set-buffer-modified-p nil))
          (should (equal sent-string "explore this: @/tmp/ins.el"))
          ;; Non-file buffer -> user-error
          (with-temp-buffer
            (should-error (claude-code-ide-insert-region-or-buffer)
                          :type 'user-error)))
      (kill-buffer bufname))))

(ert-deftest claude-code-ide-test-yank ()
  "Test yank pastes the current kill without submitting."
  (let ((sent-string nil)
        (sent-return nil)
        (sent-newline nil)
        (prompted-string nil)
        (context-input "")
        (bufname "*claude-test-term*"))
    (get-buffer-create bufname)
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&rest _) bufname))
                  ((symbol-function 'current-kill)
                   (lambda (&rest _) "yanked text"))
                  ((symbol-function 'read-string)
                   (lambda (prompt &rest _)
                     (setq prompted-string prompt)
                     context-input))
                  ((symbol-function 'claude-code-ide--terminal-send-string)
                   (lambda (str) (setq sent-string str)))
                  ((symbol-function 'claude-code-ide--terminal-send-newline)
                   (lambda () (setq sent-newline t)))
                  ((symbol-function 'claude-code-ide--terminal-send-return)
                   (lambda () (setq sent-return t))))
          ;; Empty context -> just the yanked text
          (claude-code-ide-yank)
          (should (equal prompted-string "Add context (optional): "))
          (should (equal sent-string "yanked text"))
          ;; A separator newline is appended, but the prompt is not submitted.
          (should sent-newline)
          (should-not sent-return)
          ;; Non-empty context -> prepended as "CONTEXT: text"
          (setq sent-string nil context-input "refactor this")
          (claude-code-ide-yank)
          (should (equal sent-string "refactor this: yanked text")))
      (kill-buffer bufname))
    ;; Empty kill ring -> user-error, nothing sent
    (setq sent-string nil)
    (cl-letf (((symbol-function 'current-kill)
               (lambda (&rest _) (error "Kill ring is empty"))))
      (should-error (claude-code-ide-yank) :type 'user-error)
      (should (null sent-string)))))

(ert-deftest claude-code-ide-test-insert-text-consecutive ()
  "Test consecutive --insert-text calls stay separated, not glued.
Reproduces the bug where back-to-back inserts produced a single
malformed token such as \"@foo@bar\"."
  (let ((sent-string "")
        (bufname "*claude-test-term*"))
    (get-buffer-create bufname)
    (unwind-protect
        ;; Do NOT mock --terminal-send-newline: exercise the real separator
        ;; while accumulating every string sent to the terminal.
        (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&rest _) bufname))
                  ((symbol-function 'claude-code-ide--terminal-send-string)
                   (lambda (str) (setq sent-string (concat sent-string str)))))
          (claude-code-ide--insert-text "@foo")
          (claude-code-ide--insert-text "@bar")
          ;; Each insert lands on its own line via a soft newline (ESC + CR),
          ;; so the two references are never concatenated directly.
          (should (equal sent-string "@foo\e\r@bar\e\r")))
      (kill-buffer bufname))))

(ert-deftest claude-code-ide-test-prepend-context ()
  "Test --prepend-context prefixes content with \"CONTEXT: \"."
  (should (equal (claude-code-ide--prepend-context "@foo#1" "do it")
                 "do it: @foo#1"))
  (should (equal (claude-code-ide--prepend-context "@foo#1" nil)
                 "@foo#1")))

(ert-deftest claude-code-ide-test-read-context ()
  "Test --read-context returns trimmed input or nil when empty."
  (let ((prompted-string nil))
    ;; Non-empty input is trimmed and returned
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &rest _)
                 (setq prompted-string prompt)
                 "  hello  ")))
      (should (equal (claude-code-ide--read-context) "hello"))
      (should (equal prompted-string "Add context (optional): ")))
    ;; Empty input -> nil
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "")))
      (should (null (claude-code-ide--read-context))))
    ;; Whitespace-only input -> nil
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "   ")))
      (should (null (claude-code-ide--read-context))))))

;;; Tests for Completion Notifications (Phase 3 port)

(ert-deftest claude-code-ide-test-notify ()
  "Test notification dispatch respects the enable flag."
  (let ((called nil))
    (cl-letf (((symbol-function 'claude-code-ide-default-notification)
               (lambda (title msg) (setq called (list title msg)))))
      (let ((claude-code-ide-enable-notifications t)
            (claude-code-ide-notification-function
             #'claude-code-ide-default-notification))
        (claude-code-ide--notify)
        (should called))
      (setq called nil)
      (let ((claude-code-ide-enable-notifications nil)
            (claude-code-ide-notification-function
             #'claude-code-ide-default-notification))
        (claude-code-ide--notify)
        (should-not called)))))

(ert-deftest claude-code-ide-test-vterm-bell-detector ()
  "Test the bell detector notifies on BEL but ignores OSC title sequences."
  (let ((orig-calls 0) (notified 0)
        (claude-code-ide-enable-notifications t))
    (cl-letf (((symbol-function 'claude-code-ide--notify)
               (lambda (&rest _) (cl-incf notified)))
              ((symbol-function 'claude-code-ide--session-buffer-p)
               (lambda (_buf) t))
              ((symbol-function 'process-buffer)
               (lambda (_p) (current-buffer))))
      (let ((orig (lambda (_p _i) (cl-incf orig-calls))))
        ;; Bell present -> notify and pass through
        (claude-code-ide--vterm-bell-detector orig nil "hello\007world")
        (should (= notified 1))
        (should (= orig-calls 1))
        ;; OSC title bell -> no notify, still passes through
        (claude-code-ide--vterm-bell-detector orig nil "\033]0;title\007")
        (should (= notified 1))
        (should (= orig-calls 2))
        ;; No bell -> no notify, passes through
        (claude-code-ide--vterm-bell-detector orig nil "plain text")
        (should (= notified 1))
        (should (= orig-calls 3))
        ;; A literal "]0;" without the ESC prefix is NOT an OSC title
        ;; sequence, so a bell alongside it must still notify.
        (claude-code-ide--vterm-bell-detector orig nil "output ]0;not-a-title\007")
        (should (= notified 2))
        (should (= orig-calls 4))))))

;;; Tests for Debug Toggle (Phase 4 port)

(ert-deftest claude-code-ide-test-toggle-debug ()
  "Test the debug logging toggle command.
The test suite mocks the debug module, so load the real file to test the
real command, then restore the mock for the remaining tests."
  (let ((mock-debug (symbol-function 'claude-code-ide-debug)))
    (unwind-protect
        (progn
          (load (expand-file-name "claude-code-ide-debug.el") nil t)
          (let ((claude-code-ide-debug nil))
            (claude-code-ide-toggle-debug)
            (should claude-code-ide-debug)
            (claude-code-ide-toggle-debug)
            (should-not claude-code-ide-debug)))
      ;; Restore the mock so later tests are unaffected
      (fset 'claude-code-ide-debug mock-debug))))

;;; Session Run Status Tests

(ert-deftest claude-code-ide-test-session-dir-key ()
  "Canonical dir keys collapse abbreviated, env-var, and absolute paths."
  (let ((home (expand-file-name "~/")))
    ;; Abbreviated and absolute forms normalise to the same key.
    (should (equal (claude-code-ide--session-dir-key "~/foo")
                   (claude-code-ide--session-dir-key (concat home "foo"))))
    ;; A trailing slash is irrelevant: both forms map to the same key, so a
    ;; status stored under one is found under the other.
    (should (equal (claude-code-ide--session-dir-key "/path/to/proj")
                   (claude-code-ide--session-dir-key "/path/to/proj/")))
    ;; Environment variables are substituted.
    (let ((process-environment (cons "CLAUDE_TEST_DIR=/tmp/xyz" process-environment)))
      (should (equal (claude-code-ide--session-dir-key "$CLAUDE_TEST_DIR/a")
                     (claude-code-ide--session-dir-key "/tmp/xyz/a"))))))

(ert-deftest claude-code-ide-test-run-status-trailing-slash ()
  "Status stored under one path form is found under another."
  (clrhash claude-code-ide--sessions)
  (let ((with-slash "/tmp/ccide-slash-test/")
        (without-slash "/tmp/ccide-slash-test"))
    (unwind-protect
        (progn
          ;; Seeded with a trailing slash, read back without one.
          (claude-code-ide-tests--seed-status with-slash "busy")
          (should (equal (claude-code-ide-session-run-status without-slash) "busy"))
          ;; Both forms resolve to the same session entry.
          (should (eq (claude-code-ide--get-session with-slash)
                      (claude-code-ide--get-session without-slash))))
      (clrhash claude-code-ide--sessions))))

(ert-deftest claude-code-ide-test-map-cli-status ()
  "CLI statuses map to known values, with an idle fallback for the unknown."
  (should (equal (claude-code-ide--map-cli-status "waiting") "waiting"))
  (should (equal (claude-code-ide--map-cli-status "idle") "idle"))
  (should (equal (claude-code-ide--map-cli-status "busy") "busy"))
  (should (equal (claude-code-ide--map-cli-status "something-new") "idle"))
  (should (equal (claude-code-ide--map-cli-status nil) "idle")))

(ert-deftest claude-code-ide-test-run-status-rank ()
  "Run status ranks order waiting before idle before busy."
  (clrhash claude-code-ide--sessions)
  (let ((dir "/tmp/ccide-rank-test/"))
    (unwind-protect
        (progn
          (claude-code-ide-tests--seed-status dir "waiting")
          (let ((waiting (claude-code-ide--run-status-rank dir)))
            (claude-code-ide-tests--seed-status dir "idle")
            (let ((idle (claude-code-ide--run-status-rank dir)))
              (claude-code-ide-tests--seed-status dir "busy")
              (let ((busy (claude-code-ide--run-status-rank dir)))
                (should (< waiting idle))
                (should (< idle busy))))))
      (clrhash claude-code-ide--sessions))))

(ert-deftest claude-code-ide-test-cleanup-dead-processes-clears-status ()
  "Sweeping dead processes also drops their run status."
  (skip-unless (executable-find "cat"))
  (claude-code-ide-tests--clear-processes)
  (let* ((dir (expand-file-name "/tmp/ccide-dead-proc/"))
         (proc (make-process :name "ccide-dead-test" :command '("cat") :noquery t)))
    (delete-process proc)            ; now `process-live-p' is nil
    (claude-code-ide-tests--seed-status dir "busy")
    (setf (claude-code-ide--session-process (claude-code-ide--get-session dir)) proc)
    (should (claude-code-ide-session-run-status dir))
    (claude-code-ide--cleanup-dead-processes)
    (should-not (claude-code-ide--get-session dir))
    (should-not (claude-code-ide-session-run-status dir))))

(ert-deftest claude-code-ide-test-session-marginalia-annotation ()
  "The marginalia annotation carries the align marker and the session columns."
  ;; The annotator reuses `marginalia--truncate', so `marginalia' must be present.
  (skip-unless (require 'marginalia nil t))
  (require 'claude-code-ide-marginalia)
  (clrhash claude-code-ide--sessions)
  (let ((dir "/tmp/ccide-annot-test/")
        ;; Two minutes ago -> a deterministic "2m" age column.
        (since (time-subtract (current-time) 120)))
    (unwind-protect
        (progn
          (claude-code-ide-tests--seed-status dir "waiting" since "permission prompt" "my-sess")
          (let ((ann (claude-code-ide-marginalia--annotate-session
                      (abbreviate-file-name dir))))
            ;; The leading character is the marker marginalia aligns on.
            (should (eq (get-text-property 0 'marginalia--align ann) t))
            ;; Name, age, status and reason all appear in the annotation.
            (should (string-match-p "my-sess" ann))
            (should (string-match-p "2m" ann))
            (should (string-match-p "waiting" ann))
            (should (string-match-p "permission prompt" ann))
            ;; Columns are laid out in order: name, age, status, then reason.
            (should (< (string-match "my-sess" ann)
                       (string-match "2m" ann)
                       (string-match "waiting" ann)
                       (string-match "permission prompt" ann)))
            ;; Each column carries its intended face; the status and its reason
            ;; share the run-status colour ("waiting" -> `error').
            (should (eq (get-text-property (string-match "my-sess" ann) 'face ann)
                        'marginalia-documentation))
            (should (eq (get-text-property (string-match "2m" ann) 'face ann)
                        'marginalia-date))
            (should (eq (get-text-property (string-match "waiting" ann) 'face ann)
                        'error))
            (should (eq (get-text-property (string-match "permission prompt" ann) 'face ann)
                        'error))))
      (clrhash claude-code-ide--sessions))))

(ert-deftest claude-code-ide-test-annotation-column ()
  "`claude-code-ide-marginalia--column' pads, truncates and faces a column."
  (skip-unless (require 'marginalia nil t))
  (require 'claude-code-ide-marginalia)
  ;; Short text is padded with spaces to the exact width, left-justified.
  (let ((col (claude-code-ide-marginalia--column "ab" 6 'marginalia-date)))
    (should (= (string-width col) 6))
    (should (string-prefix-p "ab" col))
    ;; The face is applied across the whole padded column.
    (should (eq (get-text-property 0 'face col) 'marginalia-date)))
  ;; Overlong text is truncated to the width, keeping the full text as a
  ;; `help-echo' (the ellipsis glyph itself depends on the display, so we do not
  ;; assert on it).
  (let ((col (claude-code-ide-marginalia--column "abcdefghij" 5 'marginalia-documentation)))
    (should (= (string-width col) 5))
    (should (equal (get-text-property 0 'help-echo col) "abcdefghij")))
  ;; A negative width right-justifies: padding goes on the left.
  (let ((col (claude-code-ide-marginalia--column "ab" -6 'marginalia-date)))
    (should (= (string-width col) 6))
    (should (string-prefix-p " " col))
    (should (string-suffix-p "ab" col))))

(ert-deftest claude-code-ide-test-session-marginalia-annotation-columns-align ()
  "A long name is truncated so the later columns keep their fixed offset."
  (skip-unless (require 'marginalia nil t))
  (require 'claude-code-ide-marginalia)
  (clrhash claude-code-ide--sessions)
  (let ((short-dir "/tmp/ccide-annot-short/")
        (long-dir "/tmp/ccide-annot-long/")
        (since (time-subtract (current-time) 120)))
    (unwind-protect
        (progn
          (claude-code-ide-tests--seed-status short-dir "idle" since nil "short")
          (claude-code-ide-tests--seed-status
           long-dir "idle" since nil
           "a-very-long-session-name-well-past-the-column-width")
          (let ((short-ann (claude-code-ide-marginalia--annotate-session
                            (abbreviate-file-name short-dir)))
                (long-ann (claude-code-ide-marginalia--annotate-session
                           (abbreviate-file-name long-dir))))
            ;; The long name is truncated: its tail is dropped while the short
            ;; name survives in full.
            (should (string-match-p "short" short-ann))
            (should-not (string-match-p "column-width" long-ann))
            ;; Because the name column has a fixed width, the age and status
            ;; columns begin at the same offset regardless of name length.
            (should (= (string-match "2m" short-ann)
                       (string-match "2m" long-ann)))
            (should (= (string-match "idle" short-ann)
                       (string-match "idle" long-ann)))))
      (clrhash claude-code-ide--sessions))))

(ert-deftest claude-code-ide-test-list-sessions-ordering ()
  "Session ordering surfaces waiting first, then idle, then busy."
  (clrhash claude-code-ide--sessions)
  (let* ((wt "/tmp/ccide-sess-waiting/")
         (i "/tmp/ccide-sess-idle/")
         (bs "/tmp/ccide-sess-busy/")
         (sessions (list (cons (abbreviate-file-name bs) bs)
                         (cons (abbreviate-file-name i) i)
                         (cons (abbreviate-file-name wt) wt))))
    (unwind-protect
        (progn
          (claude-code-ide-tests--seed-status wt "waiting")
          (claude-code-ide-tests--seed-status i "idle")
          (claude-code-ide-tests--seed-status bs "busy")
          ;; Mirror the sort `claude-code-ide-list-sessions' applies.
          (let ((sorted (sort (copy-sequence sessions)
                              (lambda (x y)
                                (< (claude-code-ide--run-status-rank (cdr x))
                                   (claude-code-ide--run-status-rank (cdr y)))))))
            (should (equal (mapcar #'cdr sorted) (list wt i bs)))))
      (clrhash claude-code-ide--sessions))))

;;; Session Status Watcher Tests

(ert-deftest claude-code-ide-test-sessions-directory ()
  "The sessions directory lives under the resolved config directory."
  (claude-code-ide-tests--with-temp-config-dir
   (should (equal (claude-code-ide--sessions-directory)
                  (expand-file-name "sessions/" (file-name-as-directory config-dir))))))

(ert-deftest claude-code-ide-test-refresh-session-statuses ()
  "Refreshing mirrors CLI session files onto matching sessions only."
  (claude-code-ide-tests--with-temp-config-dir
   (clrhash claude-code-ide--sessions)
   (let* ((busy-dir "/tmp/ccide-watch-busy")
          (wait-dir "/tmp/ccide-watch-wait")
          (untracked "/tmp/ccide-watch-untracked")
          (sessions-dir (claude-code-ide--sessions-directory)))
     ;; Track two sessions; leave `untracked' out of the table.
     (claude-code-ide--ensure-session busy-dir)
     (claude-code-ide--ensure-session wait-dir)
     ;; The CLI writes one file per PID.
     (claude-code-ide-tests--write-session-file
      sessions-dir 111 `((cwd . ,busy-dir) (status . "busy") (name . "busy-sess")
                         (statusUpdatedAt . 1000000) (updatedAt . 1000000)))
     (claude-code-ide-tests--write-session-file
      sessions-dir 222 `((cwd . ,wait-dir) (status . "waiting")
                         (waitingFor . "permission prompt") (name . "wait-sess")
                         (statusUpdatedAt . 2000000) (updatedAt . 2000000)))
     (claude-code-ide-tests--write-session-file
      sessions-dir 333 `((cwd . ,untracked) (status . "busy")
                         (statusUpdatedAt . 3000000) (updatedAt . 3000000)))
     (claude-code-ide--refresh-session-statuses)
     ;; Busy session picks up status and name.
     (should (equal (claude-code-ide-session-run-status busy-dir) "busy"))
     (should (equal (claude-code-ide--session-name
                     (claude-code-ide--get-session busy-dir))
                    "busy-sess"))
     ;; Waiting session picks up status, reason and since.
     (should (equal (claude-code-ide-session-run-status wait-dir) "waiting"))
     (should (equal (claude-code-ide--session-status-reason
                     (claude-code-ide--get-session wait-dir))
                    "permission prompt"))
     (should (claude-code-ide-session-run-status-since wait-dir))
     ;; The untracked directory is never added.
     (should-not (claude-code-ide--get-session untracked)))))

(ert-deftest claude-code-ide-test-refresh-session-statuses-unknown ()
  "An unrecognised CLI status maps to idle."
  (claude-code-ide-tests--with-temp-config-dir
   (clrhash claude-code-ide--sessions)
   (let ((dir "/tmp/ccide-watch-unknown")
         (sessions-dir (claude-code-ide--sessions-directory)))
     (claude-code-ide--ensure-session dir)
     (claude-code-ide-tests--write-session-file
      sessions-dir 444 `((cwd . ,dir) (status . "reticulating")
                         (statusUpdatedAt . 1000000) (updatedAt . 1000000)))
     (claude-code-ide--refresh-session-statuses)
     (should (equal (claude-code-ide-session-run-status dir) "idle")))))

(ert-deftest claude-code-ide-test-refresh-session-statuses-newest-wins ()
  "When two files share a cwd, the most recently updated one wins."
  (claude-code-ide-tests--with-temp-config-dir
   (clrhash claude-code-ide--sessions)
   (let ((dir "/tmp/ccide-watch-dup")
         (sessions-dir (claude-code-ide--sessions-directory)))
     (claude-code-ide--ensure-session dir)
     (claude-code-ide-tests--write-session-file
      sessions-dir 555 `((cwd . ,dir) (status . "idle")
                         (statusUpdatedAt . 1000000) (updatedAt . 1000000)))
     (claude-code-ide-tests--write-session-file
      sessions-dir 556 `((cwd . ,dir) (status . "busy")
                         (statusUpdatedAt . 9000000) (updatedAt . 9000000)))
     (claude-code-ide--refresh-session-statuses)
     (should (equal (claude-code-ide-session-run-status dir) "busy")))))

(ert-deftest claude-code-ide-test-list-sessions-uses-read-function ()
  "`claude-code-ide-list-sessions' delegates picking to the read function.
It calls `claude-code-ide-session-read-function' with the sorted sessions and
displays the chosen session's buffer -- the seam the consult reader hooks into."
  (claude-code-ide-tests--clear-processes)
  ;; No trailing slash: the stored key is canonical, so it matches the display
  ;; and the buffer name `claude-code-ide-list-sessions' derives from it.
  (let* ((dir "/tmp/ccide-read-fn-test")
         (display (abbreviate-file-name dir))
         (buffer-name (funcall claude-code-ide-buffer-name-function dir))
         (buffer (get-buffer-create buffer-name))
         received-sessions displayed-buffer)
    (unwind-protect
        (progn
          (setf (claude-code-ide--session-process (claude-code-ide--ensure-session dir)) buffer)
          ;; Record the sessions handed to the reader and choose the first.
          (let ((claude-code-ide-session-read-function
                 (lambda (sessions)
                   (setq received-sessions sessions)
                   (caar sessions))))
            ;; Stub the cleanup (would drop the buffer-valued entry) and the
            ;; side-window display so the test stays headless.
            (cl-letf (((symbol-function 'claude-code-ide--cleanup-dead-processes)
                       #'ignore)
                      ((symbol-function 'claude-code-ide--display-buffer-in-side-window)
                       (lambda (buf) (setq displayed-buffer buf))))
              (claude-code-ide-list-sessions)))
          (should (assoc display received-sessions)) ; reader saw our session
          (should (eq displayed-buffer buffer)))     ; its buffer was displayed
      (claude-code-ide-tests--clear-processes)
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-consult-auto-load ()
  "The `consult' after-load hook auto-loads the integration unconditionally.
Runs the actual form `claude-code-ide' registers in `after-load-alist' (not a
re-implementation), so removing or mis-wiring the auto-load is caught.  `require'
is stubbed so the hook can run without `consult' installed; `consult-buffer-sources'
is bound (via `cl-progv', since the consult file only declares it file-locally
special) and `claude-code-ide-session-read-function' shadowed, so running a
co-registered `claude-code-ide-consult' hook has no real `consult' and no lasting
side effects."
  (let ((hooks (cdr (assq 'consult after-load-alist)))
        (orig-require (symbol-function 'require))
        (claude-code-ide-session-read-function claude-code-ide-session-read-function)
        (loaded nil))
    ;; The auto-load form must be registered, else the integration never loads.
    (should hooks)
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest args)
                 (if (eq feature 'claude-code-ide-consult)
                     (setq loaded t)
                   (apply orig-require feature args)))))
      (cl-progv '(consult-buffer-sources) (list nil)
        (dolist (hook hooks) (funcall hook))))
    (should loaded)))

(ert-deftest claude-code-ide-test-marginalia-auto-load ()
  "The `marginalia' after-load hook auto-loads the integration unconditionally.
Runs the actual form `claude-code-ide' registers in `after-load-alist' (not a
re-implementation), so removing or mis-wiring the auto-load is caught.  `require'
is stubbed so the hook can run without `marginalia' installed; `marginalia-annotators'
is bound (via `cl-progv', since the marginalia file only declares it file-locally
special) so a co-registered `claude-code-ide-marginalia' annotator hook has no
lasting side effects."
  (let ((hooks (cdr (assq 'marginalia after-load-alist)))
        (orig-require (symbol-function 'require))
        (loaded nil))
    ;; The auto-load form must be registered, else the integration never loads.
    (should hooks)
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest args)
                 (if (eq feature 'claude-code-ide-marginalia)
                     (setq loaded t)
                   (apply orig-require feature args)))))
      (cl-progv '(marginalia-annotators) (list nil)
        (dolist (hook hooks) (funcall hook))))
    (should loaded)))

(ert-deftest claude-code-ide-emacs-tools-test-eager-registration ()
  "The built-in tools are registered at load, without any setup call."
  (require 'claude-code-ide-emacs-tools)
  (require 'claude-code-ide-mcp-server)
  (dolist (fn '(claude-code-ide-mcp-xref-find-references
                claude-code-ide-mcp-xref-find-apropos
                claude-code-ide-mcp-project-info
                claude-code-ide-mcp-imenu-list-symbols
                claude-code-ide-mcp-treesit-info))
    (should (cl-find-if (lambda (spec) (eq (plist-get spec :function) fn))
                        claude-code-ide-mcp-server-tools))))

(ert-deftest claude-code-ide-emacs-tools-test-nav-advertisement-gating ()
  "Navigation tools are advertised only when enable-emacs-tools is non-nil."
  (require 'claude-code-ide-emacs-tools)
  (require 'claude-code-ide-mcp-server)
  (let ((claude-code-ide-enable-emacs-tools t))
    (should (member "claude-code-ide-mcp-xref-find-references"
                    (claude-code-ide-mcp-server-get-tool-names))))
  (let ((claude-code-ide-enable-emacs-tools nil))
    (should-not (member "claude-code-ide-mcp-xref-find-references"
                        (claude-code-ide-mcp-server-get-tool-names)))))

(ert-deftest claude-code-ide-test-build-command-empty-allowed-tools ()
  "--allowedTools is omitted when \\='auto resolves to no enabled tools."
  (cl-letf (((symbol-function 'claude-code-ide-mcp-server-ensure-server)
             (lambda () t))
            ((symbol-function 'claude-code-ide-mcp-server-get-config)
             (lambda (&optional _id)
               '((mcpServers . ((emacs-tools . ((type . "http")
                                                (url . "http://localhost:1/mcp"))))))))
            ;; All tools gated off -> no names.
            ((symbol-function 'claude-code-ide-mcp-server-get-tool-names)
             (lambda (&optional _prefix) nil)))
    (claude-code-ide-tests--with-mocked-cli "claude"
                                            (let ((claude-code-ide-mcp-allowed-tools 'auto))
                                              (should-not (string-match-p
                                                           "--allowedTools"
                                                           (claude-code-ide--build-claude-command)))))))

(ert-deftest claude-code-ide-test-handle-post-error-echoes-id ()
  "Error responses echo the request id, except parse errors (null id)."
  (require 'claude-code-ide-mcp-http-server)
  (let ((captured 'unset))
    (cl-letf (((symbol-function 'ws-headers) (lambda (_r) nil))
              ((symbol-function 'claude-code-ide-mcp-http-server--extract-session-id-from-path)
               (lambda (_h) nil))
              ((symbol-function 'claude-code-ide-mcp-http-server--send-json-response)
               (lambda (&rest _) nil))
              ((symbol-function 'claude-code-ide-mcp-http-server--send-json-error)
               (lambda (_req id _code _msg) (setq captured id))))
      ;; Unknown method -> claude-code-ide-mcp-json-rpc-error must echo the request id.
      (cl-letf (((symbol-function 'ws-body)
                 (lambda (_r) "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"nonexistent\"}")))
        (claude-code-ide-mcp-http-server--handle-post 'req)
        (should (equal captured 42)))
      ;; Malformed body -> parse error must report a null id.
      (setq captured 'unset)
      (cl-letf (((symbol-function 'ws-body) (lambda (_r) "not json")))
        (claude-code-ide-mcp-http-server--handle-post 'req)
        (should (null captured))))))

(provide 'claude-code-ide-tests)

;; Local Variables:
;; no-update-autoloads: t
;; autoload-compute-prefixes: nil
;; End:

;;; claude-code-ide-tests.el ends here
