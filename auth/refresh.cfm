<cfsetting showdebugoutput="false">
<cfheader name="Content-Type" value="application/json">
<cfheader name="Cache-Control" value="no-store">

<!---
  /auth/refresh.cfm
  Issues a fresh MYUHCO_TOKEN for the currently authenticated CF session.
  Called by external modules (Type 4) when their token has expired but the
  user's CF portal session is still active.

  The caller must forward the user's CF session cookies (CFID/CFToken or
  the session cookie) in order for the session check to pass.

  Returns JSON:
    { "success": true,  "token": "<JWT>" }
    { "success": false, "reason": "..." }  (with appropriate HTTP status code)
--->

<!--- Require active CF session --->
<cfif NOT structKeyExists(session, "portalUser")>
  <cfheader statuscode="401">
  <cfoutput>#serializeJSON({ success = false, reason = "Not authenticated" })#</cfoutput>
  <cfabort>
</cfif>

<!--- Require TokenService to be initialized --->
<cfif NOT isObject(application.tokenService)>
  <cfheader statuscode="503">
  <cfoutput>#serializeJSON({ success = false, reason = "Token service unavailable" })#</cfoutput>
  <cfabort>
</cfif>

<cfset _refreshUserID = int(val(session.user.userID))>
<cfset _refreshSV     = int(val(session.user.sessionVersion))>

<cfif NOT _refreshUserID>
  <cfheader statuscode="400">
  <cfoutput>#serializeJSON({ success = false, reason = "Invalid session state: userID missing" })#</cfoutput>
  <cfabort>
</cfif>

<cftry>
  <cfset _refreshPayload = application.tokenService.buildPayload(_refreshUserID, _refreshSV)>
  <cfset _refreshToken   = application.tokenService.signToken(_refreshPayload)>

  <!--- Re-issue the cookie alongside the JSON response --->
  <cfset _cookieDomainOk = structKeyExists(application, "cookieDomain") AND len(application.cookieDomain) AND right(cgi.server_name, len(application.cookieDomain)-1) EQ right(application.cookieDomain, len(application.cookieDomain)-1)>
  <cfset _cookieSecure   = (cgi.https EQ "on")>
  <cfif _cookieDomainOk>
    <cfcookie name="MYUHCO_TOKEN" value="#_refreshToken#" path="/" httponly="true" secure="#_cookieSecure#" domain="#application.cookieDomain#">
  <cfelse>
    <cfcookie name="MYUHCO_TOKEN" value="#_refreshToken#" httponly="true" secure="#_cookieSecure#">
  </cfif>

  <cfoutput>#serializeJSON({ success = true, token = _refreshToken })#</cfoutput>

  <cfcatch type="any">
    <cflog file="myuhco-token" type="error"
      text="auth/refresh.cfm failed for userID #_refreshUserID#: #cfcatch.message#">
    <cfheader statuscode="500">
    <cfoutput>#serializeJSON({ success = false, reason = "Token generation failed" })#</cfoutput>
  </cfcatch>
</cftry>
