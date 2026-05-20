<cfsetting showdebugoutput="false">
<!---
  auth/redirect.cfm ──────────────────────────────────────────────────────────
  Type 4 external module SSO handoff.

  Requires an authenticated portal session. Generates a short-lived (2-minute)
  redirect token and sends the browser to the external module's /login endpoint
  with ?token= appended.

  Usage:
    /auth/redirect.cfm?to=http://localhost:3001/login
    /auth/redirect.cfm?to=http://localhost:5001/login

  Security:
    - Portal session required (auth gate enforced below).
    - Target URL must match an allowed host prefix.
    - Token is signed HMAC-SHA256 and expires in 120 seconds.
    - External module must validate and then redirect to a clean URL.
      The token must never be stored or re-used.

  Allowed hosts (extend for production registered modules):
    http://localhost:     http://127.0.0.1:
    https://localhost:    https://127.0.0.1:
───────────────────────────────────────────────────────────────────────────────
--->

<!--- ── Auth gate ────────────────────────────────────────────────────────── --->
<cfif NOT (
    structKeyExists(session, "user")
    AND structKeyExists(session.user, "userID")
    AND isNumeric(session.user.userID)
    AND session.user.userID GT 0
)>
  <cfheader statuscode="401">
  <cfcontent type="application/json; charset=utf-8">
  <cfoutput>{"error":"Authentication required"}</cfoutput>
  <cfabort>
</cfif>

<!--- ── Validate 'to' parameter ──────────────────────────────────────────── --->
<cfparam name="url.to" default="">
<cfif NOT len(trim(url.to))>
  <cfheader statuscode="400">
  <cfcontent type="application/json; charset=utf-8">
  <cfoutput>{"error":"Missing required parameter: to"}</cfoutput>
  <cfabort>
</cfif>

<!--- ── Allowed redirect target prefixes ─────────────────────────────────── --->
<cfset allowedPrefixes = [
  "http://localhost:",
  "https://localhost:",
  "http://127.0.0.1:",
  "https://127.0.0.1:"
]>
<cfset targetOk = false>
<cfloop array="#allowedPrefixes#" index="pfx">
  <cfif left(url.to, len(pfx)) EQ pfx>
    <cfset targetOk = true>
    <cfbreak>
  </cfif>
</cfloop>

<cfif NOT targetOk>
  <cfheader statuscode="403">
  <cfcontent type="application/json; charset=utf-8">
  <cfoutput>{"error":"Redirect target not permitted"}</cfoutput>
  <cfabort>
</cfif>

<!--- ── TokenService availability check ─────────────────────────────────── --->
<cfif NOT (structKeyExists(application, "tokenService") AND isObject(application.tokenService))>
  <cfheader statuscode="503">
  <cfcontent type="application/json; charset=utf-8">
  <cfoutput>{"error":"TokenService not available — reinit application"}</cfoutput>
  <cfabort>
</cfif>

<!--- ── Generate redirect token and redirect ─────────────────────────────── --->
<cftry>
  <cfset redirectPayload = application.tokenService.buildRedirectPayload(
    int(val(session.user.userID))
  )>
  <cfset redirectToken = application.tokenService.signToken(redirectPayload)>

  <!--- ── STEP 6: Record external module session in UserSessions ──────────── --->
  <cfif structKeyExists(application, "myuhcoDatasource") AND len(trim(application.myuhcoDatasource))>
    <cftry>
      <cfset sessionUserID = int(val(session.user.userID))>
      <cfset currentSessionID = trim(session.sessionid & "")>
      <cfset sessionIP     = left(trim(cgi.remote_addr & ""), 50)>
      <cfset sessionUA     = left(trim(cgi.http_user_agent & ""), 500)>
      <cfset lastVisitedPath = left(trim(cgi.script_name & (len(trim(cgi.query_string & "")) ? "?" & trim(cgi.query_string & "") : "")), 500)>

      <!--- Ensure UserSessionControl row exists before inserting child row --->
      <cfquery datasource="#application.myuhcoDatasource#">
        IF NOT EXISTS (
          SELECT 1 FROM dbo.UserSessionControl WHERE UserID = <cfqueryparam value="#sessionUserID#" cfsqltype="cf_sql_integer">
        )
        BEGIN
          INSERT INTO dbo.UserSessionControl (UserID)
          VALUES (<cfqueryparam value="#sessionUserID#" cfsqltype="cf_sql_integer">)
        END
      </cfquery>

      <cfquery datasource="#application.myuhcoDatasource#">
        INSERT INTO dbo.UserSessions (UserID, SessionID, IPAddress, UserAgent, LastVisitedPath, IsActive)
        VALUES (
          <cfqueryparam value="#sessionUserID#"  cfsqltype="cf_sql_integer">,
          <cfqueryparam value="#currentSessionID#" cfsqltype="cf_sql_varchar">,
          <cfqueryparam value="#sessionIP#"      cfsqltype="cf_sql_varchar">,
          <cfqueryparam value="#sessionUA#"      cfsqltype="cf_sql_varchar">,
          <cfqueryparam value="#lastVisitedPath#" cfsqltype="cf_sql_varchar">,
          1
        )
      </cfquery>
      <cfcatch type="any">
        <cflog file="myuhco-session" type="error"
          text="auth/redirect.cfm: UserSessions insert failed for userID #sessionUserID#: #cfcatch.message#">
      </cfcatch>
    </cftry>
  </cfif>

  <!--- STEP 7: Audit TOKEN_LOGIN event --------------------------------------- --->
  <cfif isObject(application.securityService)>
    <cfset _tl_details = "to=" & left(trim(url.to & ""), 500)>
    <cfset application.securityService.auditLog(
      eventType = "TOKEN_LOGIN",
      userID    = sessionUserID,
      ipAddress = left(trim(cgi.remote_addr & ""), 50),
      userAgent = left(trim(cgi.http_user_agent & ""), 500),
      details   = _tl_details
    )>
  </cfif>

  <cfset separator = (find("?", url.to) GT 0) ? "&" : "?">
  <cfset targetUrl  = url.to & separator & "token=" & urlEncodedFormat(redirectToken)>

  <cflocation url="#targetUrl#" addtoken="false">

  <cfcatch type="any">
    <cflog file="myuhco-token" type="error"
      text="auth/redirect.cfm failed for userID #session.user.userID#: #cfcatch.message#">
    <cfheader statuscode="500">
    <cfcontent type="application/json; charset=utf-8">
    <cfoutput>{"error":"Token generation failed"}</cfoutput>
    <cfabort>
  </cfcatch>
</cftry>
