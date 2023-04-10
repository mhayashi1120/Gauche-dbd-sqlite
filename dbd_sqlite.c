/*
 * dbd_sqlite.c
 */

#include "dbd_sqlite.h"

#include <sqlite3.h>

static sqlite3_stmt ** reallocStatements(sqlite3_stmt ** src, const int nextLength)
{
    sqlite3_stmt ** dest = SCM_NEW_ATOMIC_ARRAY(sqlite3_stmt*, nextLength);

    memcpy(dest, src, sizeof(sqlite3_stmt*) * nextLength);

    return dest;
}

static ScmObj readRow(sqlite3_stmt * pStmt)
{
    const int col = sqlite3_column_count(pStmt);

    SCM_ASSERT(col > 0);

    ScmVector * v = SCM_VECTOR(Scm_MakeVector(col, SCM_FALSE));

    for (int i = 0; i < col; i++) {
        switch (sqlite3_column_type(pStmt, i)) {
        case SQLITE_INTEGER:
        {
            ScmObj n = Scm_MakeInteger64(sqlite3_column_int64(pStmt, i));

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
            const unsigned char * text = sqlite3_column_text(pStmt, i);
            const int size = sqlite3_column_bytes(pStmt, i);
            const ScmObj str = Scm_MakeString((char *)text, size, -1, SCM_STRING_COPYING);

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
    const int col = sqlite3_column_count(pStmt);

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

static void finalizeDBMaybe(ScmObj z, void * _data)
{
    (void)_data;

    ScmSqliteDb * db = SCM_SQLITE_DB(z);

    closeDB(db);
}

static void finalizeStmtMaybe(ScmObj z, void * _data)
{
    (void)_data;

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
    const ScmObj condition = Scm_GlobalVariableRef(mod, errsym, FALSE);

    Scm_RaiseCondition(condition,
                       SCM_RAISE_CONDITION_MESSAGE,
                       Scm_GetStringConst(msg));
}

static ScmObj assocRefOption(const char * key, const ScmObj optionAlist)
{
    const ScmObj pair = Scm_Assoc(SCM_MAKE_STR_IMMUTABLE(key), optionAlist, SCM_CMP_EQUAL);

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

ScmObj openDB(ScmString * filenameArg, const ScmObj optionAlist)
{
    const char * filename = Scm_GetStringConst(filenameArg);
    sqlite3 * pDb = NULL;
    ScmString * errmsg = NULL;
    const ScmObj flagsObj = assocRefOption("flags", optionAlist);
    const ScmObj vfsObj = assocRefOption("vfs", optionAlist);
    const ScmObj timeoutObj = assocRefOption("timeout", optionAlist);
    const int flags = Scm_GetInteger(flagsObj);
    const char * vfs = (SCM_FALSEP(vfsObj)) ? NULL : Scm_GetStringConst(SCM_STRING(vfsObj));
    const int timeoutMS = (SCM_FALSEP(timeoutObj)) ? -1 : Scm_GetInteger(timeoutObj);

    const int result = sqlite3_open_v2(
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
        /* Not using v2 interface. no need consider other statement resource here */
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

    const int result = sqlite3_close_v2(db->ptr);

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

ScmObj prepareStmt(ScmSqliteDb * db, ScmString * sql, const int flags)
{
    const char * zSql = Scm_GetStringConst(sql);
    unsigned int prepFlags = flags;
    sqlite3_stmt * pStmt = NULL;
    sqlite3_stmt * pLastStmt = NULL;
    const char * zTail = zSql;
    ScmString * errmsg = NULL;
    sqlite3_stmt ** pStmts = NULL;
    int count = 0;
    int maxCount = 4;

    if (db->ptr == NULL) {
        errmsg = dupErrorMessage("Database has been closed.");
        goto error;
    }

    pStmts = SCM_NEW_ATOMIC_ARRAY(sqlite3_stmt*, maxCount);

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

        if (pStmt == NULL)
            break;

        SCM_ASSERT(zTail != zSql);

        /* grow allocation */
        if (maxCount <= count) {
            pStmts = reallocStatements(pStmts, maxCount * 2);
            maxCount = maxCount * 2;
        }

        pStmts[count] = pStmt;
        pLastStmt = pStmt;
        pStmt = NULL;
        zSql = zTail;
        count++;

        if (*zSql == '\0')
            break;
    }

    ScmSqliteStmt * stmt = SCM_NEW(ScmSqliteStmt);
    SCM_SET_CLASS(stmt, SCM_CLASS_SQLITE_STMT);

    Scm_RegisterFinalizer(SCM_OBJ(stmt), finalizeStmtMaybe, NULL);

    stmt->columns = readColumns(pLastStmt);
    stmt->db = db;
    /* Maybe shrink allocation */
    if (count < maxCount) {
        pStmts = reallocStatements(pStmts, count);
    }
    stmt->pptr = pStmts;
    stmt->ptrCount = count;

    return SCM_OBJ(stmt);

 error:

    SCM_ASSERT(errmsg != NULL);

    raiseError(errmsg);
}

/* SQLite Parameter allow ":", "$", "@", "?" prefix  */
/* This function return list that contains ScmString with those prefix */
/* e.g. "SELECT :hoge, @foo" sql -> (":hoge" "@foo")  */
/* NOTE: edge case, Programmer can choose "SELECT ?999" as a parameter. */
ScmObj listParameters(const ScmSqliteStmt * stmt, const int i)
{
    ScmString * errmsg = NULL;
    sqlite3_stmt ** pStmts = stmt->pptr;
    ScmObj result = SCM_NIL;
    sqlite3_stmt * pStmt = pStmts[i];

    if (pStmt == NULL) {
        errmsg = dupErrorMessage("Statement has been closed.");
        goto error;
    }

    int count = sqlite3_bind_parameter_count(pStmt);

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

void resetStmt(ScmSqliteStmt * stmt, const int i)
{
    SCM_ASSERT(0 <= i && i < stmt->ptrCount);

    sqlite3_stmt * pStmt = stmt->pptr[i];

    SCM_ASSERT(pStmt != NULL);

    /* this call does not reset binding parameter. */
    sqlite3_reset(pStmt);

    /* Most recent sqlite3_step has an error, sqlite3_reset return error code. */
    /* But no need to check the result since return to initial state. */
}

void bindParameters(ScmSqliteStmt * stmt, const int i, const ScmObj params)
{
    SCM_ASSERT(0 <= i && i < stmt->ptrCount);

    sqlite3_stmt * pStmt = stmt->pptr[i];

    SCM_ASSERT(pStmt != NULL);
    SCM_ASSERT(SCM_LISTP(params));

    ScmObj ps = params;

    /* Does not describe about return value. */
    sqlite3_clear_bindings(pStmt);

    const ScmSize len = Scm_Length(ps);

    /* Bind parameter index start from 1 not 0 */
    for (int i = 1; i <= len; i++) {
        const ScmObj scmValue = SCM_CAR(ps);

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

        ps = SCM_CDR(ps);
    }
}

ScmObj readLastChanges(ScmSqliteStmt * stmt)
{
    const int changes = sqlite3_changes(stmt->db->ptr);

    return Scm_MakeInteger(changes);
}

ScmObj readResult(ScmSqliteStmt * stmt, const int i)
{
    SCM_ASSERT(0 <= i && i < stmt->ptrCount);

    sqlite3_stmt * pStmt = stmt->pptr[i];
    const int result = sqlite3_step(pStmt);
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
        return readRow(pStmt);
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
    for (int i = 0; i < stmt->ptrCount; i++) {
        if (stmt->pptr[i] == NULL)
            continue;

        sqlite3_finalize(stmt->pptr[i]);
        stmt->pptr[i] = NULL;
    }

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
