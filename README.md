# Gauche-dbd-sqlite

## TODO

https://www.sqlite.org/c3ref/funclist.html

can return number of update, insert, delete after execute https://www.sqlite.org/c3ref/changes.html
bind-parameter accepts :hoge-foo -> :hoge\_foo 


Samples

```
(use gauche.sequence) 


```

Not portable code
```
(match row
  (#(id name)
   ...)
   )
```


```
(let ((id (dbi-get-value "id"))
      (name (dbi-get-value "name")))
	...)

```


## History

TODO とりあえず書きはじめ。これ書いていくつかの TODO fix して、手許の既存スクリプトが動作したらとりあえず github に up する

This similar module exists here:
https://github.com/mhayashi1120/Gauche-dbd-sqlite3/

But have License problem 

https://github.com/mhayashi1120/Gauche-dbd-sqlite3/issues/1

ライセンスに問題があったため、ゼロから作り直したいと思っていたものです。

最初にライセンスをきちんと確認しなかったのは痛い失敗だったので、

git init 初期の頃からできるだけ小まめに commit しながら、自身 (mhayashi1120@gmail.com) がゼロから作った証跡として残しときます。

長時間動くプログラムだとメモリリークしていた様子がある。
