<cfsetting showdebugoutput="false">
<cfheader name="Content-Type" value="application/json">
<cfheader name="Cache-Control" value="no-store">

<!---
  /auth/status.cfm
  Called by external modules (Type 4) to determine whether a user's session
  is still valid (i.e., they have not been logged out or force-logged out
  since the external session was created).

  Required URL parameters:
    userID    (INT)   — canonical identity key
    loginTime (INT)   — Unix epoch seconds when the external session was established
                        (stored from the token's "iat" field at session creation)

  Returns JSON:
    { "valid": true }   — session is still active
    { "valid": false }  — session has been invalidated; external module must log out

  NOTE: Timestamp comparisons use DATEDIFF(SECOND,'1970-01-01',datetime) in SQL Server.
        This is accurate when the SQL Server instance stores datetimes in UTC.
        Verify SQL Server timezone before deploying.
--->

<cfparam name="url.userID"    default="0">
<cfparam name="url.loginTime" default="0">

<cfset userID     = int(val(url.userID))>
<cfset loginEpoch = int(val(url.loginTime))>

<!--- Validate required parameters --->
<cfif NOT userID OR NOT loginEpoch>
  <cfheader statuscode="400">
  <cfoutput>#serializeJSON({ valid = false, reason = "Missing required parameters: userID, loginTime" })#</cfoutput>
  <cfabort>
</cfif>

<!--- DB not configured — cannot validate against logout records --->
<cfif NOT structKeyExists(application, "myuhcoDatasource") OR NOT len(trim(application.myuhcoDatasource))>
  <cfoutput>#serializeJSON({ valid = true })#</cfoutput>
  <cfabort>
</cfif>

<cftry>
  <cfquery name="qSC" datasource="#application.myuhcoDatasource#">
    SELECT
      DATEDIFF(SECOND, '1970-01-01 00:00:00', ISNULL(LastLogout,       '1970-01-01')) AS LogoutEpoch,
      DATEDIFF(SECOND, '1970-01-01 00:00:00', ISNULL(LastForcedLogout, '1970-01-01')) AS ForcedEpoch
    FROM UserSessionControl
    WHERE UserID = <cfqueryparam value="#userID#" cfsqltype="cf_sql_integer">
  </cfquery>

  <!--- No row — user has never been explicitly logged out --->
  <cfif qSC.recordCount EQ 0>
    <cfoutput>#serializeJSON({ valid = true })#</cfoutput>
    <cfabort>
  </cfif>

  <!--- Invalidate if any logout timestamp is more recent than the external session start --->
  <cfif qSC.LogoutEpoch GT loginEpoch OR qSC.ForcedEpoch GT loginEpoch>
    <cfoutput>#serializeJSON({ valid = false })#</cfoutput>
  <cfelse>
    <cfoutput>#serializeJSON({ valid = true })#</cfoutput>
  </cfif>

  <cfcatch type="any">
    <cflog file="myuhco-session" type="error"
      text="auth/status.cfm DB error for userID #userID#: #cfcatch.message# | #cfcatch.detail#">
    <!--- Fail open on infrastructure error — do not lock out users over a DB blip --->
    <cfoutput>#serializeJSON({ valid = true })#</cfoutput>
  </cfcatch>
</cftry>
