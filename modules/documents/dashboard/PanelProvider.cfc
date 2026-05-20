<cfcomponent displayname="DocumentsDashboardPanelProvider" output="false">

  <cffunction name="getPanels" access="public" returntype="struct" output="false">
    <cfargument name="context" type="struct" required="true">

    <cfset var result = {
      success = false,
      message = "",
      panels = [],
      assets = {
        stylesheets = ["/modules/documents/dashboard/panels.css"],
        scripts = ["/modules/documents/dashboard/panels.js"]
      }
    }>
    <cfset var documentResult = {}>
    <cfset var bucketedDocuments = {}>
    <cfset var panelDefinitions = []>

    <cfif structKeyExists(arguments.context, "panelDefinitions") AND isArray(arguments.context.panelDefinitions)>
      <cfset panelDefinitions = arguments.context.panelDefinitions>
    </cfif>

    <cftry>
      <cfset documentResult = application.documentService.getDocuments()>
      <cfif NOT documentResult.success>
        <cfset result.message = len(documentResult.message) ? documentResult.message : "Document dashboard provider unavailable.">
        <cfreturn result>
      </cfif>

      <cfset bucketedDocuments = application.documentService.bucketDocuments(
        items = documentResult.items,
        userTypeKey = structKeyExists(arguments.context, "userTypeKey") ? trim(arguments.context.userTypeKey & "") : "",
        includeAllSpecificDocs = structKeyExists(arguments.context, "includeAllSpecificDocs") ? arguments.context.includeAllSpecificDocs : false
      )>

      <cfset result.panels = application.documentService.buildDashboardPanels(
        bucketedDocuments = bucketedDocuments,
        panelDefinitions = panelDefinitions,
        moduleId = "documents"
      )>
      <cfset result.success = true>

      <cfcatch type="any">
        <cfset result.message = "Document dashboard provider failed.">
        <cflog file="myuhco-api" type="error" text="Documents dashboard provider failed: #cfcatch.message# | #cfcatch.detail#">
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

</cfcomponent>