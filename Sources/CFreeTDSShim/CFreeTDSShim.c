#include "CFreeTDSShim.h"
#include <string.h>
#include <stdio.h>

// Thread-local storage for the last error/message from FreeTDS.
// Thread-local is correct because FreeTDS calls handlers synchronously on the calling thread,
// and ConnectionManager serializes all FreeTDS operations on a single dispatch queue.
static _Thread_local char last_error[2048] = {0};
static _Thread_local int has_error = 0;

static int swift_err_handler(DBPROCESS *dbproc, int severity, int dberr,
                              int oserr, char *dberrstr, char *oserrstr) {
    snprintf(last_error, sizeof(last_error), "DB-Library error %d (severity %d): %s",
             dberr, severity, dberrstr ? dberrstr : "unknown");
    has_error = 1;
    return INT_CANCEL;
}

static int swift_msg_handler(DBPROCESS *dbproc, DBINT msgno, int msgstate,
                              int severity, char *msgtext, char *srvname,
                              char *proc, int line) {
    // Severity >= 11 are errors; lower are informational (e.g. "Changed database context to...")
    if (severity >= 11) {
        snprintf(last_error, sizeof(last_error), "SQL Server error %ld (severity %d, state %d): %s",
                 (long)msgno, severity, msgstate, msgtext ? msgtext : "unknown");
        has_error = 1;
    }
    return 0;
}

void swift_install_error_handlers(void) {
    dberrhandle(swift_err_handler);
    dbmsghandle(swift_msg_handler);
}

const char* swift_get_last_error(void) {
    if (has_error) {
        return last_error;
    }
    return NULL;
}

void swift_clear_last_error(void) {
    has_error = 0;
    last_error[0] = '\0';
}

void swift_DBSETLUSER(LOGINREC *login, const char *user) {
    DBSETLUSER(login, user);
}

void swift_DBSETLPWD(LOGINREC *login, const char *pwd) {
    DBSETLPWD(login, pwd);
}

void swift_DBSETLAPP(LOGINREC *login, const char *app) {
    DBSETLAPP(login, app);
}

RETCODE swift_dbcancel(DBPROCESS *dbproc) {
    return dbcancel(dbproc);
}
