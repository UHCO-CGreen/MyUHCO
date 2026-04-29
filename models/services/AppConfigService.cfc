<cfcomponent displayname="AppConfigService" output="false">

  <cffunction name="init" access="public" returntype="any" output="false">
    <cfargument name="datasource" type="string" required="false" default="UHCO_identity">
    <cfargument name="tableName" type="string" required="false" default="app_config">
    <cfargument name="keyColumn" type="string" required="false" default="config_key">
    <cfargument name="valueColumn" type="string" required="false" default="config_value">
    <cfargument name="appColumn" type="string" required="false" default="app_name">
    <cfargument name="appName" type="string" required="false" default="myUHCO">

    <cfset variables.datasource = trim(arguments.datasource & "")>
    <cfset variables.tableName = trim(arguments.tableName & "")>
    <cfset variables.keyColumn = trim(arguments.keyColumn & "")>
    <cfset variables.valueColumn = trim(arguments.valueColumn & "")>
    <cfset variables.appColumn = trim(arguments.appColumn & "")>
    <cfset variables.appName = trim(arguments.appName & "")>
    <cfset variables.cache = {}>
    <cfreturn this>
  </cffunction>

  <cffunction name="getValue" access="public" returntype="string" output="false">
    <cfargument name="keyName" type="string" required="true">
    <cfargument name="defaultValue" type="string" required="false" default="">

    <cfset var key = lCase(trim(arguments.keyName & ""))>
    <cfset var valueOut = trim(arguments.defaultValue & "")>
    <cfset var qConfig = "">
    <cfset var qConfigFallback = "">
    <cfset var sql = "">
    <cfset var sqlFallback = "">
    <cfset var keyAlt = lCase(replace(key, ".", "_", "all"))>
    <cfset var keyUpper = uCase(key)>
    <cfset var keyAltUpper = uCase(keyAlt)>
    <cfset var keyList = "">
    <cfset var lookedUp = false>
    <cfset var tableCandidates = [variables.tableName, "AppConfig", "app_config"]>
    <cfset var keyCandidates = [variables.keyColumn, "config_key", "key_name", "name", "[key]"]>
    <cfset var valueCandidates = [variables.valueColumn, "config_value", "key_value", "value", "[value]"]>
    <cfset var appCandidates = []>
    <cfset var t = "">
    <cfset var kCol = "">
    <cfset var vCol = "">
    <cfset var aCol = "">
    <cfset var sqlVariant = "">
    <cfset var qVariant = "">
    <cfset var qAll = "">
    <cfset var i = 0>
    <cfset var rawKey = "">
    <cfset var rawValue = "">
    <cfset var keyCanonical = canonicalizeKey(key)>
    <cfset var rawCanonical = "">

    <cfif NOT len(key)>
      <cfreturn valueOut>
    </cfif>

    <cfif structKeyExists(variables.cache, key)>
      <cfreturn variables.cache[key]>
    </cfif>

    <cfif NOT len(variables.datasource) OR NOT len(variables.tableName)>
      <cfreturn valueOut>
    </cfif>

    <cfif keyAlt EQ key>
      <cfset keyList = key & "," & keyUpper>
    <cfelse>
      <cfset keyList = key & "," & keyUpper & "," & keyAlt & "," & keyAltUpper>
    </cfif>

    <cfset sql = "SELECT #variables.valueColumn# AS config_value FROM #variables.tableName# WHERE #variables.keyColumn# IN (?)">
    <cfif len(variables.appName) AND len(variables.appColumn)>
      <cfset sql &= " AND (#variables.appColumn# = ? OR #variables.appColumn# = ? OR #variables.appColumn# IS NULL OR #variables.appColumn# = '')">
      <cfset sql &= " ORDER BY CASE WHEN #variables.appColumn# = ? OR #variables.appColumn# = ? THEN 0 ELSE 1 END">
    </cfif>

    <cftry>
      <cfquery name="qConfig" datasource="#variables.datasource#">
        #preserveSingleQuotes(sql)#
        <cfqueryparam cfsqltype="cf_sql_varchar" value="#keyList#" list="true">
        <cfif len(variables.appName) AND len(variables.appColumn)>
          <cfqueryparam cfsqltype="cf_sql_varchar" value="#variables.appName#">
          <cfqueryparam cfsqltype="cf_sql_varchar" value="#uCase(variables.appName)#">
          <cfqueryparam cfsqltype="cf_sql_varchar" value="#variables.appName#">
          <cfqueryparam cfsqltype="cf_sql_varchar" value="#uCase(variables.appName)#">
        </cfif>
      </cfquery>

      <cfif qConfig.recordCount GT 0>
        <cfset valueOut = trim(qConfig.config_value[1] & "")>
        <cfset lookedUp = true>
      </cfif>

      <cfcatch type="any">
        <cflog file="myuhco-api" type="warning" text="AppConfigService primary lookup failed for key #arguments.keyName#: #cfcatch.message#">
      </cfcatch>
    </cftry>

    <!--- Fallback for existing UHCO Identity schemas that use AppConfig without app scoping. --->
    <cfif NOT lookedUp AND NOT len(valueOut)>
      <cfset sqlFallback = "SELECT #variables.valueColumn# AS config_value FROM AppConfig WHERE #variables.keyColumn# IN (?)">
      <cftry>
        <cfquery name="qConfigFallback" datasource="#variables.datasource#">
          #preserveSingleQuotes(sqlFallback)#
          <cfqueryparam cfsqltype="cf_sql_varchar" value="#keyList#" list="true">
        </cfquery>
        <cfif qConfigFallback.recordCount GT 0>
          <cfset valueOut = trim(qConfigFallback.config_value[1] & "")>
          <cfset lookedUp = true>
        </cfif>
        <cfcatch type="any">
          <cflog file="myuhco-api" type="warning" text="AppConfigService fallback lookup failed for key #arguments.keyName#: #cfcatch.message#">
        </cfcatch>
      </cftry>
    </cfif>

    <!--- Broad fallback for legacy schemas/column names. --->
    <cfif NOT lookedUp AND NOT len(valueOut)>
      <cfset appCandidates = len(variables.appColumn) ? [variables.appColumn, "app_name", "application", "app", "context"] : [""]>
      <cfloop array="#tableCandidates#" index="t">
        <cfif lookedUp><cfbreak></cfif>
        <cfloop array="#keyCandidates#" index="kCol">
          <cfif lookedUp><cfbreak></cfif>
          <cfloop array="#valueCandidates#" index="vCol">
            <cfif lookedUp><cfbreak></cfif>
            <cfloop array="#appCandidates#" index="aCol">
              <cfif lookedUp><cfbreak></cfif>
              <cfset sqlVariant = "SELECT #vCol# AS config_value FROM #t# WHERE #kCol# IN (?)">
              <cfif len(variables.appName) AND len(aCol)>
                <cfset sqlVariant &= " AND (#aCol# = ? OR #aCol# = ? OR #aCol# IS NULL OR #aCol# = '')">
              </cfif>
              <cftry>
                <cfquery name="qVariant" datasource="#variables.datasource#">
                  #preserveSingleQuotes(sqlVariant)#
                  <cfqueryparam cfsqltype="cf_sql_varchar" value="#keyList#" list="true">
                  <cfif len(variables.appName) AND len(aCol)>
                    <cfqueryparam cfsqltype="cf_sql_varchar" value="#variables.appName#">
                    <cfqueryparam cfsqltype="cf_sql_varchar" value="#uCase(variables.appName)#">
                  </cfif>
                </cfquery>
                <cfif qVariant.recordCount GT 0>
                  <cfset valueOut = trim(qVariant.config_value[1] & "")>
                  <cfset lookedUp = true>
                </cfif>
                <cfcatch type="any"></cfcatch>
              </cftry>
            </cfloop>
          </cfloop>
        </cfloop>
      </cfloop>
    </cfif>

    <!--- Last-resort fallback: load rows and match key in CFML (handles collation/type quirks). --->
    <cfif NOT lookedUp AND NOT len(valueOut)>
      <cfloop array="#tableCandidates#" index="t">
        <cfif lookedUp><cfbreak></cfif>
        <cfloop array="#keyCandidates#" index="kCol">
          <cfif lookedUp><cfbreak></cfif>
          <cfloop array="#valueCandidates#" index="vCol">
            <cfif lookedUp><cfbreak></cfif>
            <cftry>
              <cfquery name="qAll" datasource="#variables.datasource#" maxrows="5000">
                SELECT #kCol# AS cfg_key, #vCol# AS cfg_value
                FROM #t#
              </cfquery>
              <cfloop from="1" to="#qAll.recordCount#" index="i">
                <cfset rawKey = trim(qAll.cfg_key[i] & "")>
                <cfset rawCanonical = canonicalizeKey(rawKey)>
                <cfif rawCanonical EQ keyCanonical>
                  <cfset rawValue = trim(qAll.cfg_value[i] & "")>
                  <cfif len(rawValue)>
                    <cfset valueOut = rawValue>
                    <cfset lookedUp = true>
                    <cfbreak>
                  </cfif>
                </cfif>
              </cfloop>
              <cfcatch type="any"></cfcatch>
            </cftry>
          </cfloop>
        </cfloop>
      </cfloop>
    </cfif>

    <cfif len(valueOut)>
      <cfset variables.cache[key] = valueOut>
    </cfif>
    <cfreturn valueOut>
  </cffunction>

  <cffunction name="clearCache" access="public" returntype="void" output="false">
    <cfset variables.cache = {}>
  </cffunction>

  <cffunction name="canonicalizeKey" access="private" returntype="string" output="false">
    <cfargument name="keyName" type="string" required="true">

    <cfset var outKey = lCase(trim(arguments.keyName & ""))>
    <cfset outKey = replace(outKey, "_", ".", "all")>
    <cfset outKey = reReplace(outKey, "\s+", "", "all")>
    <cfreturn outKey>
  </cffunction>

</cfcomponent>