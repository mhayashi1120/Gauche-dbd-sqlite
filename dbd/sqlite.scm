;;;
;;; dbd_sqlite
;;;

(define-module dbd.sqlite
  (use srfi-13)
  (use scheme.list)
  (use scheme.vector)
  (use util.match)
  (use text.tr)
  (use dbi)
  (use gauche.sequence)
  (use util.relation)
  (export
   <sqlite-error>

   <sqlite-connection> <sqlite-driver> <sqlite-query> <sqlite-result>

   sqlite-libversion-number sqlite-libversion
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
   (%queries :init-value '() :getter get-queries :setter set-queries!)
   ))

(define-class <sqlite-query> (<dbi-query>)
  (
   (%stmt-handle :init-keyword :%stmt-handle)
   (%stmt-flags :init-keyword :%stmt-flags)
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
    [#/^([1-9]?[0-9]*)$/ (_ decimal)
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
  (let1 columns (relation-column-names r)
    (^ [t c]
      (and-let* ([index (find-index (^ [x] (string-ci=? c x)) columns)]
                 [(< index (size-of t))])
        (ref t index)))))

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
    (error <sqlite-error> "<sqlite-result> already closed:" r))

  ;; Forcibly read from first.
  ;; Do not use seed.

  ;; NOTE: When SELECT statement return 3 rows.
  ;; 1. sqlite3_step 3 times then reach EOF.
  ;; 2. sqlite3_step 1 time read EOF.
  ;; 3. again execute sqlite3_step seems to read from first (!).
  ;;  this make strange behavior as <sequence> .
  (reset-last-stmt (get-handle r))

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
                       (logior
                        ;; Required flags
                        (or
                         (and-let1 opt (assoc-ref options-alist "required-flags")
                           (sqlite-parse-number opt))
                         (and-let1 opt (assoc-ref options-alist "readonly")
                           SQLITE_OPEN_READONLY)
                         ;; default allow all (read / write / create)
                         (logior SQLITE_OPEN_READWRITE
                                 SQLITE_OPEN_CREATE))
                        ;; Optional flags
                        (or
                         (and-let1 opt (assoc-ref options-alist "optional-flags")
                           (sqlite-parse-number opt))
                         (logior
                          (if (assoc-ref options-alist "memory")
                            SQLITE_OPEN_MEMORY 0)
                          (if (assoc-ref options-alist "sharedcache")
                            SQLITE_OPEN_SHAREDCACHE 0)
                          (if (assoc-ref options-alist "uri")
                            SQLITE_OPEN_URI 0)
                          (if (assoc-ref options-alist "fullmutex")
                            SQLITE_OPEN_FULLMUTEX 0)
                          ))
                        )))
     (cons "vfs" (assoc-ref options-alist "vfs"))
     (cons "timeout" (or (and-let1 opt (assoc-ref options-alist "timeout")
                           (sqlite-parse-number opt))
                         #f))))

  ;; To read more details visit: https://www.sqlite.org/c3ref/open.html
  ;; e.g. (dbi-connect "dbi:sqlite:/path/to/sqlite.db;memory;sharedcache;")
  ;;  Integer accept hex ("0x"), octal ("0"), decimal notation. (e.g. "0x12", "022", "18")
  ;; Supported options are:
  ;; file : Must be first option that has no value.
  ;; "db" : same as file
  ;; "flags" : Flags integer. Pass to sqlite3_open_v2 as is.
  ;;     this override all of following flags.
  ;; "required-flags" : Integer flags. This flags override other required flags.
  ;; "readonly" : Boolean no value option. Open database as read-only.
  ;; "optional-flags" : Integer flags. This flags override other optional flags.
  ;; "memory" : Boolean no value option. Open database in memory.
  ;; "sharedcache" : Enable shared cache.
  ;; "fullmutex" : Enable serialized threading mode.
  ;; "uri" : file is interpreted as a URI. This might be default in future release.
  ;; "vfs" : Name of VFS module.
  ;; "timeout" : milliseconds of timeout when read/execute query.
  ;; Supported keywords are none.
  (let-keywords args
      restargs
    (let1 file
        (match options-alist
          [((maybe-db . #t) . _)
           maybe-db]
          [_
           (assoc-ref options-alist "db" #f)])
      (let* ([options (make-options)]
             [db (open-db file options)])
        (make <sqlite-connection>
          :%db-handle db)))))

;; NOTE: dbd.sqlite module simply ignore preceeding sql statement result.
;; SELECT 1; SELECT 1, 2;  -> (#(1 2))
;; SELECT 1, 2; UPDATE foo SET col1 = "col1"; -> undefined
;; Supported keywords are:
;; :pass-through : Boolean. This option just effect `pass-through` is #t
;; :flags : Bitwise Integer hold SQLITE_PREPARE_*
;; :persistent : Boolean value. If the statement would be alive long time.
;; :strict-bind : Boolean. Report error unless binding parameter when `dbi-execute`.
;;     This is efficient to detect typo in SQL. And not report if extra parameter is supplied.
(define-method dbi-prepare ((c <sqlite-connection>) (sql <string>)
                            . args)
  (define (push-query! q)
    (set-queries! c (cons q (get-queries c))))

  (let-keywords args
      ([pass-through #f]
       [strict-bind #f]
       [persistent #f]
       [flags #f]
       . restargs)
    (set! flags (or flags
                    (or
                     (and persistent
                          SQLITE_PREPARE_PERSISTENT)
                     0)
                    ))
    (cond
     [pass-through
      (let* (
             [stmt (prepare-stmt (get-handle c) sql flags)]
             [query (make <sqlite-query>
                      :%stmt-handle stmt
                      :strict-bind? strict-bind
                      :prepared #f
                      :connection c)])
        (push-query! query)
        query)]
     [else
      (let* ([prepared (dbi-prepare-sql c sql)]
             [query (make <sqlite-query>
                      ;; This case not yet prepare statement.
                      ;; after accept user arguments from `dbi-execute` interface.
                      :%stmt-handle #f
                      :%stmt-flags flags
                      :connection c
                      :prepared prepared)])
        (push-query! query)
        query)])))

(define (inner-execute stmt index query params index-bias)
  (define (canonicalize-parameters sql-params)
    (map-with-index
     (^ [index name]
       (cond
        [(not name)
         ;; "anonymous parameters" e.g. "SELECT ?, ?"
         (assq-ref params (+ index index-bias))

         ;; nameless parameter cannot check `strict-bind?`
         ;; e.g. "SELECT ?999" -> this malicious example generate many nameless parameters.
         ;; `pass-through` query should use named parameter, just avoid SEGV.
         ;; So no need to check on this case.
         ]
        [else
         (or (assoc-ref params name #f)
             (and (~ query'strict-bind?)
                  (errorf <dbi-parameter-error>
                          "Parameter ~s is not supplied." name)))]))
     sql-params))

  (define (ensure-params)
    (cond
     [(~ query'prepared)
      (values '() 0)]
     [else
      (let1 sql-params (list-parameters (get-handle query) index)
        (values (canonicalize-parameters sql-params) (length sql-params)))]))

  (receive (real-params bias) (ensure-params)
    (match (execute-inner-stmt (get-handle query) real-params index)
      [(or (? vector? result)
           (? eof-object? result))
       (values (make <sqlite-result>
                 :source-query query
                 :seed result) bias)]
      [result
       (values result bias)])))

;; SELECT -> return <sqlite-result>
;; Other DML -> Not defined in gauche info but UPDATE, DELETE, INSERT return integer
;;  that hold affected row count. Should not use this extension if you need portable code.
;; PARAMS: keyword expand to bind parameter and others position parameter in the list.
;;   e.g. "SELECT :id, $name, ?" query accept (:id 100 :$name "hoge" 10)
(define-method dbi-execute-using-connection ((c <sqlite-connection>) (q <sqlite-query>)
                                             (params <list>))

  (define (ensure-stmt)
    (cond
     [(~ q'prepared)
      (let* ([prepared (~ q'prepared)]
             [flags (~ q'%stmt-flags)]
             [sql (apply prepared params)]
             [stmt (prepare-stmt (get-handle c) sql flags)])
        (slot-set! q '%stmt-handle stmt)
        stmt)]
     [else
      (get-handle q)]))

  (define (params->alist params)
    (let loop ([ps params]
               [res '()]
               [i 0])
      (match ps
        ['()
         (reverse! res)]
        [((? keyword? k) v . rest)
         (loop rest (cons (cons (keyword->parameter k) v) res) (+ i 1))]
        [(v . rest)
         (loop rest (cons (cons i v) res) (+ i 1))])))

  (let* ([stmt (ensure-stmt)]
         [alist (params->alist params)])
    (let loop ([index 0]
               [index-bias 0])
      (receive (result bias) (inner-execute stmt index q alist index-bias)
        (cond
         [(< (+ index 1) (inner-stmt-count stmt))
          ;; Ignore result until last.
          (loop (+ index 1) (+ index-bias bias))]
         [else
          result])))))

(define-method dbi-open? ((c <sqlite-connection>))
  (boolean (get-handle c)))

(define-method dbi-open? ((q <sqlite-query>))
  (boolean (get-handle q)))

(define-method dbi-open? ((r <sqlite-result>))
  (and-let1 q (~ r 'source-query)
    (dbi-open? q)))

(define-method purge-query! ((c <sqlite-connection>) (q <sqlite-query>))
  (let1 queries (delete q (get-queries c))
    (set-queries! c queries)))

(define-method dbi-close ((c <sqlite-connection>))
  (and-let1 h (get-handle c)
    (dolist (q (get-queries c))
      (dbi-close q))
    (close-db h)
    (clear-handle! c)))

(define-method dbi-close ((q <sqlite-query>))
  (and-let1 h (get-handle q)
    (close-stmt h)
    (purge-query! (~ q'connection) q)
    (clear-handle! q)))

(define-method dbi-close ((r <sqlite-result>))
  (and-let1 q (~ r 'source-query)
    (slot-set! r 'source-query #f)))
