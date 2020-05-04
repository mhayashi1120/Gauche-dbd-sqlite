#!/usr/bin/env gosh


(print "---------- Basic access ------------")

;;;
;;; Basic access
;;;

(use dbi)

(let1 con (dbi-connect "dbi:sqlite:sample.sqlite")
  (unwind-protect
   (begin
     (dbi-do con "CREATE TABLE account (id PRIMARY KEY, name);")
     (let ([insert (dbi-prepare con "INSERT INTO account VALUES (?, ?);")])
       (dbi-execute insert 1 "John Doe")
       (dbi-execute insert 2 "名無しさん")

       (let* ([result (dbi-do con "SELECT id, name FROM account")]
              [getter (relation-accessor result)])
         (map
          (^r
           (format #t "ID: ~s Name: ~s\n" (getter r "id") (getter r "name")))
          (relation-rows result)))))
   (dbi-close con)))


(print "---------- Simplify SELECT ------------")

;;;
;;; Simplify match library & <sequence>
;;;

(use util.match)
(use gauche.sequence)

(let1 con (dbi-connect "dbi:sqlite:sample.sqlite")
  (unwind-protect
   (map
    (match-lambda
     [#(id name)
     (format #t "ID: ~s Name: ~s\n" id name)])
    (dbi-do con "SELECT id, name FROM account"))
   (dbi-close con)))



;;;
;;; Fullmutex options
;;;

(let1 con (dbi-connect "dbi:sqlite:sample.sqlite;fullmutex;timeout=3000;")
  ;; ***do-something in multi-thread***
  )



(print "---------- Named binding  and Persistent query ------------")

;;;
;;; Named bindings with pass-through query
;;;

(let1 con (dbi-connect "dbi:sqlite:sample.sqlite;")
  (unwind-protect
   (begin
     (let1 i (dbi-prepare con "INSERT INTO account (id, name) VALUES (:id, :name)"
                          :pass-through #t :persistent #t)
       (dbi-execute i :id 3 :name "hoge")
       (dbi-execute i :id 4 :name "hoge hoge")
       (dbi-execute i :id 5 :name "hoge hoge hoge"))
     (map
      (match-lambda
       [#(id name)
        (format #t "ID: ~s Name: ~s\n" id name)])
      (dbi-do con "SELECT id, name FROM account")))
   (dbi-close con)))


