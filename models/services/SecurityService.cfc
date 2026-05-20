<cfcomponent displayname="SecurityService" output="false">
<!---
  SecurityService.cfc - STEP 7 Security Layer
  Rate limiting (AuthRateLimit) and audit logging (AuthAuditLog).
  All public methods fail silently -- security writes never interrupt page delivery.
--->

  <cfset variables.MAX_ATTEMPTS  = 5>
  <cfset variables.BLOCK_MINUTES = 15>

  <!--- init --->
  <cffunction name="init" access="public" returntype="SecurityService" output="false">
    <cfreturn this>
  </cffunction>

  <!---
    checkRateLimit
    Returns {blocked:false} or {blocked:true, retryAfterSeconds:N, message:"..."}
  --->
  <cffunction name="checkRateLimit" access="public" returntype="struct" output="false">
    <cfargument name="identifier"     type="string" required="true">
    <cfargument name="identifierType" type="string" required="true">

    <cfset var result   = structNew()>
    <cfset var qCheck   = "">
    <cfset var secsLeft = 0>
    <cfset var blockedUntilDate = "">
    <cfset result.blocked = false>

    <cfif NOT _dsReady()>
      <cfreturn result>
    </cfif>

    <cftry>
      <cfquery name="qCheck" datasource="#application.myuhcoDatasource#">
        SELECT AttemptCount, BlockedUntil
          FROM dbo.AuthRateLimit
         WHERE Identifier     = <cfqueryparam value="#left(trim(arguments.identifier),100)#"      cfsqltype="cf_sql_varchar">
           AND IdentifierType = <cfqueryparam value="#left(trim(arguments.identifierType),20)#"  cfsqltype="cf_sql_varchar">
      </cfquery>

      <cfif qCheck.recordCount EQ 0>
        <cfreturn result>
      </cfif>

      <cfif len(trim(qCheck.BlockedUntil & "")) GT 0>
        <cfset blockedUntilDate = qCheck.BlockedUntil>
        <cfif isDate(blockedUntilDate) AND blockedUntilDate GT now()>
          <cfset secsLeft = max(1, int(dateDiff("s", now(), blockedUntilDate)))>
          <cfset result.blocked           = true>
          <cfset result.retryAfterSeconds = secsLeft>
          <cfset result.message           = "Too many failed attempts. Try again in #int(ceiling(secsLeft / 60))# minute(s).">
          <cfreturn result>
        </cfif>
      </cfif>

      <cfcatch type="any">
        <cflog file="myuhco-security" type="error"
          text="SecurityService.checkRateLimit error for #arguments.identifier#: #cfcatch.message#">
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <!---
    recordFailedAttempt
    Increments attempt counter. Sets BlockedUntil after MAX_ATTEMPTS failures.
  --->
  <cffunction name="recordFailedAttempt" access="public" returntype="void" output="false">
    <cfargument name="identifier"     type="string" required="true">
    <cfargument name="identifierType" type="string" required="true">

    <cfif NOT _dsReady()>
      <cfreturn>
    </cfif>

    <cftry>
      <cfquery datasource="#application.myuhcoDatasource#">
        MERGE INTO dbo.AuthRateLimit AS target
        USING (VALUES (
            <cfqueryparam value="#left(trim(arguments.identifier),100)#"      cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#left(trim(arguments.identifierType),20)#"  cfsqltype="cf_sql_varchar">
        )) AS source (Identifier, IdentifierType)
        ON (target.Identifier = source.Identifier AND target.IdentifierType = source.IdentifierType)
        WHEN MATCHED THEN
            UPDATE SET
                AttemptCount = target.AttemptCount + 1,
                LastAttempt  = GETDATE(),
                BlockedUntil = CASE
                    WHEN (target.AttemptCount + 1) >= <cfqueryparam value="#variables.MAX_ATTEMPTS#"  cfsqltype="cf_sql_integer">
                    THEN DATEADD(MINUTE, <cfqueryparam value="#variables.BLOCK_MINUTES#" cfsqltype="cf_sql_integer">, GETDATE())
                    ELSE target.BlockedUntil
                END
        WHEN NOT MATCHED THEN
            INSERT (Identifier, IdentifierType, AttemptCount, FirstAttempt, LastAttempt)
            VALUES (
                <cfqueryparam value="#left(trim(arguments.identifier),100)#"      cfsqltype="cf_sql_varchar">,
                <cfqueryparam value="#left(trim(arguments.identifierType),20)#"  cfsqltype="cf_sql_varchar">,
                1, GETDATE(), GETDATE()
            );
      </cfquery>
      <cfcatch type="any">
        <cflog file="myuhco-security" type="error"
          text="SecurityService.recordFailedAttempt error for #arguments.identifier#: #cfcatch.message#">
      </cfcatch>
    </cftry>
  </cffunction>

  <!---
    resetRateLimit
    Deletes the rate-limit row on successful login.
  --->
  <cffunction name="resetRateLimit" access="public" returntype="void" output="false">
    <cfargument name="identifier"     type="string" required="true">
    <cfargument name="identifierType" type="string" required="true">

    <cfif NOT _dsReady()>
      <cfreturn>
    </cfif>

    <cftry>
      <cfquery datasource="#application.myuhcoDatasource#">
        DELETE FROM dbo.AuthRateLimit
         WHERE Identifier     = <cfqueryparam value="#left(trim(arguments.identifier),100)#"      cfsqltype="cf_sql_varchar">
           AND IdentifierType = <cfqueryparam value="#left(trim(arguments.identifierType),20)#"  cfsqltype="cf_sql_varchar">
      </cfquery>
      <cfcatch type="any">
        <cflog file="myuhco-security" type="error"
          text="SecurityService.resetRateLimit error for #arguments.identifier#: #cfcatch.message#">
      </cfcatch>
    </cftry>
  </cffunction>

  <!---
    auditLog
    Inserts one row into dbo.AuthAuditLog. Never throws.
    eventType CHECK constraint values:
      LOGIN | LOGOUT | FORCE_LOGOUT | TOKEN_LOGIN | SESSION_REFRESH
      ACCESS_DENIED | LOGIN_FAILED | RATE_LIMITED
  --->
  <cffunction name="auditLog" access="public" returntype="void" output="false">
    <cfargument name="eventType" type="string" required="true">
    <cfargument name="userID"    type="string" required="false" default="">
    <cfargument name="ipAddress" type="string" required="false" default="">
    <cfargument name="userAgent" type="string" required="false" default="">
    <cfargument name="details"   type="string" required="false" default="">

    <cfset var hasUserID     = isNumeric(arguments.userID) AND val(arguments.userID) GT 0>
    <cfset var safeEventType = uCase(trim(arguments.eventType))>
    <cfset var safeIP        = left(trim(arguments.ipAddress & ""), 50)>
    <cfset var safeUA        = left(trim(arguments.userAgent & ""), 500)>
    <cfset var safeDetails   = left(trim(arguments.details   & ""), 4000)>

    <cfif NOT _dsReady()>
      <cfreturn>
    </cfif>

    <cftry>
      <cfif hasUserID>
        <cfquery datasource="#application.myuhcoDatasource#">
          INSERT INTO dbo.AuthAuditLog (UserID, EventType, IPAddress, UserAgent, Details)
          VALUES (
            <cfqueryparam value="#int(val(arguments.userID))#" cfsqltype="cf_sql_integer">,
            <cfqueryparam value="#safeEventType#"              cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#safeIP#"                     cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#safeUA#"                     cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#safeDetails#"                cfsqltype="cf_sql_nvarchar">
          )
        </cfquery>
      <cfelse>
        <cfquery datasource="#application.myuhcoDatasource#">
          INSERT INTO dbo.AuthAuditLog (EventType, IPAddress, UserAgent, Details)
          VALUES (
            <cfqueryparam value="#safeEventType#" cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#safeIP#"        cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#safeUA#"        cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#safeDetails#"   cfsqltype="cf_sql_nvarchar">
          )
        </cfquery>
      </cfif>
      <cfcatch type="any">
        <cflog file="myuhco-security" type="error"
          text="SecurityService.auditLog failed (eventType=#arguments.eventType#): #cfcatch.message#">
      </cfcatch>
    </cftry>

    <!--- STEP 8: Best-effort WebSocket publish to securityEvents channel --->
    <cftry>
      <cfset var _wsPayload = structNew()>
      <cfset _wsPayload.type      = safeEventType>
      <cfset _wsPayload.userID    = (hasUserID) ? int(val(arguments.userID)) : 0>
      <cfset _wsPayload.timestamp = dateTimeFormat(now(), "yyyy-mm-dd'T'HH:nn:ss'Z'")>
      <cfset _wsPayload.source    = "myuhco">
      <cfset _wsPayload.ip        = safeIP>
      <cfset _wsPayload.details   = safeDetails>
      <cfset wsPublish("securityEvents", serializeJSON(_wsPayload))>
      <cfcatch type="any">
        <!--- WebSocket publish is best-effort; swallow silently --->
      </cfcatch>
    </cftry>
  </cffunction>

  <!--- _dsReady - internal guard. Returns true only if datasource is configured. --->
  <cffunction name="_dsReady" access="private" returntype="boolean" output="false">
    <cfif NOT structKeyExists(application, "myuhcoDatasource")>
      <cfreturn false>
    </cfif>
    <cfif NOT isSimpleValue(application.myuhcoDatasource)>
      <cfreturn false>
    </cfif>
    <cfif NOT len(trim(application.myuhcoDatasource)) GT 0>
      <cfreturn false>
    </cfif>
    <cfreturn true>
  </cffunction>

</cfcomponent>
