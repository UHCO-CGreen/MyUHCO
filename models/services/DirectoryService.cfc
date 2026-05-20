<cfcomponent displayname="DirectoryService" output="false">

  <cffunction name="getBuildSignature" access="public" returntype="string" output="false">
    <cfreturn "2026-05-19-directory-api-header-auth-v1">
  </cffunction>

  <cffunction name="init" access="public" returntype="any" output="false">
    <cfargument name="peopleApiUrl" type="string" required="false" default="">
    <cfset variables.peopleApiUrl = trim(arguments.peopleApiUrl & "")>
    <cfreturn this>
  </cffunction>

  <cffunction name="getDirectoryGroups" access="public" returntype="struct" output="false">
    <cfargument name="currentUser" type="struct" required="false" default="#structNew()#">

    <cfset var result = {
      success = false,
      message = "",
      source = "",
      groups = {
        faculty = [],
        staff = [],
        students = [],
        alumni = []
      },
      debug = {}
    }>
    <cfset var groupNames = ["faculty", "staff", "students", "alumni"]>
    <cfset var i = 0>
    <cfset var groupResult = {}>
    <cfset var successCount = 0>

    <cfloop from="1" to="#arrayLen(groupNames)#" index="i">
      <cfset groupResult = getDirectoryGroup(groupNames[i], arguments.currentUser)>
      <cfset result.groups[groupNames[i]] = groupResult.items>
      <cfset result.debug[groupNames[i]] = groupResult.debug>
      <cfif groupResult.success>
        <cfset successCount = successCount + 1>
      </cfif>
    </cfloop>

    <cfif successCount GT 0>
      <cfset result.success = true>
      <cfset result.source = "people-api-flag-endpoints">
      <cfif successCount LT arrayLen(groupNames)>
        <cfset result.message = "Directory partially loaded. One or more role endpoints were unavailable.">
      </cfif>
    <cfelse>
      <cfset result.message = "Directory load failed.">
    </cfif>

    <cfreturn result>
  </cffunction>

  <cffunction name="getDirectoryGroup" access="public" returntype="struct" output="false">
    <cfargument name="groupKey" type="string" required="true">
    <cfargument name="currentUser" type="struct" required="false" default="#structNew()#">
    <cfargument name="gradYear" type="string" required="false" default="">

    <cfset var result = {
      success = false,
      message = "",
      group = lCase(trim(arguments.groupKey & "")),
      source = "",
      items = [],
      debug = []
    }>
    <cfset var apiBaseUrl = resolveApiBaseUrl()>
    <cfset var flags = getFlagsForGroup(result.group)>
    <cfset var requestedGradYear = trim(arguments.gradYear & "")>
    <cfset var effectiveGradYear = "">
    <cfset var i = 0>
    <cfset var fetchResult = {}>
    <cfset var successCount = 0>
    <cfset var sawUnauthorized = false>

    <cfif NOT arrayLen(flags)>
      <cfset result.message = "Unknown directory group.">
      <cfreturn result>
    </cfif>

    <cfif NOT len(apiBaseUrl)>
      <cfset apiBaseUrl = "http://127.0.0.1/api/v1">
      <cflog file="myuhco-api" type="warning" text="DirectoryService base URL resolved empty; using localhost fallback.">
    </cfif>

    <cfif listFindNoCase("students,alumni", result.group) AND len(requestedGradYear)>
      <cfset effectiveGradYear = requestedGradYear>
    </cfif>

    <cfloop from="1" to="#arrayLen(flags)#" index="i">
      <cfset fetchResult = fetchPeopleByFlag(apiBaseUrl, flags[i], effectiveGradYear)>
      <cfset arrayAppend(result.debug, {
        flag = flags[i],
        success = fetchResult.success,
        statusCode = fetchResult.statusCode,
        count = arrayLen(fetchResult.people),
        requestUrl = fetchResult.requestUrl,
        tokenPresent = fetchResult.tokenPresent,
        secretPresent = fetchResult.secretPresent,
        rawKeys = fetchResult.rawKeys,
        error = fetchResult.errorMessage
      })>

      <cfif fetchResult.success>
        <cfset successCount = successCount + 1>
        <cfset result.items = appendUniquePeople(result.items, fetchResult.people)>
      <cfelseif left(fetchResult.statusCode, 3) EQ "401">
        <cfset sawUnauthorized = true>
      </cfif>
    </cfloop>

    <cfif successCount GT 0>
      <cfset result.success = true>
      <cfset result.source = "people-api-flag-endpoints">
      <cfif arrayLen(result.items) EQ 0>
        <cfset result.message = "No members returned for #result.group#.">
      </cfif>
    <cfelseif sawUnauthorized>
      <cfset result.message = "Directory API authorization failed for #result.group#. Check MYUHCO_API_TOKEN and MYUHCO_API_SECRET for the configured identity API.">
    <cfelse>
      <cfset result.message = "Directory endpoint(s) failed for #result.group#.">
    </cfif>

    <cfreturn result>
  </cffunction>

  <cffunction name="getFlagsForGroup" access="private" returntype="array" output="false">
    <cfargument name="groupKey" type="string" required="true">

    <cfset var groupName = lCase(trim(arguments.groupKey & ""))>

    <cfif groupName EQ "faculty">
      <cfreturn ["faculty-adjunct", "faculty-fulltime"]>
    <cfelseif groupName EQ "staff">
      <cfreturn ["Staff"]>
    <cfelseif groupName EQ "students">
      <cfreturn ["Current-Student"]>
    <cfelseif groupName EQ "alumni">
      <cfreturn ["Alumni"]>
    </cfif>

    <cfreturn []>
  </cffunction>

  <cffunction name="resolveApiBaseUrl" access="private" returntype="string" output="false">
    <cfset var apiBaseUrl = "">

    <cfif len(trim(variables.peopleApiUrl & ""))>
      <cfset apiBaseUrl = trim(variables.peopleApiUrl & "")>
    <cfelseif structKeyExists(application, "MYUHCO_API_URL") AND len(trim(application.MYUHCO_API_URL & ""))>
      <cfset apiBaseUrl = trim(application.MYUHCO_API_URL & "")>
    <cfelse>
      <cfset apiBaseUrl = "http://127.0.0.1/api/v1">
    </cfif>

    <cfset apiBaseUrl = reReplace(apiBaseUrl, "/+$", "", "all")>
    <cfset apiBaseUrl = reReplaceNoCase(apiBaseUrl, "/people$", "", "all")>

    <cfreturn apiBaseUrl>
  </cffunction>

  <cffunction name="fetchPeopleByFlag" access="private" returntype="struct" output="false">
    <cfargument name="apiBaseUrl" type="string" required="true">
    <cfargument name="flagValue" type="string" required="true">
    <cfargument name="gradYear" type="string" required="false" default="">

    <cfset var result = {
      success = false,
      people = [],
      statusCode = "",
      errorMessage = "",
      requestUrl = "",
      tokenPresent = false,
      secretPresent = false,
      rawKeys = []
    }>
    <cfset var endpointUrl = arguments.apiBaseUrl & "/people/">
    <cfset var httpResponse = {}>
    <cfset var payload = "">
    <cfset var parsed = "">
    <cfset var apiToken = "">
    <cfset var apiSecret = "">
    <cfset var requestedGradYear = trim(arguments.gradYear & "")>

    <cfset result.requestUrl = endpointUrl & "?flag=" & urlEncodedFormat(arguments.flagValue)>
    <cfif len(requestedGradYear)>
      <cfset result.requestUrl = result.requestUrl & "&gradyear=" & urlEncodedFormat(requestedGradYear)>
    </cfif>
    <cfset apiToken = resolveApiCredential("MYUHCO_API_TOKEN")>
    <cfset apiSecret = resolveApiCredential("MYUHCO_API_SECRET")>
    <cfset result.tokenPresent = len(apiToken) GT 0>
    <cfset result.secretPresent = len(apiSecret) GT 0>

    <cftry>
      <cfhttp method="get" url="#endpointUrl#" result="httpResponse" timeout="12" throwOnError="false">
        <cfif len(apiToken)>
          <cfhttpparam type="header" name="Authorization" value="Bearer #apiToken#">
        </cfif>
        <cfif len(apiSecret)>
          <cfhttpparam type="header" name="X-API-Secret" value="#apiSecret#">
        </cfif>
        <cfhttpparam type="url" name="flag" value="#arguments.flagValue#">
        <cfif len(requestedGradYear)>
          <cfhttpparam type="url" name="gradyear" value="#requestedGradYear#">
        </cfif>
        <cfhttpparam type="url" name="limit" value="200">
      </cfhttp>

      <cfset result.statusCode = trim(httpResponse.statusCode & "")>

      <cfif NOT findNoCase("200", httpResponse.statusCode)>
        <cfif left(result.statusCode, 3) EQ "401">
          <cfset result.errorMessage = "Unauthorized response from people API. Check MYUHCO_API_TOKEN and MYUHCO_API_SECRET.">
        <cfelse>
          <cfset result.errorMessage = "Non-200 status returned.">
        </cfif>
        <cflog file="myuhco-api" type="warning" text="DirectoryService non-200 for flag #arguments.flagValue#: #httpResponse.statusCode#">
        <cfreturn result>
      </cfif>

      <cfset payload = trim(httpResponse.fileContent & "")>
      <cfif NOT len(payload)>
        <cfset result.success = true>
        <cfreturn result>
      </cfif>

      <cfset parsed = deserializeJSON(payload)>
      <cfset result.people = normalizePeoplePayload(parsed)>
      <cfset result.rawKeys = getRawKeys(parsed)>
      <cfset result.success = true>

      <cfcatch type="any">
        <cfset result.errorMessage = cfcatch.message>
        <cflog file="myuhco-api" type="warning" text="DirectoryService error for flag #arguments.flagValue#: #cfcatch.message#">
      </cfcatch>
    </cftry>

    <cfreturn result>
  </cffunction>

  <cffunction name="resolveApiCredential" access="private" returntype="string" output="false">
    <cfargument name="keyName" type="string" required="true">

    <cfset var keyNameNormalized = trim(arguments.keyName & "")>
    <cfset var valueOut = "">
    <cfset var env = {}>
    <cfset var envKey = "">

    <cfif structKeyExists(application, keyNameNormalized) AND len(trim(application[keyNameNormalized] & ""))>
      <cfset valueOut = trim(application[keyNameNormalized] & "")>
      <cfreturn valueOut>
    </cfif>

    <cftry>
      <cfset env = getSystemEnvironment()>
      <cfif structKeyExists(env, keyNameNormalized)>
        <cfset valueOut = trim(env[keyNameNormalized] & "")>
      <cfelse>
        <cfloop collection="#env#" item="envKey">
          <cfif compareNoCase(envKey, keyNameNormalized) EQ 0>
            <cfset valueOut = trim(env[envKey] & "")>
            <cfbreak>
          </cfif>
        </cfloop>
      </cfif>
      <cfcatch type="any">
        <cfset valueOut = "">
      </cfcatch>
    </cftry>

    <cfif NOT len(valueOut)>
      <cftry>
        <cfset valueOut = trim(createObject("java", "java.lang.System").getenv(keyNameNormalized) & "")>
        <cfcatch type="any">
          <cfset valueOut = "">
        </cfcatch>
      </cftry>
    </cfif>

    <cfif len(valueOut)>
      <cfset application[keyNameNormalized] = valueOut>
    </cfif>

    <cfreturn valueOut>
  </cffunction>

  <cffunction name="appendUniquePeople" access="private" returntype="array" output="false">
    <cfargument name="targetArray" type="array" required="true">
    <cfargument name="incomingArray" type="array" required="true">

    <cfset var i = 0>
    <cfset var j = 0>
    <cfset var candidate = {}>
    <cfset var candidateKey = "">
    <cfset var existingKey = "">
    <cfset var existsAlready = false>

    <cfloop from="1" to="#arrayLen(arguments.incomingArray)#" index="i">
      <cfif isStruct(arguments.incomingArray[i])>
        <cfset candidate = arguments.incomingArray[i]>
        <cfset candidateKey = lCase(trim(candidate.userId & ""))>
        <cfif NOT len(candidateKey)>
          <cfset candidateKey = lCase(trim(candidate.username & ""))>
        </cfif>

        <cfset existsAlready = false>
        <cfloop from="1" to="#arrayLen(arguments.targetArray)#" index="j">
          <cfset existingKey = lCase(trim(arguments.targetArray[j].userId & ""))>
          <cfif NOT len(existingKey)>
            <cfset existingKey = lCase(trim(arguments.targetArray[j].username & ""))>
          </cfif>
          <cfif len(candidateKey) AND candidateKey EQ existingKey>
            <cfset existsAlready = true>
            <cfbreak>
          </cfif>
        </cfloop>

        <cfif NOT existsAlready>
          <cfset arrayAppend(arguments.targetArray, candidate)>
        </cfif>
      </cfif>
    </cfloop>

    <cfreturn arguments.targetArray>
  </cffunction>

  <cffunction name="normalizePeoplePayload" access="private" returntype="array" output="false">
    <cfargument name="payload" type="any" required="true">

    <cfset var items = []>
    <cfset var item = "">
    <cfset var payloadKey = "">

    <cfif isArray(arguments.payload)>
      <cfset items = arguments.payload>
    <cfelseif isStruct(arguments.payload)>
      <cfloop collection="#arguments.payload#" item="payloadKey">
        <cfif listFindNoCase("items,data,result,people", payloadKey) AND isArray(arguments.payload[payloadKey])>
          <cfset items = arguments.payload[payloadKey]>
          <cfbreak>
        </cfif>
      </cfloop>
      <cfif NOT arrayLen(items)>
        <cfset arrayAppend(items, arguments.payload)>
      </cfif>
    </cfif>

    <cfset var normalized = []>
    <cfset var i = 0>
    <cfset var person = {}>
    <cfset var record = {}>
    <cfset var keyName = "">
    <cfset var valueData = "">
    <cfset var namesValue = "">
    <cfset var parsedNames = []>
    <cfset var nameObj = {}>
    <cfset var nameIndex = 0>


    <cfloop from="1" to="#arrayLen(items)#" index="i">
      <cfif isStruct(items[i])>
        <cfset record = items[i]>
        <cfset person = {
          userId = "",
          username = "",
          displayName = "",
          fullName = "",
          email = "",
          emailPrimary = "",
          phone = "",
          title = "",
          title1 = "",
          combinedDegrees = "",
          degrees = "",
          address = "",
          facultyType = "",
          department = "",
          flags = "",
          organizations = "",
          webThumbUrl = "",
          currentGradYear = "",
          program = "",
          roleGroup = ""
        }>

        <!--- Pass all raw fields through so no data is silently dropped --->
        <cfloop collection="#record#" item="keyName">
          <cfset valueData = record[keyName]>
          <cfif NOT isSimpleValue(valueData)>
            <cfset valueData = serializeJSON(valueData)>
          </cfif>
          <cfset person[lCase(keyName)] = trim(valueData & "")>
        </cfloop>

        <!--- Handle mixed-case names data whether it arrives as an array or a JSON string. --->
        <cfset namesValue = "">
        <cfset parsedNames = []>
        <cfset nameObj = {}>
        <cfloop collection="#record#" item="keyName">
          <cfif compareNoCase(keyName, "NAMES") EQ 0>
            <cfset namesValue = record[keyName]>
            <cfbreak>
          </cfif>
        </cfloop>

        <cfif isArray(namesValue)>
          <cfset parsedNames = namesValue>
        <cfelseif isSimpleValue(namesValue) AND len(trim(namesValue & ""))>
          <cftry>
            <cfset parsedNames = deserializeJSON(trim(namesValue & ""))>
            <cfcatch type="any">
              <cfset parsedNames = []>
            </cfcatch>
          </cftry>
        </cfif>

        <cfif isArray(parsedNames) AND arrayLen(parsedNames)>
          <cfset nameIndex = 1>
          <cfloop from="1" to="#arrayLen(parsedNames)#" index="nameIndex">
            <cfif isStruct(parsedNames[nameIndex]) AND structKeyExists(parsedNames[nameIndex], "PRIMARY") AND parsedNames[nameIndex].PRIMARY>
              <cfset nameObj = parsedNames[nameIndex]>
              <cfbreak>
            </cfif>
          </cfloop>
          <cfif NOT structCount(nameObj) AND isStruct(parsedNames[1])>
            <cfset nameObj = parsedNames[1]>
          </cfif>

          <cfif structCount(nameObj)>
            <cfif structKeyExists(nameObj, "FULL") AND len(trim(nameObj.FULL & ""))>
              <cfset person.displayName = trim(nameObj.FULL & "")>
              <cfset person.fullName = trim(nameObj.FULL & "")>
            <cfelse>
              <cfset person.displayName = trim((nameObj.FIRST & " " & nameObj.LAST))>
              <cfset person.fullName = person.displayName>
            </cfif>
          </cfif>
        </cfif>

        <!--- Alias mapping: normalise known API field name variants (fallbacks) --->
        <cfloop collection="#record#" item="keyName">
          <cfset valueData = record[keyName]>
          <cfif NOT isSimpleValue(valueData)>
            <cfset valueData = serializeJSON(valueData)>
          </cfif>
          <cfset valueData = trim(valueData & "")>

          <cfif compareNoCase(keyName, "USERID") EQ 0 OR compareNoCase(keyName, "userId") EQ 0 OR compareNoCase(keyName, "id") EQ 0>
            <cfset person.userId = valueData>
          <cfelseif compareNoCase(keyName, "USERNAME") EQ 0 OR compareNoCase(keyName, "sAMAccountName") EQ 0 OR compareNoCase(keyName, "login") EQ 0 OR compareNoCase(keyName, "user_name") EQ 0>
            <cfset person.username = valueData>
          <cfelseif compareNoCase(keyName, "MAIL") EQ 0 OR compareNoCase(keyName, "EMAIL") EQ 0 OR compareNoCase(keyName, "email_address") EQ 0 OR compareNoCase(keyName, "emailAddress") EQ 0 OR compareNoCase(keyName, "emailPrimary") EQ 0 OR compareNoCase(keyName, "email_primary") EQ 0>
            <cfset person.emailPrimary = valueData>
            <cfset person.email = valueData>
          <cfelseif compareNoCase(keyName, "PRIMARYEMAIL") EQ 0 OR compareNoCase(keyName, "PRIMARY_EMAIL") EQ 0>
            <cfset valueData = extractPreferredArrayValue(record[keyName], ["EMAILADDRESS", "EMAIL_ADDRESS", "EMAIL", "ADDRESS", "VALUE", "TEXT", "DISPLAY", "FULL"])>
            <cfif len(valueData)>
              <cfset person.emailPrimary = valueData>
              <cfset person.email = valueData>
            </cfif>
          <cfelseif compareNoCase(keyName, "PRIMARYPHONE") EQ 0 OR compareNoCase(keyName, "PRIMARY_PHONE") EQ 0>
            <cfset valueData = extractPreferredArrayValue(record[keyName], ["FORMATTEDNUMBER", "FORMATTED_PHONE", "NUMBER", "PHONE", "PHONE_NUMBER", "PHONENUMBER", "VALUE", "TEXT", "DISPLAY", "FULL"] )>
            <cfif len(valueData)><cfset person.phone = valueData></cfif>
          <cfelseif compareNoCase(keyName, "TITLE") EQ 0 OR compareNoCase(keyName, "job_title") EQ 0 OR compareNoCase(keyName, "jobTitle") EQ 0>
            <cfset person.title = valueData>
          <cfelseif compareNoCase(keyName, "DEPARTMENT") EQ 0 OR compareNoCase(keyName, "dept") EQ 0>
            <cfset person.department = valueData>
          <cfelseif compareNoCase(keyName, "ADDRESSES") EQ 0>
            <cfset valueData = extractPreferredArrayValue(record[keyName], ["FORMATTED", "ADDRESS", "ADDRESS1", "LINE1", "FULL"] )>
            <cfif len(valueData) AND NOT len(person.address)><cfset person.address = valueData></cfif>
          <cfelseif compareNoCase(keyName, "FLAGS") EQ 0 OR compareNoCase(keyName, "flag") EQ 0 OR compareNoCase(keyName, "roles") EQ 0>
            <cfset person.flags = valueData>
          <cfelseif compareNoCase(keyName, "ORGANIZATIONS") EQ 0 OR compareNoCase(keyName, "organization") EQ 0 OR compareNoCase(keyName, "org") EQ 0>
            <cfset person.organizations = valueData>
          <cfelseif compareNoCase(keyName, "DISPLAYNAME") EQ 0 OR compareNoCase(keyName, "display_name") EQ 0>
            <cfif NOT len(person.displayName)><cfset person.displayName = valueData></cfif>
          <cfelseif compareNoCase(keyName, "EMAILPRIMARY") EQ 0 OR compareNoCase(keyName, "email_primary") EQ 0>
            <cfif NOT len(person.emailPrimary)><cfset person.emailPrimary = valueData></cfif>
            <cfif NOT len(person.email)><cfset person.email = valueData></cfif>
          <cfelseif compareNoCase(keyName, "COMBINEDDEGREES") EQ 0 OR compareNoCase(keyName, "COMBINED_DEGREES") EQ 0>
            <cfset person.combinedDegrees = valueData>
            <cfif len(valueData)><cfset person.degrees = valueData></cfif>
          <cfelseif compareNoCase(keyName, "FULLNAME") EQ 0 OR compareNoCase(keyName, "full_name") EQ 0>
            <cfif NOT len(person.displayName)><cfset person.displayName = valueData></cfif>
            <cfif NOT len(person.fullName)><cfset person.fullName = valueData></cfif>
          <cfelseif compareNoCase(keyName, "PHONE") EQ 0 OR compareNoCase(keyName, "TELEPHONENUMBER") EQ 0 OR compareNoCase(keyName, "TELEPHONE") EQ 0 OR compareNoCase(keyName, "PHONENUMBER") EQ 0>
            <cfset person.phone = valueData>
          <cfelseif compareNoCase(keyName, "WEBTHUMBIMAGE") EQ 0 OR compareNoCase(keyName, "WEBTHUMBURL") EQ 0 OR compareNoCase(keyName, "THUMBURL") EQ 0 OR compareNoCase(keyName, "THUMBNAIL") EQ 0>
            <cfset person.webThumbUrl = valueData>
          <cfelseif compareNoCase(keyName, "CURRENTGRADYEAR") EQ 0 OR compareNoCase(keyName, "GRADYEAR") EQ 0 OR compareNoCase(keyName, "GRAD_YEAR") EQ 0>
            <cfset person.currentGradYear = valueData>
          <cfelseif compareNoCase(keyName, "DEGREES") EQ 0 OR compareNoCase(keyName, "DEGREE") EQ 0>
            <cfset person.degrees = normalizeDegreeValue(record[keyName])>
          <cfelseif compareNoCase(keyName, "TITLE1") EQ 0>
            <cfset person.title1 = valueData>
          <cfelseif compareNoCase(keyName, "FACULTYTYPE") EQ 0 OR compareNoCase(keyName, "FACULTY_TYPE") EQ 0 OR compareNoCase(keyName, "FACULTYROLE") EQ 0>
            <cfset person.facultyType = valueData>
          <cfelseif compareNoCase(keyName, "PROGRAM") EQ 0 OR compareNoCase(keyName, "PROGRAM_NAME") EQ 0 OR compareNoCase(keyName, "ACADEMICPROGRAM") EQ 0>
            <cfset person.program = valueData>
          </cfif>
        </cfloop>

        <!--- Fallback: if still no displayName, use username --->
        <cfif NOT len(person.displayName)>
          <cfset person.displayName = person.username>
        </cfif>
        <cfif NOT len(person.fullName)>
          <cfset person.fullName = person.displayName>
        </cfif>
        <cfif NOT len(person.email)>
          <cfset person.email = person.emailPrimary>
        </cfif>
        <cfif NOT len(person.combinedDegrees)>
          <cfset person.combinedDegrees = person.degrees>
        </cfif>
        <cfif len(person.combinedDegrees)>
          <cfset person.degrees = person.combinedDegrees>
        </cfif>

        <cfset person.roleGroup = detectRoleGroup(person)>
        <cfset arrayAppend(normalized, person)>
      </cfif>
    </cfloop>

    <cfreturn normalized>
  </cffunction>

  <cffunction name="parseMixedArrayValue" access="private" returntype="array" output="false">
    <cfargument name="value" type="any" required="true">

    <cfset var parsedValue = []>
    <cfset var wrappedValue = []>

    <cfif isArray(arguments.value)>
      <cfreturn arguments.value>
    </cfif>

    <cfif isStruct(arguments.value)>
      <cfset arrayAppend(wrappedValue, arguments.value)>
      <cfreturn wrappedValue>
    </cfif>

    <cfif isSimpleValue(arguments.value) AND len(trim(arguments.value & ""))>
      <cftry>
        <cfset parsedValue = deserializeJSON(trim(arguments.value & ""))>
        <cfif isArray(parsedValue)>
          <cfreturn parsedValue>
        </cfif>
        <cfif isStruct(parsedValue)>
          <cfset arrayAppend(wrappedValue, parsedValue)>
          <cfreturn wrappedValue>
        </cfif>
        <cfcatch type="any">
          <cfreturn []>
        </cfcatch>
      </cftry>
    </cfif>

    <cfreturn []>
  </cffunction>

  <cffunction name="readStructValueNoCase" access="private" returntype="string" output="false">
    <cfargument name="source" type="struct" required="true">
    <cfargument name="candidateKeys" type="array" required="true">

    <cfset var keyName = "">
    <cfset var candidateKey = "">
    <cfset var rawValue = "">

    <cfloop from="1" to="#arrayLen(arguments.candidateKeys)#" index="keyName">
      <cfset candidateKey = arguments.candidateKeys[keyName]>
      <cfif structKeyExists(arguments.source, candidateKey)>
        <cfset rawValue = arguments.source[candidateKey]>
        <cfif isSimpleValue(rawValue) AND len(trim(rawValue & ""))>
          <cfreturn trim(rawValue & "")>
        </cfif>
      </cfif>
    </cfloop>

    <cfloop collection="#arguments.source#" item="keyName">
      <cfloop from="1" to="#arrayLen(arguments.candidateKeys)#" index="candidateKey">
        <cfif compareNoCase(keyName, arguments.candidateKeys[candidateKey]) EQ 0>
          <cfset rawValue = arguments.source[keyName]>
          <cfif isSimpleValue(rawValue) AND len(trim(rawValue & ""))>
            <cfreturn trim(rawValue & "")>
          </cfif>
        </cfif>
      </cfloop>
    </cfloop>

    <cfloop collection="#arguments.source#" item="keyName">
      <cfset rawValue = arguments.source[keyName]>
      <cfif isStruct(rawValue)>
        <cfset rawValue = readStructValueNoCase(rawValue, arguments.candidateKeys)>
        <cfif len(rawValue)>
          <cfreturn rawValue>
        </cfif>
      <cfelseif isArray(rawValue)>
        <cfset rawValue = extractPreferredArrayValue(rawValue, arguments.candidateKeys)>
        <cfif len(rawValue)>
          <cfreturn rawValue>
        </cfif>
      <cfelseif isSimpleValue(rawValue) AND len(trim(rawValue & "")) AND NOT listFindNoCase("PRIMARY,ISPRIMARY,TYPE,TYPENAME,CODE,ID,IDENTIFIER", keyName)>
        <cfreturn trim(rawValue & "")>
      </cfif>
    </cfloop>

    <cfreturn "">
  </cffunction>

  <cffunction name="extractPreferredArrayValue" access="private" returntype="string" output="false">
    <cfargument name="value" type="any" required="true">
    <cfargument name="candidateKeys" type="array" required="true">

    <cfset var items = parseMixedArrayValue(arguments.value)>
    <cfset var itemIndex = 0>
    <cfset var valueOut = "">

    <cfif NOT arrayLen(items)>
      <cfreturn "">
    </cfif>

    <cfloop from="1" to="#arrayLen(items)#" index="itemIndex">
      <cfif isStruct(items[itemIndex]) AND structKeyExists(items[itemIndex], "PRIMARY") AND items[itemIndex].PRIMARY>
        <cfset valueOut = readStructValueNoCase(items[itemIndex], arguments.candidateKeys)>
        <cfif len(valueOut)><cfreturn valueOut></cfif>
      </cfif>
    </cfloop>

    <cfloop from="1" to="#arrayLen(items)#" index="itemIndex">
      <cfif isStruct(items[itemIndex])>
        <cfset valueOut = readStructValueNoCase(items[itemIndex], arguments.candidateKeys)>
        <cfif len(valueOut)><cfreturn valueOut></cfif>
      <cfelseif isSimpleValue(items[itemIndex]) AND len(trim(items[itemIndex] & ""))>
        <cfreturn trim(items[itemIndex] & "")>
      </cfif>
    </cfloop>

    <cfreturn "">
  </cffunction>

  <cffunction name="normalizeDegreeValue" access="private" returntype="string" output="false">
    <cfargument name="value" type="any" required="true">

    <cfset var items = []>
    <cfset var itemIndex = 0>
    <cfset var degreeValues = []>
    <cfset var degreeValue = "">
    <cfset var rawValue = "">

    <cfif isSimpleValue(arguments.value) AND NOT isJSON(trim(arguments.value & ""))>
      <cfreturn trim(arguments.value & "")>
    </cfif>

    <cfset items = parseMixedArrayValue(arguments.value)>
    <cfif NOT arrayLen(items)>
      <cfif isSimpleValue(arguments.value)>
        <cfreturn trim(arguments.value & "")>
      </cfif>
      <cfreturn "">
    </cfif>

    <cfloop from="1" to="#arrayLen(items)#" index="itemIndex">
      <cfif isStruct(items[itemIndex])>
        <cfset degreeValue = readStructValueNoCase(items[itemIndex], ["COMBINEDDEGREES", "DEGREE", "VALUE", "NAME", "TITLE", "ABBREVIATION", "DISPLAY"])>
      <cfelseif isSimpleValue(items[itemIndex])>
        <cfset degreeValue = trim(items[itemIndex] & "")>
      <cfelse>
        <cfset degreeValue = "">
      </cfif>

      <cfif len(degreeValue)>
        <cfset rawValue = arrayToList(degreeValues, chr(10))>
        <cfif NOT listFindNoCase(rawValue, degreeValue, chr(10))>
          <cfset arrayAppend(degreeValues, degreeValue)>
        </cfif>
      </cfif>
    </cfloop>

    <cfreturn arrayToList(degreeValues, ", ")>
  </cffunction>

  <cffunction name="getRawKeys" access="private" returntype="array" output="false">
    <cfargument name="payload" type="any" required="true">

    <cfset var items = []>
    <cfset var keys = []>
    <cfset var k = "">
    <cfset var payloadKey = "">

    <cfif isArray(arguments.payload) AND arrayLen(arguments.payload) AND isStruct(arguments.payload[1])>
      <cfset items = arguments.payload>
    <cfelseif isStruct(arguments.payload)>
      <cfloop collection="#arguments.payload#" item="payloadKey">
        <cfif listFindNoCase("items,data,result,people", payloadKey) AND isArray(arguments.payload[payloadKey]) AND arrayLen(arguments.payload[payloadKey])>
          <cfset items = arguments.payload[payloadKey]>
          <cfbreak>
        </cfif>
      </cfloop>
    </cfif>

    <cfif arrayLen(items) AND isStruct(items[1])>
      <cfloop collection="#items[1]#" item="k">
        <cfset arrayAppend(keys, k)>
      </cfloop>
    </cfif>

    <cfreturn keys>
  </cffunction>

  <cffunction name="detectRoleGroup" access="private" returntype="string" output="false">
    <cfargument name="person" type="struct" required="true">

    <cfset var haystack = lCase((arguments.person.flags & " ") & (arguments.person.organizations & " ") & (arguments.person.department & " ") & (arguments.person.title & ""))>

    <cfif findNoCase("alumni", haystack)>
      <cfreturn "alumni">
    <cfelseif findNoCase("student", haystack) OR findNoCase("class20", haystack)>
      <cfreturn "students">
    <cfelseif findNoCase("faculty", haystack)>
      <cfreturn "faculty">
    <cfelseif findNoCase("staff", haystack)>
      <cfreturn "staff">
    </cfif>

    <cfreturn "staff">
  </cffunction>

  <cffunction name="classifyIntoGroups" access="private" returntype="struct" output="false">
    <cfargument name="people" type="array" required="true">

    <cfset var grouped = {
      faculty = [],
      staff = [],
      students = [],
      alumni = []
    }>
    <cfset var i = 0>
    <cfset var groupName = "">

    <cfloop from="1" to="#arrayLen(arguments.people)#" index="i">
      <cfset groupName = arguments.people[i].roleGroup>
      <cfif NOT structKeyExists(grouped, groupName)>
        <cfset groupName = "staff">
      </cfif>
      <cfset arrayAppend(grouped[groupName], arguments.people[i])>
    </cfloop>

    <cfreturn grouped>
  </cffunction>

</cfcomponent>
