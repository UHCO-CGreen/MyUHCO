<cfsetting showdebugoutput="false">
<cfparam name="form.username" default="">
<cfparam name="form.password" default="">
<cfparam name="form.ajaxStep" default="">

<cfset isAjax = len(trim(form.ajaxStep)) GT 0>
<cfset username = trim(form.username)>
<cfset response = { success = false, message = "", redirect = "" }>

<cfif isAjax>
  <cfheader name="Content-Type" value="application/json; charset=utf-8">
</cfif>

<cfif form.ajaxStep EQ "auth" AND (NOT len(username) OR NOT len(trim(form.password)))>
  <cfset response.message = "Please enter your username and password.">
  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cfif form.ajaxStep EQ "auth">
  <!--- STEP 7: Rate-limit check by IP before attempting authentication --------->
  <cfset _rl_ip = left(trim(cgi.remote_addr & ""), 100)>
  <cfset _rl_ua = left(trim(cgi.http_user_agent & ""), 500)>
  <cfif isObject(application.securityService)>
    <cfset _rl_check = application.securityService.checkRateLimit(_rl_ip, "IP")>
    <cfif _rl_check.blocked>
      <cfset application.securityService.auditLog(
        eventType = "RATE_LIMITED",
        ipAddress = _rl_ip,
        userAgent = _rl_ua,
        details   = "username=#username#"
      )>
      <cfset response.message = _rl_check.message>
      <cfheader statuscode="429">
      <cfoutput>#serializeJSON(response)#</cfoutput>
      <cfabort>
    </cfif>
  </cfif>

  <cfset authResult = application.portalAuthService.authenticateCredentials(
    username = username,
    password = form.password
  )>

  <cfif authResult.success>
    <!--- STEP 7: Reset rate-limit row (LOGIN audit fires in profile step with correct UHCO_Identity userId) --->
    <cfif isObject(application.securityService)>
      <cfset application.securityService.resetRateLimit(_rl_ip, "IP")>
    </cfif>
    <cfset session.pendingPortalUser = duplicate(authResult.user)>
    <cfset response.success = true>
    <cfset response.message = "Authenticated">
    <cfset response.displayName = authResult.user.displayName>
  <cfelse>
    <!--- STEP 7: Record failed attempt and audit login failure ----------------->
    <cfif isObject(application.securityService)>
      <cfset application.securityService.recordFailedAttempt(_rl_ip, "IP")>
      <cfset application.securityService.auditLog(
        eventType = "LOGIN_FAILED",
        ipAddress = _rl_ip,
        userAgent = _rl_ua,
        details   = "username=#username# reason=#authResult.message#"
      )>
    </cfif>
    <cfset response.message = authResult.message>
  </cfif>

  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cfif form.ajaxStep EQ "profile">
  <cfif NOT structKeyExists(session, "pendingPortalUser")>
    <cfset response.message = "Authentication session expired. Please sign in again.">
    <cfoutput>#serializeJSON(response)#</cfoutput>
    <cfabort>
  </cfif>

  <cfset profileUser = application.portalAuthService.loadUserProfile(session.pendingPortalUser)>
  <cfset application.portalAuthService.createSession(profileUser)>
  <cfset structDelete(session, "pendingPortalUser")>

  <!--- STEP 7: Audit LOGIN with UHCO_Identity userId (available after createSession) --->
  <cfif isObject(application.securityService) AND structKeyExists(session, "user") AND structKeyExists(session.user, "userID")>
    <cfset application.securityService.auditLog(
      eventType = "LOGIN",
      userID    = session.user.userID,
      ipAddress = left(trim(cgi.remote_addr & ""), 50),
      userAgent = left(trim(cgi.http_user_agent & ""), 500),
      details   = "username=#session.user.username#"
    )>
  </cfif>

  <!--- Issue MYUHCO_TOKEN cookie for external module SSO --->  
  <cfif isObject(application.tokenService)>
    <cfset _ssoUserID = int(val(session.user.userID))>
    <cfset _ssoSV = int(val(session.user.sessionVersion))>
    <cfif _ssoUserID GT 0>
      <cftry>
        <cfset _ssoPayload = application.tokenService.buildPayload(_ssoUserID, _ssoSV)>
        <cfset _ssoToken = application.tokenService.signToken(_ssoPayload)>
        <cfset _cookieDomainOk = len(application.cookieDomain) AND right(cgi.server_name, len(application.cookieDomain)-1) EQ right(application.cookieDomain, len(application.cookieDomain)-1)>
        <cfset _cookieSecure   = (cgi.https EQ "on")>
        <cfif _cookieDomainOk>
          <cfcookie name="MYUHCO_TOKEN" value="#_ssoToken#" path="/" httponly="true" secure="#_cookieSecure#" domain="#application.cookieDomain#">
        <cfelse>
          <cfcookie name="MYUHCO_TOKEN" value="#_ssoToken#" httponly="true" secure="#_cookieSecure#">
        </cfif>
        <cfcatch type="any">
          <cflog file="myuhco-token" type="error" text="Token issuance failed at login for userID #_ssoUserID#: #cfcatch.message#">
        </cfcatch>
      </cftry>
    </cfif>
  </cfif>

  <cfset response.success = true>
  <cfset response.message = "Profile loaded">
  <cfset response.redirect = "index.cfm">
  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cfif NOT len(username) OR NOT len(trim(form.password))>
  <cflocation url="login.cfm?error=Please+enter+your+username+and+password." addtoken="false">
</cfif>

<!--- STEP 7: Rate-limit check by IP (non-AJAX path) ------------------------->
<cfset _rl_ip = left(trim(cgi.remote_addr & ""), 100)>
<cfset _rl_ua = left(trim(cgi.http_user_agent & ""), 500)>
<cfif isObject(application.securityService)>
  <cfset _rl_check = application.securityService.checkRateLimit(_rl_ip, "IP")>
  <cfif _rl_check.blocked>
    <cfset application.securityService.auditLog(
      eventType = "RATE_LIMITED",
      ipAddress = _rl_ip,
      userAgent = _rl_ua,
      details   = "Username attempted: #htmlEditFormat(username)#"
    )>
    <cflocation url="login.cfm?error=#urlEncodedFormat(_rl_check.message)#" addtoken="false">
  </cfif>
</cfif>

<cfset authResult = application.portalAuthService.authenticateCredentials(
  username = username,
  password = form.password
)>

<cfif authResult.success>
  <cfset profileUser = application.portalAuthService.loadUserProfile(authResult.user)>
  <cfset application.portalAuthService.createSession(profileUser)>

  <!--- Issue MYUHCO_TOKEN cookie for external module SSO --->
  <cfif isObject(application.tokenService)>
    <cfset _ssoUserID = int(val(session.user.userID))>
    <cfset _ssoSV = int(val(session.user.sessionVersion))>
    <cfif _ssoUserID GT 0>
      <cftry>
        <cfset _ssoPayload = application.tokenService.buildPayload(_ssoUserID, _ssoSV)>
        <cfset _ssoToken = application.tokenService.signToken(_ssoPayload)>
        <cfset _cookieDomainOk = len(application.cookieDomain) AND right(cgi.server_name, len(application.cookieDomain)-1) EQ right(application.cookieDomain, len(application.cookieDomain)-1)>
        <cfset _cookieSecure   = (cgi.https EQ "on")>
        <cfif _cookieDomainOk>
          <cfcookie name="MYUHCO_TOKEN" value="#_ssoToken#" path="/" httponly="true" secure="#_cookieSecure#" domain="#application.cookieDomain#">
        <cfelse>
          <cfcookie name="MYUHCO_TOKEN" value="#_ssoToken#" httponly="true" secure="#_cookieSecure#">
        </cfif>
        <cfcatch type="any">
          <cflog file="myuhco-token" type="error" text="Token issuance failed at login for userID #_ssoUserID#: #cfcatch.message#">
        </cfcatch>
      </cftry>
    </cfif>
  </cfif>

  <!--- STEP 7: Reset rate-limit row and audit successful login (non-AJAX path) --->
  <cfif isObject(application.securityService)>
    <cfset application.securityService.resetRateLimit(_rl_ip, "IP")>
    <cfset application.securityService.auditLog(
      eventType = "LOGIN",
      userID    = (structKeyExists(session, "user") AND structKeyExists(session.user, "userID")) ? session.user.userID : "",
      ipAddress = _rl_ip,
      userAgent = _rl_ua,
      details   = "username=#encodeForHTML(username)#"
    )>
  </cfif>

  <cflocation url="index.cfm" addtoken="false">
<cfelse>
  <!--- STEP 7: Record failed attempt and audit login failure (non-AJAX path) --->
  <cfif isObject(application.securityService)>
    <cfset application.securityService.recordFailedAttempt(_rl_ip, "IP")>
    <cfset application.securityService.auditLog(
      eventType = "LOGIN_FAILED",
      ipAddress = _rl_ip,
      userAgent = _rl_ua,
      details   = "username=#encodeForHTML(username)# reason=#encodeForHTML(authResult.message)#"
    )>
  </cfif>
  <cflocation url="login.cfm?error=#urlEncodedFormat(authResult.message)#" addtoken="false">
</cfif>
