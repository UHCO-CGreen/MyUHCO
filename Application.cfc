component output="false" {

    this.name              = "MyUHCOPortal";
    this.sessionManagement = true;
    this.sessionTimeout    = createTimeSpan(0, 8, 0, 0);
    this.setClientCookies  = true;
    this.showDebugOutput   = false;

    // ── WebSocket channels (STEP 8) ────────────────────────────────────
    // securityEvents: real-time auth event feed for the admin dashboard.
    // Subscribers receive best-effort pushes; WebSocket never controls auth.
    this.wschannels = [
        { name: "securityEvents" }
    ];

    private void function loadModuleRegistry() output="false" {
        var registryPath = expandPath("/data/modules/registry.json");
        var registryInfo = {};

        try {
            if (fileExists(registryPath)) {
                registryInfo = getFileInfo(registryPath);
                application.moduleRegistry = deserializeJSON(fileRead(registryPath, "UTF-8"));
                if (!isArray(application.moduleRegistry)) {
                    application.moduleRegistry = [];
                }
                application.moduleRegistryFileModified = structKeyExists(registryInfo, "lastModified") ? registryInfo.lastModified : now();
            } else {
                application.moduleRegistry = [];
                application.moduleRegistryFileModified = "";
                cflog(file="myuhco-registry", type="warning",
                    text="registry.json not found at #registryPath#. Using empty registry.");
            }
        } catch (any e) {
            application.moduleRegistry = [];
            application.moduleRegistryFileModified = "";
            cflog(file="myuhco-registry", type="error",
                text="Module registry load failed: #e.message#");
        }

        application.moduleRegistryLoadTime = now();
    }

    // ── Application start ──────────────────────────────────────────────
    public boolean function onApplicationStart() {
        application.portalAuthService = new models.services.AuthService();
        application.directoryService = new models.services.DirectoryService();
        application.dateHelper = new models.helpers.DateHelper();
        application.appConfigService = new models.services.AppConfigService().init(
            datasource = "UHCO_Identity_Admin",
            tableName = "AppConfig",
            keyColumn = "ConfigKey",
            valueColumn = "ConfigValue",
            appColumn = "",
            appName = "myUHCO"
        );
        application.dropboxProvider = new models.services.DropboxProvider().init(
            configReader = application.appConfigService
        );
        application.documentService = new models.services.DocumentService(
            manifestPath = expandPath("/data/documents/manifest.json"),
            dropboxProvider = application.dropboxProvider
        );
        application.linkService = new models.services.LinkService(
            defaultManifestPath = expandPath("/data/links/default-links.json"),
            userDirectoryPath = expandPath("/data/links/users")
        );

        // UH API credentials
        application.MYUHCO_API_URL    = "";
        application.MYUHCO_API_TOKEN  = "";
        application.MYUHCO_API_SECRET = "";

        // Session control and token config
        application.myuhcoDatasource  = "";
        application.cookieDomain      = "";
        application.tokenService      = "";

        var env = {};
        var envKey = "";

        // Preferred: built-in system environment struct
        try {
            env = getSystemEnvironment();
        } catch (any e) {
            env = {};
        }

        // API base URL lookup (case-insensitive)
        if (structKeyExists(env, "MYUHCO_API_URL")) {
            application.MYUHCO_API_URL = trim(env["MYUHCO_API_URL"] & "");
        } else {
            for (envKey in env) {
                if (compareNoCase(envKey, "MYUHCO_API_URL") EQ 0) {
                    application.MYUHCO_API_URL = trim(env[envKey] & "");
                    break;
                }
            }
        }

        // Token lookup (case-insensitive)
        if (structKeyExists(env, "MYUHCO_API_TOKEN")) {
            application.MYUHCO_API_TOKEN = trim(env["MYUHCO_API_TOKEN"] & "");
        } else {
            for (envKey in env) {
                if (compareNoCase(envKey, "MYUHCO_API_TOKEN") EQ 0) {
                    application.MYUHCO_API_TOKEN = trim(env[envKey] & "");
                    break;
                }
            }
        }

        // Secret lookup (case-insensitive)
        if (structKeyExists(env, "MYUHCO_API_SECRET")) {
            application.MYUHCO_API_SECRET = trim(env["MYUHCO_API_SECRET"] & "");
        } else {
            for (envKey in env) {
                if (compareNoCase(envKey, "MYUHCO_API_SECRET") EQ 0) {
                    application.MYUHCO_API_SECRET = trim(env[envKey] & "");
                    break;
                }
            }
        }

        // Fallback: Java getenv
        if (NOT len(application.MYUHCO_API_URL)) {
            try {
                application.MYUHCO_API_URL = trim(createObject("java", "java.lang.System").getenv("MYUHCO_API_URL") & "");
            } catch (any e) {
                // keep empty
            }
        }
        if (NOT len(application.MYUHCO_API_TOKEN)) {
            try {
                application.MYUHCO_API_TOKEN = trim(createObject("java", "java.lang.System").getenv("MYUHCO_API_TOKEN") & "");
            } catch (any e) {
                // keep empty
            }
        }
        if (NOT len(application.MYUHCO_API_SECRET)) {
            try {
                application.MYUHCO_API_SECRET = trim(createObject("java", "java.lang.System").getenv("MYUHCO_API_SECRET") & "");
            } catch (any e) {
                // keep empty
            }
        }
        // Log presence only (never log secret values)
        cflog(
            file = "myuhco-api",
            type = "information",
            text = "Env load onApplicationStart - api url present: #iif(len(application.MYUHCO_API_URL), de('YES'), de('NO'))#, token present: #iif(len(application.MYUHCO_API_TOKEN), de('YES'), de('NO'))#, secret present: #iif(len(application.MYUHCO_API_SECRET), de('YES'), de('NO'))#"
        );

        if (NOT len(application.MYUHCO_API_URL)) {
            cflog(file = "myuhco-api", type = "warning", text = "Startup config warning: MYUHCO_API_URL is missing.");
        }
        if (NOT len(application.MYUHCO_API_TOKEN)) {
            cflog(file = "myuhco-api", type = "warning", text = "Startup config warning: MYUHCO_API_TOKEN is missing.");
        }
        if (NOT len(application.MYUHCO_API_SECRET)) {
            cflog(file = "myuhco-api", type = "warning", text = "Startup config warning: MYUHCO_API_SECRET is missing.");
        }

        // ── Session datasource (MYUHCO_DS) ─────────────────────────────────────
        if (structKeyExists(env, "MYUHCO_DS") AND len(trim(env["MYUHCO_DS"] & ""))) {
            application.myuhcoDatasource = trim(env["MYUHCO_DS"] & "");
        } else {
            try {
                application.myuhcoDatasource = trim(createObject("java", "java.lang.System").getenv("MYUHCO_DS") & "");
            } catch (any e) {
                // keep empty
            }
        }

        try {
            application.pageService = new models.services.PageService().init(
                datasource = application.myuhcoDatasource,
                tableName = "PortalPages"
            );
        } catch (any e) {
            application.pageService = "";
            cflog(file = "myuhco-pages", type = "warning",
                text = "PageService not initialized: #e.message#.");
        }

        // ── Cookie domain (MYUHCO_COOKIE_DOMAIN) ───────────────────────────────
        if (structKeyExists(env, "MYUHCO_COOKIE_DOMAIN") AND len(trim(env["MYUHCO_COOKIE_DOMAIN"] & ""))) {
            application.cookieDomain = trim(env["MYUHCO_COOKIE_DOMAIN"] & "");
        } else {
            try {
                application.cookieDomain = trim(createObject("java", "java.lang.System").getenv("MYUHCO_COOKIE_DOMAIN") & "");
            } catch (any e) {
                // keep empty
            }
        }

        // ── TokenService ────────────────────────────────────────────────────────
        try {
            application.tokenService = new models.services.TokenService().init();
        } catch (any e) {
            application.tokenService = "";
            cflog(file = "myuhco-token", type = "warning",
                text = "TokenService not initialized: #e.message#. Set MYUHCO_SECRET to enable token issuance.");
        }

        // ── AccessService ────────────────────────────────────────────────────────
        try {
            application.accessService = new models.services.AccessService().init();
        } catch (any e) {
            application.accessService = "";
            cflog(file = "myuhco-access", type = "warning",
                text = "AccessService not initialized: #e.message#.");
        }

        // ── SecurityService ──────────────────────────────────────────────────────
        try {
            application.securityService = new models.services.SecurityService().init();
        } catch (any e) {
            application.securityService = "";
            cflog(file = "myuhco-security", type = "warning",
                text = "SecurityService not initialized: #e.message#.");
        }
        // ── Module registry ──────────────────────────────────────────────────────────
        loadModuleRegistry();
        return true;
    }
    // ── Request start ──────────────────────────────────────────────────
    public boolean function onRequestStart(required string targetPage) {
        var expectedDirectoryServiceBuild = "2026-05-19-directory-api-header-auth-v1";
        var currentDirectoryServiceBuild = "";
        var expectedPageServiceBuild = "2026-05-17-pages-p2-nav-dispatch-v1";
        var currentPageServiceBuild = "";

        // Reinitialize application if requested
        if (structKeyExists(url, "reinit") AND url.reinit EQ "true") {
            onApplicationStart();
            if (lCase(arguments.targetPage) EQ "/login.cfm") {
                if (structKeyExists(url, "error") AND len(trim(url.error & ""))) {
                    location("/login.cfm?error=#urlEncodedFormat(trim(url.error & ""))#", false);
                }
                location("/login.cfm", false);
            }
        }

        // Safety: ensure onApplicationStart() has run
        if (
            !structKeyExists(application, "portalAuthService") OR
            !structKeyExists(application, "directoryService") OR
            !structKeyExists(application, "dateHelper") OR
            !structKeyExists(application, "appConfigService") OR
            !structKeyExists(application, "dropboxProvider") OR
            !structKeyExists(application, "documentService") OR
            !structKeyExists(application, "linkService") OR
            !structKeyExists(application, "pageService") OR
            !structKeyExists(application, "tokenService") OR
            !structKeyExists(application, "accessService") OR
            !structKeyExists(application, "securityService") OR
            !structKeyExists(application, "moduleRegistry")
        ) {
            onApplicationStart();
        }

        // Refresh the application-scoped directory service when its implementation changes.
        try {
            currentDirectoryServiceBuild = application.directoryService.getBuildSignature();
        } catch (any e) {
            currentDirectoryServiceBuild = "";
        }

        if (currentDirectoryServiceBuild NEQ expectedDirectoryServiceBuild) {
            application.directoryService = new models.services.DirectoryService();
        }

        try {
            currentPageServiceBuild = application.pageService.getBuildSignature();
        } catch (any e) {
            currentPageServiceBuild = "";
        }

        if (currentPageServiceBuild NEQ expectedPageServiceBuild) {
            try {
                application.pageService = new models.services.PageService().init(
                    datasource = application.myuhcoDatasource,
                    tableName = "PortalPages"
                );
            } catch (any e) {
                application.pageService = "";
                cflog(file = "myuhco-pages", type = "warning",
                    text = "PageService refresh failed: #e.message#.");
            }
        }

        try {
            var requestRegistryPath = expandPath("/data/modules/registry.json");
            if (fileExists(requestRegistryPath)) {
                var requestRegistryInfo = getFileInfo(requestRegistryPath);
                if (
                    !structKeyExists(application, "moduleRegistryFileModified")
                    OR !isDate(application.moduleRegistryFileModified)
                    OR requestRegistryInfo.lastModified GT application.moduleRegistryFileModified
                ) {
                    loadModuleRegistry();
                }
            }
        } catch (any e) {
            cflog(file="myuhco-registry", type="warning",
                text="Module registry freshness check failed: #e.message#");
        }

        // Pages that do not require an active session
        var publicPages = [
            "/login.cfm",
            "/authenticate.cfm",
            "/logout.cfm",
            "/auth/status.cfm",
            "/auth/refresh.cfm",
            "/auth/activity.cfm",
            "/modules/directory/data.cfm"
        ];

        var path = lCase(arguments.targetPage);
        var isPublicPage = arrayFind(publicPages, path);
        var isPublicModuleRoute = false;
        var requestedModuleID = "";
        var registeredModule = {};
        var isLoggedIn = application.portalAuthService.isLoggedIn();
        var currentUserID = 0;
        var currentSessionVersion = 0;
        var hasSessionVersion = false;
        var currentLoginTime = "";
        var qSessionControl = "";
        var dbSessionVersion = 0;
        var hasForcedLogout = false;
        var hasLastLogout = false;
        var requiresReinit = false;
        var forceLogoutTriggered = false;
        var logoutTriggered = false;
        var sessionVersionMismatch = false;
        var currentRequestPath = left(trim(cgi.script_name & (len(trim(cgi.query_string & "")) ? "?" & trim(cgi.query_string & "") : "")), 500);
        var currentSessionRowID = (structKeyExists(session, "userSessionRowID") AND isNumeric(session.userSessionRowID)) ? int(val(session.userSessionRowID)) : 0;

        if (
            path EQ "/index.cfm"
            AND structKeyExists(url, "module")
            AND len(trim(url.module & ""))
            AND structKeyExists(application, "moduleRegistry")
            AND isArray(application.moduleRegistry)
        ) {
            requestedModuleID = lCase(trim(url.module & ""));
            for (registeredModule in application.moduleRegistry) {
                if (
                    structKeyExists(registeredModule, "id")
                    AND lCase(trim(registeredModule.id & "")) EQ requestedModuleID
                    AND structKeyExists(registeredModule, "enabled")
                    AND registeredModule.enabled
                    AND (!structKeyExists(registeredModule, "requiresAuth") OR registeredModule.requiresAuth EQ false)
                ) {
                    isPublicModuleRoute = true;
                    break;
                }
            }
        }

        if (
            isLoggedIn
            AND structKeyExists(session, "user")
            AND structKeyExists(session.user, "userID")
            AND isNumeric(session.user.userID)
            AND session.user.userID GT 0
            AND structKeyExists(application, "myuhcoDatasource")
            AND len(trim(application.myuhcoDatasource))
        ) {
            currentUserID = int(val(session.user.userID));
            hasSessionVersion = structKeyExists(session.user, "sessionVersion") AND isNumeric(session.user.sessionVersion);
            currentSessionVersion = hasSessionVersion ? int(val(session.user.sessionVersion)) : 0;
            currentLoginTime = structKeyExists(session.user, "loginTime") ? session.user.loginTime : "";

            try {
                qSessionControl = queryExecute(
                    "SELECT SessionVersion, LastLogout, LastForcedLogout, RequireReinit FROM dbo.UserSessionControl WHERE UserID = :uid",
                    { uid: { value: currentUserID, cfsqltype: "cf_sql_integer" } },
                    { datasource: application.myuhcoDatasource }
                );

                if (qSessionControl.recordCount GT 0) {
                    dbSessionVersion = int(val(qSessionControl.SessionVersion[1]));
                    hasForcedLogout = isDate(qSessionControl.LastForcedLogout[1]);
                    hasLastLogout = isDate(qSessionControl.LastLogout[1]);
                    requiresReinit = isNumeric(qSessionControl.RequireReinit[1]) AND int(val(qSessionControl.RequireReinit[1])) EQ 1;
                    sessionVersionMismatch = hasSessionVersion AND dbSessionVersion NEQ currentSessionVersion;
                    logoutTriggered = isDate(currentLoginTime) AND hasLastLogout AND dateCompare(qSessionControl.LastLogout[1], currentLoginTime) GT 0;
                    forceLogoutTriggered = isDate(currentLoginTime) AND hasForcedLogout AND dateCompare(qSessionControl.LastForcedLogout[1], currentLoginTime) GT 0;

                    if (
                        sessionVersionMismatch
                        OR logoutTriggered
                        OR forceLogoutTriggered
                    ) {
                        structDelete(session, "user");
                        structDelete(session, "portalUser");
                        structDelete(session, "accessCache");
                        structDelete(session, "accessLastChecked");
                        structDelete(session, "lastActivityUpdate");
                        if (forceLogoutTriggered) {
                            if (requiresReinit) {
                                try {
                                    queryExecute(
                                        "UPDATE dbo.UserSessionControl SET RequireReinit = 0, UpdatedAt = GETDATE() WHERE UserID = :uid",
                                        { uid: { value: currentUserID, cfsqltype: "cf_sql_integer" } },
                                        { datasource: application.myuhcoDatasource }
                                    );
                                } catch (any e) {
                                    cflog(file="myuhco-session", type="error",
                                        text="onRequestStart RequireReinit clear failed for userID #currentUserID#: #e.message#");
                                }
                                location("/login.cfm?reinit=true&error=Your+session+was+ended+by+web+admins.+If+told+to+do+so+you+may+log+back+in.", false);
                            }
                            location("/login.cfm?error=Your+session+was+ended+by+web+admins.+If+told+to+do+so+you+may+log+back+in.", false);
                        }
                        location("/login.cfm?error=Your+session+has+expired.+Please+sign+in+again.", false);
                    }
                }
            } catch (any e) {
                cflog(file="myuhco-session", type="error",
                    text="onRequestStart session currency check failed for userID #currentUserID#: #e.message#");
            }
        }

        if (NOT isPublicPage AND NOT isPublicModuleRoute AND NOT isLoggedIn) {
            location("/login.cfm", false);
        }

        // STEP 6: Update LastActivity for authenticated portal users (throttled to once per minute)
        if (
            isLoggedIn
            AND structKeyExists(session, "user")
            AND structKeyExists(session.user, "userID")
            AND isNumeric(session.user.userID)
            AND session.user.userID GT 0
            AND structKeyExists(application, "myuhcoDatasource")
            AND len(trim(application.myuhcoDatasource))
        ) {
            var activityTick = structKeyExists(session, "lastActivityUpdate") ? session.lastActivityUpdate : 0;
            var activityUserID = int(val(session.user.userID));
            try {
                if (currentSessionRowID GT 0) {
                    queryExecute(
                        "UPDATE dbo.UserSessions SET LastVisitedPath = :path, UpdatedAt = GETDATE() WHERE SessionID = :sid AND UserID = :uid AND IsActive = 1",
                        {
                            path: { value: currentRequestPath, cfsqltype: "cf_sql_varchar" },
                            sid: { value: currentSessionRowID, cfsqltype: "cf_sql_integer" },
                            uid: { value: activityUserID, cfsqltype: "cf_sql_integer" }
                        },
                        { datasource: application.myuhcoDatasource }
                    );
                }
            } catch (any e) {
                cflog(file="myuhco-session", type="error",
                    text="onRequestStart LastVisitedPath update failed: #e.message#");
            }

            if ((getTickCount() - activityTick) GT 60000) {
                session.lastActivityUpdate = getTickCount();
                try {
                    queryExecute(
                        "UPDATE dbo.UserSessionControl SET LastActivity = GETDATE(), UpdatedAt = GETDATE() WHERE UserID = :uid",
                        { uid: { value: activityUserID, cfsqltype: "cf_sql_integer" } },
                        { datasource: application.myuhcoDatasource }
                    );
                } catch (any e) {
                    cflog(file="myuhco-session", type="error",
                        text="onRequestStart LastActivity update failed: #e.message#");
                }
            }
        }

        return true;
    }

}
