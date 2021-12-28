;;; Copyright (C) 2019-2021 Rob Browning <rlb@defaultvalue.org>
;;; SPDX-License-Identifier: LGPL-2.1-or-later OR EPL-1.0+

(define-module (lokke ns clojure test)
  #:use-module ((lokke scm test-anything) #:select (tap-test-runner))
  #:use-module ((srfi srfi-64)
                #:select (test-assert
                          test-begin
                          test-end
                          test-equal
                          test-error
                          test-group
                          test-runner-current
                          test-runner-fail-count))
  #:export (begin-tests
            deftest
            end-tests
            is
            testing)
  #:duplicates (merge-generics replace warn-override-core warn last))

(define* (begin-tests suite-name)
  (when (equal? "tap" (getenv "LOKKE_TEST_PROTOCOL"))
    (test-runner-current (tap-test-runner)))
  (test-begin (if (symbol? suite-name)
                  (symbol->string suite-name)
                  suite-name)))

(define-syntax testing
  (syntax-rules ()
    ((_ what test ...) (test-group what (begin #t test ...)))))

;; FIXME: support *load-tests*?
;; FIXME: deftest should of course not be executing the code immediately

(define-syntax-rule (deftest name body ...)
  (testing (symbol->string 'name)
    body ...))

(define* (end-tests #:optional suite-name #:key exit?)
  (let ((failed (test-runner-fail-count (test-runner-current))))
    (if suite-name
        (test-end (if (symbol? suite-name)
                      (symbol->string suite-name)
                      suite-name))
        (test-end))
    (when exit?
      (exit (if (zero? failed) 0 2)))))

;; For now just supports (is x) and (is (= x y)), since that's easy to
;; do with srfi-64, but this will almost certainly need an overhaul,
;; and/or moving away from the srfi, and mere syntax pattern matching.

(define-syntax is
  (syntax-rules (= thrown?) ;; FIXME: change literals to explicit pattern guards?
    ((_ (= expected expression)) (test-equal expected expression))
    ((_ (= expected expression) msg) (test-equal msg expected expression))
    ((_ (thrown? ex-type body ...)) (test-error ex-type body ...))
    ((_ expression) (test-assert expression))
    ((_ expression msg) (test-assert msg expression))))
