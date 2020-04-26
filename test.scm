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

;;;
;;; Basic construction
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
 , value OBJECT
 , PRIMARY KEY (id)
  );")])
         (dbi-execute q))
       (^ [_ x] x #t))

(use gauche.collection)
(use util.match)

(define (query->result q . params)
  (match (apply dbi-execute q params)
    [(? (^x (is-a? x <relation>)) r)
     (relation-rows r)]
    [x
     x]))

(define (sql->result sql . params)
  (let* ([q (dbi-prepare *connection* sql)])
    (apply query->result q params)))

(define (test-sql name expected sql . params)
  (test* name expected
         (apply sql->result sql params)))

(define (sql->result* sql . params)
  (let* ([q (dbi-prepare *connection* sql :pass-through #t)])
    (apply query->result q params)))

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

(test-sql "Empty result set"
          `()
          "SELECT * FROM hoge WHERE id = 100" )

(test-sql "text.sql parser prepared"
          `(#(1 2 "three" 4.0 #f))
          "SELECT ?, ?, ?, ?, ?"
          1 2 "three" 4.0 #f)

(test-sql "Not like pass-through query u8vector not supported."
          (test-error)
          "SELECT ?"
          #u8(1 2 3))

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
           `(#("1" 2 #u8(5 6) "1" #f 8 "LAST"))
             "SELECT :a1, $a2, @a3, ?1, :a4null, ?, :last"
             :a1 "1"
             :$a2 2
             :@a3 #u8(5 6)
             :?1 "no meaning"
             ;; Not bound but no error.
             ;; :a4null #f
             ;; nameless parameter
             8
             :last "LAST")


(let* ([q (dbi-prepare *connection* "SELECT :a" :pass-through #t :strict-bind? #t)])
  
  (test* "Strict bind (No parameter supplied.)" (test-error)
         (query->result q))

  ;; TODO reconsider
  ;; (test* "Strict bind (Extra parameter supplied.)" (test-error)
  ;;        (query->result q :a 1 :b 3))
  )

(test-log "Range log for pass-through query")
(let ([update (dbi-prepare *connection* "UPDATE hoge SET value = :value WHERE id = :id " :pass-through #t)]
      [select (dbi-prepare *connection* "SELECT value FROM hoge WHERE id = :id " :pass-through #t)])
  (dolist (testcase `(("Positive max integer" #x7fffffffffffffff)
                      ("Negative max integer" #x-8000000000000000)
                      ("Zero" 0)
                      ("Overflow long long (64bit integer)" #x8000000000000000 ,(test-error))
                      ("Overflow long long (64bit integer)" #x-8000000000000001 ,(test-error))
                      ("Large text" ,(make-string #xff #\a))
                      ))
    (match testcase
      [(name value)
       (test* #"~|name| UPDATE"
              1
              (query->result
               update 
               :value value
               :id 1))

       (test* #"~|name| SELECT"
              `(#(,value))
              (query->result
               select
               :id 1))]

      [(name value expected)
       (test* name
              expected
              (query->result
               update
               :value value
               :id 1))])))

(test-log "Transaction test")
(sql->result "BEGIN;")
(test-sql* "Insert in transaction"
           1
           "INSERT INTO hoge (id, name, value, created) VALUES (:id, :name, :value, :created)"
           :id 4
           :name "name4"
           :value 10
           :created "2020-04-01")
(test-sql* "Select in transaction found."
           `(#(4))
           "SELECT id FROM hoge WHERE id = :id"
           :id 4)
(sql->result "ROLLBACK;")
(test-sql* "Select after rollback is not found"
           `()
           "SELECT id FROM hoge WHERE id = :id"
           :id 4)

(sql->result "BEGIN;")
(test-sql* "Insert in transaction"
           1
           "INSERT INTO hoge (id, name, value, created) VALUES (:id, :name, :value, :created)"
           :id 4
           :name "name4"
           :value 10
           :created "2020-04-01")
(sql->result "COMMIT;")
(test-sql* "Select in transaction found."
           `(#(4))
           "SELECT id FROM hoge WHERE id = :id"
           :id 4)

(test-log "Generator (cursor) test")
(use gauche.generator)

(let* ([query (dbi-prepare *connection* "SELECT id FROM hoge ORDER BY id")]
       [result (dbi-execute query)]
       [gen (x->generator result)]
       )
  (test* "generator (like cursor) 1" #(1) (gen))
  (test* "generator (like cursor) 2" #(2) (gen))
  (test* "Map all results" '(#(1) #(2) #(3) #(4)) (relation-rows result))
  (test* "Again Map all results" '(#(1) #(2) #(3) #(4)) (relation-rows result))
  (dbi-close query)
  (test* "query is closed" #f (dbi-open? query))
  (dbi-close result)
  (test* "Result is closed" #f (dbi-open? result)))




;; TODO test stmt closing
;; TODO float test
;; TODO edge case
;; TODO last_insert_rowid
;; TODO <relation> test
;; TODO <sequence> test

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


;;;
;;; Misc connection
;;;

;; memory sqlite
(set! *connection* (dbi-connect #"dbi:sqlite::memory:"))

(dbi-do *connection* "CREATE TABLE hoge (id, name);")
(test* "Insert 1" 1
       (dbi-do *connection* "INSERT INTO hoge VALUES(?, ?);" '() 1 "name1"))
(test* "Insert 2, 3" 2
       (dbi-do *connection* "INSERT INTO hoge VALUES(?, ?), (?, ?);" '() 2 "name2" 3 "name3"))
(test* "Select inserted"
       `(#(1 "name1") #(2 "name2") #(3 "name3"))
       (map identity (dbi-do *connection* "SELECT * FROM hoge")))

(dbi-close *connection*)

;; TODO connect option


;; If you don't want `gosh' to exit with nonzero status even if
;; the test fails, pass #f to :exit-on-failure.
(test-end :exit-on-failure #t)




