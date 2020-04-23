;;;
;;; dbd_sqlite
;;;

(define-module dbd.sqlite
  (use dbi)
  (use gauche.sequence)
  (use util.relation)
  (export
   sqlite-libversion-number sqlite-libversion
   )
  )
(select-module dbd.sqlite)

;; Loads extension
(dynamic-load "dbd_sqlite")


;;;
;;; Sqlite module specific
;;;

;; Scheme Keyword -> SQL parameter conversion rule.
;; 1. keyword->string keyword.
;; 2. sqlite parameter prefixes are ":" "$" "@" "?" . Unless start with it, prepend ":" 
;; 3. Scheme name separator "-" -> "_" ( "-" is invalid name in SQL)
(define (keyword->parameter k)
  (define (maybe-prepend p)
    (if (#/^[:$@?]/ p)
      p
      #":~|p|"))

  ($ maybe-prepend
     $ (cut string-tr <> "-" "_")
     $ keyword->string k))


;;;
;;; Interface
;;;

(define-condition-type <sqlite-error> <dbi-error> #f
  (errcode))

(define-class <sqlite-driver> (<dbi-driver>)())

(define-class <sqlite-connection> (<dbi-connection>)
  (
   (%db-handle :init-keyword :%db-handle)
   ))

(define-class <sqlite-query> (<dbi-query>)
  (
   (%stmt-handle :init-keyword :%stmt-handle)
   (%sql :init-keyword :%sql)
   ))

(define-class <sqlite-result> (<relation> <sequence>)
  (
   (source-query :init-keyword :source-query))
  )

;; <relation> API
(define-method relation-column-names ((r <sqlite-result>))
  (stmt-read-columns (~ (~ r 'source-query) '%stmt-handle)))

(define-method relation-accessor ((r <sqlite-result>))
  (^ [t c]
    ;; TODO
    (vector-ref t (vector-index (^ [x] (string=? c x)) t))))

(define-method relation-modifier ((r <sqlite-result>))
  #f)

(define-method relation-rows ((r <sqlite-result>))
  r)

;; <sequence> API
(define-method call-with-iterator ((r <sqlite-result>) proc . option)
  (define (next-step)
    (receive (_ result) (stmt-read-next (~ (~ r'source-query) '%stmt-handle))
      result))
  
  (unless (dbi-open? r)
    (error <dbi-error> "<sqlite-result> already closed:" r))
  (let* ([next-result (next-step)]
         [eof? (eof-object? next-result)])
    (proc (^[] eof?) (^ [] next-result))))

(define-method dbi-make-connection ((d <sqlite-driver>) (options <string>)
                                    (options-alist <list>)
                                    :key username password . args)
  ;; TODO sqlite uri
  ;; rwmode
  ;; https://www.sqlite.org/c3ref/open.html
  (let* ([db (db-open file)])
    (make <sqlite-connection>
      :%db-handle db)))

;; NOTE: dbd.sqlite module simply ignore preceeding sql statement result.
;; SELECT 1; SELECT 1, 2;  -> (#(1 2))
(define-method dbi-prepare ((c <sqlite-connection>) (sql <string>)
                             :key pass-through . args)
  (let* ([prepared (if pass-through
                     (^ args
                       ;; TODO Not like base dbi-prepare,
                       ;; should not raise error if parameter is missing. 
                       sql
                       )
                     (dbi-prepare-sql c sql))]
         [stmt (prepare-stmt c prepared)]
         [query (make <sqlite-query>
                  :%stmt-handle stmt
                  :connection c
                  :prepared prepared)])
    query))

;; SELECT -> return <sqlite-result>
;; Other DML -> Not defined in gauche info but UPDATE, DELETE, INSERT return integer
;;  that hold affected row count. Should not use integer if you need portable code.
(define-method dbi-execute-using-connection ((c <sqlite-connection>) (q <dbi-query>)
                                             (params <list>))
  ;; {dbi} このメソッドは‘dbi-execute’から呼ばれます。Qが保持するクエ リ
  ;; を発行しなければなりません。クエリがパラメータ化されている場合、
  ;; DBI-EXECUTEに与えられた実際のパラメータはPARAMS引数に渡さ れます。
  
  ;; Qが‘select’-型のクエリの場合は、このメソッドは適切なリレー ションオ
  ;; ブジェクトを返さなければなりません。

  (define (canonicalize-parameters source-params)
    (let ([sql-params (stmt-parameters (~ q'%stmt-handle))]
          [val-alist (map (match-lambda
                           [(k v)
                            (cons (keyword->string k) v)])
                          (slices source-params 2))])
      (map
       (^ [name]
         (or (assoc-ref val-alist name)
             ;; TODO bind as NULL
             ;; TODO or error? option?
             #f))
       sql-params)))

  (let* ([canon-params (canonicalize-parameters params)])
    (receive (readable? result) (execute-stmt (~ q'%stmt-handle) canon-params)

      ;;TODO compound-statement
      ;; close the first select stmt -> return last stmt result.
      ;; SELECT -> return relation. donot forgot close stmt
      ;; other -> return ... DML -> count of changed rows other -> ?? undef
      ;; compound update, delete ... -> sum of changed.
      ;; 
      ;; open-stream
      (if readable?
        (make <sqlite-result>
          :source-query q)
        result))))

(define-method dbi-open? ((c <sqlite-connection>))
  (boolean (~ c '%db-handle)))

(define-method dbi-open? ((q <sqlite-query>))
  (boolean (~ q '%stmt-handle)))

(define-method dbi-open? ((r <sqlite-result>))
  ;; TODO what should happen?
  (dbi-open? (~ r 'source-query)))

;; TODO db close all of statement should close?
(define-method dbi-close ((c <sqlite-connection>))
  (when (~ c '%db-handle)
    (db-close (~ c '%db-handle))
    (slot-set! c '%db-handle #f)))

(define-method dbi-close ((q <sqlite-query>))
  (when (~ q '%stmt-handle)
    (stmt-close (~ q'%stmt-handle))
    (slot-set! q '%stmt-handle #f)))

(define-method dbi-close ((r <sqlite-result>))
  (when (~ r 'source-query)
    (dbi-close (~ r 'source-query))
    (slot-set! r 'source-query #f)))

;; Probablly no need
;; (define-method dbi-do ((c <sqlite-connection>) (sql <string>) :optional options)
;;   )


