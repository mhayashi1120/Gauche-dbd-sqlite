# Gauche-dbd-sqlite

## TODO


can return number of update, insert, delete after execute https://www.sqlite.org/c3ref/changes.html
bind-parameter accepts :hoge-foo -> :hoge\_foo 


## Samples

```

TODO dbi-connect -> dbi-prepare -> dbi-execute

(let1 con (dbi-connect "dbi:sqlite:sample.sqlite")
	(unwind-protect
		(dbi-do con "CREATE TABLE account (id PRIMARY KEY, name);")
	  (dbi-close con)))

```

INSERT
 

```
TODO dbi-connect dbi-do
```

SELECT
```
(match row
  (#(id name)
   ...)
   )
```


```
dbi-connect options
- fullmutex
- timeout

(let1 conn (dbi-connect "dbi:sqlite:sample.sqlite;fullmutex;timeout=3000;")
  )

```

```
dbi-prepare options
- persistent
- pass-through

(dbi-prepare conn "SELECT * FROM account WHERE id = :id")

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
