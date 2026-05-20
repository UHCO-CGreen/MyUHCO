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

  <cffunction name="bucketDocuments" access="public" returntype="struct" output="false">
    <cfargument name="items" type="array" required="true">
    <cfargument name="userTypeKey" type="string" required="false" default="">
    <cfargument name="includeAllSpecificDocs" type="boolean" required="false" default="false">

    <cfset var result = {
      quickDocs = [],
      rosterDocs = [],
      facultyDocs = [],
      staffDocs = [],
      studentDocs = []
    }>
    <cfset var docItem = {}>
    <cfset var docSection = "">

    <cfloop array="#arguments.items#" index="docItem">
      <cfif NOT isStruct(docItem)>
        <cfcontinue>
      </cfif>

      <cfset docSection = normalizeDocumentSection(readKey(docItem, "section"))>

      <cfif docSection EQ "quick-docs">
        <cfset arrayAppend(result.quickDocs, docItem)>
      <cfelseif docSection EQ "rosters">
        <cfset arrayAppend(result.rosterDocs, docItem)>
      <cfelseif docSection EQ "faculty">
        <cfif arguments.includeAllSpecificDocs OR arguments.userTypeKey EQ "faculty">
          <cfset arrayAppend(result.facultyDocs, docItem)>
        </cfif>
      <cfelseif docSection EQ "staff">
        <cfif arguments.includeAllSpecificDocs OR arguments.userTypeKey EQ "staff">
          <cfset arrayAppend(result.staffDocs, docItem)>
        </cfif>
      <cfelseif docSection EQ "students">
        <cfif arguments.includeAllSpecificDocs OR arguments.userTypeKey EQ "students">
          <cfset arrayAppend(result.studentDocs, docItem)>
        </cfif>
      </cfif>
    </cfloop>

    <cfset result.rosterDocs = sortRosterDocuments(result.rosterDocs)>

    <cfreturn result>
  </cffunction>

  <cffunction name="buildDashboardPanels" access="public" returntype="array" output="false">
    <cfargument name="bucketedDocuments" type="struct" required="true">
    <cfargument name="panelDefinitions" type="array" required="false" default="#[]#">
    <cfargument name="moduleId" type="string" required="false" default="documents">

    <cfset var panels = []>
    <cfset var panelDef = {}>
    <cfset var panelId = "">
    <cfset var sourceDocs = []>
    <cfset var panel = {}>
    <cfset var maxItems = 6>

    <cfloop array="#arguments.panelDefinitions#" index="panelDef">
      <cfif NOT isStruct(panelDef)>
        <cfcontinue>
      </cfif>

      <cfset panelId = lCase(readKey(panelDef, "id"))>
      <cfif NOT len(panelId)>
        <cfcontinue>
      </cfif>
      <cfif structKeyExists(panelDef, "enabled") AND NOT panelDef.enabled>
        <cfcontinue>
      </cfif>

      <cfset sourceDocs = []>
      <cfif panelId EQ "quick-docs">
        <cfset sourceDocs = structKeyExists(arguments.bucketedDocuments, "quickDocs") ? arguments.bucketedDocuments.quickDocs : []>
      <cfelseif panelId EQ "rosters">
        <cfset sourceDocs = structKeyExists(arguments.bucketedDocuments, "rosterDocs") ? arguments.bucketedDocuments.rosterDocs : []>
      <cfelse>
        <cfcontinue>
      </cfif>

      <cfset maxItems = val(readKey(panelDef, "maxItems"))>
      <cfif maxItems LTE 0>
        <cfset maxItems = 6>
      </cfif>

      <cfset panel = {
        moduleId = arguments.moduleId,
        panelId = panelId,
        title = len(readKey(panelDef, "title")) ? readKey(panelDef, "title") : panelId,
        type = len(readKey(panelDef, "type")) ? lCase(readKey(panelDef, "type")) : "link-list",
        viewAllHref = len(readKey(panelDef, "viewAllHref")) ? readKey(panelDef, "viewAllHref") : "index.cfm?module=" & arguments.moduleId,
        emptyMessage = len(readKey(panelDef, "emptyMessage")) ? readKey(panelDef, "emptyMessage") : "No items are available.",
        column = len(readKey(panelDef, "column")) ? lCase(readKey(panelDef, "column")) : "main",
        sortOrder = val(readKey(panelDef, "sortOrder")),
        itemCount = arrayLen(sourceDocs),
        items = buildDashboardPanelItems(sourceDocs, maxItems, panelId)
      }>

      <cfif panel.column NEQ "sidebar">
        <cfset panel.column = "main">
      </cfif>

      <cfset arrayAppend(panels, panel)>
    </cfloop>

    <cfreturn panels>
  </cffunction>

  <cffunction name="resolveManifestPath" access="private" returntype="string" output="false">
    <cfif len(variables.manifestPath)>
      <cfreturn variables.manifestPath>
    </cfif>
    <cfreturn expandPath("/data/documents/manifest.json")>
  </cffunction>

  <cffunction name="normalizeDocumentSection" access="private" returntype="string" output="false">
    <cfargument name="sectionValue" type="string" required="false" default="">

    <cfset var normalized = lCase(trim(arguments.sectionValue & ""))>

    <cfif normalized EQ "quick docs">
      <cfreturn "quick-docs">
    </cfif>
    <cfif normalized EQ "roster" OR normalized EQ "class-rosters" OR normalized EQ "class rosters">
      <cfreturn "rosters">
    </cfif>
    <cfif normalized EQ "student">
      <cfreturn "students">
    </cfif>

    <cfreturn normalized>
  </cffunction>

  <cffunction name="buildDashboardPanelItems" access="private" returntype="array" output="false">
    <cfargument name="docs" type="array" required="true">
    <cfargument name="maxItems" type="numeric" required="false" default="6">
    <cfargument name="panelId" type="string" required="false" default="">

    <cfset var items = []>
    <cfset var i = 0>
    <cfset var docItem = {}>
    <cfset var maxCount = arguments.maxItems>
    <cfset var descriptionText = "">
    <cfset var displayTitle = {}>

    <cfif maxCount LTE 0>
      <cfset maxCount = 6>
    </cfif>

    <cfloop from="1" to="#arrayLen(arguments.docs)#" index="i">
      <cfif i GT maxCount>
        <cfbreak>
      </cfif>

      <cfset docItem = arguments.docs[i]>
      <cfif NOT isStruct(docItem)>
        <cfcontinue>
      </cfif>

      <cfset descriptionText = readKey(docItem, "description")>
      <cfif NOT len(descriptionText)>
        <cfset descriptionText = readKey(docItem, "category")>
      </cfif>

      <cfif arguments.panelId EQ "quick-docs">
        <cfset displayTitle = getDashboardDisplayTitle(docItem, 30)>
      <cfelseif arguments.panelId EQ "rosters">
        <cfset displayTitle = getDashboardDisplayTitle(docItem, 80)>
      <cfelse>
        <cfset displayTitle = getDashboardDisplayTitle(docItem, 120)>
      </cfif>

      <cfset arrayAppend(items, {
        title = displayTitle.fullTitle,
        shortTitle = displayTitle.shortTitle,
        fullTitle = displayTitle.fullTitle,
        href = readKey(docItem, "href"),
        description = descriptionText,
        badge = readKey(docItem, "size"),
        publishedAt = readKey(docItem, "updatedAt"),
        updatedShort = getDashboardShortUpdatedLabel(docItem),
        icon = getDashboardItemIconClass(docItem),
        target = "_blank"
      })>
    </cfloop>

    <cfreturn items>
  </cffunction>

  <cffunction name="toDashboardTitleCaseWords" access="private" returntype="string" output="false">
    <cfargument name="value" type="string" required="true">

    <cfset var cleanedValue = trim(arguments.value & "")>
    <cfset var words = []>
    <cfset var resultWords = []>
    <cfset var i = 0>
    <cfset var wordValue = "">

    <cfif NOT len(cleanedValue)>
      <cfreturn "">
    </cfif>

    <cfset words = listToArray(cleanedValue, " ")>
    <cfloop from="1" to="#arrayLen(words)#" index="i">
      <cfset wordValue = trim(words[i])>
      <cfif len(wordValue)>
        <cfset arrayAppend(resultWords, uCase(left(wordValue, 1)) & lCase(mid(wordValue, 2, len(wordValue))))>
      </cfif>
    </cfloop>

    <cfreturn arrayToList(resultWords, " ")>
  </cffunction>

  <cffunction name="getDashboardDisplayTitle" access="private" returntype="struct" output="false">
    <cfargument name="docItem" type="struct" required="true">
    <cfargument name="maxLen" type="numeric" required="false" default="20">

    <cfset var rawTitle = readKey(arguments.docItem, "title")>
    <cfset var normalizedTitle = reReplace(rawTitle, "[-_]", " ", "all")>
    <cfset var truncatedTitle = "">

    <cfset normalizedTitle = reReplace(normalizedTitle, "\s+", " ", "all")>
    <cfset normalizedTitle = toDashboardTitleCaseWords(normalizedTitle)>

    <cfif NOT len(normalizedTitle)>
      <cfset normalizedTitle = "Untitled Document">
    </cfif>

    <cfset truncatedTitle = normalizedTitle>
    <cfif len(normalizedTitle) GT arguments.maxLen>
      <cfset truncatedTitle = left(normalizedTitle, arguments.maxLen) & "...">
    </cfif>

    <cfreturn {
      fullTitle = normalizedTitle,
      shortTitle = truncatedTitle
    }>
  </cffunction>

  <cffunction name="getDashboardShortUpdatedLabel" access="private" returntype="string" output="false">
    <cfargument name="docItem" type="struct" required="true">

    <cfset var updatedRaw = readKey(arguments.docItem, "updatedAt")>
    <cfset var dateToken = "">
    <cfset var dateParts = []>
    <cfset var ymdParts = []>

    <cfif NOT len(updatedRaw)>
      <cfreturn "">
    </cfif>

    <cfset dateToken = listFirst(updatedRaw, " ")>

    <cfif reFind("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$", dateToken)>
      <cfset dateParts = listToArray(dateToken, "/")>
      <cfif arrayLen(dateParts) EQ 3>
        <cfreturn "Upd " & dateParts[1] & "/" & dateParts[2] & "/" & right(dateParts[3], 2)>
      </cfif>
    </cfif>

    <cfif reFind("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", dateToken)>
      <cfset ymdParts = listToArray(dateToken, "-")>
      <cfif arrayLen(ymdParts) EQ 3>
        <cfreturn "Upd " & ymdParts[2] & "/" & ymdParts[3] & "/" & right(ymdParts[1], 2)>
      </cfif>
    </cfif>

    <cfif len(dateToken) GT 10>
      <cfset dateToken = left(dateToken, 10)>
    </cfif>

    <cfreturn "Upd " & dateToken>
  </cffunction>

  <cffunction name="getDashboardItemIconClass" access="private" returntype="string" output="false">
    <cfargument name="docItem" type="struct" required="true">

    <cfset var hrefValue = lCase(readKey(arguments.docItem, "href"))>
    <cfset var titleValue = lCase(readKey(arguments.docItem, "title"))>
    <cfset var categoryValue = lCase(readKey(arguments.docItem, "category"))>
    <cfset var haystack = hrefValue & " " & titleValue & " " & categoryValue>

    <cfif findNoCase("pdf", haystack)>
      <cfreturn "fas fa-file-pdf">
    </cfif>
    <cfif findNoCase("doc", haystack) OR findNoCase("docx", haystack)>
      <cfreturn "fas fa-file-word">
    </cfif>
    <cfif findNoCase("xls", haystack) OR findNoCase("xlsx", haystack) OR findNoCase("csv", haystack)>
      <cfreturn "fas fa-file-excel">
    </cfif>
    <cfif findNoCase("ppt", haystack) OR findNoCase("pptx", haystack)>
      <cfreturn "fas fa-file-powerpoint">
    </cfif>
    <cfif findNoCase("zip", haystack) OR findNoCase("rar", haystack) OR findNoCase("7z", haystack)>
      <cfreturn "fas fa-file-archive">
    </cfif>

    <cfreturn "fas fa-file-alt">
  </cffunction>

  <cffunction name="getRosterSortYear" access="private" returntype="numeric" output="false">
    <cfargument name="docItem" type="struct" required="true">

    <cfset var titleValue = readKey(arguments.docItem, "title")>
    <cfset var matchData = {}>

    <cfif NOT len(titleValue)>
      <cfreturn 0>
    </cfif>

    <cfset matchData = reFindNoCase("(19|20)\d{2}", titleValue, 1, true)>
    <cfif structKeyExists(matchData, "match") AND arrayLen(matchData.match) GTE 1 AND len(matchData.match[1])>
      <cfreturn val(matchData.match[1])>
    </cfif>

    <cfreturn 0>
  </cffunction>

  <cffunction name="sortRosterDocuments" access="private" returntype="array" output="false">
    <cfargument name="docs" type="array" required="true">

    <cfset var sortedDocs = duplicate(arguments.docs)>

    <cfset arraySort(sortedDocs, function(leftDoc, rightDoc) {
      var leftYear = getRosterSortYear(leftDoc);
      var rightYear = getRosterSortYear(rightDoc);

      if (leftYear LT rightYear) {
        return -1;
      }
      if (leftYear GT rightYear) {
        return 1;
      }
      return compareNoCase(
        readKey(leftDoc, "title"),
        readKey(rightDoc, "title")
      );
    })>

    <cfreturn sortedDocs>
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
    <cfset var dropboxPath = "">
    <cfset var isPdf = false>
    <cfset var categoryText = "">
    <cfset var sizeText = "">

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
        <cfset dropboxPath = readKey(sourceItems[i], "dropboxPath")>
        <cfif NOT len(dropboxPath)>
          <cfset dropboxPath = readKey(sourceItems[i], "path")>
        </cfif>
        <cfset categoryText = lCase(readKey(sourceItems[i], "category"))>
        <cfset sizeText = lCase(readKey(sourceItems[i], "size"))>
        <cfset isPdf = isPdfResource(item.href)
          OR isPdfResource(dropboxPath)
          OR categoryText EQ "pdf"
          OR findNoCase("pdf", sizeText)>
        <cfif len(dropboxPath) AND isPdf>
          <cfset item.href = buildInlinePdfUrl(dropboxPath)>
        <cfelseif isPdf>
          <cfset item.href = buildInlinePdfUrl("", item.href)>
        </cfif>
        <cfset item.size = formatFileSize(item.size)>
        <cfset item.updatedAt = formatUpdatedAt(item.updatedAt)>
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
    <cfset var section = "">
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

      <cfset section = "">
      <cfset audience = "all">
      <cfif findNoCase("/quickdocs/", lCase("/" & relPath)) OR findNoCase("/quick-docs/", lCase("/" & relPath)) OR findNoCase("/quick docs/", lCase("/" & relPath))>
        <cfset section = "quick-docs">
        <cfset audience = "all">
      <cfelseif findNoCase("/rosters/", lCase("/" & relPath)) OR findNoCase("/class rosters/", lCase("/" & relPath)) OR findNoCase("/class-rosters/", lCase("/" & relPath))>
        <cfset section = "rosters">
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

      <cfset sizeText = formatFileSize(f.size)>
      <cfif NOT len(sizeText)>
        <cfset sizeText = uCase(f.extension)>
      </cfif>

      <cfset item = {
        id = "dropbox-" & hash(lCase(f.path), "MD5"),
        title = trim(title),
        description = "Dropbox document",
        category = uCase(f.extension),
        section = section,
        audience = audience,
        updatedAt = formatUpdatedAt(trim(f.clientModified & "")),
        href = "",
        size = sizeText
      }>

      <cfif lCase(f.extension) EQ "pdf">
        <cfset item.href = buildInlinePdfUrl(f.path)>
      <cfelse>
        <cftry>
          <cfset item.href = variables.dropboxProvider.getTemporaryLink(f.path)>
          <cfcatch type="any">
            <cfset item.href = "">
          </cfcatch>
        </cftry>
      </cfif>

      <cfset arrayAppend(out.items, item)>
    </cfloop>

    <cfreturn out>
  </cffunction>

  <cffunction name="formatFileSize" access="private" returntype="string" output="false">
    <cfargument name="sizeValue" required="false" default="">

    <cfset var raw = trim(arguments.sizeValue & "")>
    <cfset var cleaned = "">
    <cfset var bytes = 0>
    <cfset var mb = 0>
    <cfset var gb = 0>

    <cfif NOT len(raw)>
      <cfreturn "">
    </cfif>

    <!--- Already human-readable. --->
    <cfif reFindNoCase("\\b(GB|MB)\\b", raw)>
      <cfreturn raw>
    </cfif>

    <!--- Support values like "12,345 bytes" and "12345". --->
    <cfset cleaned = reReplace(raw, "[^0-9]", "", "all")>
    <cfset bytes = val(cleaned)>
    <cfif bytes LTE 0>
      <cfreturn raw>
    </cfif>

    <cfset mb = bytes / (1024 * 1024)>
    <cfif mb GTE 1024>
      <cfset gb = mb / 1024>
      <cfreturn numberFormat(gb, "0.00") & " GB">
    </cfif>

    <cfreturn numberFormat(mb, "0.00") & " MB">
  </cffunction>

  <cffunction name="formatUpdatedAt" access="private" returntype="string" output="false">
    <cfargument name="updatedValue" type="string" required="false" default="">

    <cfset var raw = trim(arguments.updatedValue & "")>
    <cfset var parsed = "">
    <cfset var isoParts = {}>
    <cfset var y = 0>
    <cfset var m = 0>
    <cfset var d = 0>
    <cfset var hh = 0>
    <cfset var mm = 0>
    <cfset var ss = 0>

    <cfif NOT len(raw)>
      <cfreturn "">
    </cfif>

    <cftry>
      <cfif reFindNoCase("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(:\\d{2})?(\\.\\d+)?(Z|[+\\-]\\d{2}:?\\d{2})?$", raw)>
        <cfset isoParts = reFindNoCase("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2}))?", raw, 1, true)>
        <cfif structKeyExists(isoParts, "match") AND arrayLen(isoParts.match) GTE 6>
          <cfset y = val(isoParts.match[2])>
          <cfset m = val(isoParts.match[3])>
          <cfset d = val(isoParts.match[4])>
          <cfset hh = val(isoParts.match[5])>
          <cfset mm = val(isoParts.match[6])>
          <cfif arrayLen(isoParts.match) GTE 7>
            <cfset ss = val(isoParts.match[7])>
          </cfif>
          <cfset parsed = createDateTime(y, m, d, hh, mm, ss)>
        </cfif>
      <cfelseif isDate(raw)>
        <cfset parsed = raw>
      <cfelse>
        <cfset parsed = parseDateTime(raw)>
      </cfif>

      <cfif NOT isDate(parsed)>
        <cfreturn raw>
      </cfif>

      <cfreturn dateFormat(parsed, "mm/dd/yyyy") & " " & lCase(timeFormat(parsed, "hh:mm tt"))>
      <cfcatch type="any">
        <cfreturn raw>
      </cfcatch>
    </cftry>
  </cffunction>

  <cffunction name="isPdfResource" access="private" returntype="boolean" output="false">
    <cfargument name="value" type="string" required="true">

    <cfset var v = lCase(trim(arguments.value & ""))>
    <cfif NOT len(v)>
      <cfreturn false>
    </cfif>

    <cfif reFindNoCase("\\.pdf($|[?&##])", v)>
      <cfreturn true>
    </cfif>

    <cfreturn false>
  </cffunction>

  <cffunction name="buildInlinePdfUrl" access="private" returntype="string" output="false">
    <cfargument name="dropboxPath" type="string" required="true">
    <cfargument name="sourceUrl" type="string" required="false" default="">

    <cfset var cleanPath = trim(arguments.dropboxPath & "")>
    <cfset var cleanUrl = trim(arguments.sourceUrl & "")>

    <cfif len(cleanPath)>
      <cfreturn "document-view.cfm?path=" & urlEncodedFormat(cleanPath)>
    </cfif>

    <cfif len(cleanUrl)>
      <cfset cleanUrl = normalizePdfHref(cleanUrl)>
      <cfreturn "document-view.cfm?url=" & urlEncodedFormat(cleanUrl)>
    </cfif>

    <cfreturn "">
  </cffunction>

  <cffunction name="normalizePdfHref" access="private" returntype="string" output="false">
    <cfargument name="href" type="string" required="true">

    <cfset var urlValue = trim(arguments.href & "")>

    <cfif NOT len(urlValue)>
      <cfreturn "">
    </cfif>

    <cfif findNoCase("dropbox.com", urlValue)>
      <cfif reFindNoCase("([?&])dl=1($|&)", urlValue)>
        <cfset urlValue = reReplaceNoCase(urlValue, "([?&])dl=1($|&)", "\1dl=0\2", "all")>
      <cfelseif NOT reFindNoCase("([?&])dl=", urlValue)>
        <cfif find("?", urlValue)>
          <cfset urlValue = urlValue & "&dl=0">
        <cfelse>
          <cfset urlValue = urlValue & "?dl=0">
        </cfif>
      </cfif>
    </cfif>

    <cfreturn urlValue>
  </cffunction>

</cfcomponent>
