(defpackage #:hello
  (:use #:cl)
  (:export #:main))
(in-package #:hello)

(defun main ()
  (format t "hello-ok~%")
  (finish-output))
