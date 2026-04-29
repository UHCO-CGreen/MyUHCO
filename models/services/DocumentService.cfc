<cfcomponent displayname="DocumentService" output="false">

  <cffunction name="init" access="public" returntype="any" output="false">
    <cfargument name="manifestPath" type="string" required="false" default="">
    <cfset variables.manifestPath = trim(arguments.manifestPath & "")>
    <cfreturn this>
  </cffunction>

  <cffunction name="getDocuments" access="public" returntype="struct" output="false">
    <cfset var result = {
      success = false,
      source = "",
      message = "",
      items = [],
      quickDocsFolderUrl = ""
    }>
    <cfset var manifestPath = resolveManifestPath()>
    <cfset var manifestData = {}>
    <cfset var remoteData = {}>

    <cftry>
      <cfset manifestData = readJsonFile(manifestPath)>

      <cfif structKeyExists(manifestData, "sourceUrl") AND len(trim(manifestData.sourceUrl & ""))>
        <cfset remoteData = fetchRemoteManifest(trim(manifestData.sourceUrl & ""))>
        <cfif remoteData.success>
          <cfset result.items = normalizeDocuments(remoteData.payload)>
          <cfset result.quickDocsFolderUrl = readRootValue(remoteData.payload, "quickDocsFolderUrl")>
          <cfset result.source = "dropbox-remote">
          <cfset result.success = true>
          <cfreturn result>
        </cfif>
      </cfif>

      <cfset result.items = normalizeDocuments(manifestData)>
      <cfset result.quickDocsFolderUrl = readRootValue(manifestData, "quickDocsFolderUrl")>
      <cfset result.source = "dropbox-local-manifest">
      <cfset result.success = true>

      <cfcatch type="any">
        <cfset result.message = "Document manifest load failed.">
        <cflog file="myuhco-api" type="error" text="DocumentService error: #cfcatch.message# | #cfcatch.detail#">
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="resolveManifestPath" access="private" returntype="string" output="false">
    <cfif len(variables.manifestPath)>
      <cfreturn variables.manifestPath>
    </cfif>
    <cfreturn expandPath("/data/documents/manifest.json")>
  </cffunction>

  <cffunction name="readJsonFile" access="private" returntype="any" output="false">
    <cfargument name="filePath" type="string" required="true">

    <cfset var raw = "">
    <cfif NOT fileExists(arguments.filePath)>
      <cfreturn {}>
    </cfif>

    <cffile action="read" file="#arguments.filePath#" variable="raw" charset="utf-8">
    <cfif NOT len(trim(raw))>
      <cfreturn {}>
    </cfif>

    <cfreturn deserializeJSON(raw)>
  </cffunction>

  <cffunction name="fetchRemoteManifest" access="private" returntype="struct" output="false">
    <cfargument name="url" type="string" required="true">

    <cfset var result = { success = false, payload = {} }>
    <cfset var response = {}>

    <cftry>
      <cfhttp method="get" url="#arguments.url#" result="response" timeout="12" throwOnError="false"></cfhttp>
      <cfif findNoCase("200", response.statusCode) AND len(trim(response.fileContent & ""))>
        <cfset result.payload = deserializeJSON(response.fileContent)>
        <cfset result.success = true>
      <cfelse>
        <cflog file="myuhco-api" type="warning" text="DocumentService Dropbox fetch failed with status #response.statusCode#">
      </cfif>
      <cfcatch type="any">
        <cflog file="myuhco-api" type="warning" text="DocumentService Dropbox fetch error: #cfcatch.message#">
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="normalizeDocuments" access="private" returntype="array" output="false">
    <cfargument name="payload" type="any" required="true">

    <cfset var sourceItems = []>
    <cfset var outputItems = []>
    <cfset var i = 0>
    <cfset var item = {}>

    <cfif isArray(arguments.payload)>
      <cfset sourceItems = arguments.payload>
    <cfelseif isStruct(arguments.payload)>
      <cfif structKeyExists(arguments.payload, "documents") AND isArray(arguments.payload.documents)>
        <cfset sourceItems = arguments.payload.documents>
      <cfelseif structKeyExists(arguments.payload, "items") AND isArray(arguments.payload.items)>
        <cfset sourceItems = arguments.payload.items>
      </cfif>
    </cfif>

    <cfloop from="1" to="#arrayLen(sourceItems)#" index="i">
      <cfif isStruct(sourceItems[i])>
        <cfset item = {
          id = readKey(sourceItems[i], "id"),
          title = readKey(sourceItems[i], "title"),
          description = readKey(sourceItems[i], "description"),
          category = readKey(sourceItems[i], "category"),
          section = readKey(sourceItems[i], "section"),
          audience = readKey(sourceItems[i], "audience"),
          updatedAt = readKey(sourceItems[i], "updatedAt"),
          href = readKey(sourceItems[i], "href"),
          size = readKey(sourceItems[i], "size")
        }>
        <cfif len(item.title) OR len(item.href)>
          <cfif NOT len(item.id)>
            <cfset item.id = "doc-" & i>
          </cfif>
          <cfset arrayAppend(outputItems, item)>
        </cfif>
      </cfif>
    </cfloop>

    <cfreturn outputItems>
  </cffunction>

  <cffunction name="readKey" access="private" returntype="string" output="false">
    <cfargument name="record" type="struct" required="true">
    <cfargument name="keyName" type="string" required="true">

    <cfset var k = "">
    <cfset var valueData = "">

    <cfif structKeyExists(arguments.record, arguments.keyName)>
      <cfset valueData = arguments.record[arguments.keyName]>
      <cfif NOT isSimpleValue(valueData)>
        <cfset valueData = serializeJSON(valueData)>
      </cfif>
      <cfreturn trim(valueData & "")>
    </cfif>

    <cfloop collection="#arguments.record#" item="k">
      <cfif compareNoCase(k, arguments.keyName) EQ 0>
        <cfset valueData = arguments.record[k]>
        <cfif NOT isSimpleValue(valueData)>
          <cfset valueData = serializeJSON(valueData)>
        </cfif>
        <cfreturn trim(valueData & "")>
      </cfif>
    </cfloop>

    <cfreturn "">
  </cffunction>

  <cffunction name="readRootValue" access="private" returntype="string" output="false">
    <cfargument name="payload" type="any" required="true">
    <cfargument name="keyName" type="string" required="true">

    <cfif NOT isStruct(arguments.payload)>
      <cfreturn "">
    </cfif>

    <cfreturn readKey(arguments.payload, arguments.keyName)>
  </cffunction>

</cfcomponent>
