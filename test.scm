;;;
;;; Test dbd_sqlite
;;;

(use gauche.test)

(test-start "dbd.sqlite")
(use dbd.sqlite)
(test-module 'dbd.sqlite)

(test* "get version with no error" #t
       (sqlite-libversion)
       (^ [_ x] (string? x)))

(test-log "libsqlite Version: ~a" (sqlite-libversion))

(test* "getversion with no error" #t
       (sqlite-libversion-number)
       (^ [_ x] (number? x)))


(use dbi)
(use file.util)

(debug-print-width #f)

(define *temp-sqlite* #f)

(receive (oport file) (sys-mkstemp (build-path (temporary-directory) "gauche-sqlite"))
  (close-port oport)
  (test-log "sqlite file: ~s" file)
  (set! *temp-sqlite* file))

(define *connection* #f)
(set! *connection* (dbi-connect #"dbi:sqlite:~|*temp-sqlite*|"))

(use dbd.sqlite)

(test* "Sqlite Connection" <sqlite-connection>
       (class-of *connection*))

(test* "Sqlite connection is open" #t
       (dbi-open? *connection*))

;; TODO connect option

;;;
;;; DDL
;;;

(dolist (q `("SELECT 1"
             "SELECT 1;"
             "SELECT 1; SELECT 2"
             "SELECT 1; SELECT 2;"
             ;; Last char is space
             "SELECT 1; SELECT 2; "))
  (test* #"Query Preparation ~|q|" <sqlite-query>
         (dbi-prepare *connection* q)
         (^ [_ x] (class-of x))))

(test* "Execute with no error" #t
       (let ([q (dbi-prepare
                 *connection*
                 "CREATE TABLE hoge
  (
   id INTEGER NOT NULL
 , name TEXT NOT NULL
 , created DATETIME NOT NULL
 , flag INTEGER
 , value INTEGER
 , rate FLOAT
 , PRIMARY KEY (id)
  );")])
         (dbi-execute q))
       (^ [_ x] x #t))

(use gauche.collection)

(define (query->list q . params)
  (map identity (apply dbi-execute q params)))

(define (sql->result sql . params)
  (let* ([q (dbi-prepare *connection* sql)])
    (apply query->list q params)))

(define (test-sql name expected sql . params)
  (test* name expected
         (apply sql->result sql params)))

(define (sql->result* sql . params)
  (let* ([q (dbi-prepare *connection* sql :pass-through #t)])
    (apply query->list q params)))

(define (test-sql* name expected sql . params)
  (test* name expected
         (apply sql->result* sql params)))

;; Multiple statement
(test-sql "Multiple statement and get last statement result."
          `(#(1 "n1") #(2 "n2") #(3 "n3"))
          "INSERT INTO hoge(id, name, created) VALUES (1, 'n1', '2020-01-01 00:01:02');
INSERT INTO hoge(id, name, created) VALUES (2, 'n2', '2020-02-03 01:02:03');
INSERT INTO hoge(id, name, created) VALUES (3, 'n3', '2020-03-04 02:03:04');
SELECT id, name FROM hoge" )

;; Ignore first statement result
(test-sql "Multiple statements and get last statement result. 2"
          `(#(1 2))
          "SELECT 1; SELECT 1, 2;" )

(test-sql "TODO"
          `(#(1 2 "three" 4.0 #f))
          "SELECT ?, ?, ?, ?, ?"
          1 2 "three" 4.0 #f)

;; TODO not like pass-through u8vector not supported.

;; TODO last_insert_rowid
;; TODO check changes after UPDATE, DELETE, INSERT

;;;
;;; Pass through
;;;

;; Get by ":" prefix param
(test-sql* "Select by \":\" parameter" `(#("n1")) "SELECT name FROM hoge WHERE id = :id" :id 1)
(test-sql* "Select by \"@\" parameter" `(#("n1")) "SELECT name FROM hoge WHERE id = @id" :@id 1)
(test-sql* "Select by \"$\" parameter" `(#("n1")) "SELECT name FROM hoge WHERE id = $id" :$id 1)
(test-sql* "Select by index parameter 1-1" `(#("n1")) "SELECT name FROM hoge WHERE id = ?" 1)
(test-sql* "Select by index parameter 1-2" `(#("n2" #f)) "SELECT name, ? FROM hoge WHERE id = ?" #f 2)
(test-sql* "Select by index parameter 2" `(#("n1")) "SELECT name FROM hoge WHERE id = :001" :001 1)
(test-sql* "Select by index parameter 3" `(#("n1")) "SELECT name FROM hoge WHERE id = ?002" :?002 1)
(test-sql* "Select by index parameter 4" `(#("n1")) "SELECT name FROM hoge WHERE id = ?3" :?3 1)
(test-sql* "Select by index parameter 5" `(#("n1")) "SELECT name FROM hoge WHERE id = ?4" #f #f #f :?4 1)

(test-sql* "Select binding parameter"
           `(#("1" 2 #u8(5 6) "1" #f 8))
             "SELECT :a1, $a2, @a3, ?1, :a4null, ?"
             :a1 "1"
             :$a2 2
             :@a3 #u8(5 6)
             :?1 "no meaning"
             ;; Not bound but no error.
             ;; :a4null #f
             ;; nameless parameter
             8
             )


(let* ([q (dbi-prepare *connection* "SELECT :a" :pass-through #t :strict-bind? #t)])
  
  (test* "Strict bind (No parameter supplied.)" (test-error)
         (query->list q))

  ;; TODO reconsider
  ;; (test* "Strict bind (Extra parameter supplied.)" (test-error)
  ;;        (query->list q :a 1 :b 3))
  )

;; TODO text insert -> select -> update -> select
;; TODO long range test -> insert -> select -> update -> select
;; TODO float test
;; TODO Prepared reuse (need reset?)
;; TODO generator

;; TODO edge case



;;;
;;; SQL syntax error
;;;

(define (error-test name query)
  (test* name (test-error)
        (sql->result query)))

(error-test "No existing object" "SELECT 1 FROM hoge1")
(error-test "First statement has no existing object" "SELECT 1 FROM hoge1; No meaning statement;")
(error-test "Last statement has syntax error" "SELECT 1 FROM hoge; No meaning statement;")
(error-test "Empty statement" "SELECT 1 ; ;")

;;;
;;; Teardown
;;;

(dbi-close *connection*)

(test* "Connection is closed" #f
       (dbi-open? *connection*))

;; If you don't want `gosh' to exit with nonzero status even if
;; the test fails, pass #f to :exit-on-failure.
(test-end :exit-on-failure #t)




