;;; Copyright (C) 2015-2019 Rob Browning <rlb@defaultvalue.org>
;;; SPDX-License-Identifier: LGPL-2.1-or-later OR EPL-1.0+

(define-module (lokke repl)
  #:use-module ((lokke base util) #:select (module-name->ns-sym))
  #:use-module ((lokke ns) #:select (default-environment))
  #:use-module ((lokke pr) #:select (prn))
  #:use-module ((system base language) #:select (language-name))
  #:use-module ((system repl common)
                #:select (make-repl repl-language repl-option-set!))
  #:use-module ((system repl repl) #:select (run-repl))
  #:export (repl)
  #:duplicates (merge-generics replace warn-override-core warn last))

;; If upstream is willing to add an initial-module argument to repl,
;; or equivalent, and some way to set the printer, then we won't need
;; all this.  For now, just do exactly what the Guile top-repl does,
;; and then change the module to the default-environment, i.e. (lokke
;; user).

(define (prompt repl)
  (format #f "~A@~A~A> " (language-name (repl-language repl))
          (module-name->ns-sym (module-name (current-module)))
          (let ((level (length (cond
                                ((fluid-ref *repl-stack*) => cdr)
                                (else '())))))
            (if (zero? level) "" (format #f " [~a]" level)))))

;; start-repl adapted from the version in Guile 2.2.6 (LGPL 3)
(define* (start-repl-w-reader #:optional (lang (current-language))
                              #:key debug reader)
  ;; ,language at the REPL will update the current-language.  Make
  ;; sure that it does so in a new dynamic scope.
  (parameterize ((current-language lang))
    (let ((repl (make-repl lang debug)))
      (repl-option-set! repl 'print (lambda (repl x) (prn x)))
      (repl-option-set! repl 'prompt prompt)
      (run-repl repl))))

;; call-with-sigint taken from the version in Guile 2.2.6 (LGPL 3)
;; FIXME: propose accommodations upstream
(define call-with-sigint
  (if (not (provided? 'posix))
      (lambda (thunk) (thunk))
      (lambda (thunk)
        (let ((handler #f))
          (dynamic-wind
            (lambda ()
              (set! handler
                    (sigaction SIGINT
                      (lambda (sig)
                        (scm-error 'signal #f "User interrupt" '()
                                   (list sig))))))
            thunk
            (lambda ()
              (if handler
                  ;; restore Scheme handler, SIG_IGN or SIG_DFL.
                  (sigaction SIGINT (car handler) (cdr handler))
                  ;; restore original C handler.
                  (sigaction SIGINT #f))))))))

(define setlocale
  (if (defined? 'setlocale (resolve-module '(guile)))
      (@ (guile) setlocale)
      #f))

;; repl-for-current-module adapted from the version in Guile 2.2.6 (LGPL 3)
;; FIXME: propose accommodations upstream
(define (repl-for-current-module)
  (save-module-excursion
   (lambda ()
     (let ((guile-user-module (resolve-module '(guile-user))))
       ;; Use some convenient modules (in reverse order)
       (set-current-module guile-user-module)
       (process-use-modules
        (append
         '(((ice-9 r5rs))
           ((ice-9 session)))
         (if (provided? 'regex)
             '(((ice-9 regex)))
             '())
         (if (provided? 'threads)
             '(((ice-9 threads)))
             '()))))))
  (call-with-sigint
   (lambda ()
     (and setlocale
          (catch 'system-error
            (lambda ()
              (setlocale LC_ALL ""))
            (lambda (key subr fmt args errno)
                (format (current-error-port)
                        "warning: failed to install locale: ~a~%"
                        (strerror (car errno))))))
       (let ((status (start-repl-w-reader (current-language))))
         (run-hook exit-hook)
         status))))

(define (repl)
  (set-current-module (default-environment))
  (current-language 'lokke)
  (repl-for-current-module))
