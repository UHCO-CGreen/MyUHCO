component output="false" {

    variables.algorithm = "HmacSHA256";

    /**
     * Initialize service. Reads MYUHCO_SECRET from environment.
     * Throws TokenService.ConfigError if the secret is not set.
     */
    public any function init() {
        var env = {};
        variables.secret = "";

        try {
            env = getSystemEnvironment();
        } catch (any e) {
            env = {};
        }

        if (structKeyExists(env, "MYUHCO_SECRET") AND len(trim(env["MYUHCO_SECRET"] & ""))) {
            variables.secret = trim(env["MYUHCO_SECRET"] & "");
        } else {
            try {
                variables.secret = trim(createObject("java", "java.lang.System").getenv("MYUHCO_SECRET") & "");
            } catch (any e) {
                variables.secret = "";
            }
        }

        if (NOT len(variables.secret)) {
            throw(
                type    = "TokenService.ConfigError",
                message = "MYUHCO_SECRET environment variable is not set"
            );
        }

        return this;
    }

    /**
     * Build the standard MyUHCO token payload.
     * exp = now + 300 seconds (5-minute window).
     * iat = epoch seconds at time of issuance.
     *
     * @userID         INT — canonical identity key from UHCO_Identity API
     * @sessionVersion INT — current value from UserSessionControl
     */
    public struct function buildPayload(required numeric userID, required numeric sessionVersion) {
        var nowEpoch = _dateToEpoch(now());
        var p = structNew("ordered");
        p["userID"]         = javaCast("int", arguments.userID);
        p["sessionVersion"] = javaCast("int", arguments.sessionVersion);
        p["iat"]            = javaCast("int", nowEpoch);
        p["exp"]            = javaCast("int", nowEpoch + 300);
        return p;
    }

    /**
     * Build a short-lived redirect payload for Type 4 external module SSO.
     * Does not include sessionVersion — external apps only need userID + exp.
     *
     * @userID      INT — canonical identity key
     * @ttlSeconds  Lifetime in seconds (default 120 — 2 minutes)
     */
    public struct function buildRedirectPayload(required numeric userID, numeric ttlSeconds=120) {
        var nowEpoch = _dateToEpoch(now());
        var p = structNew("ordered");
        p["userID"] = javaCast("int", arguments.userID);
        p["iat"]    = javaCast("int", nowEpoch);
        p["exp"]    = javaCast("int", nowEpoch + arguments.ttlSeconds);
        return p;
    }

    /**
     * Build a long-lived public display token payload for a standalone public module.
     * Default lifetime is 365 days.
     */
    public struct function buildModuleAccessPayload(required string moduleID, numeric ttlSeconds=31536000) {
        var nowEpoch = _dateToEpoch(now());
        var p = structNew("ordered");
        p["kind"]     = "public-module";
        p["moduleID"] = trim(arguments.moduleID & "");
        p["iat"]      = javaCast("int", nowEpoch);
        p["exp"]      = javaCast("int", nowEpoch + arguments.ttlSeconds);
        return p;
    }

    /**
     * Sign a payload struct. Returns a JWT-format token string (header.payload.signature).
     * Required payload keys: userID (int), exp (epoch int).
     * sessionVersion is optional (present in session tokens, absent in redirect tokens).
     */
    public string function signToken(required struct payload) {
        if (NOT structKeyExists(arguments.payload, "userID")) {
            throw(type = "TokenService.PayloadError", message = "payload.userID is required");
        }
        if (NOT structKeyExists(arguments.payload, "exp")) {
            throw(type = "TokenService.PayloadError", message = "payload.exp is required");
        }

        return _signPayload(arguments.payload);
    }

    /**
     * Sign a token for a public standalone module display route.
     */
    public string function signModuleAccessToken(required string moduleID, numeric ttlSeconds=31536000) {
        return _signPayload(buildModuleAccessPayload(arguments.moduleID, arguments.ttlSeconds));
    }

    /**
     * Verify a token string.
     * Returns: { valid=bool, payload=struct (when valid), reason=string (when invalid) }
     */
    public struct function verifyToken(required string token) {
        var parts = listToArray(arguments.token, ".");

        if (arrayLen(parts) NEQ 3) {
            return { valid = false, reason = "Invalid token format" };
        }

        var encodedHeader  = parts[1];
        var encodedPayload = parts[2];
        var signature      = parts[3];
        var expected       = _generateSignature(encodedHeader & "." & encodedPayload);

        if (signature NEQ expected) {
            return { valid = false, reason = "Invalid signature" };
        }

        var payloadJson = _base64UrlDecode(encodedPayload);
        var payload     = deserializeJSON(payloadJson);

        if (NOT structKeyExists(payload, "exp")) {
            return { valid = false, reason = "Missing exp" };
        }

        if (_dateToEpoch(now()) GT payload.exp) {
            return { valid = false, reason = "Token expired" };
        }

        return { valid = true, payload = payload };
    }

    /**
     * Verify that a token is a valid public display token for the requested module.
     */
    public struct function verifyModuleAccessToken(required string token, required string moduleID) {
        var verification = verifyToken(arguments.token);
        var payload = {};

        if (!verification.valid) {
            return verification;
        }

        payload = verification.payload;
        if (!structKeyExists(payload, "kind") OR trim(payload.kind & "") NEQ "public-module") {
            return { valid = false, reason = "Invalid token kind" };
        }

        if (!structKeyExists(payload, "moduleID") OR !len(trim(payload.moduleID & ""))) {
            return { valid = false, reason = "Missing moduleID" };
        }

        if (lCase(trim(payload.moduleID & "")) NEQ lCase(trim(arguments.moduleID & ""))) {
            return { valid = false, reason = "Module mismatch" };
        }

        return verification;
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    /**
     * Generate HMAC-SHA256 signature for the input string.
     * Returns base64url-encoded signature bytes.
     */
    private string function _generateSignature(required string input) {
        var mac     = createObject("java", "javax.crypto.Mac").getInstance(variables.algorithm);
        var keySpec = createObject("java", "javax.crypto.spec.SecretKeySpec").init(
            charsetDecode(variables.secret, "utf-8"),
            variables.algorithm
        );
        mac.init(keySpec);
        var rawHmac = mac.doFinal(charsetDecode(arguments.input, "utf-8"));

        // binaryEncode gives base64 of raw bytes; make it URL-safe
        var b64 = binaryEncode(rawHmac, "base64");
        b64 = replace(b64, "+", "-", "all");
        b64 = replace(b64, "/", "_", "all");
        b64 = replace(b64, "=", "", "all");
        return b64;
    }

    /**
     * Sign any payload struct into the shared JWT-style token format.
     */
    private string function _signPayload(required struct payload) {
        var header         = { "alg" = "HS256", "typ" = "JWT" };
        var encodedHeader  = _base64UrlEncode(serializeJSON(header));
        var encodedPayload = _base64UrlEncode(serializeJSON(arguments.payload));
        var signature      = _generateSignature(encodedHeader & "." & encodedPayload);

        return encodedHeader & "." & encodedPayload & "." & signature;
    }

    /**
     * Encode a plain string to base64url format.
     * Used for header and payload segments.
     */
    private string function _base64UrlEncode(required string input) {
        var b64 = toBase64(input);
        b64 = replace(b64, "+", "-", "all");
        b64 = replace(b64, "/", "_", "all");
        b64 = replace(b64, "=", "", "all");
        return b64;
    }

    /**
     * Decode a base64url segment back to a plain string.
     */
    private string function _base64UrlDecode(required string input) {
        var b64 = replace(arguments.input, "-", "+", "all");
        b64 = replace(b64, "_", "/", "all");
        while ((len(b64) mod 4) NEQ 0) {
            b64 &= "=";
        }
        return toString(binaryDecode(b64, "base64"));
    }

    /**
     * Convert a CF date/time value to Unix epoch seconds (UTC).
     */
    private numeric function _dateToEpoch(required date dt) {
        return int(arguments.dt.getTime() / 1000);
    }

}
