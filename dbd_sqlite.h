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

typedef struct ScmSqliteDbRec {
	SCM_HEADER;
	sqlite3 *ptr; /* NULL if closed */
} ScmSqliteDb;

SCM_CLASS_DECL(Scm_SqliteDbClass);
#define SCM_CLASS_SQLITE_DB (&Scm_SqliteDbClass)
#define SCM_SQLITE_DB(obj) ((ScmSqliteDb*)(obj))
#define SCM_SQLITE_DB_P(obj) (SCM_XTYPEP(obj, SCM_CLASS_SQLITE_DB))

typedef struct ScmSqliteStmtRec {
	SCM_HEADER;
	ScmSqliteDb * db;
	// This columns just hold last statement in SQL
	ScmObj columns;
	int ptrCount;
	sqlite3_stmt ** pptr; /* NULL if closed each element */
} ScmSqliteStmt;

SCM_CLASS_DECL(Scm_SqliteStmtClass);
#define SCM_CLASS_SQLITE_STMT (&Scm_SqliteStmtClass)
#define SCM_SQLITE_STMT(obj) ((ScmSqliteStmt*)(obj))
#define SCM_SQLITE_STMT_P(obj) (SCM_XTYPEP(obj, SCM_CLASS_SQLITE_STMT))

extern ScmObj getLibSqliteVersion();

extern ScmObj getLibSqliteVersionNumber();

extern void bindParameters(ScmSqliteStmt * stmt, int i, ScmObj params);
extern ScmObj openDB(ScmString * filenameArg, ScmObj optionAlist);
extern void closeDB(ScmSqliteDb * db);
extern ScmObj prepareStmt(ScmSqliteDb * db, ScmString * sql, int flags);
extern void resetStmt(ScmSqliteStmt * stmt, int i);
extern void closeStmt(ScmSqliteStmt * stmt);
extern ScmObj listParameters(ScmSqliteStmt * stmt, int i);
extern ScmObj readLastChanges(ScmSqliteStmt * stmt);
extern ScmObj readResult(ScmSqliteStmt * stmt, int i);

/* Epilogue */
SCM_DECL_END

#endif  /* GAUCHE_DBD_SQLITE_H */
