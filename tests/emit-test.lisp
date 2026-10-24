(defpackage #:cl-microvm-packager/tests
  (:use #:cl #:rove))
(in-package #:cl-microvm-packager/tests)

(deftest image-ref-downcases-the-system
  (ok (string= "ghcr.io/egao1980/cl-microvm/hello:0.1.0"
               (cl-microvm-packager:image-ref "Hello" "0.1.0"))))
