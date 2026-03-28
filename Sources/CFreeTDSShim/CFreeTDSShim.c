#include "CFreeTDSShim.h"

void swift_DBSETLUSER(LOGINREC *login, const char *user) {
    DBSETLUSER(login, user);
}

void swift_DBSETLPWD(LOGINREC *login, const char *pwd) {
    DBSETLPWD(login, pwd);
}

void swift_DBSETLAPP(LOGINREC *login, const char *app) {
    DBSETLAPP(login, app);
}
