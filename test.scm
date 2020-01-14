;;;
;;; Test dbd_sqlite
;;;

(use gauche.test)

(test-start "dbd_sqlite")
(use dbd_sqlite)
(test-module 'dbd_sqlite)

;; The following is a dummy test code.
;; Replace it for your tests.
(test* "test-dbd_sqlite" "dbd_sqlite is working"
       (test-dbd_sqlite))

;; If you don't want `gosh' to exit with nonzero status even if
;; the test fails, pass #f to :exit-on-failure.
(test-end :exit-on-failure #t)




