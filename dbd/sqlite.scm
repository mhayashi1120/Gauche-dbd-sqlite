;;;
;;; dbd_sqlite
;;;

(define-module dbd.sqlite
  (export
   sqlite-libversion-number sqlite-libversion
   )
  )
(select-module dbd.sqlite)

;; Loads extension
(dynamic-load "dbd_sqlite")




