;;; Copyright (C) 2020 Rob Browning <rlb@defaultvalue.org>
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

(define-module (lokke reader literal)
  #:use-module ((ice-9 match) #:select (match))
  #:use-module ((lokke hash-map) #:select (hash-map? kv-list)) 
  #:use-module ((lokke base metadata) #:select (meta with-meta))
  #:use-module ((lokke transmogrify) #:select (clj-instances->literals))
  #:use-module ((srfi srfi-1) #:select (proper-list?))
  #:export (reader-hash-map
            reader-hash-map?
            reader-hash-map-elts
            reader-hash-map-meta
            reader-hash-set
            reader-hash-set-elts
            reader-hash-set-meta
            reader-vector
            reader-vector?
            reader-vector-elts
            reader-vector-meta
            with-reader-meta))

;; For now, we'll still promise that the first item is the symbol
;; distinguishing the item, i.e. not require require the use of
;; reader-hash-set? predicates, etc.

(define (reader-vector meta . elts)
  (cons* '/lokke/reader-vector meta elts))

(define (reader-vector? x)
  (and (pair? x) (proper-list? x)
       (eq? '/lokke/reader-vector (car x))
       (begin
         (unless (pair? (cdr x))
           (error "No metadata in reader vector:" x))
         (unless (or (eq? #nil (cadr x))
                     (reader-hash-map? (cadr x)))
           (error "Invalid metadata in reader vector:" x))
         #t)))

(define (reader-vector-meta m) (cadr m))
(define (reader-vector-elts m) (cddr m))


(define (reader-hash-set meta . elts)
  (cons* '/lokke/reader-hash-set meta elts))

(define (reader-hash-set? x)
  (and (list? x) (eq? '/lokke/reader-hash-set (car x))))

(define (reader-hash-set-meta m) (cadr m))
(define (reader-hash-set-elts m) (cddr m))


(define (reader-hash-map meta . elts)
  (cons* '/lokke/reader-hash-map meta elts))

(define (reader-hash-map? x)
  (and (pair? x) (proper-list? x)
       (eq? '/lokke/reader-hash-map (car x))
       (let ((len (length x)))
         (unless (> len 1)
           (error "No metadata in reader map:" x))
         (unless (or (eq? #nil (cadr x))
                     (reader-hash-map? (cadr x)))
           (error "Invalid metadata in reader map:" x))
         (unless (even? len)
           (error "Missing value for key in reader map:" x))         
         #t)))

(define (reader-hash-map-meta m) (cadr m))
(define (reader-hash-map-elts m) (cddr m))


(define (with-reader-meta x meta)
  (unless (or (eq? #nil meta) (hash-map? meta))
    (scm-error 'wrong-type-arg 'with-reader-meta
               "metadata is not nil or a map: ~s" (list meta) (list meta)))
  (match x
    (((or '/lokke/reader-hash-set '/lokke/reader-hash-map '/lokke/reader-vector)
      existing-meta elt ...)
     (cons* (car x) (clj-instances->literals meta) elt))
    (_ (error "Reader cannot apply metadata to" x))))
