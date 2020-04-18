;;;
;;; Test dbd_sqlite
;;;

(use gauche.test)

(test-start "dbd.sqlite")
(use dbd.sqlite)
(test-module 'dbd.sqlite)

(test* "get and print version with no error" #t
       (sqlite-libversion)
       (^ [_ x] (string? x)))

(test* "get and print version with no error" #t
       (sqlite-libversion-number)
       (^ [_ x] (number? x)))


;; If you don't want `gosh' to exit with nonzero status even if
;; the test fails, pass #f to :exit-on-failure.
(test-end :exit-on-failure #t)




