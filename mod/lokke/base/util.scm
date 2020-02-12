;;; Copyright (C) 2019 Rob Browning <rlb@defaultvalue.org>
;;;
;;; This project is free software; you can redistribute it and/or
;;; modify it under the terms of (at your option) either of the
;;; following two licences:
;;;
;;;   1) The GNU Lesser General Public License as published by the
;;;      Free Software Foundation; either version 2.1, or (at your
;;;      option) any later version
;;;
;;;   2) The Eclipse Public License; either version 1.0 or (at your
;;;      option) any later version.

(define-module (lokke base util)
  #:use-module ((ice-9 receive) #:select (receive))
  #:use-module ((srfi srfi-1) #:select (drop take))
  #:use-module ((system syntax) #:select (syntax-local-binding))
  #:export (global-identifier?
            keyword->string
            module-name->ns-str
            module-name->ns-sym
            pairify
            require-nil
            string->keyword
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

(define (global-identifier? syn)
  (receive (type _)
      (syntax-local-binding syn)
    (eq? 'global type)))

;; We use this as a syntax-pattern fender to detect reader-vectors.
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
    ((_ fn-name arg)
     (unless (eq? #nil arg)
       (scm-error 'wrong-type-arg fn-name
                  "Wrong type argument in position 1: ~A"
                  (list arg) (list arg))))))
