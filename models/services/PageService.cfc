<cfcomponent displayname="PageService" output="false">

  <cffunction name="init" access="public" returntype="any" output="false">
    <cfargument name="datasource" type="string" required="false" default="">
    <cfargument name="tableName" type="string" required="false" default="PortalPages">

    <cfset variables.datasource = trim(arguments.datasource & "")>
    <cfset variables.tableName = trim(arguments.tableName & "")>
    <cfset variables.qualifiedTableName = "">
    <cfreturn this>
  </cffunction>

  <cffunction name="isReady" access="public" returntype="boolean" output="false">
    <cfreturn len(variables.datasource) GT 0 AND len(variables.tableName) GT 0>
  </cffunction>

  <cffunction name="getBuildSignature" access="public" returntype="string" output="false">
    <cfreturn "2026-05-17-pages-p2-nav-dispatch-v1">
  </cffunction>

  <cffunction name="getTableStatus" access="public" returntype="struct" output="false">
    <cfset var result = {
      ready = isReady(),
      exists = false,
      datasource = variables.datasource,
      tableName = variables.tableName,
      qualifiedTableName = "",
      errorMessage = ""
    }>
    <cfset var resolvedTableName = "">

    <cfif NOT result.ready>
      <cfset result.errorMessage = "MYUHCO datasource is not configured.">
      <cfreturn result>
    </cfif>

    <cftry>
      <cfset resolvedTableName = getQualifiedTableName()>
      <cfif len(resolvedTableName)>
        <cfset result.exists = true>
        <cfset result.qualifiedTableName = resolvedTableName>
      </cfif>
      <cfcatch type="any">
        <cfset result.errorMessage = cfcatch.message>
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="listPages" access="public" returntype="struct" output="false">
    <cfargument name="includeDrafts" type="boolean" required="false" default="true">

    <cfset var result = { success = false, message = "", pages = [] }>
    <cfset var qPages = "">
    <cfset var tableRef = "">

    <cfif NOT isReady()>
      <cfset result.message = "Pages datasource is not configured.">
      <cfreturn result>
    </cfif>

    <cftry>
      <cfset tableRef = getQualifiedTableName()>
      <cfif NOT len(tableRef)>
        <cfset result.message = "PortalPages was not found in the configured datasource.">
        <cfreturn result>
      </cfif>
      <cfquery name="qPages" datasource="#variables.datasource#">
        SELECT
          PageID,
          Slug,
          Title,
          NavLabel,
          Summary,
          IsPublished,
          ShowInNav,
          NavSortOrder,
          CreatedAt,
          UpdatedAt
        FROM #tableRef#
        <cfif NOT arguments.includeDrafts>
          WHERE IsPublished = <cfqueryparam value="1" cfsqltype="cf_sql_bit">
        </cfif>
        ORDER BY
          CASE WHEN ShowInNav = 1 THEN 0 ELSE 1 END,
          NavSortOrder,
          Title,
          PageID
      </cfquery>

      <cfloop query="qPages">
        <cfset arrayAppend(result.pages, {
          pageId = int(qPages.PageID),
          slug = trim(qPages.Slug & ""),
          title = trim(qPages.Title & ""),
          navLabel = trim(qPages.NavLabel & ""),
          summary = trim(qPages.Summary & ""),
          isPublished = qPages.IsPublished EQ true OR val(qPages.IsPublished) EQ 1,
          showInNav = qPages.ShowInNav EQ true OR val(qPages.ShowInNav) EQ 1,
          navSortOrder = int(val(qPages.NavSortOrder)),
          createdAt = qPages.CreatedAt,
          updatedAt = qPages.UpdatedAt
        })>
      </cfloop>

      <cfset result.success = true>
      <cfcatch type="any">
        <cfset result.message = cfcatch.message>
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="listNavPages" access="public" returntype="struct" output="false">
    <cfset var result = { success = false, message = "", pages = [] }>
    <cfset var qPages = "">
    <cfset var tableRef = "">

    <cfif NOT isReady()>
      <cfset result.message = "Pages datasource is not configured.">
      <cfreturn result>
    </cfif>

    <cftry>
      <cfset tableRef = getQualifiedTableName()>
      <cfif NOT len(tableRef)>
        <cfset result.message = "PortalPages was not found in the configured datasource.">
        <cfreturn result>
      </cfif>

      <cfquery name="qPages" datasource="#variables.datasource#">
        SELECT
          PageID,
          Slug,
          Title,
          NavLabel,
          NavSortOrder
        FROM #tableRef#
        WHERE IsPublished = <cfqueryparam value="1" cfsqltype="cf_sql_bit">
          AND ShowInNav = <cfqueryparam value="1" cfsqltype="cf_sql_bit">
        ORDER BY NavSortOrder, Title, PageID
      </cfquery>

      <cfloop query="qPages">
        <cfset arrayAppend(result.pages, {
          pageId = int(qPages.PageID),
          slug = trim(qPages.Slug & ""),
          title = trim(qPages.Title & ""),
          navLabel = trim(qPages.NavLabel & ""),
          navSortOrder = int(val(qPages.NavSortOrder))
        })>
      </cfloop>

      <cfset result.success = true>
      <cfcatch type="any">
        <cfset result.message = cfcatch.message>
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="getPublishedPageBySlug" access="public" returntype="struct" output="false">
    <cfargument name="slug" type="string" required="true">

    <cfset var result = { success = false, message = "", found = false, isDraft = false, page = defaultPageRecord() }>
    <cfset var qPage = "">
    <cfset var safeSlug = normalizeSlug(arguments.slug)>
    <cfset var tableRef = "">

    <cfif NOT isReady()>
      <cfset result.message = "Pages datasource is not configured.">
      <cfreturn result>
    </cfif>

    <cfif NOT len(safeSlug)>
      <cfset result.success = true>
      <cfreturn result>
    </cfif>

    <cftry>
      <cfset tableRef = getQualifiedTableName()>
      <cfif NOT len(tableRef)>
        <cfset result.message = "PortalPages was not found in the configured datasource.">
        <cfreturn result>
      </cfif>

      <cfquery name="qPage" datasource="#variables.datasource#" maxrows="1">
        SELECT
          PageID,
          Slug,
          Title,
          NavLabel,
          Summary,
          BodyHtml,
          IsPublished,
          ShowInNav,
          NavSortOrder,
          CreatedBy,
          UpdatedBy,
          CreatedAt,
          UpdatedAt
        FROM #tableRef#
        WHERE Slug = <cfqueryparam value="#safeSlug#" cfsqltype="cf_sql_varchar">
      </cfquery>

      <cfif qPage.recordCount GT 0>
        <cfset result.page = {
          pageId = int(qPage.PageID[1]),
          slug = trim(qPage.Slug[1] & ""),
          title = trim(qPage.Title[1] & ""),
          navLabel = trim(qPage.NavLabel[1] & ""),
          summary = trim(qPage.Summary[1] & ""),
          bodyHtml = qPage.BodyHtml[1] & "",
          isPublished = qPage.IsPublished[1] EQ true OR val(qPage.IsPublished[1]) EQ 1,
          showInNav = qPage.ShowInNav[1] EQ true OR val(qPage.ShowInNav[1]) EQ 1,
          navSortOrder = int(val(qPage.NavSortOrder[1])),
          createdBy = int(val(qPage.CreatedBy[1])),
          updatedBy = int(val(qPage.UpdatedBy[1])),
          createdAt = qPage.CreatedAt[1],
          updatedAt = qPage.UpdatedAt[1]
        }>
        <cfset result.found = result.page.isPublished>
        <cfset result.isDraft = NOT result.page.isPublished>
      </cfif>

      <cfset result.success = true>
      <cfcatch type="any">
        <cfset result.message = cfcatch.message>
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="getPage" access="public" returntype="struct" output="false">
    <cfargument name="pageId" type="numeric" required="false" default="0">
    <cfargument name="slug" type="string" required="false" default="">

    <cfset var result = { success = false, message = "", found = false, page = defaultPageRecord() }>
    <cfset var qPage = "">
    <cfset var safeSlug = trim(arguments.slug & "")>
    <cfset var tableRef = "">

    <cfif NOT isReady()>
      <cfset result.message = "Pages datasource is not configured.">
      <cfreturn result>
    </cfif>

    <cfif int(val(arguments.pageId)) LTE 0 AND NOT len(safeSlug)>
      <cfset result.success = true>
      <cfreturn result>
    </cfif>

    <cftry>
      <cfset tableRef = getQualifiedTableName()>
      <cfif NOT len(tableRef)>
        <cfset result.message = "PortalPages was not found in the configured datasource.">
        <cfreturn result>
      </cfif>
      <cfquery name="qPage" datasource="#variables.datasource#" maxrows="1">
        SELECT
          PageID,
          Slug,
          Title,
          NavLabel,
          Summary,
          BodyHtml,
          IsPublished,
          ShowInNav,
          NavSortOrder,
          CreatedBy,
          UpdatedBy,
          CreatedAt,
          UpdatedAt
        FROM #tableRef#
        WHERE 1 = 1
        <cfif int(val(arguments.pageId)) GT 0>
          AND PageID = <cfqueryparam value="#int(val(arguments.pageId))#" cfsqltype="cf_sql_integer">
        <cfelse>
          AND Slug = <cfqueryparam value="#safeSlug#" cfsqltype="cf_sql_varchar">
        </cfif>
      </cfquery>

      <cfif qPage.recordCount GT 0>
        <cfset result.page = {
          pageId = int(qPage.PageID[1]),
          slug = trim(qPage.Slug[1] & ""),
          title = trim(qPage.Title[1] & ""),
          navLabel = trim(qPage.NavLabel[1] & ""),
          summary = trim(qPage.Summary[1] & ""),
          bodyHtml = qPage.BodyHtml[1] & "",
          isPublished = qPage.IsPublished[1] EQ true OR val(qPage.IsPublished[1]) EQ 1,
          showInNav = qPage.ShowInNav[1] EQ true OR val(qPage.ShowInNav[1]) EQ 1,
          navSortOrder = int(val(qPage.NavSortOrder[1])),
          createdBy = int(val(qPage.CreatedBy[1])),
          updatedBy = int(val(qPage.UpdatedBy[1])),
          createdAt = qPage.CreatedAt[1],
          updatedAt = qPage.UpdatedAt[1]
        }>
        <cfset result.found = true>
      </cfif>

      <cfset result.success = true>
      <cfcatch type="any">
        <cfset result.message = cfcatch.message>
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="savePage" access="public" returntype="struct" output="false">
    <cfargument name="pageData" type="struct" required="true">
    <cfargument name="actorUserId" type="numeric" required="false" default="0">

    <cfset var result = { success = false, message = "", pageId = 0, slug = "" }>
    <cfset var pageId = int(val(readStructNumber(arguments.pageData, "pageId", 0)))>
    <cfset var slug = normalizeSlug(readStructString(arguments.pageData, "slug", ""))>
    <cfset var title = trim(readStructString(arguments.pageData, "title", ""))>
    <cfset var navLabel = trim(readStructString(arguments.pageData, "navLabel", ""))>
    <cfset var summary = trim(readStructString(arguments.pageData, "summary", ""))>
    <cfset var bodyHtml = readStructString(arguments.pageData, "bodyHtml", "")>
    <cfset var isPublished = readStructBoolean(arguments.pageData, "isPublished", false)>
    <cfset var showInNav = readStructBoolean(arguments.pageData, "showInNav", false)>
    <cfset var navSortOrder = int(val(readStructNumber(arguments.pageData, "navSortOrder", 100)))>
    <cfset var actorUserIdValue = int(val(arguments.actorUserId))>
    <cfset var qExisting = "">
    <cfset var qSave = "">
    <cfset var qIdentity = "">
    <cfset var tableRef = "">

    <cfif NOT isReady()>
      <cfset result.message = "Pages datasource is not configured.">
      <cfreturn result>
    </cfif>

    <cfif NOT len(slug)>
      <cfset result.message = "Slug is required.">
      <cfreturn result>
    </cfif>

    <cfif NOT len(title)>
      <cfset result.message = "Title is required.">
      <cfreturn result>
    </cfif>

    <cftry>
      <cfset tableRef = getQualifiedTableName()>
      <cfif NOT len(tableRef)>
        <cfset result.message = "PortalPages was not found in the configured datasource.">
        <cfreturn result>
      </cfif>
      <cfquery name="qExisting" datasource="#variables.datasource#" maxrows="1">
        SELECT PageID
        FROM #tableRef#
        WHERE Slug = <cfqueryparam value="#slug#" cfsqltype="cf_sql_varchar">
        <cfif pageId GT 0>
          AND PageID <> <cfqueryparam value="#pageId#" cfsqltype="cf_sql_integer">
        </cfif>
      </cfquery>

      <cfif qExisting.recordCount GT 0>
        <cfset result.message = "That slug is already in use.">
        <cfreturn result>
      </cfif>

      <cfif pageId GT 0>
        <cfquery name="qSave" datasource="#variables.datasource#">
          UPDATE #tableRef#
          SET
            Slug = <cfqueryparam value="#slug#" cfsqltype="cf_sql_varchar">,
            Title = <cfqueryparam value="#left(title, 200)#" cfsqltype="cf_sql_nvarchar">,
            NavLabel = <cfqueryparam value="#left(navLabel, 120)#" cfsqltype="cf_sql_nvarchar" null="#NOT len(navLabel)#">,
            Summary = <cfqueryparam value="#left(summary, 500)#" cfsqltype="cf_sql_nvarchar" null="#NOT len(summary)#">,
            BodyHtml = <cfqueryparam value="#bodyHtml#" cfsqltype="cf_sql_nvarchar" null="#NOT len(bodyHtml)#">,
            IsPublished = <cfqueryparam value="#isPublished ? 1 : 0#" cfsqltype="cf_sql_bit">,
            ShowInNav = <cfqueryparam value="#showInNav ? 1 : 0#" cfsqltype="cf_sql_bit">,
            NavSortOrder = <cfqueryparam value="#navSortOrder#" cfsqltype="cf_sql_integer">,
            UpdatedBy = <cfqueryparam value="#actorUserIdValue#" cfsqltype="cf_sql_integer" null="#actorUserIdValue LTE 0#">,
            UpdatedAt = GETDATE()
          WHERE PageID = <cfqueryparam value="#pageId#" cfsqltype="cf_sql_integer">
        </cfquery>
        <cfset result.pageId = pageId>
      <cfelse>
        <cfquery name="qSave" datasource="#variables.datasource#">
          INSERT INTO #tableRef# (
            Slug,
            Title,
            NavLabel,
            Summary,
            BodyHtml,
            IsPublished,
            ShowInNav,
            NavSortOrder,
            CreatedBy,
            UpdatedBy,
            CreatedAt,
            UpdatedAt
          ) VALUES (
            <cfqueryparam value="#slug#" cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#left(title, 200)#" cfsqltype="cf_sql_nvarchar">,
            <cfqueryparam value="#left(navLabel, 120)#" cfsqltype="cf_sql_nvarchar" null="#NOT len(navLabel)#">,
            <cfqueryparam value="#left(summary, 500)#" cfsqltype="cf_sql_nvarchar" null="#NOT len(summary)#">,
            <cfqueryparam value="#bodyHtml#" cfsqltype="cf_sql_nvarchar" null="#NOT len(bodyHtml)#">,
            <cfqueryparam value="#isPublished ? 1 : 0#" cfsqltype="cf_sql_bit">,
            <cfqueryparam value="#showInNav ? 1 : 0#" cfsqltype="cf_sql_bit">,
            <cfqueryparam value="#navSortOrder#" cfsqltype="cf_sql_integer">,
            <cfqueryparam value="#actorUserIdValue#" cfsqltype="cf_sql_integer" null="#actorUserIdValue LTE 0#">,
            <cfqueryparam value="#actorUserIdValue#" cfsqltype="cf_sql_integer" null="#actorUserIdValue LTE 0#">,
            GETDATE(),
            GETDATE()
          )
        </cfquery>
        <cfquery name="qIdentity" datasource="#variables.datasource#" maxrows="1">
          SELECT TOP 1 PageID
          FROM #tableRef#
          WHERE Slug = <cfqueryparam value="#slug#" cfsqltype="cf_sql_varchar">
          ORDER BY PageID DESC
        </cfquery>
        <cfif qIdentity.recordCount GT 0>
          <cfset result.pageId = int(qIdentity.PageID[1])>
        </cfif>
      </cfif>

      <cfset result.slug = slug>
      <cfset result.success = true>
      <cfcatch type="any">
        <cfset result.message = cfcatch.message>
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="deletePage" access="public" returntype="struct" output="false">
    <cfargument name="pageId" type="numeric" required="true">

    <cfset var result = { success = false, message = "" }>
    <cfset var safePageId = int(val(arguments.pageId))>
    <cfset var qDelete = "">
    <cfset var tableRef = "">

    <cfif NOT isReady()>
      <cfset result.message = "Pages datasource is not configured.">
      <cfreturn result>
    </cfif>

    <cfif safePageId LTE 0>
      <cfset result.message = "A valid page ID is required.">
      <cfreturn result>
    </cfif>

    <cftry>
      <cfset tableRef = getQualifiedTableName()>
      <cfif NOT len(tableRef)>
        <cfset result.message = "PortalPages was not found in the configured datasource.">
        <cfreturn result>
      </cfif>
      <cfquery name="qDelete" datasource="#variables.datasource#">
        DELETE FROM #tableRef#
        WHERE PageID = <cfqueryparam value="#safePageId#" cfsqltype="cf_sql_integer">
      </cfquery>
      <cfset result.success = true>
      <cfcatch type="any">
        <cfset result.message = cfcatch.message>
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="defaultPageRecord" access="public" returntype="struct" output="false">
    <cfreturn {
      pageId = 0,
      slug = "",
      title = "",
      navLabel = "",
      summary = "",
      bodyHtml = "",
      isPublished = false,
      showInNav = false,
      navSortOrder = 100,
      createdBy = 0,
      updatedBy = 0,
      createdAt = "",
      updatedAt = ""
    }>
  </cffunction>

  <cffunction name="normalizeSlug" access="private" returntype="string" output="false">
    <cfargument name="rawSlug" type="string" required="true">

    <cfset var slug = lCase(trim(arguments.rawSlug & ""))>
    <cfset slug = reReplace(slug, "[^a-z0-9\-/]+", "-", "all")>
    <cfset slug = reReplace(slug, "-{2,}", "-", "all")>
    <cfset slug = reReplace(slug, "(^[-/]+|[-/]+$)", "", "all")>
    <cfreturn left(slug, 120)>
  </cffunction>

  <cffunction name="readStructString" access="private" returntype="string" output="false">
    <cfargument name="source" type="struct" required="true">
    <cfargument name="keyName" type="string" required="true">
    <cfargument name="defaultValue" type="string" required="false" default="">

    <cfset var valueOut = arguments.defaultValue>
    <cfif structKeyExists(arguments.source, arguments.keyName)>
      <cfset valueOut = arguments.source[arguments.keyName]>
      <cfif NOT isSimpleValue(valueOut)>
        <cfset valueOut = serializeJSON(valueOut)>
      </cfif>
    </cfif>
    <cfreturn valueOut & "">
  </cffunction>

  <cffunction name="readStructBoolean" access="private" returntype="boolean" output="false">
    <cfargument name="source" type="struct" required="true">
    <cfargument name="keyName" type="string" required="true">
    <cfargument name="defaultValue" type="boolean" required="false" default="false">

    <cfset var rawValue = arguments.defaultValue>
    <cfif structKeyExists(arguments.source, arguments.keyName)>
      <cfset rawValue = arguments.source[arguments.keyName]>
    </cfif>

    <cfif isBoolean(rawValue)>
      <cfreturn rawValue>
    </cfif>

    <cfreturn listFindNoCase("1,true,yes,on", trim(rawValue & "")) GT 0>
  </cffunction>

  <cffunction name="readStructNumber" access="private" returntype="numeric" output="false">
    <cfargument name="source" type="struct" required="true">
    <cfargument name="keyName" type="string" required="true">
    <cfargument name="defaultValue" type="numeric" required="false" default="0">

    <cfif structKeyExists(arguments.source, arguments.keyName) AND isNumeric(arguments.source[arguments.keyName])>
      <cfreturn val(arguments.source[arguments.keyName])>
    </cfif>

    <cfreturn arguments.defaultValue>
  </cffunction>

  <cffunction name="getQualifiedTableName" access="private" returntype="string" output="false">
    <cfset var qTable = "">
    <cfset var qProbe = "">
    <cfset var qualifiedName = trim(variables.qualifiedTableName & "")>
    <cfset var candidateNames = ["[dbo].[#variables.tableName#]", "[#variables.tableName#]"]>
    <cfset var candidateName = "">

    <cfif len(qualifiedName)>
      <cfreturn qualifiedName>
    </cfif>

    <cftry>
      <cfloop array="#candidateNames#" index="candidateName">
        <cftry>
          <cfquery name="qProbe" datasource="#variables.datasource#" maxrows="1">
            SELECT TOP 1 PageID
            FROM #candidateName#
          </cfquery>
          <cfset variables.qualifiedTableName = candidateName>
          <cfreturn candidateName>
          <cfcatch type="any"></cfcatch>
        </cftry>
      </cfloop>

      <cfquery name="qTable" datasource="#variables.datasource#" maxrows="1">
        SELECT TOP 1
          s.name AS schema_name,
          t.name AS table_name
        FROM sys.tables t
        INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE t.name = <cfqueryparam value="#variables.tableName#" cfsqltype="cf_sql_varchar">
        ORDER BY CASE WHEN s.name = 'dbo' THEN 0 ELSE 1 END, s.name
      </cfquery>

      <cfif qTable.recordCount GT 0>
        <cfset qualifiedName = "[" & qTable.schema_name[1] & "].[" & qTable.table_name[1] & "]">
      <cfelse>
        <cfreturn "">
      </cfif>

      <cfquery name="qProbe" datasource="#variables.datasource#" maxrows="1">
        SELECT TOP 1 PageID
        FROM #qualifiedName#
      </cfquery>

      <cfset variables.qualifiedTableName = qualifiedName>
      <cfcatch type="any">
        <cfreturn "">
      </cfcatch>
    </cftry>

    <cfreturn qualifiedName>
  </cffunction>

</cfcomponent>