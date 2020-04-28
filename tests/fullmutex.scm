#!/usr/bin/env gosh

(use dbi)
(use util.match)

(define (test-fullmutex db)
  (let1 c (dbi-connect #"dbi:sqlite:~|db|;fullmutex;")
    (dotimes (i 5)
      #?= (relation-rows (dbi-do c "SELECT * FROM hoge"))
      (sys-sleep 1))
    (dbi-close c)
    0))

(define (main args)
  (match (cdr args)
    [(db)
     (test-fullmutex db)]
    [else
     (exit 1)]))