;;;
;;; dbd_sqlite
;;;

(define-module dbd.sqlite
  (export test-dbd_sqlite ;; dummy
          sqlite-libversion-number sqlite-libversion
          )
  )
(select-module dbd.sqlite)

;; Loads extension
(dynamic-load "dbd_sqlite")

;;
;; Put your Scheme definitions here
;;



