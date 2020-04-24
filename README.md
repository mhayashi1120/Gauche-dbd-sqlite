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