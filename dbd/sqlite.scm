;;;
;;; dbd_sqlite
;;;

(define-module dbd.sqlite
  (use util.match)
  (use text.tr)
  (use dbi)
  (use gauche.sequence)
  (use util.relation)
  (export
   <sqlite-connection> <sqlite-driver> <sqlite-query> <sqlite-result>
   sqlite-libversion-number sqlite-libversion

   call-with-iterator

   relation-column-names relation-accessor
   relation-modifier relation-rows
   )
  )
(select-module dbd.sqlite)

;; Loads extension
(dynamic-load "dbd_sqlite")

;;;
;;; DBI class
;;;

(define-class <sqlite-driver> (<dbi-driver>)())

(define-class <sqlite-connection> (<dbi-connection>)
  (
   (%db-handle :init-keyword :%db-handle)
   ))

(define-class <sqlite-query> (<dbi-query>)
  (
   (%stmt-handle :init-keyword :%stmt-handle)
   (strict-bind? :init-keyword :strict-bind?)
   ))

(define-class <sqlite-result> (<relation> <sequence>)
  (
   (source-query :init-keyword :source-query)
   (seed :init-keyword :seed)
   ))

(define-condition-type <sqlite-error> <dbi-error> #f
  (errcode))

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

(define (sqlite-parse-number s)
  (rxmatch-case s
    [#/^0x([0-9a-f]+)$/i (_ hex)
     (string->number hex 16)]
    [#/^0[0-7]+$/ (_ oct)
     (string->number oct 8)]
    [#/^([0-9]+)$/ (_ decimal)
     (string->number decimal 10)]
    [else
     (errorf "Not a supported flags ~a" s)]) )

;;;
;;; Internal accessor
;;;

(define-method get-handle ((c <sqlite-connection>))
  (~ c'%db-handle))

(define-method clear-handle! ((c <sqlite-connection>))
  (slot-set! c '%db-handle #f))

(define-method get-handle ((q <sqlite-query>))
  (~ q '%stmt-handle))

(define-method clear-handle! ((q <sqlite-query>))
  (slot-set! q '%stmt-handle #f))

(define-method get-handle ((r <sqlite-result>))
  (get-handle (~ r 'source-query)))

;;;
;;; <relation> API
;;;

(define-method relation-column-names ((r <sqlite-result>))
  (list-columns (get-handle r)))

(define-method relation-accessor ((r <sqlite-result>))
  (^ [t c]
    (and-let* ([index (vector-index (^ [x] (string-ci=? c x)) t)]
               [(< index (vector-length t))])
      (vector-ref t index))))

(define-method relation-modifier ((r <sqlite-result>))
  #f)

;; <sqlite-result> -> <list>
(define-method relation-rows ((r <sqlite-result>))
  (map identity r))

;;;
;;; <sequence> API
;;;

;; This generic method desired work with:
;; 1. map
;; 2. x->generator
(define-method call-with-iterator ((r <sqlite-result>) proc . option)
  (define (step)
    (stmt-read-next (get-handle r)))
  
  (unless (dbi-open? r)
    (error <dbi-error> "<sqlite-result> already closed:" r))

  ;; Forcibly read from first.
  ;; Do not use seed.

  ;; NOTE: When SELECT statement return 3 rows.
  ;; 1. sqlite3_step 3 times then reach EOF.
  ;; 2. sqlite3_step 1 time read EOF.
  ;; 3. again execute sqlite3_step seems to read from first (!).
  ;;  this make strange behavior as <sequence> .
  (reset-stmt (get-handle r))

  (let* ([result (step)])
    (proc
     (cut eof-object? result)
     (^ []
       (begin0
           result
         (set! result (step)))))))

;;;
;;; DBI interface
;;;

(define-method dbi-make-connection ((d <sqlite-driver>) (options <string>)
                                    (options-alist <list>)
                                    . args)

  (define (make-options)
    (list
     (cons "flags" (or (and-let1 opt (assoc-ref options-alist "flags")
                         (sqlite-parse-number opt))
                       (logior SQLITE_OPEN_READWRITE
                               SQLITE_OPEN_CREATE)))
     (cons "vfs" (assoc-ref options-alist "vfs"))
     (cons "timeout" (or (and-let1 opt (assoc-ref options-alist "timeout")
                           (sqlite-parse-number opt))
                         #f))))

  ;; To read more details visit: https://www.sqlite.org/c3ref/open.html
  ;; TODO e.g. /path/to/sqlite.db;memory;uri;
  ;; Supported options are: 
  ;; file : Must be first option that has no value. 
  ;; "db" : same as file
  ;; "flags" : Flags integer pass to sqlite3_open_v2 . (e.g. TODO)
  ;; "memory" : TODO
  ;; "uri" : TODO
  ;; "readonly" : TODO
  ;; "vfs" : Name of VFS module.
  ;; "timeout" : milliseconds of timeout when read/execute query.
  ;; Supported keywords are none.
  (let-keywords args
      restargs
    (let1 file
        (match options-alist
          [((maybe-db . #t) . _)
           maybe-db]
          [else
           (assoc-ref options-alist "db" #f)])
      (let* ([options (make-options)]
             [db (open-db file options)])
        (make <sqlite-connection>
          :%db-handle db)))))

;; NOTE: dbd.sqlite module simply ignore preceeding sql statement result.
;; SELECT 1; SELECT 1, 2;  -> (#(1 2))
;; SELECT 1, 2; UPDATE foo SET (col1 = "col1"); -> integer (dbd.sqlite specific)
(define-method dbi-prepare ((c <sqlite-connection>) (sql <string>)
                            . args)
  (let-keywords args
      ([pass-through #f]
       ;; This option just effect `pass-through` is #t
       ;; Error! "SELECT :a" with (:b = 1)
       ;; TODO "SELECT :a" with (:a = 1, :b = 1)
       [strict-bind? #f]
       . restargs)
    (cond
     [pass-through
      (let* ([stmt (prepare-stmt (get-handle c) sql)]
             [query (make <sqlite-query>
                      :%stmt-handle stmt
                      :strict-bind? strict-bind?
                      :prepared (^ args sql)
                      :connection c)]))]
     [else
      (let* ([prepared (dbi-prepare-sql c sql)]
             [query (make <sqlite-query>
                      ;; This case not yet prepare statement.
                      ;; after accept user arguments from `dbi-execute` interface.
                      :%stmt-handle #f
                      :connection c
                      :prepared prepared)])
        query)])))

;; SELECT -> return <sqlite-result>
;; Other DML -> Not defined in gauche info but UPDATE, DELETE, INSERT return integer
;;  that hold affected row count. Should not use this extension if you need portable code.
;; PARAMS: TODO keyword expand to bind parameter and others position parameter in the PARAMS.
;;   e.g. TODO
;; NOTE: No need to mixture index parameter and named parameter, but should work.
(define-method dbi-execute-using-connection ((c <sqlite-connection>) (q <sqlite-query>)
                                             (params <list>))

  (define (canonicalize-parameters source-params)
    (let ([sql-params (list-parameters (get-handle q))]
          [val-alist (let loop ([ps source-params]
                                [res '()]
                                [i 1])
                       (match ps
                         ['()
                          (reverse! res)]
                         [((? keyword? k) v . rest)
                          (loop rest (cons (cons (keyword->parameter k) v) res) (+ i 1))]
                         [(v . rest)
                          (loop rest (cons (cons i v) res) (+ i 1))]))])
      (map-with-index
       (^ [index name]
         (cond
          [(not name)
           ;; "anonymous parameters" e.g. "SELECT ?, ?"
           (assq-ref val-alist (+ index 1))

           ;; nameless parameter cannot check `strict-bind?`
           ;; e.g. "SELECT ?999" -> this malicious example generate many nameless parameters.
           ;; `pass-through` query should use named parameter, so no need to check on this case.
           ]
          [else
           (or (assoc-ref val-alist name #f)
               (and (~ q 'strict-bind?)
                    (errorf "Parameter ~s not found" name)))]))
       sql-params)))

  (define (ensure-prepare&params)
    (cond
     [(not (~ q'%stmt-handle))
      (let* ([prepared (~ q'prepared)]
             [sql (apply prepared params)]
             [stmt (prepare-stmt (get-handle c) sql)])
        (slot-set! q '%stmt-handle stmt)
        params)]
     [else
      (canonicalize-parameters params)]))

  (let1 real-params (ensure-prepare&params)
    (match (execute-stmt (get-handle q) real-params)
      [(or (? vector? result)
           (? eof-object? result))
       (make <sqlite-result>
         :source-query q
         :seed result)]
      [result
       result])))

(define-method dbi-open? ((c <sqlite-connection>))
  (boolean (get-handle c)))

(define-method dbi-open? ((q <sqlite-query>))
  (boolean (get-handle q)))

(define-method dbi-open? ((r <sqlite-result>))
  (and-let1 q (~ r 'source-query)
    (dbi-open? q)))

(define-method dbi-close ((c <sqlite-connection>))
  (and-let1 h (get-handle c)
    (db-close h)
    (clear-handle! c)))

(define-method dbi-close ((q <sqlite-query>))
  (and-let1 h (get-handle q)
    (close-stmt h)
    (clear-handle! q)))

(define-method dbi-close ((r <sqlite-result>))
  (and-let1 q (~ r 'source-query)
    (dbi-close q)
    (slot-set! r 'source-query #f)))

;; Probablly no need
;; (define-method dbi-do ((c <sqlite-connection>) (sql <string>) :optional options)
;;   )


