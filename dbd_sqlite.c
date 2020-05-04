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
	    const ScmObj str = Scm_MakeString(text, size, -1, SCM_STRING_COPYING);

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

    if (col <= 0) {
	return NULL;
    }

    ScmVector * result = SCM_VECTOR(Scm_MakeVector(col, SCM_FALSE));

    for (int i = 0; i < col; i++) {
	const char * name = sqlite3_column_name(pStmt, i);

	Scm_VectorSet(result, i, SCM_MAKE_STR_COPYING(name));
    }

    return SCM_OBJ(result);
}

static void finalizeDBMaybe(ScmObj z, void *data)
{
    ScmSqliteDb * db = SCM_SQLITE_DB(z);

    closeDB(db);
}

static void finalizeStmtMaybe(ScmObj z, void *data)
{
    ScmSqliteStmt * stmt = SCM_SQLITE_STMT(z);

    closeStmt(stmt);
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
    const char * msg = sqlite3_errmsg(pDb);

    if (msg == NULL)
	return NULL;

    return dupErrorMessage(msg);
}

static void raiseError(ScmString * msg)
{
    ScmModule * mod = SCM_FIND_MODULE("dbd.sqlite", FALSE);
    ScmSymbol * errsym = SCM_SYMBOL(SCM_INTERN("<sqlite-error>"));
    ScmObj condition = Scm_GlobalVariableRef(mod, errsym, FALSE);

    Scm_RaiseCondition(condition,
    		       SCM_RAISE_CONDITION_MESSAGE,
    		       Scm_GetStringConst(msg));
}

static ScmObj assocRefOption(const char * key, ScmObj optionAlist)
{
    ScmObj pair = Scm_Assoc(SCM_MAKE_STR_IMMUTABLE(key), optionAlist, SCM_CMP_EQUAL);

    if (!SCM_PAIRP(pair)) {
	Scm_Error("Not found key.");
    }

    return SCM_CDR(pair);
}


ScmObj getLibSqliteVersionNumber()
{
    return Scm_MakeInteger(sqlite3_libversion_number());
}

ScmObj getLibSqliteVersion()
{
    return SCM_MAKE_STR_IMMUTABLE(sqlite3_libversion());
}

ScmObj openDB(ScmString * filenameArg, ScmObj optionAlist)
{
    const char * filename = Scm_GetStringConst(filenameArg);
    sqlite3 * pDb = NULL;
    ScmString * errmsg = NULL;
    ScmObj flagsObj = assocRefOption("flags", optionAlist);
    ScmObj vfsObj = assocRefOption("vfs", optionAlist);
    ScmObj timeoutObj = assocRefOption("timeout", optionAlist);
    const int flags = Scm_GetInteger(flagsObj);
    const char * vfs = (SCM_FALSEP(vfsObj)) ? NULL : Scm_GetStringConst(SCM_STRING(vfsObj));
    const int timeoutMS = (SCM_FALSEP(timeoutObj)) ? -1 : Scm_GetInteger(timeoutObj);
    
    int result = sqlite3_open_v2(
	filename, &pDb,
	flags,
	vfs        /* Name of VFS module to use */
	);

    if (result != SQLITE_OK) {
	if (pDb != NULL) {
	    errmsg = getErrorMessage(pDb);
	} else {
	    errmsg = dupErrorMessage("Unknown error while opening DB.");
	}
	goto error;
    }

    if (0 <= timeoutMS) {
	sqlite3_busy_timeout(pDb, timeoutMS);
    }

    ScmSqliteDb * db = SCM_NEW(ScmSqliteDb);
    SCM_SET_CLASS(db, SCM_CLASS_SQLITE_DB);

    Scm_RegisterFinalizer(SCM_OBJ(db), finalizeDBMaybe, NULL);

    db->ptr = pDb;

    return SCM_OBJ(db);

error:

    if (pDb != NULL) {
	/* Not using v2 interface. no need release other resource here */
	sqlite3_close(pDb);
    }

    if (errmsg == NULL)
	return SCM_FALSE;

    raiseError(errmsg);
}

void closeDB(ScmSqliteDb * db)
{
    ScmString * errmsg = NULL;

    if (db->ptr == NULL) {
	return;
    }

    int result = sqlite3_close_v2(db->ptr);

    if (result != SQLITE_OK) {
	errmsg = getErrorMessage(db->ptr);
	goto error;
    }

    db->ptr = NULL;

    Scm_UnregisterFinalizer(SCM_OBJ(db));

    return;

error:

    if (errmsg == NULL)
	return;

    raiseError(errmsg);
}

ScmObj prepareStmt(ScmSqliteDb * db, ScmString * sql, int flags)
{
    const char * zSql = Scm_GetStringConst(sql);
    unsigned int prepFlags = flags;
    sqlite3_stmt * pStmt = NULL;
    const char * zTail = zSql;
    ScmString * errmsg = NULL;

    if (db->ptr == NULL) {
	errmsg = dupErrorMessage("Database has been closed.");
	goto error;
    }

    while (1) {
	int result = sqlite3_prepare_v3(
	    db->ptr, zSql, -1,
	    /* Zero or more SQLITE_PREPARE_* flags */
	    prepFlags,
	    &pStmt, &zTail
	    );

	if (result != SQLITE_OK) {
	    errmsg = getErrorMessage(db->ptr);
	    goto error;
	}

	if (pStmt == NULL) {
	    errmsg = dupErrorMessage("Unknown error: statement is not prepared.");
	    goto error;
	}

	if (*zTail == '\0')
	    break;

	SCM_ASSERT(zTail != zSql);

	int stepResult = sqlite3_step(pStmt);

	/* ignore result until last statement. */
	sqlite3_finalize(pStmt);

	if (stepResult != SQLITE_DONE &&
	    stepResult != SQLITE_ROW) {
	    errmsg = dupErrorMessage("sqlite step failed");
	    goto error;
	}

	pStmt = NULL;
	zSql = zTail;
    }
    
    SCM_ASSERT(pStmt != NULL);

    ScmSqliteStmt * stmt = SCM_NEW(ScmSqliteStmt);
    SCM_SET_CLASS(stmt, SCM_CLASS_SQLITE_STMT);

    Scm_RegisterFinalizer(SCM_OBJ(stmt), finalizeStmtMaybe, NULL);

    stmt->columns = readColumns(pStmt);
    stmt->db = db;
    stmt->sql = SCM_STRING(SCM_MAKE_STR_COPYING(zSql));
    stmt->ptr = pStmt;

    return SCM_OBJ(stmt);

error:

    SCM_ASSERT(errmsg != NULL);

    raiseError(errmsg);
}

/* SQLite Parameter allow ":", "$", "@", "?" prefix  */
/* This function return list that contains ScmString with those prefix */
/* e.g. "SELECT :hoge, @foo" sql -> (":hoge" "@foo")  */
/* NOTE: edge case, Programmer can choose "SELECT ?999" as a parameter. */
ScmObj listParameters(ScmSqliteStmt * stmt)
{
    ScmString * errmsg = NULL;

    if (stmt->ptr == NULL) {
	errmsg = dupErrorMessage("Statement has been closed.");
	goto error;
    }

    sqlite3_stmt * pStmt = stmt->ptr;
    int count = sqlite3_bind_parameter_count(pStmt);
    ScmObj result = SCM_NIL;

    /* parameter index start from 1 not 0 */
    for (int i = count; 0 < i; i--) {
	const char * name = sqlite3_bind_parameter_name(pStmt, i);

	if (name == NULL) {
	    result = Scm_Cons(SCM_FALSE, result);
	} else {
	    result = Scm_Cons(SCM_MAKE_STR_COPYING(name), result);
	}
    }

    return result;

error:

    SCM_ASSERT(errmsg != NULL);

    raiseError(errmsg);
}

void resetStmt(ScmSqliteStmt * stmt)
{
    SCM_ASSERT(stmt->ptr != NULL);

    /* this call does not reset binding parameter. */
    sqlite3_reset(stmt->ptr);

    /* Most recent sqlite3_step has an error, sqlite3_reset return error code. */
    /* But no need to check the result since return to initial state. */
}

void bindParameters(ScmSqliteStmt * stmt, ScmObj params)
{
    SCM_ASSERT(stmt->ptr != NULL);
    SCM_ASSERT(SCM_LISTP(params));

    sqlite3_stmt * pStmt = stmt->ptr;

    /* Does not describe about return value. */
    sqlite3_clear_bindings(pStmt);

    ScmSize len = Scm_Length(params);

    /* Bind parameter index start from 1 not 0 */
    for (int i = 1; i <= len; i++) {
	ScmObj scmValue = SCM_CAR(params);

	if (SCM_STRINGP(scmValue)) {
	    ScmSmallInt size;
	    const char * text = Scm_GetStringContent(SCM_STRING(scmValue), &size, NULL, NULL);

	    sqlite3_bind_text(pStmt, i, text, size, NULL);
	} else if (SCM_INTEGERP(scmValue)) {
	    sqlite3_int64 ll = Scm_GetInteger64(scmValue);
	    sqlite3_bind_int64(pStmt, i, ll);
	} else if (SCM_FLONUMP(scmValue)) {
	    const double f = Scm_GetDouble(scmValue);

	    sqlite3_bind_double(pStmt, i, f);
	} else if (SCM_UVECTORP(scmValue) && SCM_UVECTOR_SUBTYPE_P(scmValue, SCM_UVECTOR_U8)) {
	    const int size = SCM_UVECTOR_SIZE(scmValue);
	    const unsigned char * blob = SCM_UVECTOR_ELEMENTS(scmValue);

	    sqlite3_bind_blob(pStmt, i, blob, size, NULL);
	} else if (SCM_FALSEP(scmValue)) {
	    sqlite3_bind_null(pStmt, i);
	} else {
	    raiseError(SCM_STRING(Scm_Sprintf("Not a supported type %S.", scmValue)));
	}

	params = SCM_CDR(params);
    }
}

ScmObj readLastChanges(ScmSqliteStmt * stmt)
{
    int changes = sqlite3_changes(stmt->db->ptr);

    return Scm_MakeInteger(changes);
}

ScmObj readResult(ScmSqliteStmt * stmt)
{
    int result = sqlite3_step(stmt->ptr);
    ScmString * errmsg = NULL;

    switch (result)
    {
    case SQLITE_DONE:
	{
	if (stmt->columns != NULL) { 
	    return SCM_EOF;
	} else {
	    return readLastChanges(stmt);
	}
	}
    case SQLITE_ROW:
	return readRow(stmt->ptr);
	/* TODO busy test */
    /* case SQLITE_BUSY: */
    /* 	errmsg = dupErrorMessage("Database is busy."); */
    /* 	goto error; */
    /* case SQLITE_MISUSE: */
    /* 	errmsg = dupErrorMessage("Statement is in misuse."); */
    /* 	goto error; */
    default:
	/* sqlite3_prepare_vX interface retrun many code. Handle sqlite3_errmsg */
	errmsg = getErrorMessage(stmt->db->ptr);
	goto error;
    }

error:

    SCM_ASSERT(errmsg != NULL);

    raiseError(errmsg);
}

void closeStmt(ScmSqliteStmt * stmt)
{
    if (stmt->db->ptr == NULL || stmt->ptr == NULL) {
	return;
    }

    sqlite3_finalize(stmt->ptr);

    stmt->ptr = NULL;
    stmt->db = NULL;

    Scm_UnregisterFinalizer(SCM_OBJ(stmt));
}

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
