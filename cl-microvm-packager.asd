(defsystem "cl-microvm-packager"
  :version "0.1.0"
  :description "Pack a project .asd and its GHCR closure into a cl-microvm image."
  :author "egao1980"
  :license "MIT"
  :depends-on ("cl-repository-client")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "emit"))
  :in-order-to ((test-op (test-op "cl-microvm-packager/tests"))))

(defsystem "cl-microvm-packager/tests"
  :depends-on ("cl-microvm-packager" "rove")
  :pathname "tests"
  :components ((:file "emit-test"))
  :perform (test-op (op c)
             (symbol-call :rove :run c)))
