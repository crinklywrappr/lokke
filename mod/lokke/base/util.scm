;;; Copyright (C) 2019 Rob Browning <rlb@defaultvalue.org>
;;; SPDX-License-Identifier: LGPL-2.1-or-later OR EPL-1.0+

(define-module (lokke base util)
  #:use-module ((ice-9 receive) #:select (receive))
  #:use-module ((srfi srfi-1) #:select (drop take))
  #:use-module ((system syntax) #:select (syntax-local-binding))
  #:export (global-identifier?
            keyword->string
            map-tag?
            meta-tag?
            module-name->ns-str
            module-name->ns-sym
            pairify
            require-nil
            set-tag?
            string->keyword
            synquote-resolve-symbol-str
            vec-tag?))

(define (string->keyword x) (symbol->keyword (string->symbol x)))
(define (keyword->string x) (symbol->string (keyword->symbol x)))

(define (module-name->ns-str m)
  (string-join (map symbol->string
                    (if (and (> (length m) 2)
                             (equal? '(lokke ns) (take m 2)))
			(drop m 2)
			(cons 'guile m)))
               "."))

(define (module-name->ns-sym m)
  (string->symbol (module-name->ns-str m)))

(define (synquote-resolve-symbol-str s s-mod)
  (let ((src-module (module-import-interface s-mod (string->symbol s))))
    (string-append (module-name->ns-str (module-name (or src-module s-mod)))
                   "/"
                   s)))

(define (global-identifier? syn)
  (receive (type _)
      (syntax-local-binding syn)
    (eq? 'global type)))

;; We use these as a syntax-pattern fender to detect reader-types.
(define (map-tag? x) (eq? '/lokke/reader-hash-map (syntax->datum x)))
(define (meta-tag? x) (eq? '/lokke/reader-meta (syntax->datum x)))
(define (set-tag? x) (eq? '/lokke/reader-hash-set (syntax->datum x)))
(define (vec-tag? x) (eq? '/lokke/reader-vector (syntax->datum x)))

(define (pairify lst)
  ;; (a b c d) -> ((a b) (c d) ...)
  (let loop ((rest lst))
    (cond
     ((null? rest) '())
     ((null? (cdr rest)) (error "Can't pairify odd length list" lst))
     (else (cons (take rest 2) (loop (cddr rest)))))))

;; Need this because #nil is a <boolean> too...
(define-syntax require-nil
  (syntax-rules ()
    ((_ fn-name arg) (require-nil fn-name 1 arg))
    ((_ fn-name pos arg)
     (unless (eq? #nil arg)
       (scm-error 'wrong-type-arg fn-name
                  "Wrong type argument in position ~a: ~s"
                  (list pos arg) (list arg))))))
