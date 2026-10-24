(in-package #:cl-microvm-packager)

(defun image-ref (system version)
  "GHCR name of the image EMIT-IMAGE builds for SYSTEM at VERSION."
  (format nil "ghcr.io/egao1980/cl-microvm/~(~A~):~A" system version))

(defun emit-image (&key system project tag (base "cl-microvm:sbcl-2.6.7"))
  "Run scripts/emit-image.sh. Deps are resolved inside the linux builder, not on the host."
  (check-type system string)
  (let* ((dir (uiop:ensure-directory-pathname project))
         (script (asdf:system-relative-pathname "cl-microvm-packager" "scripts/emit-image.sh"))
         (argv (list (namestring script)
                     system
                     (namestring dir)
                     (or tag "")
                     base)))
    (let ((output (uiop:run-program argv :output :string :error-output *error-output*)))
      (write-string output)
      (finish-output)
      (or (loop for line in (uiop:split-string output :separator '(#\Newline))
                when (uiop:string-prefix-p "ref " line)
                  return (subseq line 4))
          (image-ref system "see-build-log")))))
