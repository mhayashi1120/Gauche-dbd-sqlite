/*
 * dbd_sqlite.c
 */

#include "dbd_sqlite.h"

#include <sqlite3.h>


static ScmObj readRow(sqlite3_stmt * pStmt)
{
    int col = sqlite3_column_count(pStmt);

    SCM_ASSERT(col > 0);

    ScmVector * v = SCM_VECTOR(Scm_MakeVector(col, SCM_FALSE));

    for (int i = 0; i < col; i++) {
	switch (sqlite3_column_type(pStmt, i)) {
	case SQLITE_INTEGER:
	{
	    ScmObj n = Scm_MakeInteger(sqlite3_column_int64(pStmt, i));

	    Scm_VectorSet(v, i, n);
	    break;
	}
	case SQLITE_FLOAT:
	{
	    ScmObj f = Scm_MakeFlonum(sqlite3_column_double(pStmt, i));

	    Scm_VectorSet(v, i, f);
	    break;
	}
	case SQLITE_TEXT:
	{
	    const char * text = sqlite3_column_text(pStmt, i);
	    const int size = sqlite3_column_bytes(pStmt, i);
	    const ScmObj str = Scm_MakeString(text, size, size, SCM_STRING_COPYING);

	    Scm_VectorSet(v, i, str);
	    break;
	}
	case SQLITE_BLOB:
	{
	    const unsigned char * blob = sqlite3_column_blob(pStmt, i);
	    const int size = sqlite3_column_bytes(pStmt, i);
	    const ScmObj u8vec = Scm_MakeU8VectorFromArray(size, blob);

	    Scm_VectorSet(v, i, u8vec);
	    break;
	}
	case SQLITE_NULL:
	    break;
	}
    }

    return SCM_OBJ(v);
}

static ScmObj readColumns(sqlite3_stmt * pStmt)
{
    int col = sqlite3_column_count(pStmt);
    ScmObj result = SCM_NIL;

    SCM_ASSERT(0 < col);

    for (int i = col - 1; 0 <= i; i--) {
	const char * name = sqlite3_column_name(pStmt, i);

	result = Scm_Cons(SCM_MAKE_STR_COPYING(name), result);
    }

    return result;
}

static void finalizeDBMaybe(ScmObj z, void *data)
{
printf("finalize DB %p\n", z);
fflush(stdout);
}

static void finalizeStmtMaybe(ScmObj z, void *data)
{
printf("finalize STMT %p\n", z);
fflush(stdout);
}

/* duplicate sqlite3_errmsg and keep it as Scheme object. */
/* When sqlite3_* finalize process is ran before raise error */
/* errmsg will be cleared. */
static ScmString * dupErrorMessage(const char * errmsg)
{
    return SCM_STRING(SCM_MAKE_STR_COPYING(errmsg));
}

static ScmString * getErrorMessage(sqlite3 * pDb)
{
    return dupErrorMessage(sqlite3_errmsg(pDb));
}

static void raiseError(ScmString * msg)
{
    Scm_Error(Scm_GetStringConst(msg));
}

/* TODO sqlite3_last_insert_rowid -> no need just call SQL if need.*/

ScmObj getLibSqliteVersionNumber()
{
    return Scm_MakeInteger(sqlite3_libversion_number());
}

ScmObj getLibSqliteVersion()
{
    return SCM_MAKE_STR_IMMUTABLE(sqlite3_libversion());
}

ScmObj openDB(ScmString * filenameArg, int flags)
{
    const char * filename = Scm_GetStringConst(filenameArg);
    sqlite3 * pDb = NULL;
    ScmString * errmsg = NULL;

    int result = sqlite3_open_v2(
	filename, &pDb,
	flags,              /* Flags */
	NULL        /* Name of VFS module to use TODO */
	);

    if (result != SQLITE_OK) {
	if (pDb != NULL) {
	    errmsg = getErrorMessage(pDb);
	} else {
	    errmsg = dupErrorMessage("dbd.sqlite: Unknown error while opening DB.");
	}
	goto error;
    }

    ScmSqliteDb * db = SCM_NEW(ScmSqliteDb);
    SCM_SET_CLASS(db, SCM_CLASS_SQLITE_DB);

    Scm_RegisterFinalizer(SCM_OBJ(db), finalizeDBMaybe, NULL);

    db->ptr = pDb;

    return SCM_OBJ(db);

error:

    if (pDb != NULL) {
	/* TODO or sqlite3_close no need release other resource here */
	sqlite3_close_v2(pDb);
    }

    if (errmsg == NULL)
	return SCM_FALSE;

    raiseError(errmsg);
}

void closeDB(ScmSqliteDb * db)
{
    if (db->ptr == NULL) {
	return;
    }

    int result = sqlite3_close_v2(db->ptr);

    /* TODO close all statements ? close_v2 interface doc seems to say close automatically all. */
    db->ptr = NULL;

    Scm_UnregisterFinalizer(SCM_OBJ(db));

    /* TODO result */
}

ScmObj prepareStmt(ScmSqliteDb * db, ScmString * sql)
{
    ScmSmallInt size;
    const char * zSql = Scm_GetStringContent(sql, &size, NULL, NULL);
    unsigned int prepFlags = 0;
    sqlite3_stmt * pStmt;
    const char * zTail = zSql;
    ScmString * errmsg = NULL;

    /* TODO must check not closed caller */
    /* should not assert. just return? */
    SCM_ASSERT(db->ptr != NULL);

    while (1) {
	int result = sqlite3_prepare_v3(
	    db->ptr, zSql, size,
	    /* Zero or more SQLITE_PREPARE_ flags */
	    prepFlags,
	    &pStmt, &zTail
	    );

	if (result != SQLITE_OK) {
	    errmsg = getErrorMessage(db->ptr);
	    goto error;
	}

	if (pStmt == NULL) {
	    errmsg = dupErrorMessage("Unknown error statement is not created.");
	    goto error;
	}

	if (*zTail == '\0')
	    break;

	/* TODO */
	int stepResult = sqlite3_step(pStmt);

	/* ignore result until last statement. */
	sqlite3_finalize(pStmt);

	if (stepResult != SQLITE_DONE &&
	    stepResult != SQLITE_ROW) {
	    errmsg = dupErrorMessage("todo");
	    goto error;
	}

	pStmt = NULL;
	zSql = zTail;
	/* TODO sql has "SELECT 1; invalid statement;" */
	/* "SELECT 1; \n" (space appended) what happen?*/
    }
    
    SCM_ASSERT(pStmt != NULL);

    /* TODO register finalizer */
    ScmSqliteStmt * stmt = SCM_NEW(ScmSqliteStmt);
    SCM_SET_CLASS(stmt, SCM_CLASS_SQLITE_STMT);

    stmt->db = db;
    stmt->sql = SCM_STRING(SCM_MAKE_STR_COPYING(zSql));
    stmt->ptr = pStmt;

    return SCM_OBJ(stmt);

error:

    if (errmsg == NULL)
	return SCM_FALSE;

    raiseError(errmsg);
}

/* SQLite Parameter allow ":", "$", "@", "?" prefix  */
/* This function return list that contains ScmString with those prefix */
/* e.g. "SELECT :hoge, @foo" sql -> (":hoge" "@foo")  */
/* TODO anonymous */
/* TODO call before bind sqlite3_reset(stmt); */
ScmObj requiredParameters(ScmSqliteStmt * stmt)
{
    SCM_ASSERT(stmt->ptr != NULL);

    sqlite3_stmt * pStmt = stmt->ptr;
    int count = sqlite3_bind_parameter_count(pStmt);
    ScmObj result = SCM_NIL;

    /* parameter index start from 1 not 0 */
    for (int i = count; 0 < i; i--) {
	const char * name = sqlite3_bind_parameter_name(pStmt, i);

	result = Scm_Cons(SCM_MAKE_STR_COPYING(name), result);
    }

    return result;
}

void bindParameters(ScmSqliteStmt * stmt, ScmObj params)
{
    SCM_ASSERT(stmt->ptr != NULL);
    SCM_ASSERT(SCM_LISTP(params));

    sqlite3_stmt * pStmt = stmt->ptr;
    ScmSize len = Scm_Length(params);

    /* TODO clear_bindings -> sqlite3_reset()? clear_bindings?*/
    /* Bind parameter index start from 1 not 0 */
    for (int i = 1; i <= len; i++) {
	ScmObj scmValue = SCM_CAR(params);

	if (SCM_STRINGP(scmValue)) {
	    ScmSmallInt size;
	    const char * text = Scm_GetStringContent(SCM_STRING(scmValue), &size, NULL, NULL);

	    /* TODO fifth arg */
	    sqlite3_bind_text(pStmt, i, text, size, NULL);
	} else if (SCM_INTEGERP(scmValue)) {
	    /* TODO range */
	    /* negative value */
	    /* TODO sqlite3_bind_int  when small? */
	    sqlite3_int64 ll = Scm_GetInteger64(scmValue);
	    sqlite3_bind_int64(pStmt, i, ll);
	} else if (SCM_FLONUM(scmValue)) {
	    /* TODO other inexact value? */
	    const double f = Scm_GetDouble(scmValue);
	    sqlite3_bind_double(pStmt, i, f);
	} else if (SCM_UVECTORP(scmValue)) {
	    /* TODO restrict to just u8? */
	    const int size = SCM_UVECTOR_SIZE(scmValue);
	    const unsigned char * blob = SCM_UVECTOR_ELEMENTS(scmValue);
	    /* TODO fifth arg */
	    sqlite3_bind_blob(pStmt, i, blob, size, NULL);
	} else if (SCM_FALSEP(scmValue)) {
	    sqlite3_bind_null(pStmt, i);
	} else {
	    SCM_ASSERT(0);
	}

	params = SCM_CDR(params);
    }
    
}

ScmObj readLastChanges(ScmSqliteStmt * stmt)
{
    int changes = sqlite3_changes(stmt->db->ptr);

    /* TODO int size */
    return Scm_MakeInteger(changes);
}

ScmObj readResult(ScmSqliteStmt * stmt)
{
    int result = sqlite3_step(stmt->ptr);
    ScmString * errmsg = NULL;

    switch (result)
    {
    case SQLITE_BUSY:
	errmsg = dupErrorMessage("Database is busy.");
	goto error;
    case SQLITE_DONE:
	{
	ScmObj second = NULL;

	if (stmt->columns != NULL) 
	    second = SCM_EOF;
	else
	    second = readLastChanges(stmt);

	ScmObj result = Scm_Values2(SCM_FALSE, second);

	sqlite3_finalize(stmt->ptr);
	stmt->ptr = NULL;
	return result;
	}
    case SQLITE_ROW:
	stmt->columns = readColumns(stmt->ptr);
	return Scm_Values2(SCM_TRUE, readRow(stmt->ptr));
    case SQLITE_ERROR:
	errmsg = getErrorMessage(stmt->db->ptr);
	goto error;
    case SQLITE_MISUSE:
	errmsg = dupErrorMessage("Statement is in misuse.");
	goto error;
    default:
	SCM_ASSERT(0);
    }

error:
    sqlite3_finalize(stmt->ptr);

    if (errmsg == NULL)
	/* TODO reconsider */
	return SCM_FALSE;

    raiseError(errmsg);
}

void closeStmt(ScmSqliteStmt * stmt)
{
    if (stmt->ptr == NULL) {
	return;
    }

    sqlite3_finalize(stmt->ptr);
    stmt->ptr = NULL;
    stmt->db = NULL;
}

/* TODO timeout */


/*
 * Module initialization function.
 */
extern void Scm_Init_dbd_sqlitelib(ScmModule*);

void Scm_Init_dbd_sqlite(void)
{
    ScmModule *mod;

    /* Register this DSO to Gauche */
    SCM_INIT_EXTENSION(dbd_sqlite);

    /* Create the module if it doesn't exist yet. */
    mod = SCM_MODULE(SCM_FIND_MODULE("dbd.sqlite", TRUE));

    /* Register stub-generated procedures */
    Scm_Init_dbd_sqlitelib(mod);
}
