#ifndef CFreeTDSShim_h
#define CFreeTDSShim_h

#include <sybfront.h>
#include <sybdb.h>

// Expose C macros to Swift as callable functions
void swift_DBSETLUSER(LOGINREC *login, const char *user);
void swift_DBSETLPWD(LOGINREC *login, const char *pwd);
void swift_DBSETLAPP(LOGINREC *login, const char *app);

// Cancel an in-progress query (safe to call from a different thread)
RETCODE swift_dbcancel(DBPROCESS *dbproc);

// FreeTDS error/message handler registration and retrieval
void swift_install_error_handlers(void);
const char* swift_get_last_error(void);
void swift_clear_last_error(void);

#endif
