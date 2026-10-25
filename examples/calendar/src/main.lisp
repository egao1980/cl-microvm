(defpackage #:calendar-demo
  (:use #:cl)
  (:export #:main))
(in-package #:calendar-demo)

(defun say (control &rest args)
  (apply #'format t control args)
  (terpri)
  (finish-output))

(defun flag (value)
  (if value "yes" "no"))

(defun on (year month day)
  (datetime-protocol:make-date year month day))

(defun main ()
  ;; Постановление № 1466: 3 Jan → 9 Jan, 4 Jan → 31 Dec.
  (let ((cal (stack-calendars:russian-holidays-calendar :year 2026)))
    (say "ru-2026-01-09-holiday ~A" (flag (stack-calendars:holiday-p cal (on 2026 1 9))))
    (say "ru-2026-12-31-holiday ~A" (flag (stack-calendars:holiday-p cal (on 2026 12 31)))))
  ;; Постановление № 1314: Saturday 27 Apr 2024 is a working day.
  (let ((cal (stack-calendars:russian-holidays-calendar :year 2024)))
    (say "ru-2024-04-27-business-day ~A"
         (flag (stack-calendars:business-day-p cal (on 2024 4 27)))))
  (say "calendar-ok"))
