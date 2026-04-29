<cfcomponent displayname="AuthService" output="false">

  <!---
    Portal AuthService — mirrors the admin AuthService pattern from uhco_ident.
    Authenticates against CougarNet LDAP. No admin DB lookup is needed; any
    active member of the configured OPT groups is granted portal access.

    Session key: session.portalUser  (distinct from admin's session.user)
  --->

  <cffunction
    name="authenticate"
    access="public"
    returntype="struct"
    output="false"
  >
    <cfargument name="username" type="string" required="true">
    <cfargument name="password" type="string" required="true">

    <cfset var result = {
      success = false,
      message = "",
      user    = {}
    }>

    <cftry>
      <cfldap
        action="QUERY"
        name="GetUserInfo"
        attributes="displayName,memberOf,sAMAccountName,mail,telephoneNumber,accountExpires,userAccountControl,department,title,employeeID"
        start="DC=cougarnet,DC=uh,DC=edu"
        scope="SUBTREE"
        filter="(&(objectClass=User)(objectCategory=Person)(sAMAccountName=#arguments.username#)(|(memberOf=CN=OPT-ASC,OU=ASC USERS,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-STAFF,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-OPTOMETRY,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-FACULTY-1,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2022,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2023,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2024,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2025,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2026,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2027,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2028,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)))"
        maxrows="1"
        server="cougarnet.uh.edu"
        username="COUGARNET\#arguments.username#"
        password="#arguments.password#">

      <!--- No matching group membership --->
      <cfif GetUserInfo.recordCount EQ 0>
        <cfset result.message = "User not authorized">
        <cfreturn result>
      </cfif>

      <!--- Disabled account --->
      <cfif bitAnd(GetUserInfo.userAccountControl, 2)>
        <cfset result.message = "Account disabled">
        <cfreturn result>
      </cfif>

      <!--- Account expired --->
      <cfif GetUserInfo.accountExpires NEQ 0
         AND GetUserInfo.accountExpires LT
           dateDiff("s", createDate(1601,1,1), now())>
        <cfset result.message = "Account expired">
        <cfreturn result>
      </cfif>

      <cfset var ldapUsername = trim(GetUserInfo.sAMAccountName[1] & "")>
      <cfset var ldapDisplayName = trim(GetUserInfo.displayName[1] & "")>
      <cfset var ldapEmail = trim(GetUserInfo.mail[1] & "")>
      <cfset var ldapDepartment = trim(GetUserInfo.department[1] & "")>
      <cfset var ldapTitle = trim(GetUserInfo.title[1] & "")>
      <cfset var ldapPhone = trim(GetUserInfo.telephoneNumber[1] & "")>
      <cfset var ldapEmployeeID = trim(GetUserInfo.employeeID[1] & "")>

      <!--- Success --->
      <cfset result.success = true>
      <cfset result.user = {
        username    = lCase(ldapUsername),
        displayName = ldapDisplayName,
        email       = ldapEmail,
        department  = ldapDepartment,
        title       = ldapTitle,
        phone       = ldapPhone,
        employeeID  = ldapEmployeeID,
        authType    = "ldap",
        loginAt     = now()
      }>

      <!--- Fetch additional profile data from API --->
      <cfset var apiToken = "">
      <cfset var apiSecret = "">
      <cfset var httpResponse = {}>
      <cfset var apiData = {}>
      <cfset var apiRecord = {}>
      <cfset var k = "">
      <cfset var statusText = "">
      <cfset var tokenPresent = "NO">
      <cfset var secretPresent = "NO">
      <cfset var keyVal = "">
      <cfset var keyMap = {
        userId = "",
        degrees = "",
        flags = "",
        organizations = "",
        currentGradYear = "",
        webProfileImage = "",
        webThumbImage = ""
      }>

      <cfif structKeyExists(application, "MYUHCO_API_TOKEN")>
        <cfset apiToken = application.MYUHCO_API_TOKEN>
      </cfif>
      <cfif structKeyExists(application, "MYUHCO_API_SECRET")>
        <cfset apiSecret = application.MYUHCO_API_SECRET>
      </cfif>

      <cfif len(apiToken) GT 0>
        <cfset tokenPresent = "YES">
      </cfif>
      <cfif len(apiSecret) GT 0>
        <cfset secretPresent = "YES">
      </cfif>

      <cftry>
        <cflog
          file="myuhco-api"
          type="information"
          text="API Call - Token present: #tokenPresent#, Secret present: #secretPresent#, Username: #ldapUsername#">

        <cfhttp
          method="get"
          url="#getMyuhcoQuickpullUrl()#"
          result="httpResponse"
          timeout="10">
          <cfhttpparam type="url" name="token" value="#apiToken#">
          <cfhttpparam type="url" name="secret" value="#apiSecret#">
          <cfhttpparam type="url" name="id" value="#ldapUsername#">
        </cfhttp>

        <cflog
          file="myuhco-api"
          type="information"
          text="API Response - Status: #httpResponse.statusCode#, Content length: #len(httpResponse.fileContent)#">

        <cfif findNoCase("200", httpResponse.statusCode)>
          <cfset apiData = deserializeJSON(httpResponse.fileContent)>

          <!--- Normalize API payload to a single struct record --->
          <cfif isStruct(apiData)>
            <cfset apiRecord = apiData>
            <cfif structKeyExists(apiData, "data") AND isArray(apiData.data) AND arrayLen(apiData.data) AND isStruct(apiData.data[1])>
              <cfset apiRecord = apiData.data[1]>
            <cfelseif structKeyExists(apiData, "result") AND isArray(apiData.result) AND arrayLen(apiData.result) AND isStruct(apiData.result[1])>
              <cfset apiRecord = apiData.result[1]>
            <cfelseif structKeyExists(apiData, "result") AND isStruct(apiData.result)>
              <cfset apiRecord = apiData.result>
            </cfif>
          <cfelseif isArray(apiData) AND arrayLen(apiData) AND isStruct(apiData[1])>
            <cfset apiRecord = apiData[1]>
          </cfif>

          <!--- Case-insensitive key extraction from normalized record --->
          <cfif isStruct(apiRecord)>
            <cfloop collection="#apiRecord#" item="k">
                <cfset keyVal = apiRecord[k]>
              <cfif compareNoCase(k, "USERID") EQ 0>
                  <cfif isSimpleValue(keyVal)>
                    <cfset keyMap.userId = trim(keyVal & "")>
                  <cfelse>
                    <cfset keyMap.userId = serializeJSON(keyVal)>
                  </cfif>
              <cfelseif compareNoCase(k, "DEGREES") EQ 0>
                  <cfif isSimpleValue(keyVal)>
                    <cfset keyMap.degrees = trim(keyVal & "")>
                  <cfelse>
                    <cfset keyMap.degrees = serializeJSON(keyVal)>
                  </cfif>
              <cfelseif compareNoCase(k, "FLAGS") EQ 0>
                  <cfif isSimpleValue(keyVal)>
                    <cfset keyMap.flags = trim(keyVal & "")>
                  <cfelse>
                    <cfset keyMap.flags = serializeJSON(keyVal)>
                  </cfif>
              <cfelseif compareNoCase(k, "ORGANIZATIONS") EQ 0>
                  <cfif isSimpleValue(keyVal)>
                    <cfset keyMap.organizations = trim(keyVal & "")>
                  <cfelse>
                    <cfset keyMap.organizations = serializeJSON(keyVal)>
                  </cfif>
              <cfelseif compareNoCase(k, "CURRENTGRADYEAR") EQ 0>
                  <cfif isSimpleValue(keyVal)>
                    <cfset keyMap.currentGradYear = trim(keyVal & "")>
                  <cfelse>
                    <cfset keyMap.currentGradYear = serializeJSON(keyVal)>
                  </cfif>
              <cfelseif compareNoCase(k, "WEBPROFILEIMAGE") EQ 0>
                  <cfif isSimpleValue(keyVal)>
                    <cfset keyMap.webProfileImage = trim(keyVal & "")>
                  <cfelse>
                    <cfset keyMap.webProfileImage = serializeJSON(keyVal)>
                  </cfif>
              <cfelseif compareNoCase(k, "WEBTHUMBIMAGE") EQ 0>
                  <cfif isSimpleValue(keyVal)>
                    <cfset keyMap.webThumbImage = trim(keyVal & "")>
                  <cfelse>
                    <cfset keyMap.webThumbImage = serializeJSON(keyVal)>
                  </cfif>
              </cfif>
            </cfloop>
          </cfif>

          <!--- Add API response fields to user struct --->
          <cfset result.user.userId = keyMap.userId>
          <cfset result.user.degrees = keyMap.degrees>
          <cfset result.user.flags = keyMap.flags>
          <cfset result.user.organizations = keyMap.organizations>
          <cfset result.user.currentGradYear = keyMap.currentGradYear>
          <cfset result.user.webProfileImage = keyMap.webProfileImage>
          <cfset result.user.webThumbImage = keyMap.webThumbImage>

          <cflog
            file="myuhco-api"
            type="information"
            text="API data parsed for user #ldapUsername#. Field lengths: userId=#len(result.user.userId)#, degrees=#len(result.user.degrees)#, flags=#len(result.user.flags)#, organizations=#len(result.user.organizations)#, currentGradYear=#len(result.user.currentGradYear)#, webProfileImage=#len(result.user.webProfileImage)#, webThumbImage=#len(result.user.webThumbImage)#">
        <cfelse>
          <cflog
            file="myuhco-api"
            type="error"
            text="API call failed for user #ldapUsername#. Status: #httpResponse.statusCode# | Response: #left(httpResponse.fileContent, 500)#">
        </cfif>

        <cfcatch type="any">
          <!--- API failures should not be logged as LDAP failures --->
          <cflog
            file="myuhco-api"
            type="error"
            text="API integration error for user #ldapUsername#: #cfcatch.message# | #cfcatch.detail#">
        </cfcatch>
      </cftry>

      <cfreturn result>

      <cfcatch type="any">
        <cflog
          file="myuhco-ldap"
          type="error"
          text="LDAP ERROR: #cfcatch.message# | #cfcatch.detail#"
        >
        <cfif cfcatch.message CONTAINS "error code 49">
          <cfif cfcatch.message CONTAINS "52e">
            <cfset result.message = "Invalid credentials. Please check your username or password and try again.">
          <cfelseif cfcatch.message CONTAINS "525">
            <cfset result.message = "User not found. Please check your username and try again.">
          <cfelseif cfcatch.message CONTAINS "530">
            <cfset result.message = "Not permitted to log on at this time. Please contact your IT admin.">
          <cfelseif cfcatch.message CONTAINS "532">
            <cfset result.message = "Password expired. Please change your password before attempting to log in again.">
          <cfelseif cfcatch.message CONTAINS "533">
            <cfset result.message = "Account disabled. Please contact your IT admin.">
          <cfelseif cfcatch.message CONTAINS "701">
            <cfset result.message = "Account expired. Please contact your IT admin.">
          <cfelseif cfcatch.message CONTAINS "773">
            <cfset result.message = "You must reset your password before logging in.">
          <cfelse>
            <cfset result.message = "Login failed (code 49). Please try again.">
          </cfif>
        <cfelse>
          <cfset result.message = "Authentication error. Please try again.">
        </cfif>
        <cfreturn result>
      </cfcatch>

    </cftry>

  </cffunction>

  <cffunction
    name="authenticateCredentials"
    access="public"
    returntype="struct"
    output="false"
  >
    <cfargument name="username" type="string" required="true">
    <cfargument name="password" type="string" required="true">

    <cfset var result = {
      success = false,
      message = "",
      user    = {}
    }>

    <cftry>
      <cfldap
        action="QUERY"
        name="GetUserInfo"
        attributes="displayName,memberOf,sAMAccountName,mail,telephoneNumber,accountExpires,userAccountControl,department,title,employeeID"
        start="DC=cougarnet,DC=uh,DC=edu"
        scope="SUBTREE"
        filter="(&(objectClass=User)(objectCategory=Person)(sAMAccountName=#arguments.username#)(|(memberOf=CN=OPT-ASC,OU=ASC USERS,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-STAFF,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-OPTOMETRY,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-FACULTY-1,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2022,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2023,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2024,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2025,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2026,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2027,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)(memberOf=CN=OPT-CLASS2028,OU=Distribution Groups,OU=OPTOMETRY,DC=cougarnet,DC=uh,DC=edu)))"
        maxrows="1"
        server="cougarnet.uh.edu"
        username="COUGARNET\#arguments.username#"
        password="#arguments.password#">

      <cfif GetUserInfo.recordCount EQ 0>
        <cfset result.message = "User not authorized">
        <cfreturn result>
      </cfif>

      <cfif bitAnd(GetUserInfo.userAccountControl, 2)>
        <cfset result.message = "Account disabled">
        <cfreturn result>
      </cfif>

      <cfif GetUserInfo.accountExpires NEQ 0
         AND GetUserInfo.accountExpires LT
           dateDiff("s", createDate(1601,1,1), now())>
        <cfset result.message = "Account expired">
        <cfreturn result>
      </cfif>

      <cfset result.success = true>
      <cfset result.user = {
        username    = lCase(trim(GetUserInfo.sAMAccountName[1] & "")),
        displayName = trim(GetUserInfo.displayName[1] & ""),
        email       = trim(GetUserInfo.mail[1] & ""),
        department  = trim(GetUserInfo.department[1] & ""),
        title       = trim(GetUserInfo.title[1] & ""),
        phone       = trim(GetUserInfo.telephoneNumber[1] & ""),
        employeeID  = trim(GetUserInfo.employeeID[1] & ""),
        authType    = "ldap",
        loginAt     = now()
      }>

      <cfreturn result>

      <cfcatch type="any">
        <cflog
          file="myuhco-ldap"
          type="error"
          text="LDAP ERROR: #cfcatch.message# | #cfcatch.detail#"
        >
        <cfif cfcatch.message CONTAINS "error code 49">
          <cfif cfcatch.message CONTAINS "52e">
            <cfset result.message = "Invalid credentials. Please check your username or password and try again.">
          <cfelseif cfcatch.message CONTAINS "525">
            <cfset result.message = "User not found. Please check your username and try again.">
          <cfelseif cfcatch.message CONTAINS "530">
            <cfset result.message = "Not permitted to log on at this time. Please contact your IT admin.">
          <cfelseif cfcatch.message CONTAINS "532">
            <cfset result.message = "Password expired. Please change your password before attempting to log in again.">
          <cfelseif cfcatch.message CONTAINS "533">
            <cfset result.message = "Account disabled. Please contact your IT admin.">
          <cfelseif cfcatch.message CONTAINS "701">
            <cfset result.message = "Account expired. Please contact your IT admin.">
          <cfelseif cfcatch.message CONTAINS "773">
            <cfset result.message = "You must reset your password before logging in.">
          <cfelse>
            <cfset result.message = "Login failed (code 49). Please try again.">
          </cfif>
        <cfelse>
          <cfset result.message = "Authentication error. Please try again.">
        </cfif>
        <cfreturn result>
      </cfcatch>
    </cftry>
  </cffunction>

  <cffunction name="loadUserProfile" access="public" returntype="struct" output="false">
    <cfargument name="user" type="struct" required="true">

    <cfset var profileUser = duplicate(arguments.user)>
    <cfset var apiToken = "">
    <cfset var apiSecret = "">
    <cfset var httpResponse = {}>
    <cfset var apiData = {}>
    <cfset var apiRecord = {}>
    <cfset var k = "">
    <cfset var keyVal = "">
    <cfset var tokenPresent = "NO">
    <cfset var secretPresent = "NO">
    <cfset var keyMap = {
      userId = "",
      degrees = "",
      flags = "",
      organizations = "",
      currentGradYear = "",
      webProfileImage = "",
      webThumbImage = ""
    }>

    <cfif structKeyExists(application, "MYUHCO_API_TOKEN")>
      <cfset apiToken = application.MYUHCO_API_TOKEN>
    </cfif>
    <cfif structKeyExists(application, "MYUHCO_API_SECRET")>
      <cfset apiSecret = application.MYUHCO_API_SECRET>
    </cfif>

    <cfif len(apiToken) GT 0>
      <cfset tokenPresent = "YES">
    </cfif>
    <cfif len(apiSecret) GT 0>
      <cfset secretPresent = "YES">
    </cfif>

    <cftry>
      <cflog
        file="myuhco-api"
        type="information"
        text="API Call - Token present: #tokenPresent#, Secret present: #secretPresent#, Username: #profileUser.username#">

      <cfhttp
        method="get"
        url="#getMyuhcoQuickpullUrl()#"
        result="httpResponse"
        timeout="10">
        <cfhttpparam type="url" name="token" value="#apiToken#">
        <cfhttpparam type="url" name="secret" value="#apiSecret#">
        <cfhttpparam type="url" name="id" value="#profileUser.username#">
      </cfhttp>

      <cflog
        file="myuhco-api"
        type="information"
        text="API Response - Status: #httpResponse.statusCode#, Content length: #len(httpResponse.fileContent)#">

      <cfif findNoCase("200", httpResponse.statusCode)>
        <cfset apiData = deserializeJSON(httpResponse.fileContent)>

        <cfif isStruct(apiData)>
          <cfset apiRecord = apiData>
          <cfif structKeyExists(apiData, "data") AND isArray(apiData.data) AND arrayLen(apiData.data) AND isStruct(apiData.data[1])>
            <cfset apiRecord = apiData.data[1]>
          <cfelseif structKeyExists(apiData, "result") AND isArray(apiData.result) AND arrayLen(apiData.result) AND isStruct(apiData.result[1])>
            <cfset apiRecord = apiData.result[1]>
          <cfelseif structKeyExists(apiData, "result") AND isStruct(apiData.result)>
            <cfset apiRecord = apiData.result>
          </cfif>
        <cfelseif isArray(apiData) AND arrayLen(apiData) AND isStruct(apiData[1])>
          <cfset apiRecord = apiData[1]>
        </cfif>

        <cfif isStruct(apiRecord)>
          <cfloop collection="#apiRecord#" item="k">
            <cfset keyVal = apiRecord[k]>
            <cfif compareNoCase(k, "USERID") EQ 0>
              <cfif isSimpleValue(keyVal)>
                <cfset keyMap.userId = trim(keyVal & "")>
              <cfelse>
                <cfset keyMap.userId = serializeJSON(keyVal)>
              </cfif>
            <cfelseif compareNoCase(k, "DEGREES") EQ 0>
              <cfif isSimpleValue(keyVal)>
                <cfset keyMap.degrees = trim(keyVal & "")>
              <cfelse>
                <cfset keyMap.degrees = serializeJSON(keyVal)>
              </cfif>
            <cfelseif compareNoCase(k, "FLAGS") EQ 0>
              <cfif isSimpleValue(keyVal)>
                <cfset keyMap.flags = trim(keyVal & "")>
              <cfelse>
                <cfset keyMap.flags = serializeJSON(keyVal)>
              </cfif>
            <cfelseif compareNoCase(k, "ORGANIZATIONS") EQ 0>
              <cfif isSimpleValue(keyVal)>
                <cfset keyMap.organizations = trim(keyVal & "")>
              <cfelse>
                <cfset keyMap.organizations = serializeJSON(keyVal)>
              </cfif>
            <cfelseif compareNoCase(k, "CURRENTGRADYEAR") EQ 0>
              <cfif isSimpleValue(keyVal)>
                <cfset keyMap.currentGradYear = trim(keyVal & "")>
              <cfelse>
                <cfset keyMap.currentGradYear = serializeJSON(keyVal)>
              </cfif>
            <cfelseif compareNoCase(k, "WEBPROFILEIMAGE") EQ 0>
              <cfif isSimpleValue(keyVal)>
                <cfset keyMap.webProfileImage = trim(keyVal & "")>
              <cfelse>
                <cfset keyMap.webProfileImage = serializeJSON(keyVal)>
              </cfif>
            <cfelseif compareNoCase(k, "WEBTHUMBIMAGE") EQ 0>
              <cfif isSimpleValue(keyVal)>
                <cfset keyMap.webThumbImage = trim(keyVal & "")>
              <cfelse>
                <cfset keyMap.webThumbImage = serializeJSON(keyVal)>
              </cfif>
            </cfif>
          </cfloop>
        </cfif>

        <cfset profileUser.userId = keyMap.userId>
        <cfset profileUser.degrees = keyMap.degrees>
        <cfset profileUser.flags = keyMap.flags>
        <cfset profileUser.organizations = keyMap.organizations>
        <cfset profileUser.currentGradYear = keyMap.currentGradYear>
        <cfset profileUser.webProfileImage = keyMap.webProfileImage>
        <cfset profileUser.webThumbImage = keyMap.webThumbImage>

        <cflog
          file="myuhco-api"
          type="information"
          text="API data parsed for user #profileUser.username#. Field lengths: userId=#len(profileUser.userId)#, degrees=#len(profileUser.degrees)#, flags=#len(profileUser.flags)#, organizations=#len(profileUser.organizations)#, currentGradYear=#len(profileUser.currentGradYear)#, webProfileImage=#len(profileUser.webProfileImage)#, webThumbImage=#len(profileUser.webThumbImage)#">
      <cfelse>
        <cflog
          file="myuhco-api"
          type="error"
          text="API call failed for user #profileUser.username#. Status: #httpResponse.statusCode# | Response: #left(httpResponse.fileContent, 500)#">
      </cfif>

      <cfcatch type="any">
        <cflog
          file="myuhco-api"
          type="error"
          text="API integration error for user #profileUser.username#: #cfcatch.message# | #cfcatch.detail#">
      </cfcatch>
    </cftry>

    <cfreturn profileUser>
  </cffunction>

  <cffunction name="createSession" access="public" returntype="void" output="false">
    <cfargument name="user" type="struct" required="true">

    <cfset session.portalUser = duplicate(arguments.user)>
  </cffunction>

  <cffunction name="isLoggedIn" access="public" returntype="boolean" output="false">
    <cfreturn structKeyExists(session, "portalUser")>
  </cffunction>

  <cffunction name="logout" access="public" returntype="void" output="false">
    <cfif structKeyExists(session, "portalUser")>
      <cfset structDelete(session, "portalUser")>
    </cfif>
    <cfset sessionInvalidate()>
  </cffunction>

  <cffunction name="getMyuhcoQuickpullUrl" access="private" returntype="string" output="false">
    <cfset var baseUrl = "http://127.0.0.1/api/v1">

    <cfif structKeyExists(application, "MYUHCO_API_URL") AND len(trim(application.MYUHCO_API_URL & ""))>
      <cfset baseUrl = trim(application.MYUHCO_API_URL & "")>
    </cfif>

    <cfset baseUrl = reReplace(baseUrl, "/+$", "", "all")>
    <cfreturn baseUrl & "/quickpulls/myuhco">
  </cffunction>

</cfcomponent>
