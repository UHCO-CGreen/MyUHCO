<cfsetting showdebugoutput="false">
<cfscript>
  // ── Run all token system diagnostics ───────────────────────────────────────
  tests      = [];
  roundTripToken = ""; // shared for tamper test

  // ── Helper: append a test result ─────────────────────────────────────────
  function addTest(name, status, detail) {
    tests.append({ name=arguments.name, status=arguments.status, detail=arguments.detail });
  }

  // ────────────────────────────────────────────────────────────────────────
  // 1. TokenService initialized
  // ────────────────────────────────────────────────────────────────────────
  tsOk = isObject(application.tokenService);
  addTest(
    "TokenService initialized",
    tsOk ? "pass" : "fail",
    tsOk
      ? "application.tokenService is an active CFC instance"
      : "application.tokenService is not an object. Verify MYUHCO_SECRET is set and check myuhco-token.log."
  );

  // ────────────────────────────────────────────────────────────────────────
  // 2. MYUHCO_DS (session datasource)
  // ────────────────────────────────────────────────────────────────────────
  dsOk = structKeyExists(application, "myuhcoDatasource") AND len(trim(application.myuhcoDatasource));
  addTest(
    "MYUHCO_DS configured",
    dsOk ? "pass" : "warn",
    dsOk
      ? "Datasource: " & application.myuhcoDatasource
      : "Not configured. sessionVersion defaults to 1 and DB session control features are disabled."
  );

  // ────────────────────────────────────────────────────────────────────────
  // 3. MYUHCO_COOKIE_DOMAIN
  // ────────────────────────────────────────────────────────────────────────
  domOk = structKeyExists(application, "cookieDomain") AND len(trim(application.cookieDomain));
  addTest(
    "MYUHCO_COOKIE_DOMAIN configured",
    domOk ? "pass" : "warn",
    domOk
      ? "Domain: " & application.cookieDomain
      : "Not set. MYUHCO_TOKEN is scoped to the current domain only — cross-subdomain SSO is disabled."
  );

  // ────────────────────────────────────────────────────────────────────────
  // 4. Sign/verify round-trip
  // ────────────────────────────────────────────────────────────────────────
  if (tsOk) {
    try {
      testPayload    = application.tokenService.buildPayload(99999, 1);
      roundTripToken = application.tokenService.signToken(testPayload);
      rtVerify       = application.tokenService.verifyToken(roundTripToken);
      addTest(
        "Sign/verify round-trip",
        rtVerify.valid ? "pass" : "fail",
        rtVerify.valid
          ? "Token signed and verified successfully. userID=99999, sessionVersion=1"
          : "Verification failed after signing: " & rtVerify.reason
      );
    } catch (any e) {
      addTest("Sign/verify round-trip", "fail", "Exception: " & e.message);
    }
  } else {
    addTest("Sign/verify round-trip", "skip", "Skipped — TokenService not initialized.");
  }

  // ────────────────────────────────────────────────────────────────────────
  // 5. Expired token rejected
  // ────────────────────────────────────────────────────────────────────────
  if (tsOk) {
    try {
      expPayload = { userID=javaCast("int",99999), sessionVersion=javaCast("int",1), iat=javaCast("int",1000000), exp=javaCast("int",1000001) };
      expToken   = application.tokenService.signToken(expPayload);
      expVerify  = application.tokenService.verifyToken(expToken);
      addTest(
        "Expired token rejected",
        (!expVerify.valid AND expVerify.reason EQ "Token expired") ? "pass" : "fail",
        (!expVerify.valid AND expVerify.reason EQ "Token expired")
          ? "Correctly rejected with: '" & expVerify.reason & "'"
          : "Unexpected result — valid=" & expVerify.valid & (structKeyExists(expVerify,"reason") ? ", reason=" & expVerify.reason : "")
      );
    } catch (any e) {
      addTest("Expired token rejected", "fail", "Exception: " & e.message);
    }
  } else {
    addTest("Expired token rejected", "skip", "Skipped — TokenService not initialized.");
  }

  // ────────────────────────────────────────────────────────────────────────
  // 6. Tampered token rejected
  // ────────────────────────────────────────────────────────────────────────
  if (tsOk AND len(roundTripToken)) {
    try {
      tamperedToken  = roundTripToken & "X";
      tampVerify     = application.tokenService.verifyToken(tamperedToken);
      addTest(
        "Tampered token rejected",
        !tampVerify.valid ? "pass" : "fail",
        !tampVerify.valid
          ? "Correctly rejected with: '" & tampVerify.reason & "'"
          : "FAIL — modified token incorrectly validated as valid."
      );
    } catch (any e) {
      addTest("Tampered token rejected", "fail", "Exception: " & e.message);
    }
  } else {
    addTest("Tampered token rejected", "skip", "Skipped — round-trip token not available.");
  }

  // ────────────────────────────────────────────────────────────────────────
  // 7. Session state (sessionVersion + loginTime)
  // ────────────────────────────────────────────────────────────────────────
  svOk = structKeyExists(session, "user")
      AND structKeyExists(session.user, "sessionVersion")
      AND isNumeric(session.user.sessionVersion);
  ltOk = structKeyExists(session, "user")
      AND structKeyExists(session.user, "loginTime");
  svStatus = (svOk AND ltOk) ? "pass" : (svOk OR ltOk ? "warn" : "fail");
  svDetail = "sessionVersion: " & (svOk ? session.user.sessionVersion : "MISSING")
           & " | loginTime: " & (ltOk ? session.user.loginTime : "MISSING");
  addTest("Session state (sessionVersion + loginTime)", svStatus, svDetail);

  // ────────────────────────────────────────────────────────────────────────
  // 8. MYUHCO_TOKEN cookie present and valid
  // ────────────────────────────────────────────────────────────────────────
  cookiePresent = structKeyExists(cookie, "MYUHCO_TOKEN") AND len(trim(cookie.MYUHCO_TOKEN));
  if (cookiePresent AND tsOk) {
    try {
      ckVerify = application.tokenService.verifyToken(cookie.MYUHCO_TOKEN);
      if (ckVerify.valid) {
        addTest(
          "MYUHCO_TOKEN cookie",
          "pass",
          "Present and valid. userID=" & ckVerify.payload.userID
            & ", sessionVersion=" & ckVerify.payload.sessionVersion
            & ", exp=" & ckVerify.payload.exp
        );
      } else {
        addTest(
          "MYUHCO_TOKEN cookie",
          "warn",
          "Present but verification failed: '" & ckVerify.reason & "'. Token TTL is 5 minutes — re-login to issue a fresh one."
        );
      }
    } catch (any e) {
      addTest("MYUHCO_TOKEN cookie", "fail", "Present but could not parse: " & e.message);
    }
  } else if (cookiePresent) {
    addTest("MYUHCO_TOKEN cookie", "warn", "Present (TokenService unavailable to verify payload).");
  } else {
    addTest(
      "MYUHCO_TOKEN cookie",
      "warn",
      "Not present. Cookie is issued at login and expires after 5 minutes. Log out and back in, then reload this page."
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 9. DB connectivity (UserSessionControl)
  // ────────────────────────────────────────────────────────────────────────
  if (dsOk) {
    try {
      dbQ = queryExecute(
        "SELECT COUNT(*) AS TotalRows FROM UserSessionControl",
        {},
        { datasource=application.myuhcoDatasource }
      );
      addTest(
        "DB connectivity (UserSessionControl)",
        "pass",
        "Query succeeded. Row count: " & dbQ.TotalRows
      );
    } catch (any e) {
      addTest("DB connectivity (UserSessionControl)", "fail", "Query failed: " & e.message & (len(e.detail) ? " | " & e.detail : ""));
    }
  } else {
    addTest("DB connectivity (UserSessionControl)", "skip", "Skipped — MYUHCO_DS not configured.");
  }

  // ────────────────────────────────────────────────────────────────────────
  // 10. Session currency (direct DB — same logic as /auth/status.cfm)
  // ────────────────────────────────────────────────────────────────────────
  sessionUserID  = (svOk ? int(val(session.user.userID)) : 0);
  loginEpochTest = 0;
  if (ltOk AND isDate(session.user.loginTime)) {
    loginEpochTest = int(dateDiff("s", createDateTime(1970,1,1,0,0,0), session.user.loginTime));
  }
  if (sessionUserID GT 0 AND loginEpochTest GT 0 AND dsOk) {
    try {
      qSC2 = queryExecute(
        "SELECT DATEDIFF(SECOND,'1970-01-01 00:00:00',ISNULL(LastLogout,'1970-01-01')) AS LogoutEpoch,
                DATEDIFF(SECOND,'1970-01-01 00:00:00',ISNULL(LastForcedLogout,'1970-01-01')) AS ForcedEpoch
         FROM UserSessionControl WHERE UserID = :uid",
        { uid = { value=sessionUserID, cfsqltype="cf_sql_integer" } },
        { datasource=application.myuhcoDatasource }
      );
      if (qSC2.recordCount EQ 0) {
        addTest("Session currency (UserSessionControl)", "warn",
          "No row for userID=#sessionUserID#. Row is created on login — log out and back in.");
      } else if (qSC2.LogoutEpoch GT loginEpochTest OR qSC2.ForcedEpoch GT loginEpochTest) {
        addTest("Session currency (UserSessionControl)", "fail",
          "Session invalidated: LogoutEpoch=#qSC2.LogoutEpoch#, ForcedEpoch=#qSC2.ForcedEpoch# > loginTime=#loginEpochTest#");
      } else {
        addTest("Session currency (UserSessionControl)", "pass",
          "Session is current for userID=#sessionUserID#. LogoutEpoch=#qSC2.LogoutEpoch#, ForcedEpoch=#qSC2.ForcedEpoch# (both < loginTime=#loginEpochTest#)");
      }
    } catch (any e) {
      addTest("Session currency (UserSessionControl)", "fail", "Query failed: " & e.message);
    }
  } else {
    addTest("Session currency (UserSessionControl)", "skip",
      "Skipped — " & (!dsOk ? "MYUHCO_DS not configured" : "userId or loginTime not available") & ".");
  }

  // ────────────────────────────────────────────────────────────────────────
  // 11. Token refresh (direct sign — same logic as /auth/refresh.cfm)
  // ────────────────────────────────────────────────────────────────────────
  if (sessionUserID GT 0 AND tsOk) {
    try {
      _rfPayload = application.tokenService.buildPayload(sessionUserID, int(val(session.user.sessionVersion)));
      _rfToken   = application.tokenService.signToken(_rfPayload);
      _rfVerify  = application.tokenService.verifyToken(_rfToken);
      addTest(
        "Token refresh (direct sign)",
        _rfVerify.valid ? "pass" : "fail",
        _rfVerify.valid
          ? "Fresh token signed and verified. userID=#sessionUserID#, sessionVersion=#_rfPayload.sessionVersion#, exp=#_rfPayload.exp#"
          : "Fresh token failed verify: " & _rfVerify.reason
      );
    } catch (any e) {
      addTest("Token refresh (direct sign)", "fail", e.message);
    }
  } else {
    addTest("Token refresh (direct sign)", "skip",
      "Skipped — " & (!tsOk ? "TokenService not initialized" : "userId not available") & ".");
  }

  // ── Summary counts ───────────────────────────────────────────────────────
  passCount = 0; failCount = 0; warnCount = 0; skipCount = 0;
  for (t in tests) {
    switch (t.status) {
      case "pass": passCount++; break;
      case "fail": failCount++; break;
      case "warn": warnCount++; break;
      case "skip": skipCount++; break;
    }
  }
  overallStatus = failCount GT 0 ? "danger" : (warnCount GT 0 ? "warning" : "success");
  overallLabel  = failCount GT 0 ? "FAILURES DETECTED" : (warnCount GT 0 ? "WARNINGS" : "ALL CHECKS PASSED");
</cfscript>

<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Token System Verification — MyUHCO</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="/assets/css/dist/myuhco/portal.css">
  <style>
    body { background: #f4f6f8; }
    .verify-wrap { max-width: 860px; margin: 2.5rem auto; padding: 0 1rem; }
    .status-badge { min-width: 52px; text-align: center; font-size: .75rem; padding: .3em .6em; }
    .test-detail  { font-size: .85rem; color: #555; margin-top: .2rem; word-break: break-word; }
    .session-block{ font-size: .8rem; font-family: monospace; background: #f8f9fa; border: 1px solid #dee2e6; border-radius: .375rem; padding: .75rem 1rem; }
  </style>
</head>
<body id="MyUHCO">
<div class="verify-wrap">

  <div class="d-flex align-items-center justify-content-between mb-3">
    <div>
      <h4 class="mb-0 fw-semibold">Token System Verification</h4>
      <small class="text-muted">STEP 2 — MyUHCO / <cfoutput>#cgi.server_name#</cfoutput></small>
    </div>
    <a href="index.cfm" class="btn btn-sm btn-outline-secondary">← Portal</a>
  </div>

  <cfoutput>
  <div class="alert alert-#overallStatus# d-flex align-items-center gap-2 mb-4" role="alert">
    <strong>#overallLabel#</strong>
    &nbsp;— #passCount# passed &nbsp;·&nbsp; #failCount# failed &nbsp;·&nbsp; #warnCount# warnings &nbsp;·&nbsp; #skipCount# skipped
  </div>
  </cfoutput>

  <!--- Test results list --->
  <div class="card shadow-sm border-0 mb-4">
    <div class="card-header fw-semibold bg-white border-bottom">Diagnostic Checks</div>
    <ul class="list-group list-group-flush">
      <cfoutput>
      <cfloop array="#tests#" index="t">
        <cfset badgeClass = t.status EQ "pass" ? "bg-success"
                          : t.status EQ "fail" ? "bg-danger"
                          : t.status EQ "warn" ? "bg-warning text-dark"
                          : "bg-secondary">
        <li class="list-group-item d-flex align-items-start gap-3 py-3">
          <span class="badge status-badge #badgeClass# mt-1">#uCase(t.status)#</span>
          <div>
            <div class="fw-medium">#encodeForHTML(t.name)#</div>
            <div class="test-detail">#encodeForHTML(t.detail)#</div>
          </div>
        </li>
      </cfloop>
      </cfoutput>
    </ul>
  </div>

  <!--- Session snapshot --->
  <div class="card shadow-sm border-0 mb-4">
    <div class="card-header fw-semibold bg-white border-bottom">Session Snapshot (session.user)</div>
    <div class="card-body">
      <cfif structKeyExists(session, "user")>
        <cfoutput>
        <div class="session-block">
          <cfloop collection="#session.user#" item="k">
            <cfset sv = session.user[k]>
            <!--- Suppress long API blobs --->
            <cfif NOT listFindNoCase("degrees,flags,organizations", k)>
              <div><strong>#encodeForHTML(k)#:</strong>
                #isSimpleValue(sv) ? encodeForHTML(left(sv & "", 200)) : "[complex]"#
              </div>
            </cfif>
          </cfloop>
        </div>
        </cfoutput>
      <cfelse>
        <p class="text-muted mb-0">session.user is not set.</p>
      </cfif>
    </div>
  </div>

  <!--- Environment config summary --->
  <div class="card shadow-sm border-0 mb-4">
    <div class="card-header fw-semibold bg-white border-bottom">Application Config</div>
    <div class="card-body">
      <cfoutput>
      <div class="session-block">
        <div><strong>tokenService:</strong>      #isObject(application.tokenService) ? "initialized" : "NOT initialized"#</div>
        <div><strong>myuhcoDatasource:</strong>  #len(trim(application.myuhcoDatasource)) ? encodeForHTML(application.myuhcoDatasource) : "(not set)"#</div>
        <div><strong>cookieDomain:</strong>      #len(trim(application.cookieDomain))     ? encodeForHTML(application.cookieDomain)     : "(not set)"#</div>
        <div><strong>MYUHCO_TOKEN cookie:</strong> #structKeyExists(cookie,"MYUHCO_TOKEN") AND len(trim(cookie.MYUHCO_TOKEN)) ? "present" : "not present"#</div>
      </div>
      </cfoutput>
    </div>
  </div>

  <p class="text-muted text-center" style="font-size:.8rem">
    This page requires an active portal session. Accessible to authenticated users only.<br>
    Reinit application: <a href="?reinit=true">?reinit=true</a>
  </p>

</div>
</body>
</html>
