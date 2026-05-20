<cfsetting showdebugoutput="false">

<cfparam name="url.path" default="">
<cfparam name="url.url" default="">
<cfset requestedPath = trim(url.path & "")>
<cfset requestedUrl = trim(url.url & "")>
<cfset ext = "">

<cfif NOT structKeyExists(session, "user")>
  <cfheader statuscode="401">
  <cfoutput>Unauthorized.</cfoutput>
  <cfabort>
</cfif>

<cfif NOT len(requestedPath) AND NOT len(requestedUrl)>
  <cfheader statuscode="400">
  <cfoutput>Missing document reference.</cfoutput>
  <cfabort>
</cfif>

<cfif len(requestedPath)>
  <cfset ext = lCase(listLast(requestedPath, "."))>
  <cfif ext NEQ "pdf">
    <cfheader statuscode="400">
    <cfoutput>Only PDF preview is supported.</cfoutput>
    <cfabort>
  </cfif>
</cfif>

<cfif NOT structKeyExists(application, "dropboxProvider")>
  <cfheader statuscode="503">
  <cfoutput>Document provider unavailable.</cfoutput>
  <cfabort>
</cfif>

<cfset tempPath = "">
<cfset fileName = listLast(requestedPath, "/")>
<cfset safeFileName = replace(fileName, '"', "", "all")>
<cfset pdfBinary = "">
<cfset viewerResp = "">
<cfset responseType = "">
<cfset dispositionValue = "">
<cfset headerContentType = "">

<cfif NOT len(safeFileName) AND len(requestedUrl)>
  <cfset safeFileName = listFirst(listLast(requestedUrl, "/"), "?")>
</cfif>
<cfif NOT len(safeFileName)>
  <cfset safeFileName = "document.pdf">
</cfif>
<cfif listLast(safeFileName, ".") NEQ "pdf">
  <cfset safeFileName = safeFileName & ".pdf">
</cfif>

<cftry>
  <cfif len(requestedPath)>
    <cfset tempPath = application.dropboxProvider.downloadFileToTemp(requestedPath, "pdf")>
  <cfelse>
    <cfif NOT reFindNoCase("^https?://", requestedUrl) OR NOT findNoCase("dropbox", requestedUrl)>
      <cfheader statuscode="400">
      <cfoutput>Invalid preview URL.</cfoutput>
      <cfabort>
    </cfif>
    <cfhttp method="get" url="#requestedUrl#" result="viewerResp" throwOnError="false" timeout="60" getAsBinary="yes"></cfhttp>
    <cfif left(viewerResp.statusCode, 3) NEQ "200">
      <cfheader statuscode="502">
      <cfoutput>Unable to fetch PDF.</cfoutput>
      <cfabort>
    </cfif>
    <cfif structKeyExists(viewerResp, "mimeType")>
      <cfset responseType = lCase(trim(viewerResp.mimeType & ""))>
    <cfelse>
      <cfset responseType = "">
    </cfif>
    <cfif NOT findNoCase("pdf", responseType)>
      <cfset headerContentType = "">
      <cfif structKeyExists(viewerResp, "responseHeader") AND structKeyExists(viewerResp.responseHeader, "Content-Type")>
        <cfset headerContentType = viewerResp.responseHeader["Content-Type"]>
      </cfif>
      <cfset responseType = lCase(trim(headerContentType & ""))>
    </cfif>
    <cfif len(responseType) AND NOT findNoCase("pdf", responseType)>
      <cfheader statuscode="415">
      <cfoutput>Preview URL did not return a PDF.</cfoutput>
      <cfabort>
    </cfif>
    <cfset pdfBinary = viewerResp.fileContent>
  </cfif>

  <cfset dispositionValue = 'inline; filename="' & safeFileName & '"'>
  <cfheader name="Content-Type" value="application/pdf">
  <cfheader name="X-Content-Type-Options" value="nosniff">
  <cfheader name="Cache-Control" value="private, no-store, max-age=0">
  <cfheader name="Content-Disposition" value="#dispositionValue#">
  <cfif len(tempPath)>
    <cfcontent type="application/pdf" file="#tempPath#" deletefile="true" reset="true">
  <cfelse>
    <cfcontent type="application/pdf" variable="#pdfBinary#" reset="true">
  </cfif>
  <cfabort>

  <cfcatch type="any">
    <cfif len(tempPath) AND fileExists(tempPath)>
      <cfset fileDelete(tempPath)>
    </cfif>
    <cflog file="myuhco-api" type="error" text="document-view.cfm error: #cfcatch.message# | #cfcatch.detail# | path=#requestedPath#">
    <cfheader statuscode="500">
    <cfoutput>Unable to open document.</cfoutput>
  </cfcatch>
</cftry>
