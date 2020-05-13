# Gauche-dbd-sqlite

This module is newly created version of Gauche sqlite binding.

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

       (let* ([result (dbi-do con "SELECT id, name FROM account")]
              [getter (relation-accessor result)])
         (map
          (^r
           (format #t "ID: ~s Name: ~s\n" (getter r "id") (getter r "name")))
          (relation-rows result)))))
   (dbi-close con)))

```

### Simplify by match library and <sequence>
 

```
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
        (format #t "ID: ~s Name: ~s\n" id name)])
      (dbi-do con "SELECT id, name FROM account")))
   (dbi-close con)))
```


## Comments

### 2020-05-13

Gauche の Sqlite3 の binding を公開します。

以前、[こちら](https://github.com/mhayashi1120/Gauche-dbd-sqlite3/) で公開していたのですが、[ライセンスの確認がとれない問題](https://github.com/mhayashi1120/Gauche-dbd-sqlite3/issues/1) があり、ゼロから作り直したいと思っていたものです。fork した際に **ライセンスをきちんと確認しなかったのは痛い失敗** でした。Gauche-dbd-sqlite3 のソースは読まない縛りで作り直し、ここ数年間まったく見ていません。

しばらくプログラミングから離れていたこともあり、最初に手をつけてから時間がかかりましたが、 git init 初期の頃からできるだけ小まめに commit しながら、自身 (mhayashi1120@gmail.com) がゼロから作った証跡として残しときます。

前の Gauche-dbd-sqlite3 との違い、 bugfix など

(dbi-connect "dbi:sqlite3:*filename*") -> (dbi-connect "dbi:sqlite:*filename*")

- 長時間動くプログラムだとメモリリークしていた様子がありました。Finalize の処理がなかったためと思われます。
- Gauche の dbi interface に忠実に準拠しました。余計な機能も(ほぼ)入れませんでした。
- dbi-prepare の引数に parameter 変数を渡さないといけなかったはずですが、仕様に忠実に dbi-execute の parameter 引数として渡すようにしました。
- pass-through の named parameter はキーワード引数に対して :hoge-foo -> :hoge\_foo という変換を施します。

その他、細々とした違いはあるかもしれません。

## Ref

https://www.sqlite.org/c3ref/funclist.html
http://practical-scheme.net/gauche/
https://github.com/kahua/Gauche-dbd-mysql


