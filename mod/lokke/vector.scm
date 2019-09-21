;;; Copyright (C) 2019 Rob Browning <rlb@defaultvalue.org>
;;;
;;; This project is free software; you can redistribute it and/or
;;; modify it under the terms of (at your option) either of the
;;; following two licences:
;;;
;;;   1) The GNU Lesser General Public License as published by the
;;;      Free Software Foundation; either version 2.1, or (at your
;;;      option) any later version.
;;;
;;;   2) The Eclipse Public License; either version 1.0 or (at your
;;;      option) any later version.

(read-set! keywords 'postfix)  ;; srfi-88

(define-module (lokke vector)
  use-module: (oop goops)
  use-module: ((lokke collection)
               select: (<coll>
                        <seq>
                        assoc
                        coll?
                        conj
                        contains?
                        count
                        counted?
                        empty
                        empty?
                        find
                        first
                        get
                        nth
                        reduce
                        rest
                        seq
                        update))
  use-module: ((lokke base map-entry) select: (map-entry))
  use-module: ((lokke pr) select: (*out* pr pr-str print print-str))
  use-module: ((lokke scm vector)
                select: (<lokke-vector>
                         list->lokke-vector
                         lokke-vec
                         lokke-vector
                         lokke-vector->list
                         lokke-vector-assoc
                         lokke-vector-conj
                         lokke-vector-length
                         lokke-vector-ref
                         lokke-vector?
                         vector->lokke-vector))
  replace: (vector vector?)  export: (vec)
  re-export: (assoc
              conj
              contains?
              count
              counted?
              empty
              empty?
              find
              first
              get
              nth
              pr
              print
              rest
              seq
              update)
  duplicates: (merge-generics replace warn-override-core warn last))

(define vector? lokke-vector?)

(define-method (conj (v <lokke-vector>) . xs)
  (reduce (lambda (result x)
            (lokke-vector-conj result x))
          v
          xs))

(define empty-vector (@@ (lokke scm vector) lokke-empty-vector))

(define (vector . items) (list->lokke-vector items))
(define (vec coll) (reduce lokke-vector-conj empty-vector coll))

(define (read-only-str s) (substring/read-only s 0))

;; FIXME: rewrite some of the collection -> string functions?

(define (render-str v render)
  (let ((length (lokke-vector-length v)))
    (if (zero? length)
        "[]"
        (read-only-str
         (string-append "[" (string-join (lokke-vector->list v) " ") "]")))))

(define-method (pr-str (v <lokke-vector>)) (render-str v pr))
(define-method (print (v <lokke-vector>)) (render-str v print))

(define (show-vector v emit)
  (let ((length (lokke-vector-length v)))
    (if (zero? length)
        (display "[]" (*out*))
        (begin
          (display "[" (*out*))
          (emit (lokke-vector-ref v 0))
          (do ((i 1 (1+ i)))
              ((= i length))
            (display " " (*out*))
            (emit (lokke-vector-ref v i)))
          (display "]" (*out*))))))

(define-method (pr (v <lokke-vector>)) (show-vector v pr))
(define-method (print (v <lokke-vector>)) (show-vector v print))

(define-method (count (v <lokke-vector>)) (lokke-vector-length v))
(define-method (empty (v <lokke-vector>)) empty-vector)
(define-method (empty? (v <lokke-vector>)) (zero? (lokke-vector-length v)))

(define-method (assoc (v <lokke-vector>) . indexes-and-values)
  (apply lokke-vector-assoc indexes-and-values))

(define (valid-index? v i)
  (and (integer? i) (>= i 0) (< i (lokke-vector-length v))))

(define-method (contains? (v <lokke-vector>) i)
  (valid-index? v i))

(define (valid-index? v i)
  (and (integer? i) (>= i 0) (< i (lokke-vector-length v))))

(define-method (contains? (v <lokke-vector>) i)
  (valid-index? v i))

(define-method (nth (v <lokke-vector>) i) (lokke-vector-ref v i #nil))
(define-method (nth (v <lokke-vector>) i not-found)
  (lokke-vector-ref v i not-found))

(define-method (get (v <lokke-vector>) i) (lokke-vector-ref v i #nil))
(define-method (get (v <lokke-vector>) i not-found)
  (lokke-vector-ref v i not-found))

(define-method (find (v <lokke-vector>) i)
  (if (valid-index? v i)
      (map-entry i (lokke-vector-ref v i))
      #nil))

(define-method (update (v <lokke-vector>) i f . args)
  (lokke-vector-assoc v i (f (lokke-vector-ref v i #nil))))

;; FIXME: perhaps a generic vec-seq for things with O(1) i ref?

(define-class <lokke-vector-seq> (<seq>)
  (v init-keyword: v:)
  (i init-keyword: i: init-value: 0))

(define-method (seq (v <lokke-vector>))
  (if (zero? (lokke-vector-length v))
      #nil
      (make <lokke-vector-seq> v: v)))

(define-method (seq (s <lokke-vector-seq>))
  (let* ((i (slot-ref s 'i))
         (v (slot-ref s 'v)))
    (if (< i (lokke-vector-length v))
        s
        #nil)))

(define-method (first (x <lokke-vector-seq>))
  (let* ((i (slot-ref x 'i))
         (v (slot-ref x 'v)))
    (if (< i (lokke-vector-length v))
        (lokke-vector-ref v i)
        #nil)))

(define-method (rest (x <lokke-vector-seq>))
  (let ((v (slot-ref x 'v))
        (i (slot-ref x 'i)))
    (make <lokke-vector-seq> v: v i: (1+ i))))

(define-method (counted? (vs <lokke-vector-seq>)) #t)

(define-method (count (x <lokke-vector-seq>))
  (let ((v (slot-ref x 'v))
        (i (slot-ref x 'i)))
    (- (lokke-vector-length v) i)))
