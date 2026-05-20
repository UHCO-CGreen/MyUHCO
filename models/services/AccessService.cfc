component displayName="AccessService" accessors="true" {

    // Cache TTL: 10 minutes in milliseconds (getTickCount units)
    variables.CACHE_TTL_MS = 600000;

    public AccessService function init() {
        return this;
    }

    /**
     * Returns true if the current session user has the given permission.
     * Fetches from UHCO_Identity API on first call or when cache is stale (10 min).
     * Returns false — never aborts — so callers decide the HTTP response.
     */
    public boolean function hasPermission(required string permission) {

        // Must be logged in
        if (NOT structKeyExists(session, "user") OR NOT structKeyExists(session.user, "userID")) {
            return false;
        }

        var userID    = session.user.userID;
        var lastCheck = structKeyExists(session, "accessLastChecked") ? session.accessLastChecked : 0;
        var isStale   = ((getTickCount() - lastCheck) GT variables.CACHE_TTL_MS);

        if (NOT structKeyExists(session, "accessCache") OR isStale) {
            _refreshCache(userID);
        }

        if (NOT isArray(session.accessCache)) return false;

        return arrayFind(session.accessCache, lCase(trim(arguments.permission))) GT 0;
    }

    /**
     * Aborts with HTTP 403 if the current session user lacks the given permission.
     * Use at the top of protected CFM files.
     */
    public void function requirePermission(required string permission) {
        if (NOT hasPermission(arguments.permission)) {
            // STEP 7: Audit ACCESS_DENIED
            if (structKeyExists(application, "securityService") AND isObject(application.securityService)) {
                var _auditUID = (structKeyExists(session, "user") AND structKeyExists(session.user, "userID"))
                                    ? session.user.userID : "";
                application.securityService.auditLog(
                    eventType = "ACCESS_DENIED",
                    userID    = _auditUID,
                    ipAddress = left(trim(cgi.remote_addr & ""), 50),
                    userAgent = left(trim(cgi.http_user_agent & ""), 500),
                    details   = "permission=#arguments.permission#"
                );
            }
            cfheader(statuscode="403");
            cfabort(showerror="403 Forbidden — required permission: #arguments.permission#");
        }
    }

    /**
     * Fetches the user's permissions from UHCO_Identity and writes session.accessCache.
     * On any failure, cache is left as an empty array (fail closed).
     */
    private void function _refreshCache(required string userID) {

        var apiUrl    = application.MYUHCO_API_URL;
        var apiToken  = application.MYUHCO_API_TOKEN;
        var apiSecret = application.MYUHCO_API_SECRET;
        var result    = {};

        // Reset cache before fetch so a failed call is never stale-hit
        session.accessCache       = [];
        session.accessLastChecked = getTickCount();

        if (NOT len(trim(apiUrl)) OR NOT len(trim(apiToken)) OR NOT len(trim(apiSecret))) {
            cflog(
                file = "myuhco-access",
                type = "warning",
                text = "AccessService._refreshCache: API credentials not configured — all permissions denied for userID #arguments.userID#."
            );
            return;
        }

        try {
            cfhttp(
                url     = "#apiUrl#/access",
                method  = "GET",
                timeout = 5,
                result  = "result"
            ) {
                cfhttpparam(type="url", name="userID",  value="#arguments.userID#");
                cfhttpparam(type="header", name="Authorization", value="Bearer #apiToken#");
                cfhttpparam(type="header", name="X-API-Secret", value="#apiSecret#");
            }

            if (left(result.statusCode, 3) EQ "200") {
                var parsed = deserializeJSON(result.fileContent);
                // UHCO_Identity may return uppercase keys (CF serializeJSON default)
                var permKey = structKeyExists(parsed, "permissions") ? "permissions" : "PERMISSIONS";
                if (structKeyExists(parsed, permKey) AND isArray(parsed[permKey])) {
                    session.accessCache = parsed[permKey];
                }
            } else {
                cflog(
                    file = "myuhco-access",
                    type = "warning",
                    text = "AccessService._refreshCache: API returned #result.statusCode# for userID #arguments.userID#."
                );
            }

        } catch (any e) {
            cflog(
                file = "myuhco-access",
                type = "error",
                text = "AccessService._refreshCache exception for userID #arguments.userID#: #e.message#"
            );
        }
    }

}
