;;; Copyright (C) 2019-2020 Rob Browning <rlb@defaultvalue.org>
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

;; This is the lowest level, supporting *everything*, including
;; definitions required by code generated by the compiler, etc., and
;; providing bits needed to bootstrap the system by compiling
;; clojure.core, i.e. (lokke ns clojure core).

(define-module (lokke boot)
  ;; To avoid unquote and unquote-splicing, which when available,
  ;; break the syntax-quote syntax, and might not be terrible for
  ;; this particular module to be pure anyway.
  #:pure
  #:use-module ((guile)
                #:select ((quote . %scm-quote)
                          @
                          car
                          case
                          cddr
                          cdr
                          cond
                          cond-expand
                          cons
                          cons*
                          datum->syntax
                          define
                          define-syntax
                          define-syntax-rule
                          eq?
                          error
                          format
                          lambda
                          let
                          list
                          list?
                          map
                          null?
                          null?
                          quasisyntax
                          syntax
                          syntax->datum
                          syntax-case
                          syntax-error
                          syntax-rules
                          unsyntax
                          unsyntax-splicing
                          use-modules))
  #:use-module ((lokke ns) #:select (ns))
  #:use-module ((lokke metadata) #:select (with-meta))
  #:use-module ((lokke reader literal)
                #:select (reader-hash-map-elts
                          reader-hash-set-elts
                          reader-vector-elts))
  #:use-module ((srfi srfi-1) #:select (append-map take))
  #:export (/lokke/reader-hash-map
            /lokke/reader-hash-set
            /lokke/reader-meta
            /lokke/reader-vector
            syntax-quote)
  #:re-export (ns)
  #:replace (quote unquote unquote-splicing)
  #:duplicates (merge-generics replace warn-override-core warn last))

;; 3.0 requires this, but it can't go in the (guile) #:select above
;; because *that* crashes 2.2
(cond-expand
  ;; note "guile-3" means >= 3
  (guile-3
   (use-modules ((guile) #:select (... else))))
  (else))


(define (convert-for-public-message expr)
  (define (convert expr)
    (cond
     ((null? expr) expr)
     ((list? expr)
      (case (car expr)
        ((/lokke/reader-vector)
         (cons (%scm-quote vector) (map convert (reader-vector-elts expr))))
        ((/lokke/reader-hash-map)
         (cons (%scm-quote hash-map) (map convert (reader-hash-map-elts expr))))
        ((/lokke/reader-hash-set)
         (cons (%scm-quote hash-set) (map convert (reader-hash-set-elts expr))))
        (else (map convert-for-public-message expr))))
     (else expr)))
  (convert expr))

(define-syntax synerr
  (syntax-rules ()
    ((_ name exp msg)
     (error (format #f "~s: ~a in form ~s" name msg
                    (convert-for-public-message (syntax->datum exp)))))))

;; If we eventually have a lower-level module for vector, hash-map,
;; and hash-set (to avoid circular references via ns, etc.), we could
;; just use-module above and avoid needing the direct @ refs here.

(define-syntax-rule (/lokke/reader-hash-map meta exp ...)
  (with-meta ((@ (lokke hash-map) hash-map) exp ...) meta))

(define-syntax-rule (/lokke/reader-hash-set meta exp ...)
  (with-meta ((@ (lokke hash-set) hash-set) exp ...) meta))

(define-syntax-rule (/lokke/reader-vector meta exp ...)
  (with-meta ((@ (lokke vector) vector) exp ...) meta))

(define-syntax-rule (/lokke/reader-meta x ...)
  (warn (format #f "Ignoring metadata in unsupported position: ~s"
                '(/lokke/reader-meta x ...))))

(define-syntax quote
  ;; Note that ~ and ~@ (i.e. unquote and unquote-splicing) still
  ;; expand symbols inside quoted forms, matching the JVM, but that's
  ;; handled by the reader.
  ;;
  ;; FIXME: could perhaps rewrite to scan, and just %scm-quote the whole value
  ;; if the form really is "const", i.e. has no internal maps/sets/vectors.
  (lambda (x)
    (syntax-case x (/lokke/reader-hash-map
                    /lokke/reader-hash-set
                    /lokke/reader-vector)

      ((_ (/lokke/reader-vector meta exp ...))
       #`(/lokke/reader-vector #,@(map (lambda (e) #`(quote #,e)) #'(meta exp ...))))

      ((_ (/lokke/reader-hash-map meta exp ...))
       #`(/lokke/reader-hash-map #,@(map (lambda (e) #`(quote #,e)) #'(meta exp ...))))

      ((_ (/lokke/reader-hash-set meta exp ...))
       #`(/lokke/reader-hash-set #,@(map (lambda (e) #`(quote #,e)) #'(meta exp ...))))

      ((_ (/lokke/reader-vector))
       (synerr "quote" x "internal error, reader vector missing argument"))
      ((_ (/lokke/reader-hash-map))
       (synerr "quote" x "internal error, reader hash-map missing argument"))
      ((_ (/lokke/reader-hash-set))
       (synerr "quote" x "internal error, reader hash-set missing argument"))

      ;; Explicitly match #nil, so it doesn't match (exp ...) below.
      ((_ nil) (eq? #nil (syntax->datum #'nil))
       #nil)

      ((_ (exp ...)) #`(list #,@(map (lambda (e) #`(quote #,e)) #'(exp ...))))

      ;; "leaf" value, including ()
      ((_ x) #'(%scm-quote x)))))


(define-syntax unquote
  (syntax-rules ()
    ((_ x ...) (syntax-error "invocation outside syntax-quote"))))

(define-syntax unquote-splicing
  (syntax-rules ()
    ((_ x ...) (syntax-error "invocation outside syntax-quote"))))


(define (pairify-map-entries ctx exps)
  ;; (a b c d) -> ((/lokke/reader-vector a b) ...)
  (let ((rvec-syn (datum->syntax ctx '/lokke/reader-vector)))
    (let loop ((rest exps))
      (cond
       ((null? rest) '())
       ((null? (cdr rest)) (error "Can't pairify odd length list" exps))
       (else (cons (cons* rvec-syn #nil (take rest 2))
                   (loop (cddr rest))))))))

(define-syntax syntax-quote
  ;; FIXME: could perhaps rewrite to scan, and just %scm-quote the whole value
  ;; if the form really is "const", i.e. has no internal maps/sets/vectors.

  ;; FIXME:? the jvm checks for even number of hash-map forms, but
  ;; then writes code that would allow an odd number at runtime,
  ;; e.g. `{~@(list 1 2)} is rejected, but `{~@(list 1) ~@(list 2 3)}
  ;; is not, but of course crashes later.

  (lambda (x)
    (define (synquote sub-syn)
      (syntax-case sub-syn (/lokke/reader-hash-map
                            /lokke/reader-hash-set
                            /lokke/reader-vector
                            unquote
                            unquote-splicing)

        ((unquote) (synerr "unquote" x "no arguments"))
        ((unquote exp) #'(exp))

        ((unquote-splicing) (synerr "unquote-splicing" x "no arguments"))

        ((unquote-splicing (/lokke/reader-vector meta exp ...)) #'(exp ...))

        ((unquote-splicing (/lokke/reader-hash-map meta exp ...))
         (pairify-map-entries #'sub-syn #'(exp ...)))

        ((unquote-splicing (/lokke/reader-hash-set meta exp ...)) #'(exp ...))

        ((unquote-splicing exp) #'(exp))


        ((/lokke/reader-vector nil exp ...) (eq? #nil (syntax->datum #'nil))
         #`(/lokke/reader-vector
            #nil
            #,@(map (lambda (e) #`(syntax-quote #,e))
                    #'(exp ...))))

        ((/lokke/reader-vector (/lokke/reader-hash-map kvs ...) exp ...)
         #`(/lokke/reader-vector
            #,@(map (lambda (e) #`(syntax-quote #,e))
                    #'((/lokke/reader-hash-map kvs ...) exp ...))))

        ((/lokke/reader-vector)
         (synerr "syntax-quote" x
                 "internal error, reader vector missing argument"))


        ((/lokke/reader-hash-map nil exp ...) (eq? #nil (syntax->datum #'nil))
         #`(/lokke/reader-hash-map
            #nil
            #,@(map (lambda (e) #`(syntax-quote #,e))
                    #'(exp ...))))

        ((/lokke/reader-hash-map (/lokke/reader-hash-map kvs ...) exp ...)
         #`(/lokke/reader-hash-map
            #,@(map (lambda (e) #`(syntax-quote #,e))
                    #'((/lokke/reader-hash-map kvs ...) exp ...))))

        ((/lokke/reader-hash-map)
         (synerr "syntax-quote" x
                 "internal error, reader hash-map missing argument"))


        ((/lokke/reader-hash-set nil exp ...) (eq? #nil (syntax->datum #'nil))
         #`(/lokke/reader-hash-set
            #nil
            #,@(map (lambda (e) #`(syntax-quote #,e))
                    #'(exp ...))))

        ((/lokke/reader-hash-set (/lokke/reader-hash-map kvs ...) exp ...)
         #`(/lokke/reader-hash-set
            #,@(map (lambda (e) #`(syntax-quote #,e))
                    #'((/lokke/reader-hash-map kvs ...) exp ...))))

        ((/lokke/reader-hash-set)
         (synerr "syntax-quote" x
                 "internal error, reader hash-set missing argument"))


        ;; Explicitly match #nil, so it doesn't match (exp ...) below.
        (nil (eq? #nil (syntax->datum #'nil))
         (list #nil))

        ((exp ...)
         #`((list
             #,@(map (lambda (e) #`(syntax-quote #,e))
                     #'(exp ...)))))

        ;; "leaf" value, including ()
        (x #'((quote x)))))

    (syntax-case x (/lokke/reader-hash-map
                    /lokke/reader-hash-set
                    /lokke/reader-vector
                    unquote
                    unquote-splicing)

      ((_ (unquote)) (synerr "unquote" x "no arguments"))
      ((_ (unquote exp)) #'exp)

      ((_ (unquote-splicing)) (synerr "unquotes-splicing" x "no arguments"))
      ((_ (unquote-splicing exp ...))
       (synerr "unquote-splicing" x "not inside list"))

      ((_ (/lokke/reader-vector exp ...))
       #`(/lokke/reader-vector #,@(append-map synquote #'(exp ...))))

      ((_ (/lokke/reader-hash-map exp ...))
       #`(/lokke/reader-hash-map #,@(append-map synquote #'(exp ...))))

      ((_ (/lokke/reader-hash-set exp ...))
       #`(/lokke/reader-hash-set #,@(append-map synquote #'(exp ...))))

      ;; Explicitly match #nil, so it doesn't match (exp ...) below.
      ((_ nil) (eq? #nil (syntax->datum #'nil))
       #nil)

      ((_ (exp ...))
       #`(list #,@(append-map synquote #'(exp ...))))

      ;; "leaf" value, including ()
      ((_ x) #'(quote x)))))
