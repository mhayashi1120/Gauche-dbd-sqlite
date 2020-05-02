# Gauche-dbd-sqlite

## TODO


can return number of update, insert, delete after execute https://www.sqlite.org/c3ref/changes.html
bind-parameter accepts :hoge-foo -> :hoge\_foo 


## Samples

### Basic access

```
(use dbi)

(let1 con (dbi-connect "dbi:sqlite:sample.sqlite")
  (unwind-protect
   (begin
     (dbi-do con "CREATE TABLE account (id PRIMARY KEY, name);")
     (let ([insert (dbi-prepare con "INSERT INTO account VALUES (?, ?);")])
       (dbi-execute insert 1 "John Doe")
       (dbi-execute insert 2 "名無しさん")

       (let* ([result (dbi-do con "SELECT * FROM account")]
              [getter (relation-accessor result)])
         (map
          (^r
           (format #t "ID: ~a Name: ~a\n" (getter r "id") (getter r "name")))
          (relation-rows result)))))
   (dbi-close con)))

```

### Simplify match library & <sequence>
 

```
(use util.match)
(use gauche.sequence)

(let1 con (dbi-connect "dbi:sqlite:sample.sqlite")
  (unwind-protect
   (map
    (match-lambda
     [#(id name)
     (format #t "ID: ~a Name: ~a\n" id name)])
    (dbi-do con "SELECT * FROM account"))
   (dbi-close con)))

```

### Fullmutex options

```
(let1 con (dbi-connect "dbi:sqlite:sample.sqlite;fullmutex;timeout=3000;")
  ;; ***do-something in multi-thread***
  )
```

### Named bindings with pass-through query

```
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
        (format #t "ID: ~a Name: ~a\n" id name)])
      (dbi-do con "SELECT * FROM account")))
   (dbi-close con)))
```


## Ref

https://www.sqlite.org/c3ref/funclist.html



## History

TODO とりあえず書きはじめ。これ書いていくつかの TODO fix して、手許の既存スクリプトが動作したらとりあえず github に up する
旧はアーカイブに

This similar module exists here:
https://github.com/mhayashi1120/Gauche-dbd-sqlite3/

But have License problem 

https://github.com/mhayashi1120/Gauche-dbd-sqlite3/issues/1

ライセンスに問題があったため、ゼロから作り直したいと思っていたものです。

最初にライセンスをきちんと確認しなかったのは痛い失敗だったので、

git init 初期の頃からできるだけ小まめに commit しながら、自身 (mhayashi1120@gmail.com) がゼロから作った証跡として残しときます。

長時間動くプログラムだとメモリリークしていた様子がある。

前の Gauche-dbd-sqlite3 との違い。

Gauche-dbd-sqlite3 のソースは読まない縛り。

Gauche の dbi interface に忠実になった。

"dbi:sqlite3:**filename**" -> "dbi:sqlite:**filename**"

旧バージョンのソースは見ていないので不正確


raise internal error as <sqlite-error>

マルチバイト文字の test
