<cfcomponent displayname="DocumentService" output="false">

  <cffunction name="init" access="public" returntype="any" output="false">
    <cfargument name="manifestPath" type="string" required="false" default="">
    <cfargument name="dropboxProvider" required="false" default="">
    <cfset variables.manifestPath = trim(arguments.manifestPath & "")>
    <cfset variables.dropboxDocumentExtensions = "pdf,doc,docx,xls,xlsx,ppt,pptx,csv,txt,rtf">
    <cfif isObject(arguments.dropboxProvider)>
      <cfset variables.dropboxProvider = arguments.dropboxProvider>
    <cfelse>
      <cfset variables.dropboxProvider = new models.services.DropboxProvider().init()>
    </cfif>
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
    <cfset var dropboxPath = "">
    <cfset var folderData = {}>

    <cftry>
      <cfset manifestData = readJsonFile(manifestPath)>

      <cfset dropboxPath = readRootValue(manifestData, "dropboxManifestPath")>
      <cfif NOT len(dropboxPath)>
        <cfset dropboxPath = readRootValue(manifestData, "dropboxPath")>
      </cfif>

      <cfif len(dropboxPath)>
        <cfif reFindNoCase("\.json$", dropboxPath)>
          <cfset manifestData = variables.dropboxProvider.downloadJson(dropboxPath)>
          <cfset result.items = normalizeDocuments(manifestData)>
          <cfset result.quickDocsFolderUrl = readRootValue(manifestData, "quickDocsFolderUrl")>
          <cfset result.source = "dropbox-api-manifest">
        <cfelse>
          <cfset folderData = buildDocumentsFromDropboxFolder(dropboxPath, manifestData)>
          <cfset result.items = folderData.items>
          <cfset result.quickDocsFolderUrl = folderData.quickDocsFolderUrl>
          <cfset result.source = "dropbox-api-folder">
        </cfif>
        <cfset result.success = true>
        <cfreturn result>
      </cfif>

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

  <cffunction name="buildDocumentsFromDropboxFolder" access="private" returntype="struct" output="false">
    <cfargument name="folderPath" type="string" required="true">
    <cfargument name="manifestSeed" type="any" required="false" default="#structNew()#">

    <cfset var out = { items = [], quickDocsFolderUrl = "" }>
    <cfset var files = []>
    <cfset var i = 0>
    <cfset var f = {}>
    <cfset var item = {}>
    <cfset var title = "">
    <cfset var section = "quick-docs">
    <cfset var audience = "all">
    <cfset var cleanRoot = trim(arguments.folderPath & "")>
    <cfset var relPath = "">
    <cfset var sizeText = "">
    <cfset var maxItems = val(readRootValue(arguments.manifestSeed, "dropboxMaxItems"))>
    <cfset var allowedExtensions = trim(readRootValue(arguments.manifestSeed, "dropboxAllowedExtensions") & "")>

    <cfif maxItems LTE 0>
      <cfset maxItems = 250>
    </cfif>

    <cfif NOT len(allowedExtensions)>
      <cfset allowedExtensions = variables.dropboxDocumentExtensions>
    </cfif>

    <cfset files = variables.dropboxProvider.listFolderEntriesRecursive(
      folderPath = arguments.folderPath,
      allowedExtensions = allowedExtensions
    )>

    <!--- If strict extension filtering returns no rows, retry with all files. --->
    <cfif arrayLen(files) EQ 0>
      <cfset files = variables.dropboxProvider.listFolderEntriesRecursive(
        folderPath = arguments.folderPath,
        allowedExtensions = ""
      )>
    </cfif>

    <cfif isStruct(arguments.manifestSeed)>
      <cfset out.quickDocsFolderUrl = readRootValue(arguments.manifestSeed, "quickDocsFolderUrl")>
    </cfif>
    <cfif NOT len(out.quickDocsFolderUrl)>
      <cfset out.quickDocsFolderUrl = cleanRoot>
    </cfif>

    <cfloop from="1" to="#arrayLen(files)#" index="i">
      <cfif i GT maxItems>
        <cfbreak>
      </cfif>

      <cfset f = files[i]>
      <cfset title = reReplace(listFirst(f.filename, "."), "[_\-]+", " ", "all")>
      <cfset relPath = replaceNoCase(f.path, cleanRoot, "", "one")>
      <cfif left(relPath, 1) EQ "/">
        <cfset relPath = right(relPath, len(relPath) - 1)>
      </cfif>

      <cfset section = "quick-docs">
      <cfset audience = "all">
      <cfif findNoCase("/quickdocs/", lCase("/" & relPath)) OR findNoCase("/quick-docs/", lCase("/" & relPath)) OR findNoCase("/quick docs/", lCase("/" & relPath))>
        <cfset section = "quick-docs">
        <cfset audience = "all">
      <cfelseif findNoCase("/faculty docs/", lCase("/" & relPath)) OR findNoCase("/facultydocs/", lCase("/" & relPath)) OR findNoCase("/faculty/", lCase("/" & relPath))>
        <cfset section = "faculty">
        <cfset audience = "faculty">
      <cfelseif findNoCase("/staff docs/", lCase("/" & relPath)) OR findNoCase("/staffdocs/", lCase("/" & relPath)) OR findNoCase("/staff/", lCase("/" & relPath))>
        <cfset section = "staff">
        <cfset audience = "staff">
      <cfelseif findNoCase("/student docs/", lCase("/" & relPath)) OR findNoCase("/studentdocs/", lCase("/" & relPath)) OR findNoCase("/students/", lCase("/" & relPath))>
        <cfset section = "students">
        <cfset audience = "students">
      </cfif>

      <cfset sizeText = uCase(f.extension)>
      <cfif len(trim(f.size & ""))>
        <cfset sizeText = f.size & " bytes">
      </cfif>

      <cfset item = {
        id = "dropbox-" & hash(lCase(f.path), "MD5"),
        title = trim(title),
        description = "Dropbox document",
        category = uCase(f.extension),
        section = section,
        audience = audience,
        updatedAt = trim(f.clientModified & ""),
        href = "",
        size = sizeText
      }>

      <cftry>
        <cfset item.href = variables.dropboxProvider.getTemporaryLink(f.path)>
        <cfcatch type="any">
          <cfset item.href = "">
        </cfcatch>
      </cftry>

      <cfset arrayAppend(out.items, item)>
    </cfloop>

    <cfreturn out>
  </cffunction>

</cfcomponent>
