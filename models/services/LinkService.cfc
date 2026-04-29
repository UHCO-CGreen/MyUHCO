<cfcomponent displayname="LinkService" output="false">

  <cffunction name="init" access="public" returntype="any" output="false">
    <cfargument name="defaultManifestPath" type="string" required="false" default="">
    <cfargument name="userDirectoryPath" type="string" required="false" default="">

    <cfset variables.defaultManifestPath = trim(arguments.defaultManifestPath & "")>
    <cfset variables.userDirectoryPath = trim(arguments.userDirectoryPath & "")>
    <cfreturn this>
  </cffunction>

  <cffunction name="getMergedLinks" access="public" returntype="struct" output="false">
    <cfargument name="userId" type="string" required="true">

    <cfset var result = {
      success = false,
      message = "",
      links = []
    }>
    <cfset var defaults = []>
    <cfset var saved = []>

    <cftry>
      <cfset defaults = getDefaultLinks()>
      <cfset saved = getUserLinks(arguments.userId)>
      <cfset result.links = mergeAndSort(defaults, saved)>
      <cfset result.success = true>

      <cfcatch type="any">
        <cfset result.message = "Link load failed.">
        <cflog file="myuhco-api" type="error" text="LinkService load error: #cfcatch.message# | #cfcatch.detail#">
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="saveUserLink" access="public" returntype="struct" output="false">
    <cfargument name="userId" type="string" required="true">
    <cfargument name="title" type="string" required="true">
    <cfargument name="href" type="string" required="true">

    <cfset var result = { success = false, message = "" }>
    <cfset var userLinks = []>
    <cfset var safeTitle = trim(arguments.title & "")>
    <cfset var safeHref = trim(arguments.href & "")>
    <cfset var userFile = getUserFilePath(arguments.userId)>

    <cfif NOT len(safeTitle) OR NOT len(safeHref)>
      <cfset result.message = "Title and URL are required.">
      <cfreturn result>
    </cfif>

    <cftry>
      <cfset userLinks = getUserLinks(arguments.userId)>
      <cfset arrayAppend(userLinks, {
        id = "u-" & replace(createUUID(), "-", "", "all"),
        title = safeTitle,
        href = safeHref,
        source = "user",
        section = "other-links"
      })>
      <cffile action="write" file="#userFile#" output="#serializeJSON(userLinks)#" charset="utf-8">
      <cfset result.success = true>

      <cfcatch type="any">
        <cfset result.message = "Unable to save link.">
        <cflog file="myuhco-api" type="error" text="LinkService save error: #cfcatch.message# | #cfcatch.detail#">
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="deleteUserLink" access="public" returntype="struct" output="false">
    <cfargument name="userId" type="string" required="true">
    <cfargument name="linkId" type="string" required="true">

    <cfset var result = { success = false, message = "" }>
    <cfset var userLinks = []>
    <cfset var filtered = []>
    <cfset var i = 0>
    <cfset var userFile = getUserFilePath(arguments.userId)>

    <cftry>
      <cfset userLinks = getUserLinks(arguments.userId)>
      <cfloop from="1" to="#arrayLen(userLinks)#" index="i">
        <cfif compare(userLinks[i].id & "", arguments.linkId & "") NEQ 0>
          <cfset arrayAppend(filtered, userLinks[i])>
        </cfif>
      </cfloop>
      <cffile action="write" file="#userFile#" output="#serializeJSON(filtered)#" charset="utf-8">
      <cfset result.success = true>

      <cfcatch type="any">
        <cfset result.message = "Unable to delete link.">
        <cflog file="myuhco-api" type="error" text="LinkService delete error: #cfcatch.message# | #cfcatch.detail#">
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="getDefaultLinks" access="private" returntype="array" output="false">
    <cfset var filePath = resolveDefaultManifestPath()>
    <cfset var parsed = {}>
    <cfset var links = []>
    <cfset var i = 0>

    <cfif NOT fileExists(filePath)>
      <cfreturn []>
    </cfif>

    <cffile action="read" file="#filePath#" variable="rawJson" charset="utf-8">
    <cfif NOT len(trim(rawJson))>
      <cfreturn []>
    </cfif>

    <cfset parsed = deserializeJSON(rawJson)>

    <cfif isArray(parsed)>
      <cfset links = parsed>
    <cfelseif isStruct(parsed) AND structKeyExists(parsed, "links") AND isArray(parsed.links)>
      <cfset links = parsed.links>
    </cfif>

    <cfset var normalized = []>
    <cfset var item = {}>

    <cfloop from="1" to="#arrayLen(links)#" index="i">
      <cfif isStruct(links[i])>
        <cfset item = {
          id = readKey(links[i], "id"),
          title = readKey(links[i], "title"),
          href = readKey(links[i], "href"),
          source = "default",
          section = normalizeLinkSection(readKey(links[i], "section")),
          sortOrder = val(readKey(links[i], "sortOrder"))
        }>
        <cfif NOT len(item.id)>
          <cfset item.id = "d-" & i>
        </cfif>
        <cfif len(item.title) AND len(item.href)>
          <cfset arrayAppend(normalized, item)>
        </cfif>
      </cfif>
    </cfloop>

    <cfreturn normalized>
  </cffunction>

  <cffunction name="getUserLinks" access="private" returntype="array" output="false">
    <cfargument name="userId" type="string" required="true">

    <cfset var filePath = getUserFilePath(arguments.userId)>
    <cfset var parsed = []>

    <cfif NOT fileExists(filePath)>
      <cfreturn []>
    </cfif>

    <cffile action="read" file="#filePath#" variable="rawJson" charset="utf-8">
    <cfif NOT len(trim(rawJson))>
      <cfreturn []>
    </cfif>

    <cfset parsed = deserializeJSON(rawJson)>
    <cfif NOT isArray(parsed)>
      <cfreturn []>
    </cfif>

    <cfreturn parsed>
  </cffunction>

  <cffunction name="mergeAndSort" access="private" returntype="array" output="false">
    <cfargument name="defaults" type="array" required="true">
    <cfargument name="saved" type="array" required="true">

    <cfset var merged = []>
    <cfset var seen = structNew("ordered")>
    <cfset var i = 0>
    <cfset var entry = {}>

    <cfloop from="1" to="#arrayLen(arguments.defaults)#" index="i">
      <cfset entry = arguments.defaults[i]>
      <cfif NOT structKeyExists(seen, lCase(entry.id & ""))>
        <cfset arrayAppend(merged, entry)>
        <cfset seen[lCase(entry.id & "")] = true>
      </cfif>
    </cfloop>

    <cfloop from="1" to="#arrayLen(arguments.saved)#" index="i">
      <cfif isStruct(arguments.saved[i])>
        <cfset entry = {
          id = readKey(arguments.saved[i], "id"),
          title = readKey(arguments.saved[i], "title"),
          href = readKey(arguments.saved[i], "href"),
          source = "user",
          section = "other-links",
          sortOrder = 100000 + i
        }>
        <cfif len(entry.id) AND len(entry.title) AND len(entry.href) AND NOT structKeyExists(seen, lCase(entry.id))>
          <cfset arrayAppend(merged, entry)>
          <cfset seen[lCase(entry.id)] = true>
        </cfif>
      </cfif>
    </cfloop>

    <cfset merged = sortMergedLinks(merged)>

    <cfreturn merged>
  </cffunction>

  <cffunction name="sortMergedLinks" access="private" returntype="array" output="false">
    <cfargument name="items" type="array" required="true">

    <cfset var sortedItems = duplicate(arguments.items)>
    <cfset var i = 0>
    <cfset var j = 0>
    <cfset var current = {}>

    <cfif arrayLen(sortedItems) LTE 1>
      <cfreturn sortedItems>
    </cfif>

    <cfloop from="2" to="#arrayLen(sortedItems)#" index="i">
      <cfset current = sortedItems[i]>
      <cfset j = i - 1>

      <cfloop condition="j GTE 1 AND compareLinkEntries(sortedItems[j], current) GT 0">
        <cfset sortedItems[j + 1] = sortedItems[j]>
        <cfset j = j - 1>
      </cfloop>

      <cfset sortedItems[j + 1] = current>
    </cfloop>

    <cfreturn sortedItems>
  </cffunction>

  <cffunction name="compareLinkEntries" access="private" returntype="numeric" output="false">
    <cfargument name="a" type="struct" required="true">
    <cfargument name="b" type="struct" required="true">

    <cfset var orderA = 999999>
    <cfset var orderB = 999999>
    <cfset var titleCompare = 0>

    <cfif structKeyExists(arguments.a, "sortOrder")>
      <cfset orderA = val(arguments.a.sortOrder)>
    </cfif>
    <cfif structKeyExists(arguments.b, "sortOrder")>
      <cfset orderB = val(arguments.b.sortOrder)>
    </cfif>

    <cfif orderA LT orderB>
      <cfreturn -1>
    <cfelseif orderA GT orderB>
      <cfreturn 1>
    </cfif>

    <cfset titleCompare = compareNoCase(arguments.a.title & "", arguments.b.title & "")>
    <cfif titleCompare LT 0>
      <cfreturn -1>
    <cfelseif titleCompare GT 0>
      <cfreturn 1>
    </cfif>

    <cfreturn compareNoCase(arguments.a.id & "", arguments.b.id & "")>
  </cffunction>

  <cffunction name="normalizeLinkSection" access="private" returntype="string" output="false">
    <cfargument name="sectionRaw" type="string" required="true">

    <cfset var sectionValue = lCase(trim(arguments.sectionRaw & ""))>

    <cfif sectionValue EQ "college-forms" OR sectionValue EQ "college forms" OR sectionValue EQ "collegeforms">
      <cfreturn "college-forms">
    </cfif>

    <cfreturn "other-links">
  </cffunction>

  <cffunction name="resolveDefaultManifestPath" access="private" returntype="string" output="false">
    <cfif len(variables.defaultManifestPath)>
      <cfreturn variables.defaultManifestPath>
    </cfif>
    <cfreturn expandPath("/data/links/default-links.json")>
  </cffunction>

  <cffunction name="resolveUserDirectoryPath" access="private" returntype="string" output="false">
    <cfif len(variables.userDirectoryPath)>
      <cfreturn variables.userDirectoryPath>
    </cfif>
    <cfreturn expandPath("/data/links/users")>
  </cffunction>

  <cffunction name="getUserFilePath" access="private" returntype="string" output="false">
    <cfargument name="userId" type="string" required="true">

    <cfset var safeUserId = lCase(reReplace(arguments.userId, "[^a-zA-Z0-9_-]", "", "all"))>
    <cfif NOT len(safeUserId)>
      <cfset safeUserId = "anonymous">
    </cfif>

    <cfset var folderPath = resolveUserDirectoryPath()>
    <cfif NOT directoryExists(folderPath)>
      <cfset directoryCreate(folderPath)>
    </cfif>

    <cfreturn folderPath & "/" & safeUserId & ".json">
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

</cfcomponent>
