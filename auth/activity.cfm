<cfsetting showdebugoutput="false">
<!---
  auth/activity.cfm ──────────────────────────────────────────────────────────
  STEP 6 — Session Tracking

  External modules call this endpoint on every protected-page load (throttled
  to once per 5 minutes client-side) to update LastActivity in
  UserSessionControl.

  Request:
    GET /auth/activity.cfm?userID=128
    Authorization: Bearer <API_TOKEN>
    X-API-Secret: <API_SECRET>

  Auth:
    Authorization bearer token + X-API-Secret must match the portal's
    configured MYUHCO_API_TOKEN and MYUHCO_API_SECRET. Same credentials
    external modules use for UHCO_Identity.

  Response:
    200  {"ok":true}
    400  {"error":"..."}   — missing/invalid parameters
    401  {"error":"..."}   — bad credentials
    503  {"error":"..."}   — datasource not configured
───────────────────────────────────────────────────────────────────────────────
--->

<cfcontent type="application/json; charset=utf-8">

<!--- ── Parameter intake ─────────────────────────────────────────────────── --->
<cfparam name="url.userID" default="">
<cfset requestHeaders = getHttpRequestData().headers>
<cfset authHeader = "">
<cfset secretHeader = "">
<cfset headerName = "">

<cfif structKeyExists(requestHeaders, "Authorization")>
  <cfset authHeader = trim(requestHeaders["Authorization"] & "")>
<cfelse>
  <cfloop collection="#requestHeaders#" item="headerName">
    <cfif compareNoCase(headerName, "Authorization") EQ 0>
      <cfset authHeader = trim(requestHeaders[headerName] & "")>
      <cfbreak>
    </cfif>
  </cfloop>
</cfif>

<cfif structKeyExists(requestHeaders, "X-API-Secret")>
  <cfset secretHeader = trim(requestHeaders["X-API-Secret"] & "")>
<cfelse>
  <cfloop collection="#requestHeaders#" item="headerName">
    <cfif compareNoCase(headerName, "X-API-Secret") EQ 0>
      <cfset secretHeader = trim(requestHeaders[headerName] & "")>
      <cfbreak>
    </cfif>
  </cfloop>
</cfif>

<cfif NOT (len(trim(url.userID)) AND len(authHeader) AND len(secretHeader))>
  <cfheader statuscode="400">
  <cfoutput>{"error":"Missing required inputs: userID, Authorization header, X-API-Secret header"}</cfoutput>
  <cfabort>
</cfif>

<cfif NOT isNumeric(url.userID) OR int(val(url.userID)) LTE 0>
  <cfheader statuscode="400">
  <cfoutput>{"error":"Invalid userID"}</cfoutput>
  <cfabort>
</cfif>

<!--- ── Credential validation ────────────────────────────────────────────── --->
<cfset var storedToken  = structKeyExists(application, "MYUHCO_API_TOKEN")  ? application.MYUHCO_API_TOKEN  : "">
<cfset var storedSecret = structKeyExists(application, "MYUHCO_API_SECRET") ? application.MYUHCO_API_SECRET : "">

<cfif NOT len(storedToken) OR NOT len(storedSecret)>
  <cfheader statuscode="503">
  <cfoutput>{"error":"API credentials not configured on portal"}</cfoutput>
  <cfabort>
</cfif>

<cfif NOT reFindNoCase("^Bearer\s+", authHeader)>
  <cfheader statuscode="401">
  <cfoutput>{"error":"Invalid Authorization header"}</cfoutput>
  <cfabort>
</cfif>

<cfset authToken = reReplaceNoCase(authHeader, "^Bearer\s+", "", "one")>

<cfif trim(authToken) NEQ storedToken OR trim(secretHeader) NEQ storedSecret>
  <cfheader statuscode="401">
  <cfoutput>{"error":"Invalid credentials"}</cfoutput>
  <cfabort>
</cfif>

<!--- ── Datasource check ─────────────────────────────────────────────────── --->
<cfif NOT (structKeyExists(application, "myuhcoDatasource") AND len(trim(application.myuhcoDatasource)))>
  <cfheader statuscode="503">
  <cfoutput>{"error":"Datasource not configured"}</cfoutput>
  <cfabort>
</cfif>

<!--- ── Update LastActivity ──────────────────────────────────────────────── --->
<cfset var activityUserID = int(val(url.userID))>

<cftry>
  <cfquery datasource="#application.myuhcoDatasource#">
    UPDATE dbo.UserSessionControl
    SET LastActivity = GETDATE(),
        UpdatedAt    = GETDATE()
    WHERE UserID = <cfqueryparam value="#activityUserID#" cfsqltype="cf_sql_integer">
  </cfquery>

  <cfoutput>{"ok":true}</cfoutput>

  <cfcatch type="any">
    <cflog file="myuhco-session" type="error"
      text="auth/activity.cfm DB error for userID #activityUserID#: #cfcatch.message#">
    <cfheader statuscode="500">
    <cfoutput>{"error":"Database error"}</cfoutput>
  </cfcatch>
</cftry>
