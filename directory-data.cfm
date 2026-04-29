<cfsetting showdebugoutput="false">
<cfheader name="Content-Type" value="application/json; charset=utf-8">

<cfset response = {
  success = false,
  message = "",
  group = "",
  items = [],
  debug = []
}>

<cfparam name="url.group" default="">
<cfparam name="url.gradyear" default="">
<cfset requestedGroup = lCase(trim(url.group & ""))>
<cfset requestedGradYear = trim(url.gradyear & "")>

<cfif NOT structKeyExists(session, "portalUser")>
  <cfheader statuscode="401">
  <cfset response.message = "Unauthorized.">
  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cfif NOT listFindNoCase("faculty,staff,students,alumni", requestedGroup)>
  <cfheader statuscode="400">
  <cfset response.message = "Invalid group parameter.">
  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cfif listFindNoCase("students,alumni", requestedGroup)>
  <cfif NOT len(requestedGradYear)>
    <cfheader statuscode="400">
    <cfset response.message = "gradyear is required for students and alumni.">
    <cfoutput>#serializeJSON(response)#</cfoutput>
    <cfabort>
  </cfif>
  <cfif NOT reFind("^[0-9]{4}$", requestedGradYear)>
    <cfheader statuscode="400">
    <cfset response.message = "Invalid gradyear format.">
    <cfoutput>#serializeJSON(response)#</cfoutput>
    <cfabort>
  </cfif>
</cfif>

<cfif NOT structKeyExists(application, "directoryService")>
  <cfheader statuscode="503">
  <cfset response.message = "Directory service is not initialized.">
  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cftry>
  <cfset groupResult = application.directoryService.getDirectoryGroup(
    groupKey = requestedGroup,
    currentUser = session.portalUser,
    gradYear = requestedGradYear
  )>

  <cfset response.success = groupResult.success>
  <cfset response.message = groupResult.message>
  <cfset response.group = groupResult.group>
  <cfset response.items = groupResult.items>
  <cfset response.debug = groupResult.debug>

  <cfcatch type="any">
    <cfheader statuscode="500">
    <cfset response.message = "Directory request failed: " & cfcatch.message>
    <cflog file="myuhco-api" type="error" text="directory-data.cfm error: #cfcatch.message# | #cfcatch.detail#">
  </cfcatch>
</cftry>

<cfoutput>#serializeJSON(response)#</cfoutput>
