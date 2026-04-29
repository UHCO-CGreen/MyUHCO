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
  <cfset authResult = application.portalAuthService.authenticateCredentials(
    username = username,
    password = form.password
  )>

  <cfif authResult.success>
    <cfset session.pendingPortalUser = duplicate(authResult.user)>
    <cfset response.success = true>
    <cfset response.message = "Authenticated">
    <cfset response.displayName = authResult.user.displayName>
  <cfelse>
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

  <cfset response.success = true>
  <cfset response.message = "Profile loaded">
  <cfset response.redirect = "index.cfm">
  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cfif NOT len(username) OR NOT len(trim(form.password))>
  <cflocation url="login.cfm?error=Please+enter+your+username+and+password." addtoken="false">
</cfif>

<cfset authResult = application.portalAuthService.authenticateCredentials(
  username = username,
  password = form.password
)>

<cfif authResult.success>
  <cfset profileUser = application.portalAuthService.loadUserProfile(authResult.user)>
  <cfset application.portalAuthService.createSession(profileUser)>
  <cflocation url="index.cfm" addtoken="false">
<cfelse>
  <cflocation url="login.cfm?error=#urlEncodedFormat(authResult.message)#" addtoken="false">
</cfif>
