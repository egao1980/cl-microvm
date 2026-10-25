;;;; Guest entry. No deps beyond SBCL, ASDF, and (on demand) Swank.
(require :asdf)
(setf *debugger-hook*
      (lambda (condition hook)
        (declare (ignore hook))
        (format *error-output* "cl-microvm: ~A~%" condition)
        (finish-output *error-output*)
        (sb-ext:exit :code 1)))

;; Fasls compiled in the packer already reference these contribs. The loader
;; interns those symbols before any top-level REQUIRE in the same file runs,
;; so the packages have to exist before ASDF loads the closure.
(require :sb-bsd-sockets)
(require :sb-posix)
(require :sb-rotate-byte)
(require :sb-cltl2)
(require :sb-introspect)

(defun env (name)
  (let ((value (uiop:getenv name)))
    (and value (plusp (length value)) value)))

(defun say (control &rest args)
  (apply #'format t control args)
  (terpri)
  (finish-output))

(defun setup-registry ()
  (asdf:initialize-source-registry
   '(:source-registry
     (:directory #p"/opt/swank/")
     (:tree #p"/opt/app/")
     (:tree #p"/opt/cl/")
     :ignore-inherited-configuration))
  (when (probe-file #p"/opt/cl/")
    (dolist (system-dir (uiop:subdirectories #p"/opt/cl/"))
      (dolist (version-dir (uiop:subdirectories system-dir))
        (let ((init (merge-pathnames "cl-repo-init.lisp" version-dir)))
          (when (probe-file init)
            (load init)))))))

(defun write-secret (text)
  ;; Same merge Swank 2.31 uses, plus the conventional ~/.slime-secret path.
  (let ((paths (list (merge-pathnames (user-homedir-pathname) #p".slime-secret")
                     (merge-pathnames ".slime-secret" (user-homedir-pathname)))))
    (dolist (path paths)
      (with-open-file (out path :direction :output :if-exists :supersede :if-does-not-exist :create)
        (write-line text out)))))

(defun random-secret ()
  (with-open-file (in "/dev/urandom" :element-type '(unsigned-byte 8))
    (with-output-to-string (out)
      (loop repeat 16
            for byte = (read-byte in)
            do (format out "~2,'0X" byte)))))

(defun start-swank ()
  (let* ((port (parse-integer (env "SWANK_PORT")))
         (interface (or (env "SWANK_INTERFACE") "0.0.0.0"))
         (secret (or (env "SWANK_SECRET") (random-secret))))
    (asdf:load-system "swank")
    (write-secret secret)
    (uiop:symbol-call :swank :create-server
                      :port port
                      :interface interface
                      :style :spawn
                      :dont-close t)
    (say "swank-port ~D" port)
    (say "swank-secret ~A" secret)))

(defun split-ws (line)
  (remove "" (uiop:split-string line :separator '(#\Space #\Tab)) :test #'string=))

(defun non-loopback-route-p ()
  (with-open-file (in "/proc/net/route" :if-does-not-exist nil)
    (when in
      (read-line in nil nil)
      (loop for line = (read-line in nil nil)
            while line
            for parts = (split-ws line)
            thereis (and (>= (length parts) 2)
                         (not (string= (first parts) "lo")))))))

(defun ipv4-address (text)
  (let ((parts (uiop:split-string text :separator ".")))
    (when (and (= 4 (length parts))
               (every (lambda (part) (and (plusp (length part)) (every #'digit-char-p part))) parts))
      (sb-bsd-sockets:make-inet-address text))))

(defun probe-tcp (host port)
  (let ((sock (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp))
        (addr (or (ipv4-address host)
                  (sb-bsd-sockets:host-ent-address (sb-bsd-sockets:get-host-by-name host)))))
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-connect sock addr port)
           t)
      (sb-bsd-sockets:socket-close sock))))

(defun run-probe ()
  (unless (member :sb-thread *features*)
    (error "SBCL was built without threads"))
  (let ((threads (loop repeat 4
                       collect (sb-thread:make-thread (lambda () (sleep 0.05) 1)))))
    (unless (= 4 (reduce #'+ (mapcar #'sb-thread:join-thread threads)))
      (error "thread join failed")))
  (say "threads-ok")
  (let ((path "/data/.probe"))
    (with-open-file (out path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-line "ok" out))
    (with-open-file (in path)
      (unless (string= "ok" (read-line in))
        (error "probe file mismatch"))))
  (say "fs-ok")
  (let ((host (env "CL_MICROVM_PROBE_HOST")))
    (cond
      (host
       (probe-tcp host (parse-integer (env "CL_MICROVM_PROBE_PORT"))))
      ((not (non-loopback-route-p))
       (error "no non-loopback route")))
    (say "net-ok")))

(defun invoke-entry (spec)
  (let ((colon (position #\: spec)))
    (unless colon
      (error "CL_ENTRY must be package:function, got ~A" spec))
    (let* ((package (string-upcase (subseq spec 0 colon)))
           (name (string-upcase (subseq spec (1+ colon))))
           (symbol (uiop:find-symbol* name package)))
      (funcall (fdefinition symbol)))))

(defun park ()
  (loop (sleep 3600)))

(setup-registry)
(let ((system (env "CL_SYSTEM"))
      (swank (env "SWANK_PORT")))
  (when swank
    (start-swank))
  (cond
    (system
     (asdf:load-system system)
     (let ((entry (env "CL_ENTRY")))
       (when entry
         (invoke-entry entry)))
     (if swank
         (park)
         (sb-ext:exit :code 0)))
    (swank
     (park))
    (t
     (run-probe)
     (sb-ext:exit :code 0))))
