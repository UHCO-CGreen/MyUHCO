<cfsetting showdebugoutput="false">
<cfheader name="Content-Type" value="application/json; charset=utf-8">

<cfset response = {
  success = false,
  message = "",
  diagnostics = {
    config = {},
    dropbox = {},
    documents = {}
  }
}>

<cfif NOT structKeyExists(session, "user")>
  <cfheader statuscode="401">
  <cfset response.message = "Unauthorized.">
  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cfif NOT structKeyExists(application, "dropboxProvider") OR NOT structKeyExists(application, "documentService")>
  <cfheader statuscode="503">
  <cfset response.message = "Required services are not initialized.">
  <cfoutput>#serializeJSON(response)#</cfoutput>
  <cfabort>
</cfif>

<cfparam name="url.folderPath" default="">

<cftry>
  <cfif structKeyExists(application, "appConfigService")>
    <cfset response.diagnostics.config = {
      appKeyPresent = len(trim(application.appConfigService.getValue("dropbox.app_key", "") & "")) GT 0,
      appSecretPresent = len(trim(application.appConfigService.getValue("dropbox.app_secret", "") & "")) GT 0,
      refreshTokenPresent = len(trim(application.appConfigService.getValue("dropbox.refresh_token", "") & "")) GT 0
    }>
  </cfif>

  <cfset response.diagnostics.dropbox = application.dropboxProvider.testConnection(folderPath = trim(url.folderPath & ""))>

  <cfset docResult = application.documentService.getDocuments()>
  <cfset response.diagnostics.documents = {
    success = docResult.success,
    source = docResult.source,
    message = docResult.message,
    itemCount = arrayLen(docResult.items),
    quickDocsFolderUrl = docResult.quickDocsFolderUrl
  }>

  <cfset response.success = response.diagnostics.dropbox.success AND response.diagnostics.documents.success>
  <cfif response.success>
    <cfset response.message = "Dropbox and document service checks passed.">
  <cfelse>
    <cfset response.message = "One or more checks failed.">
  </cfif>

  <cfcatch type="any">
    <cfheader statuscode="500">
    <cfset response.success = false>
    <cfset response.message = "Diagnostics failed: " & cfcatch.message>
    <cflog file="myuhco-api" type="error" text="document-service-test.cfm error: #cfcatch.message# | #cfcatch.detail#">
  </cfcatch>
</cftry>

<cfoutput>#serializeJSON(response)#</cfoutput>