/*
 * dbd_sqlite.c
 */

#include "dbd_sqlite.h"

/*
 * The following function is a dummy one; replace it for
 * your C function definitions.
 */

ScmObj test_dbd_sqlite(void)
{
    return SCM_MAKE_STR("dbd_sqlite is working");
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
    mod = SCM_MODULE(SCM_FIND_MODULE("dbd_sqlite", TRUE));

    /* Register stub-generated procedures */
    Scm_Init_dbd_sqlitelib(mod);
}
