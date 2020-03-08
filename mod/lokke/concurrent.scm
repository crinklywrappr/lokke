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

;; This module must not depend on (lokke collection) because because
;; it depends on (lokke base syntax) which depends on (lokke base
;; destructure) which depends on hash-map which depends on this.

(define-module (lokke concurrent)
  #:use-module ((ice-9 atomic) #:select (make-atomic-box))
  #:use-module ((ice-9 futures) #:select ((future . %scm-future) touch))
  #:use-module (oop goops)
  #:use-module ((lokke metadata) #:select (alter-meta! meta))
  #:use-module ((lokke scm atom)
                #:select (atom?
                          atom
                          atom-add-watch
                          atom-alter-meta!
                          atom-compare-and-set!
                          atom-deref
                          atom-meta
                          atom-remove-watch
                          atom-reset!
                          atom-set-validator!
                          atom-swap!))
  #:export (<atom>
            alter-meta!
            atom?
            add-watch
            remove-watch
            deref
            future
            reset!
            set-validator!
            swap!)
  #:re-export (atom)
  #:duplicates (merge-generics replace warn-override-core warn last))

(define <atom> (class-of (make-atomic-box #t)))
(define (atom? x) (is-a? x <atom>))
(define-method (deref (a <atom>)) (atom-deref a))
(define-method (reset! (a <atom>) newval) (atom-reset! a newval))
(define-method (swap! (a <atom>) . args) (apply atom-swap! a args))
(define-method (compare-and-set! (a <atom>) oldval newval)
  (apply atom-compare-and-set! a oldval newval))

(define-method (add-watch (a <atom>) key fn) (atom-add-watch a key fn))
(define-method (remove-watch (a <atom>) key) (atom-remove-watch a key))
(define-method (set-validator! (a <atom>) validate)
  (atom-set-validator! a validate))

(define-method (meta (a <atom>)) (atom-meta a))
(define-method (alter-meta! (a <atom>) f . args)
  (apply atom-alter-meta! a f args))


;; Can't just alias guile futures because this doesn't work w/goops:
;;   (define <future> (@@ (ice-9 futures) <future>))
;; think maybe because it's a record, and even if (class-of
;; (%scm-future #f)) would work, we can't use it because it deadlocks
;; compilation somehow right now (guile 2.2.6).

(define-class <future> ()
  (scm-future #:init-keyword #:scm-future))

(define-method (deref (x <future>))
  (touch (slot-ref x 'scm-future)))

(define-syntax-rule (future exp ...)
  (make <future>
    ;; Provide our version of binding conveyance by transferring the state
    #:scm-future (let ((bindings (current-dynamic-state)))
                   (%scm-future
                    (with-dynamic-state bindings (lambda () exp ...))))))
