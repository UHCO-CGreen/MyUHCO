component output="false" {

    this.name              = "MyUHCOPortal";
    this.sessionManagement = true;
    this.sessionTimeout    = createTimeSpan(0, 8, 0, 0);
    this.setClientCookies  = true;
    this.showDebugOutput   = false;

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

        return true;
    }
    // ── Request start ──────────────────────────────────────────────────
    public boolean function onRequestStart(required string targetPage) {

        // Reinitialize application if requested
        if (structKeyExists(url, "reinit") AND url.reinit EQ "true") {
            onApplicationStart();
        }

        // Safety: ensure onApplicationStart() has run
        if (
            !structKeyExists(application, "portalAuthService") OR
            !structKeyExists(application, "directoryService") OR
            !structKeyExists(application, "dateHelper") OR
            !structKeyExists(application, "appConfigService") OR
            !structKeyExists(application, "dropboxProvider") OR
            !structKeyExists(application, "documentService") OR
            !structKeyExists(application, "linkService")
        ) {
            onApplicationStart();
        }

        // Pages that do not require an active session
        var publicPages = [
            "/login.cfm",
            "/authenticate.cfm",
            "/logout.cfm"
        ];

        var path = lCase(arguments.targetPage);
        var isPublicPage = arrayFind(publicPages, path);

        if (NOT isPublicPage AND NOT application.portalAuthService.isLoggedIn()) {
            location("/login.cfm", false);
        }

        return true;
    }

}
