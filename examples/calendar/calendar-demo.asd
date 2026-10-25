(defsystem "calendar-demo"
  :version "0.1.0"
  :description "Russian holiday decree demo packed from ghcr.io/egao1980/cl-systems."
  :author "egao1980"
  :license "MIT"
  :depends-on ("cl-stack-calendars")
  :serial t
  :pathname "src"
  :components ((:file "main")))
