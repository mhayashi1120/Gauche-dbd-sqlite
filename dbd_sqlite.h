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
// #define SCM_SQLITE_DB_UNBOX(obj) SCM_FOREIGN_POINTER_REF(ScmSqliteDb*, obj)
// #define SCM_SQLITE_DB_BOX(res) \
//     Scm_MakeForeignPointer(Scm_SqliteDbClass, res)


typedef struct ScmSqliteStmtRec {
	SCM_HEADER;
	ScmSqliteDb * db;
	ScmString * sql;
	ScmObj columns;
	sqlite3_stmt * ptr; /* NULL if closed */
} ScmSqliteStmt;

SCM_CLASS_DECL(Scm_SqliteStmtClass);
#define SCM_CLASS_SQLITE_STMT (&Scm_SqliteStmtClass)
#define SCM_SQLITE_STMT(obj) ((ScmSqliteStmt*)(obj))
#define SCM_SQLITE_STMT_P(obj) (SCM_XTYPEP(obj, SCM_CLASS_SQLITE_STMT))
// #define SCM_SQLITE_STMT_UNBOX(obj) SCM_FOREIGN_POINTER_REF(ScmSqliteStmt*, obj)
// #define SCM_SQLITE_STMT_BOX(res) \
//     Scm_MakeForeignPointer(Scm_SqliteStmtClass, res)

extern ScmObj getLibSqliteVersion();

extern ScmObj getLibSqliteVersionNumber();

extern void bindParameters(ScmSqliteStmt * stmt, ScmObj params);
extern ScmObj openDB(ScmString * filenameArg, int flags);
extern void closeDB(ScmSqliteDb * db);
extern ScmObj prepareStmt(ScmSqliteDb * db, ScmString * sql);
extern void closeStmt(ScmSqliteStmt * stmt);
extern ScmObj requiredParameters(ScmSqliteStmt * stmt);
extern ScmObj readLastChanges(ScmSqliteStmt * stmt);
extern ScmObj readResult(ScmSqliteStmt * stmt);

/* Epilogue */
SCM_DECL_END

#endif  /* GAUCHE_DBD_SQLITE_H */
