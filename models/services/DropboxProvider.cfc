<cfcomponent output="false" singleton>

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="configReader" required="false" default="">
        <cfargument name="config" type="struct" required="false" default="#structNew()#">
        <cfset variables.configReader = arguments.configReader>
        <cfset variables.config = arguments.config>
        <cfset variables.allowedExtensions = "jpg,jpeg,png,webp">
        <cfset variables.tokenCacheKey = "uhco_dropbox_access_token_cache">
        <cfreturn this>
    </cffunction>

    <cffunction name="getAccessToken" access="public" returntype="string" output="false">
        <cfset var appKey = trim(getConfigValue("dropbox.app_key", "") & "")>
        <cfset var appSecret = trim(getConfigValue("dropbox.app_secret", "") & "")>
        <cfset var refreshToken = trim(getConfigValue("dropbox.refresh_token", "") & "")>
        <cfset var cachedToken = "">
        <cfset var tokenResponse = {}>
        <cfset var expiresIn = 0>

        <cfif !len(appKey) OR !len(appSecret) OR !len(refreshToken)>
            <cfthrow
                type="DropboxProvider.MissingConfig"
                message="Dropbox credentials are missing from AppConfig."
            >
        </cfif>

        <cflock scope="server" type="readonly" timeout="5">
            <cfif structKeyExists(server, variables.tokenCacheKey)
                AND isStruct(server[variables.tokenCacheKey])
                AND structKeyExists(server[variables.tokenCacheKey], "token")
                AND structKeyExists(server[variables.tokenCacheKey], "expiresAt")
                AND now() LT server[variables.tokenCacheKey].expiresAt>
                <cfset cachedToken = server[variables.tokenCacheKey].token>
            </cfif>
        </cflock>

        <cfif len(cachedToken)>
            <cfreturn cachedToken>
        </cfif>

        <cfset tokenResponse = _requestToken(appKey, appSecret, refreshToken)>

        <cfif !structKeyExists(tokenResponse, "access_token") OR !len(trim(tokenResponse.access_token ?: ""))>
            <cfthrow
                type="DropboxProvider.TokenError"
                message="Dropbox token response did not include access_token."
            >
        </cfif>

        <cfset expiresIn = val(tokenResponse.expires_in ?: 14400)>
        <cfif expiresIn LTE 120>
            <cfset expiresIn = 120>
        </cfif>

        <cflock scope="server" type="exclusive" timeout="5">
            <cfset server[variables.tokenCacheKey] = {
                token = tokenResponse.access_token,
                expiresAt = dateAdd("s", expiresIn - 60, now())
            }>
        </cflock>

        <cfreturn tokenResponse.access_token>
    </cffunction>

    <cffunction name="listFolderRecursive" access="public" returntype="array" output="false">
        <cfargument name="folderPath" type="string" required="false" default="">

        <cfreturn listFolderEntriesRecursive(arguments.folderPath, variables.allowedExtensions)>
    </cffunction>

    <cffunction name="listFolderEntriesRecursive" access="public" returntype="array" output="false">
        <cfargument name="folderPath" type="string" required="false" default="">
        <cfargument name="allowedExtensions" type="string" required="false" default="">

        <cfset var normalizedFolder = _normalizeDropboxPath(arguments.folderPath)>
        <cfset var payloadJson = "">
        <cfset var responseData = {}>
        <cfset var hasMore = false>
        <cfset var files = []>
        <cfset var nextFiles = []>
        <cfset var cursorJson = "">

        <cfset payloadJson = '{'
            & '"path":' & serializeJSON(normalizedFolder)
            & ',"recursive":true'
            & ',"include_deleted":false'
            & ',"include_has_explicit_shared_members":false'
            & ',"include_media_info":false'
            & '}'>

        <cfset responseData = _postDropboxJson(
            endpoint = "https://api.dropboxapi.com/2/files/list_folder",
            payload = payloadJson,
            timeoutSeconds = 60
        )>

        <cfset files = _collectEntries(responseData, arguments.allowedExtensions)>
        <cfset hasMore = structKeyExists(responseData, "has_more") AND responseData.has_more>

        <cfloop condition="hasMore">
            <cfset cursorJson = '{"cursor":' & serializeJSON(responseData.cursor ?: "") & '}'>

            <cfset responseData = _postDropboxJson(
                endpoint = "https://api.dropboxapi.com/2/files/list_folder/continue",
                payload = cursorJson,
                timeoutSeconds = 60
            )>

            <cfset nextFiles = _collectEntries(responseData, arguments.allowedExtensions)>
            <cfloop array="#nextFiles#" index="f">
                <cfset arrayAppend(files, f)>
            </cfloop>
            <cfset hasMore = structKeyExists(responseData, "has_more") AND responseData.has_more>
        </cfloop>

        <cfreturn files>
    </cffunction>

    <cffunction name="fileExists" access="public" returntype="boolean" output="false">
        <cfargument name="dropboxPath" type="string" required="true">

        <cfset var normalizedPath = _normalizeDropboxPath(arguments.dropboxPath)>
        <cfset var httpResp = "">
        <cfset var requestBody = "">
        <cfset var pathRootHeader = _getPathRootHeaderValue()>
        <cfset var selectUserHeader = _getSelectUserHeaderValue()>

        <cfif !len(normalizedPath)>
            <cfreturn false>
        </cfif>

        <cfset requestBody = '{"path":' & serializeJSON(normalizedPath) & '}'>

        <cfhttp
            url="https://api.dropboxapi.com/2/files/get_metadata"
            method="post"
            result="httpResp"
            timeout="30"
            throwOnError="false"
        >
            <cfhttpparam type="header" name="Authorization" value="Bearer #getAccessToken()#">
            <cfif len(pathRootHeader)>
                <cfhttpparam type="header" name="Dropbox-API-Path-Root" value="#pathRootHeader#">
            </cfif>
            <cfif len(selectUserHeader)>
                <cfhttpparam type="header" name="Dropbox-API-Select-User" value="#selectUserHeader#">
            </cfif>
            <cfhttpparam type="header" name="Content-Type" value="application/json">
            <cfhttpparam type="body" value="#requestBody#">
        </cfhttp>

        <cfif left(httpResp.statusCode, 3) EQ "200">
            <cfreturn true>
        </cfif>

        <cfif left(httpResp.statusCode, 3) EQ "409">
            <cfreturn false>
        </cfif>

        <cfthrow
            type="DropboxProvider.MetadataError"
            message="#_extractErrorMessage(httpResp, "Dropbox metadata request failed.")#"
        >
    </cffunction>

    <cffunction name="downloadToTemp" access="public" returntype="string" output="false">
        <cfargument name="dropboxPath" type="string" required="true">

        <cfreturn downloadFileToTemp(arguments.dropboxPath, variables.allowedExtensions)>
    </cffunction>

    <cffunction name="downloadFileToTemp" access="public" returntype="string" output="false">
        <cfargument name="dropboxPath" type="string" required="true">
        <cfargument name="allowedExtensions" type="string" required="false" default="">

        <cfset var normalizedPath = _normalizeDropboxPath(arguments.dropboxPath)>
        <cfset var ext = lCase(listLast(normalizedPath, "."))>
        <cfset var tempFileName = "">
        <cfset var tempFilePath = "">
        <cfset var httpResp = "">
        <cfset var apiArg = "">
        <cfset var pathRootHeader = _getPathRootHeaderValue()>
        <cfset var selectUserHeader = _getSelectUserHeaderValue()>

        <cfif !len(normalizedPath)>
            <cfthrow type="DropboxProvider.InvalidPath" message="Dropbox path is empty.">
        </cfif>

        <cfif len(trim(arguments.allowedExtensions & "")) AND !listFindNoCase(arguments.allowedExtensions, ext)>
            <cfthrow type="DropboxProvider.InvalidPath" message="Dropbox path extension is not allowed.">
        </cfif>

        <cfset apiArg = '{"path":' & serializeJSON(normalizedPath) & '}'>
        <cfset tempFileName = "dropbox_#createUUID()#.#ext#">
        <cfset tempFilePath = getTempDirectory() & tempFileName>

        <cfhttp
            url="https://content.dropboxapi.com/2/files/download"
            method="post"
            result="httpResp"
            timeout="90"
            throwOnError="false"
            path="#getTempDirectory()#"
            file="#tempFileName#"
        >
            <cfhttpparam type="header" name="Authorization" value="Bearer #getAccessToken()#">
            <cfif len(pathRootHeader)>
                <cfhttpparam type="header" name="Dropbox-API-Path-Root" value="#pathRootHeader#">
            </cfif>
            <cfif len(selectUserHeader)>
                <cfhttpparam type="header" name="Dropbox-API-Select-User" value="#selectUserHeader#">
            </cfif>
            <cfhttpparam type="header" name="Dropbox-API-Arg" value="#apiArg#">
        </cfhttp>

        <cfif left(httpResp.statusCode, 3) NEQ "200">
            <!--- cfhttp wrote the error response body to the temp file; read it for the message. --->
            <cfset var errorBody = "">
            <cfif fileExists(tempFilePath)>
                <cftry>
                    <cfset errorBody = fileRead(tempFilePath)>
                    <cfcatch></cfcatch>
                </cftry>
                <cfset fileDelete(tempFilePath)>
            </cfif>
            <cfthrow
                type="DropboxProvider.DownloadError"
                   message="Dropbox file download failed. (HTTP #httpResp.statusCode#) for path: [#normalizedPath#]#len(errorBody) ? ': ' & left(errorBody, 400) : ''#"
            >
        </cfif>

        <cfreturn tempFilePath>
    </cffunction>

    <cffunction name="downloadJson" access="public" returntype="any" output="false">
        <cfargument name="dropboxPath" type="string" required="true">

        <cfset var tempPath = "">
        <cfset var raw = "">

        <cfset tempPath = downloadFileToTemp(arguments.dropboxPath, "json")>

        <cftry>
            <cfset raw = fileRead(tempPath, "utf-8")>
            <cfif !len(trim(raw & ""))>
                <cfreturn {}>
            </cfif>
            <cfif !isJSON(raw)>
                <cfthrow type="DropboxProvider.ApiError" message="Dropbox JSON file content is invalid JSON.">
            </cfif>
            <cfreturn deserializeJSON(raw)>
            <cffinally>
                <cfif len(tempPath) AND fileExists(tempPath)>
                    <cfset fileDelete(tempPath)>
                </cfif>
            </cffinally>
        </cftry>
    </cffunction>

    <cffunction name="getTemporaryLink" access="public" returntype="string" output="false">
        <cfargument name="dropboxPath" type="string" required="true">

        <cfset var normalizedPath = _normalizeDropboxPath(arguments.dropboxPath)>
        <cfset var payload = '{"path":' & serializeJSON(normalizedPath) & '}'>
        <cfset var responseData = _postDropboxJson(
            endpoint = "https://api.dropboxapi.com/2/files/get_temporary_link",
            payload  = payload
        )>

        <cfif !structKeyExists(responseData, "link") OR !len(responseData.link ?: "")>
            <cfthrow type="DropboxProvider.ApiError" message="Dropbox did not return a temporary link for the requested path.">
        </cfif>

        <cfreturn responseData.link>
    </cffunction>

    <cffunction name="testConnection" access="public" returntype="struct" output="false">
        <cfargument name="folderPath" type="string" required="false" default="">

        <cfset var rootPath = len(trim(arguments.folderPath))
            ? arguments.folderPath
            : getConfigValue("dropbox.root_folder", "")>
        <cfset var files = []>

        <cftry>
            <cfset files = listFolderRecursive(rootPath)>
            <cfreturn {
                success = true,
                message = "Connected to Dropbox successfully.",
                rootPath = _normalizeDropboxPath(rootPath),
                fileCount = arrayLen(files)
            }>
            <cfcatch type="any">
                <cfreturn {
                    success = false,
                    message = cfcatch.message,
                    detail = cfcatch.detail ?: ""
                }>
            </cfcatch>
        </cftry>
    </cffunction>

    <cffunction name="clearTokenCache" access="public" returntype="void" output="false">
        <cfset _clearTokenCache()>
    </cffunction>

    <cffunction name="_requestToken" access="private" returntype="struct" output="false">
        <cfargument name="appKey" type="string" required="true">
        <cfargument name="appSecret" type="string" required="true">
        <cfargument name="refreshToken" type="string" required="true">

        <cfset var httpResp = "">

        <cfhttp
            url="https://api.dropbox.com/oauth2/token"
            method="post"
            result="httpResp"
            timeout="30"
            throwOnError="false"
        >
            <cfhttpparam type="formField" name="grant_type" value="refresh_token">
            <cfhttpparam type="formField" name="refresh_token" value="#arguments.refreshToken#">
            <cfhttpparam type="formField" name="client_id" value="#arguments.appKey#">
            <cfhttpparam type="formField" name="client_secret" value="#arguments.appSecret#">
        </cfhttp>

        <cfif left(httpResp.statusCode, 3) NEQ "200">
            <cfthrow
                type="DropboxProvider.TokenError"
                message="#_extractErrorMessage(httpResp, "Dropbox token exchange failed.")#"
            >
        </cfif>

        <cfif !isJSON(httpResp.fileContent ?: "")>
            <cfthrow
                type="DropboxProvider.TokenError"
                message="Dropbox token exchange returned non-JSON content."
            >
        </cfif>

        <cfreturn deserializeJSON(httpResp.fileContent)>
    </cffunction>

    <cffunction name="_postDropboxJson" access="private" returntype="struct" output="false">
        <cfargument name="endpoint" type="string" required="true">
        <cfargument name="payload" type="any" required="true">
        <cfargument name="timeoutSeconds" type="numeric" required="false" default="30">

        <cfset var httpResp = "">
        <cfset var didRetry = false>
        <cfset var requestBody = "">
        <cfset var pathRootHeader = _getPathRootHeaderValue()>
        <cfset var selectUserHeader = _getSelectUserHeaderValue()>

        <cfset requestBody = isSimpleValue(arguments.payload) ? toString(arguments.payload) : serializeJSON(arguments.payload)>

        <cfloop condition="true">
            <cfhttp
                url="#arguments.endpoint#"
                method="post"
                result="httpResp"
                timeout="#arguments.timeoutSeconds#"
                throwOnError="false"
            >
                <cfhttpparam type="header" name="Authorization" value="Bearer #getAccessToken()#">
                <cfif len(pathRootHeader)>
                    <cfhttpparam type="header" name="Dropbox-API-Path-Root" value="#pathRootHeader#">
                </cfif>
                <cfif len(selectUserHeader)>
                    <cfhttpparam type="header" name="Dropbox-API-Select-User" value="#selectUserHeader#">
                </cfif>
                <cfhttpparam type="header" name="Content-Type" value="application/json">
                <cfhttpparam type="body" value="#requestBody#">
            </cfhttp>

            <!--- One retry on auth failures after forcing token cache clear. --->
            <cfif !didRetry AND listFind("401,403", left(httpResp.statusCode, 3))>
                <cfset didRetry = true>
                <cfset _clearTokenCache()>
                <cfcontinue>
            </cfif>

            <cfbreak>
        </cfloop>

        <cfif left(httpResp.statusCode, 3) NEQ "200">
            <cfthrow
                type="DropboxProvider.ApiError"
                message="#_extractErrorMessage(httpResp, "Dropbox API request failed.")#"
            >
        </cfif>

        <cfif !isJSON(httpResp.fileContent ?: "")>
            <cfthrow
                type="DropboxProvider.ApiError"
                message="Dropbox API returned non-JSON content."
            >
        </cfif>

        <cfreturn deserializeJSON(httpResp.fileContent)>
    </cffunction>

    <cffunction name="_clearTokenCache" access="private" returntype="void" output="false">
        <cflock scope="server" type="exclusive" timeout="5">
            <cfif structKeyExists(server, variables.tokenCacheKey)>
                <cfset structDelete(server, variables.tokenCacheKey)>
            </cfif>
        </cflock>
    </cffunction>

    <cffunction name="_getPathRootHeaderValue" access="private" returntype="string" output="false">
        <cfset var namespaceID = trim(getConfigValue("dropbox.path_root_namespace_id", "") & "")>

        <cfif !len(namespaceID)>
            <cfreturn "">
        </cfif>

        <cfreturn '{".tag":"namespace_id","namespace_id":' & serializeJSON(namespaceID) & '}'>
    </cffunction>

    <cffunction name="_getSelectUserHeaderValue" access="private" returntype="string" output="false">
        <cfset var memberID = trim(getConfigValue("dropbox.select_user_member_id", "") & "")>
        <cfreturn memberID>
    </cffunction>

    <cffunction name="_collectFileEntries" access="private" returntype="array" output="false">
        <cfargument name="responseData" type="struct" required="true">

        <cfreturn _collectEntries(arguments.responseData, variables.allowedExtensions)>
    </cffunction>

    <cffunction name="_collectEntries" access="private" returntype="array" output="false">
        <cfargument name="responseData" type="struct" required="true">
        <cfargument name="allowedExtensions" type="string" required="false" default="">

        <cfset var files = []>
        <cfset var entry = {}>
        <cfset var pathDisplay = "">
        <cfset var ext = "">
        <cfset var allowAll = NOT len(trim(arguments.allowedExtensions & ""))>

        <cfif !structKeyExists(arguments.responseData, "entries") OR !isArray(arguments.responseData.entries)>
            <cfreturn files>
        </cfif>

        <cfloop array="#arguments.responseData.entries#" index="entry">
            <cfif (entry[".tag"] ?: "") EQ "file">
                <cfset pathDisplay = entry.path_display ?: entry.path_lower ?: "">
                <cfset ext = lCase(listLast(pathDisplay, "."))>
                <cfif len(pathDisplay) AND (allowAll OR listFindNoCase(arguments.allowedExtensions, ext))>
                    <cfset arrayAppend(files, {
                        filename = listLast(pathDisplay, "/\\"),
                        path = pathDisplay,
                        extension = ext,
                        size = structKeyExists(entry, "size") ? entry.size : "",
                        clientModified = structKeyExists(entry, "client_modified") ? entry.client_modified : ""
                    })>
                </cfif>
            </cfif>
        </cfloop>

        <cfreturn files>
    </cffunction>

    <cffunction name="_extractErrorMessage" access="private" returntype="string" output="false">
        <cfargument name="httpResp" required="true">
        <cfargument name="fallbackMessage" type="string" required="true">

        <cfset var messageText = arguments.fallbackMessage>
        <cfset var parsed = {}>
        <cfset var appKey = trim(getConfigValue("dropbox.app_key", "") & "")>
        <cfset var appKeyHint = len(appKey) GTE 6 ? (left(appKey, 3) & "..." & right(appKey, 3)) : appKey>

        <cfif isStruct(arguments.httpResp) AND structKeyExists(arguments.httpResp, "statusCode")>
            <cfset messageText &= " (HTTP #arguments.httpResp.statusCode#)">
        </cfif>

        <cfif isStruct(arguments.httpResp) AND structKeyExists(arguments.httpResp, "fileContent") AND isJSON(arguments.httpResp.fileContent ?: "")>
            <cfset parsed = deserializeJSON(arguments.httpResp.fileContent)>
            <cfif structKeyExists(parsed, "error_description") AND len(trim(parsed.error_description ?: ""))>
                <cfreturn messageText & ": " & parsed.error_description>
            </cfif>
            <cfif structKeyExists(parsed, "error_summary") AND len(trim(parsed.error_summary ?: ""))>
                <cfif findNoCase("missing_scope", parsed.error_summary)>
                    <cfreturn messageText & ": " & parsed.error_summary & " (App key: " & appKeyHint & "). Verify app scopes include files.metadata.read and files.content.read, then generate a NEW refresh token and update AppConfig.">
                </cfif>
                <cfreturn messageText & ": " & parsed.error_summary>
            </cfif>
            <cfif structKeyExists(parsed, "error")>
                <cfreturn messageText & ": " & serializeJSON(parsed.error)>
            </cfif>
        </cfif>

        <cfif isStruct(arguments.httpResp) AND structKeyExists(arguments.httpResp, "fileContent") AND len(trim(arguments.httpResp.fileContent ?: ""))>
            <cfreturn messageText & ": " & left(arguments.httpResp.fileContent, 400)>
        </cfif>

        <cfreturn messageText>
    </cffunction>

    <cffunction name="_normalizeDropboxPath" access="private" returntype="string" output="false">
        <cfargument name="rawPath" type="string" required="true">

        <cfset var pathValue = trim(arguments.rawPath)>

        <cfif !len(pathValue) OR pathValue EQ "/">
            <cfreturn "">
        </cfif>

        <cfset pathValue = urlDecode(pathValue)>
        <cfset pathValue = replace(pathValue, "\\", "/", "all")>
        <cfset pathValue = reReplace(pathValue, "/+", "/", "all")>

        <cfif left(pathValue, 1) NEQ "/">
            <cfset pathValue = "/" & pathValue>
        </cfif>

        <cfif len(pathValue) GT 1 AND right(pathValue, 1) EQ "/">
            <cfset pathValue = left(pathValue, len(pathValue) - 1)>
        </cfif>

        <cfreturn pathValue>
    </cffunction>

    <cffunction name="getConfigValue" access="private" returntype="string" output="false">
        <cfargument name="keyName" type="string" required="true">
        <cfargument name="defaultValue" type="string" required="false" default="">

        <cfset var keyRaw = trim(arguments.keyName & "")>
        <cfset var valueOut = trim(arguments.defaultValue & "")>
        <cfset var appKey = uCase(reReplace(keyRaw, "[^A-Za-z0-9]+", "_", "all"))>
        <cfset var env = {}>
        <cfset var envKey = "">

        <cfif structKeyExists(variables, "config") AND isStruct(variables.config)>
            <cfif structKeyExists(variables.config, keyRaw) AND len(trim(variables.config[keyRaw] & ""))>
                <cfreturn trim(variables.config[keyRaw] & "")>
            </cfif>
            <cfif structKeyExists(variables.config, appKey) AND len(trim(variables.config[appKey] & ""))>
                <cfreturn trim(variables.config[appKey] & "")>
            </cfif>
        </cfif>

        <cfif structKeyExists(variables, "configReader") AND isObject(variables.configReader)>
            <cftry>
                <cfset valueOut = trim(variables.configReader.getValue(keyRaw, valueOut) & "")>
                <cfif len(valueOut)>
                    <cfreturn valueOut>
                </cfif>
                <cfcatch type="any"></cfcatch>
            </cftry>
        </cfif>

        <cfif structKeyExists(application, appKey) AND len(trim(application[appKey] & ""))>
            <cfreturn trim(application[appKey] & "")>
        </cfif>

        <cftry>
            <cfset env = getSystemEnvironment()>
            <cfif structKeyExists(env, appKey)>
                <cfset valueOut = trim(env[appKey] & "")>
            <cfelse>
                <cfloop collection="#env#" item="envKey">
                    <cfif compareNoCase(envKey, appKey) EQ 0>
                        <cfset valueOut = trim(env[envKey] & "")>
                        <cfbreak>
                    </cfif>
                </cfloop>
            </cfif>
            <cfcatch type="any"></cfcatch>
        </cftry>

        <cfif len(valueOut)>
            <cfreturn valueOut>
        </cfif>

        <cftry>
            <cfset valueOut = trim(createObject("java", "java.lang.System").getenv(appKey) & "")>
            <cfcatch type="any">
                <cfset valueOut = trim(arguments.defaultValue & "")>
            </cfcatch>
        </cftry>

        <cfreturn valueOut>
    </cffunction>

</cfcomponent>
