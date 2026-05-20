<!---
  admin/force-logout-reinit.cfm
  POST only. Accepts targetUserID form field.
  Forces logout, marks the target user for a one-time app reinit on next request,
  and returns JSON: {"success":true} or {"error":"..."}
--->
<cfsetting showdebugoutput="false">
<cfheader name="Content-Type" value="application/json; charset=utf-8">

<cfif cgi.request_method NEQ "POST">
  <cfheader statuscode="405">
  <cfoutput>{"error":"Method not allowed"}</cfoutput>
  <cfabort>
</cfif>

<cfif NOT structKeyExists(session, "user")>
  <cfheader statuscode="401">
  <cfoutput>{"error":"Unauthorized"}</cfoutput>
  <cfabort>
</cfif>

<cfif NOT application.accessService.hasPermission("portal.admin")>
  <cfheader statuscode="403">
  <cfoutput>{"error":"Forbidden"}</cfoutput>
  <cfabort>
</cfif>

<cfparam name="form.targetUserID" default="0">
<cfset targetUserID = int(val(form.targetUserID))>
<cfif targetUserID LTE 0>
  <cfheader statuscode="400">
  <cfoutput>{"error":"Invalid userID"}</cfoutput>
  <cfabort>
</cfif>

<cfif structKeyExists(session.user, "userID") AND int(val(session.user.userID)) EQ targetUserID>
  <cfheader statuscode="400">
  <cfoutput>{"error":"Cannot force-logout your own session via this endpoint. Use /logout.cfm."}</cfoutput>
  <cfabort>
</cfif>

<cftry>
  <cfquery datasource="#application.myuhcoDatasource#">
    IF NOT EXISTS (
      SELECT 1 FROM dbo.UserSessionControl
      WHERE UserID = <cfqueryparam value="#targetUserID#" cfsqltype="cf_sql_integer">
    )
    BEGIN
      INSERT INTO dbo.UserSessionControl (UserID)
      VALUES (<cfqueryparam value="#targetUserID#" cfsqltype="cf_sql_integer">)
    END
  </cfquery>

  <cfquery datasource="#application.myuhcoDatasource#">
    UPDATE dbo.UserSessionControl
    SET LastForcedLogout = GETDATE(),
        SessionVersion   = SessionVersion + 1,
        RequireReinit    = 1,
        UpdatedAt        = GETDATE()
    WHERE UserID = <cfqueryparam value="#targetUserID#" cfsqltype="cf_sql_integer">
  </cfquery>

  <cfquery datasource="#application.myuhcoDatasource#">
    UPDATE dbo.UserSessions
    SET IsActive   = 0,
        LogoutTime = GETDATE(),
        UpdatedAt  = GETDATE()
    WHERE UserID   = <cfqueryparam value="#targetUserID#" cfsqltype="cf_sql_integer">
      AND IsActive = 1
  </cfquery>

  <cfif isObject(application.securityService)>
    <cfset application.securityService.auditLog(
      eventType = "FORCE_LOGOUT",
      userID    = session.user.userID,
      ipAddress = left(trim(cgi.remote_addr & ""), 50),
      userAgent = left(trim(cgi.http_user_agent & ""), 500),
      details   = "targetUserID=#targetUserID# reinit=true"
    )>
  </cfif>

  <cfoutput>{"success":true}</cfoutput>

  <cfcatch type="any">
    <cflog file="myuhco-security" type="error"
      text="force-logout-reinit.cfm error for targetUserID=#targetUserID#: #cfcatch.message#">
    <cfheader statuscode="500">
    <cfoutput>{"error":"Server error"}</cfoutput>
  </cfcatch>
</cftry>