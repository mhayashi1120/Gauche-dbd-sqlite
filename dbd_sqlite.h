/*
 * dbd_sqlite.h
 */

/* Prologue */
#ifndef GAUCHE_DBD_SQLITE_H
#define GAUCHE_DBD_SQLITE_H

#include <gauche.h>
#include <gauche/extend.h>

#include <sqlite3.h>

SCM_DECL_BEGIN

typedef struct ScmSqlite3DbRec {
	SCM_HEADER;
	sqlite3 *ptr; /* NULL if closed */
} ScmSqlite3Db;

// SCM_CLASS_DECL(Scm_SqliteDbClass);
// #define SCM_CLASS_SQLITE_DB (&Scm_SqliteDbClass)
// #define SCM_SQLITE3_DB(obj) ((ScmSqlite3Db*)(obj))
// #define SCM_SQLITE3_DB_P(obj) (SCM_XTYPEP(obj, SCM_CLASS_SQLITE_DB))

typedef struct ScmSqlite3StmtRec {
	SCM_HEADER;
	ScmString * sql;
	ScmList * columns;
	sqlite3_stmt *ptr; /* NULL if closed */
} ScmSqlite3Stmt;

// SCM_CLASS_DECL(Scm_SqliteStmtClass);
// #define SCM_CLASS_SQLITE_STMT (&Scm_SqliteStmtClass)
// #define SCM_SQLITE3_STMT(obj) ((ScmSqlite3Stmt*)(obj))
// #define SCM_SQLITE3_STMT_P(obj) (SCM_XTYPEP(obj, SCM_CLASS_SQLITE_STMT))

extern ScmObj getLibSqliteVersion();

extern ScmObj getLibSqliteVersionNumber();

/* Epilogue */
SCM_DECL_END

#endif  /* GAUCHE_DBD_SQLITE_H */
