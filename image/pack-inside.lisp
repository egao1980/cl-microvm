;;;; Runs inside cl-microvm:builder. Installs the project closure with
;;;; cl-repository when the .asd has external deps, then compiles fasls
;;;; for this image's SBCL into /opt/cache.
(require :asdf)
(setf *debugger-hook*
      (lambda (condition hook)
        (declare (ignore hook))
        (format *error-output* "cl-microvm-packager: ~A~%" condition)
        (finish-output *error-output*)
        (sb-ext:exit :code 1)))

(defvar *system* (or (uiop:getenv "CL_SYSTEM")
                     (error "CL_SYSTEM is required")))

(asdf:initialize-source-registry
 '(:source-registry
   (:tree #p"/opt/app/")
   (:tree #p"/opt/cl-repository/")
   :ignore-inherited-configuration))

(defun dep-name (dep)
  (cond
    ((stringp dep) (string-downcase dep))
    ((and (symbolp dep) (not (keywordp dep))) (string-downcase (symbol-name dep)))
    ((and (consp dep) (eq (first dep) :version)) (dep-name (second dep)))
    ((and (consp dep) (eq (first dep) :feature))
     (when (uiop:featurep (second dep))
       (dep-name (third dep))))
    (t nil)))

(defun builtin-p (name)
  (or (member name '("asdf" "uiop" "swank") :test #'string=)
      (uiop:string-prefix-p "sb-" name)))

(defun external-deps (name)
  (let ((seen (make-hash-table :test #'equal))
        (external '()))
    (labels ((walk (system-name)
               (let ((n (string-downcase system-name)))
                 (unless (or (gethash n seen) (builtin-p n))
                   (setf (gethash n seen) t)
                   (let ((sys (asdf:find-system n nil)))
                     (cond
                       ((null sys)
                        (pushnew n external :test #'string=))
                       (t
                        (dolist (dep (asdf:system-depends-on sys))
                          (let ((child (dep-name dep)))
                            (when child
                              (walk child)))))))))))
      (let ((sys (or (asdf:find-system name nil)
                     (error "system ~A is not on /opt/app" name))))
        (dolist (dep (asdf:system-depends-on sys))
          (let ((child (dep-name dep)))
            (when child
              (walk child))))))
    (nreverse external)))

(defun quicklisp-source-p (system)
  (let* ((sys (if (typep system 'asdf:system)
                  system
                  (asdf:find-system system nil)))
         (file (and sys (ignore-errors (asdf:system-source-file sys))))
         (text (and file (namestring file))))
    (and text (search "quicklisp" text :test #'char-equal))))

(defun load-client ()
  (let ((setup (uiop:getenv "QUICKLISP_SETUP")))
    (when (and setup (probe-file setup))
      (load setup)))
  ;; The client checkout is not a closed tree: cl-oci-client needs sibling
  ;; systems such as http-protocol. CL_WORKSPACE is that tree, and only for
  ;; this load. Quicklisp covers the rest of the bootstrap.
  (let ((workspace (uiop:getenv "CL_WORKSPACE")))
    (asdf:initialize-source-registry
     `(:source-registry
       (:tree #p"/opt/app/")
       (:tree #p"/opt/cl-repository/")
       ,@(when (and workspace (plusp (length workspace)))
           `((:tree ,(uiop:ensure-directory-pathname workspace))))
       :inherit-configuration)))
  (asdf:load-system "cl-repository-client"))

(defun image-source-p (system)
  (let* ((sys (if (typep system 'asdf:system)
                  system
                  (asdf:find-system system nil)))
         (file (and sys (ignore-errors (asdf:system-source-file sys))))
         (text (and file (namestring file))))
    (and text
         (or (uiop:string-prefix-p "/opt/app/" text)
             (uiop:string-prefix-p "/opt/cl/" text)
             (uiop:string-prefix-p "/opt/cl-repository/" text)))))

(defun isolate-closure ()
  "The guest has /opt/app and /opt/cl only. Forget every system the
bootstrap found in Quicklisp or CL_WORKSPACE so ENSURE-SYSTEM-DEPENDENCIES
installs that closure from GHCR. Packages already loaded stay loaded."
  (setf asdf:*system-definition-search-functions*
        (remove-if (lambda (fn)
                     (and (symbolp fn)
                          (let ((pkg (symbol-package fn)))
                            (and pkg
                                 (let ((name (package-name pkg)))
                                   (or (search "QUICKLISP" name :test #'char-equal)
                                       (member name '("QL" "QL-DIST" "QL-SETUP")
                                               :test #'string-equal)))))))
                   asdf:*system-definition-search-functions*))
  (asdf:initialize-source-registry
   '(:source-registry
     (:tree #p"/opt/app/")
     (:tree #p"/opt/cl/")
     (:tree #p"/opt/cl-repository/")
     :ignore-inherited-configuration))
  (dolist (name (copy-list (asdf:registered-systems)))
    (let ((sys (asdf:registered-system name)))
      (when (and sys (not (image-source-p sys)))
        (asdf:clear-system name)))))

(defun assert-no-quicklisp (name)
  (let ((seen (make-hash-table :test #'equal)))
    (labels ((walk (system-name)
               (let ((n (string-downcase system-name)))
                 (unless (or (gethash n seen) (builtin-p n))
                   (setf (gethash n seen) t)
                   (let ((sys (or (asdf:find-system n nil)
                                  (error "closure system ~A is not installed" n))))
                     (when (quicklisp-source-p sys)
                       (error "refusing Quicklisp system ~A from ~A"
                              n (namestring (asdf:system-source-file sys))))
                     (dolist (dep (asdf:system-depends-on sys))
                       (let ((child (dep-name dep)))
                         (when child
                           (walk child)))))))))
      (walk name))))

(defun install-deps ()
  (load-client)
  (isolate-closure)
  (setf (symbol-value (find-symbol "*SYSTEMS-ROOT*" :cl-repository-client/installer))
        (uiop:ensure-directory-pathname #p"/opt/cl/"))
  (uiop:symbol-call :cl-repo :add-registry "https://ghcr.io"
                    :namespace "egao1980/cl-systems" :priority :prepend)
  (uiop:symbol-call :cl-repo :ensure-system-dependencies *system*
                    :also-tests nil :default-source :oci)
  (let ((missing (ignore-errors
                  (symbol-value (find-symbol "*MISSING-DEPS-ACCUMULATOR*"
                                             :cl-repository-client/quickload)))))
    (when missing
      (error "not on ghcr.io/egao1980/cl-systems: ~{~A~^, ~}" missing)))
  (assert-no-quicklisp *system*))

(let ((deps (external-deps *system*)))
  (when deps
    (install-deps)))
(asdf:load-system *system*)
(let* ((sys (asdf:find-system *system*))
       (version (or (asdf:component-version sys) "0.0.0")))
  (ensure-directories-exist "/out/")
  (with-open-file (out "/out/meta" :direction :output :if-exists :supersede)
    (format out "system ~A~%version ~A~%" *system* version)))
(sb-ext:exit :code 0)
