;;;
;;; Test dbd_sqlite
;;;

(use gauche.test)

(test-start "dbd.sqlite")
(use dbd.sqlite)
(test-module 'dbd.sqlite)

(test* "get version with no error" (test-none-of (test-error))
       (sqlite-libversion))

(test-log "libsqlite Version: ~a" (sqlite-libversion))

(test* "getversion with no error" (test-none-of (test-error))
       (sqlite-libversion-number))


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

(define *insert-rowids* '())
(define (append-rowids! . ids)
  (set! *insert-rowids* (append *insert-rowids* ids)))

(use dbd.sqlite)

(test* "Sqlite Connection" <sqlite-connection>
       (class-of *connection*))

(test* "Sqlite connection is open" #t
       (dbi-open? *connection*))


;;;
;;; Basic construction
;;;

(test-log "Basic construction.")

(dolist (q `(""
             "SELECT 1"
             "SELECT 1;"
             "SELECT 1; SELECT 2"
             "SELECT 1; SELECT 2;"
             ;; Last char is space
             "SELECT 1; SELECT 2; "))
  (test* #"Query Preparation ~|q|" <sqlite-query>
         (dbi-prepare *connection* q)
         (^ [_ x] (class-of x))))

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
  (test* "Execute with no error" (test-none-of (test-error))
         (dbi-execute q)))

(use util.match)

;; To simple test easily, make <relation> to <list>
(define (query->result q . params)
  (match (apply dbi-execute q params)
    [(? (^x (is-a? x <relation>)) r)
     (relation-rows r)]
    [x
     x]))

(test-log "Basic prepared query (text.sql)")

(define (sql->result sql . params)
  (let* ([q (dbi-prepare *connection* sql)])
    (apply query->result q params)))

(define (test-sql name expected sql . params)
  (test* name expected
         (apply sql->result sql params)))

;; Multiple statement
(test-sql "Multiple statement and get last statement result."
          `(#(1 "n1") #(2 "n2") #(3 "n3"))
          "INSERT INTO hoge(id, name, created) VALUES (1, 'n1', '2020-01-01 00:01:02');
INSERT INTO hoge(id, name, created) VALUES (2, 'n2', '2020-02-03 01:02:03');
INSERT INTO hoge(id, name, created) VALUES (3, 'n3', '2020-03-04 02:03:04');
SELECT id, name FROM hoge")
(append-rowids! 1 2 3)

(let1 result (dbi-do *connection* "SELECT id, name FROM hoge WHERE id = 1")
  (test* "Relation accessor (columns)"
         #("id" "name")
         (relation-column-names result))
  (let* ([top (car (relation-rows result))]
         [getter (relation-accessor result)])
    (test* "Relation accessor (column)"
           1
           (getter top "id"))
    (test* "Relation accessor (column)"
           "n1"
           (getter top "name")))
  )

;; Ignore first statement result
(test-sql "Multiple statements and get last statement result. 2"
          `(#(1 2))
          "SELECT 1; SELECT 1, 2;")

(test-sql "Empty result set"
          `()
          "SELECT * FROM hoge WHERE id = 100")

(test-sql "text.sql parser prepared"
          `(#(1 2 "three" 4.0 #f))
          "SELECT ?, ?, ?, ?, ?"
          1 2 "three" 4.0 #f)

(test-sql "Not like pass-through query u8vector is not supported."
          (test-error <dbi-parameter-error>)
          "SELECT ?"
          #u8(1 2 3))

(test-sql "Insert and get last_insert_rowid"
          `(#(4))
          "INSERT INTO hoge(name, created) VALUES (?, ?); SELECT last_insert_rowid();"
          "name4" "2020-04-30")
(append-rowids! 4)

(test-sql "Constraints error"
          (test-error <sqlite-error> #/constraint/i)
          "INSERT INTO hoge(id, name, created) VALUES (?, ?, ?);"
          4 "name4.5" "2020-04-30")

(let* ([q (dbi-prepare *connection* "INSERT INTO hoge(id, name, created) VALUES (?, ?, ?);")])
  (dbi-execute q 5 "name5" "2020-04-30")
  (dbi-execute q 6 "name6" "2020-05-01")
  (dbi-execute q 7 "名前7" "2020-05-02")
  (append-rowids! 5 6 7)
  (test* "Persistent prepared query is working"
         `(#(5) #(6) #(7))
         (relation-rows (dbi-do *connection* "SELECT id FROM hoge WHERE id in (5,6,7)"))))

(test* "Read multibyte string"
       #("名前7")
       (car (relation-rows (dbi-do *connection* "SELECT name FROM hoge WHERE id = 7"))))

(test-sql
 "Last empty statement is simply ignored"
 `(#(1))
 "SELECT 1 ; ;")

(test-sql
 "Last empty statement is simply ignored (with space)"
 `(#(1))
 "SELECT 1 ; ; ")

(dolist (q `("SELECT 1 ; ; SELECT 2"
             "SELECT 1 ; ; SELECT 2"
             "SELECT 1 ; ; SELECT 2;"
             "SELECT 1 ; ; SELECT 2; "))
  (test-sql
   #"Middle empty statement is simply ignored ~|q|"
   `(#(2))
   q))

(test-sql "Many statements in the SQL"
          `(#(5))
          "SELECT 1 ; SELECT 2; SELECT 3; SELECT 4; SELECT 5;")

;; prepare flag

(let* ([q0 (dbi-prepare *connection* "SELECT * FROM hoge")]
       [q1 (dbi-prepare *connection* "SELECT * FROM hoge" :persistent #t)]
       [q2 (dbi-prepare *connection* "SELECT * FROM hoge" :pass-through #t :persistent #t)]
       [answer (relation-rows (dbi-execute q0))])
  (test* "Same result persistent query."
         answer
         (relation-rows (dbi-execute q1)))
  (test* "Same result persistent query (pass-through)."
         answer
         (relation-rows (dbi-execute q2))))

;;;
;;; Pass through
;;;

(test-log "pass-through query.")

(define (sql->result* sql . params)
  (let* ([q (dbi-prepare *connection* sql :pass-through #t)])
    (apply query->result q params)))

(define (test-sql* name expected sql . params)
  (test* name expected
         (apply sql->result* sql params)))

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

(test-sql*
 "Select binding parameter 2"
 `(#(100 "hoge" 10 "hoge" 100))
 "SELECT :id, $name, ?, ?002, ?001"
 :id 100
 :$name "hoge"
 10
 )


(let* ([q (dbi-prepare *connection* "SELECT :a" :pass-through #t :strict-bind #t)])
  
  (test* "Strict bind (No parameter supplied.)" (test-error <dbi-parameter-error>)
         (query->result q))

  (test* "Strict bind (Ignore extra parameter supplied.)" `(#(1))
         (query->result q :a 1 :b 3))
  )

(test-log "pass-through query")
(let ([update (dbi-prepare *connection* "UPDATE hoge SET value = :value WHERE id = :id " :pass-through #t)]
      [select (dbi-prepare *connection* "SELECT value FROM hoge WHERE id = :id " :pass-through #t)])
  (dolist (testcase `(("Positive max integer" #x7fffffffffffffff)
                      ("Negative max integer" #x-8000000000000000)
                      ("Float value" 4.0000000000000000001 :expected 4)
                      ("Float value" 4.1)
                      ("Zero" 0)
                      (:error "Overflow long long (64bit integer)" #x8000000000000000)
                      (:error "Overflow long long (64bit integer)" #x-8000000000000001)
                      ("Large text" ,(make-string #xff #\a))
                      (:error "Unsupported type u16vec" #u16(1 256))
                      (:error "Unsupported type boolean" #t)
                      ))
    (match testcase
      [((? string? name) value . keywords)
       (let-keywords keywords
           ([expected value]
            . _rest)
         (test* #"~|name| UPDATE"
                1
                (query->result
                 update 
                 :value value
                 :id 1))

         (test* #"~|name| SELECT"
                `(#(,expected))
                (query->result
                 select
                 :id 1)))]

      [(:error name value)
       (test* name
              (test-error)
              (query->result
               update
               :value value
               :id 1))])))

(test-log "Transaction test")
(sql->result "BEGIN;")
(test-sql* "Insert in transaction"
           1
           "INSERT INTO hoge (id, name, value, created) VALUES (:id, :name, :value, :created)"
           :id 104
           :name "name4"
           :value 10
           :created "2020-04-01")

(test-sql* "Select in transaction found."
           `(#(104))
           "SELECT id FROM hoge WHERE id = :id"
           :id 104)
(sql->result "ROLLBACK;")
(test-sql* "Select after rollback is not found"
           `()
           "SELECT id FROM hoge WHERE id = :id"
           :id 104)

(sql->result "BEGIN;")
(test-sql* "Insert in transaction"
           1
           "INSERT INTO hoge (id, name, value, created) VALUES (:id, :name, :value, :created)"
           :id 104
           :name "name4"
           :value 10
           :created "2020-04-01")
(sql->result "COMMIT;")
(append-rowids! 104)

(test-sql* "Select in transaction found."
           `(#(104))
           "SELECT id FROM hoge WHERE id = :id"
           :id 104)

(let* ([q (dbi-prepare *connection* "INSERT INTO hoge(id, name, created) VALUES (?, ?, ?);" :pass-through #t :persistent #t)])
  (dbi-execute q 105 "name105" "2020-04-30")
  (dbi-execute q 106 "name106" "2020-05-01")
  (dbi-execute q 107 "name107" "2020-05-02")
  (append-rowids! 105 106 107)
  (test* "Persistent prepared query is working (Pass-through)"
         `(#(105) #(106) #(107))
         (relation-rows (dbi-do *connection* "SELECT id FROM hoge WHERE id in (105,106,107)"))))


(test-sql*
 "Statement has space at end"
 1
 "INSERT INTO hoge (id, name, created) VALUES (:id, :name, :created);\n"
 :id 108
 :name "name108"
 :created "2020-05-03")

(append-rowids! 108)

;;;
;;; Complext multiple statements
;;;

(test-sql*
 "Multiple pass-through query."
 1
 (string-append
  "INSERT INTO hoge (id, name, created) VALUES (:id, :name, :created); " ; executed but result is ignored
  "SELECT * FROM hoge WHERE id >= 200 AND id < 300; " ;ignore
  "UPDATE hoge SET name = :name2 WHERE id = :id ; " ; result is returned.
  )
 :id 200
 :name "name200"
 :created "2020-05-01"
 :name2 "name200-2"
 )
(append-rowids! 200)

(test-sql*
 "Multiple pass-through query 2."
 `(#(200 "name200-2") #(201 "name201-2"))
 (string-append
  "INSERT INTO hoge (id, name, created) VALUES (:id, :name, :created); " ; executed but result is ignored
  "SELECT * FROM hoge WHERE id >= 200 AND id < 300; " ;ignore
  "UPDATE hoge SET name = :name2 WHERE id = :id ; " ; execute but result is ignored.
  "SELECT id, name FROM hoge WHERE id >= 200 AND id < 300; " ; return result contains after above update
  )
 :id 201
 :name "name201"
 :created "2020-05-10"
 :name2 "name201-2"
 )
(append-rowids! 201)

;; default bindings
(test-sql
 "Multiple query (text.sql)."
 `(#(202 "name202-2"))
 (string-append
  "INSERT INTO hoge (id, name, created) VALUES (?, ?, ?); " ; executed but result is ignored
  "SELECT * FROM hoge WHERE id = 202; "                     ;ignore
  "UPDATE hoge SET name = ? WHERE id = ? ; " ; execute but result is ignored.
  "SELECT id, name FROM hoge WHERE id = 202; " ; return result contains after above update
  )
 202 "name202"
 "2020-05-11"
 "name202-2"
 202)
(append-rowids! 202)

(test-sql*
 "Multiple query pass-through nameless param."
 `(#(203 "name203-2"))
 (string-append
  "INSERT INTO hoge (id, name, created) VALUES (?, ?, ?); " ; executed but result is ignored
  "SELECT * FROM hoge WHERE id = 203; "                     ;ignore
  "UPDATE hoge SET name = ? WHERE id = ? ; " ; execute but result is ignored.
  "SELECT id, name FROM hoge WHERE id = 203; " ; return result contains after above update
  )
 203 "name203"
 "2020-05-12"
 "name203-2"
 203)
(append-rowids! 203)

;;;
;;; generator
;;;

(test-log "Generator (cursor) test")
(use gauche.generator)

(let* ([query (dbi-prepare *connection* "SELECT id FROM hoge ORDER BY id")]
       [result (dbi-execute query)]
       [gen (x->generator result)]
       )
  (test* "generator (like cursor) 1" #(1) (gen))
  (test* "generator (like cursor) 2" #(2) (gen))
  (test* "Map all results" (map (cut vector <>) *insert-rowids*) (relation-rows result))
  (test* "Again Map all results" (map (cut vector <>) *insert-rowids*) (relation-rows result))
  (dbi-close query)
  (test* "query is closed" #f (dbi-open? query))
  (dbi-close result)
  (test* "Result is closed" #f (dbi-open? result)))

;;;
;;; SQL syntax error
;;;

(define (error-test name query)
  (test* name (test-error <sqlite-error>)
        (sql->result query)))

(error-test "No existing object" "SELECT 1 FROM hoge1")
(error-test "First statement has no existing object" "SELECT 1 FROM hoge1; No meaning statement;")
(error-test "Last statement has syntax error" "SELECT 1 FROM hoge; No meaning statement;")

;;;
;;; Teardown
;;;

(dbi-close *connection*)

(test* "Connection is closed" #f
       (dbi-open? *connection*))

;;;
;;; Misc connection
;;;

;;
;; memory sqlite
;;
(test-log "In memory SQLite")
(set! *connection* (dbi-connect #"dbi:sqlite::memory:"))

(dbi-do *connection* "CREATE TABLE hoge (id, name);")
(test* "Insert 1" 1
       (dbi-do *connection* "INSERT INTO hoge VALUES(?, ?);" '() 1 "name1"))
(test* "Insert 2, 3" 2
       (dbi-do *connection* "INSERT INTO hoge VALUES(?, ?), (?, ?);" '() 2 "name2" 3 "name3"))
(test* "Select inserted"
       `(#(1 "name1") #(2 "name2") #(3 "name3"))
       (relation-rows (dbi-do *connection* "SELECT * FROM hoge")))

(dbi-close *connection*)

;;
;; Connection is terminated
;;

(test-log "close connection before commit.")
(set! *connection* (dbi-connect #"dbi:sqlite:~|*temp-sqlite*|;"))

(dbi-do *connection* "BEGIN")
(dbi-do *connection* "INSERT INTO hoge (id, name, created) VALUES (:id, :name, :created)"
        `(:pass-through #t)
        :id 100
        :name "name100"
        :created "2020-04-27 23:34:45")

(test* "Check insert result in transaction"
       `(#("name100"))
       (relation-rows (dbi-do *connection* "SELECT name FROM hoge WHERE id = 100")))

(dbi-close *connection*)

(set! *connection* (dbi-connect #"dbi:sqlite:~|*temp-sqlite*|;"))

(test* "Check insert result in transaction is not exists"
       `()
       (relation-rows (dbi-do *connection* "SELECT name FROM hoge WHERE id = 100")))

(dbi-close *connection*)

;;
;; Fullmutex
;;

(test-log "fullmutex connection")

(use gauche.process)

;; (set! *connection* (dbi-connect #"dbi:sqlite:~|*temp-sqlite*|;fullmutex;"))
(set! *connection* (dbi-connect #"dbi:sqlite:~|*temp-sqlite*|;"))


(use gauche.threads)

(dbi-close *connection*)

;; TODO uri filename

;; TODO other connect option
;; TODO check timeout behavior


(remove-file *temp-sqlite*)

;; If you don't want `gosh' to exit with nonzero status even if
;; the test fails, pass #f to :exit-on-failure.
(test-end :exit-on-failure #t)




