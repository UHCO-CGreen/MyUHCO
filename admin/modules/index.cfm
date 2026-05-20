<cfsetting showdebugoutput="false">
<!---
  admin/modules/index.cfm — Module Registry Admin (Step A4)
  Requires portal login + portal.admin permission.
  Lists all registered modules; enables/disables individual modules; reloads registry from disk.
  Dashboard panel admin controls manage enable state and sort order at the registry level.
  Sidebar module ordering is managed with up/down controls per nav group.
--->

<!--- ── Auth gate ────────────────────────────────────────────────────────── --->
<cfif NOT (
    structKeyExists(session, "user")
    AND structKeyExists(session.user, "userID")
    AND isNumeric(session.user.userID)
    AND session.user.userID GT 0
)>
  <cflocation url="/login.cfm" addtoken="false">
</cfif>
<cfset application.accessService.requirePermission("portal.admin")>

<!--- ── Handle POST actions ─────────────────────────────────────────────── --->
<cfset _flash = { msg: "", type: "" }>
<cfset _generatedPublicToken = "">
<cfset _generatedPublicUrl = "">
<cfset _generatedPublicModuleId = "">
<cfif cgi.request_method EQ "POST">
  <cfparam name="form._action"   default="">
  <cfparam name="form._moduleId" default="">
  <cfparam name="form._panelId"  default="">
  <cfparam name="form._panelOrder" default="">
  <cfparam name="form._direction" default="">

  <cfif form._action EQ "toggle">
    <cfset _modId = lCase(trim(form._moduleId & ""))>
    <cfif len(_modId)>
      <cflock name="moduleRegistryWrite" type="exclusive" timeout="10">
        <cftry>
          <cfset _regPath    = expandPath("/data/modules/registry.json")>
          <cfset _regParsed  = deserializeJSON(fileRead(_regPath, "UTF-8"))>
          <cfset _toggled    = false>
          <cfset _newState   = false>
          <cfloop from="1" to="#arrayLen(_regParsed)#" index="_ri">
            <cfif structKeyExists(_regParsed[_ri], "id") AND lCase(trim(_regParsed[_ri].id & "")) EQ _modId>
              <cfset _regParsed[_ri].enabled = NOT _regParsed[_ri].enabled>
              <cfset _newState = _regParsed[_ri].enabled>
              <cfset _toggled  = true>
              <cfbreak>
            </cfif>
          </cfloop>
          <cfif _toggled>
            <cffile action="write" file="#_regPath#" output="#serializeJSON(_regParsed)#" charset="UTF-8">
            <cfset application.moduleRegistry         = _regParsed>
            <cfset application.moduleRegistryLoadTime = now()>
            <cfset _flash = { msg: "Module '#encodeForHTML(_modId)#' #_newState ? 'enabled' : 'disabled'#. Registry reloaded.", type: "success" }>
          <cfelse>
            <cfset _flash = { msg: "Module '#encodeForHTML(_modId)#' not found in registry.", type: "warning" }>
          </cfif>
          <cfcatch type="any">
            <cfset _flash = { msg: "Error updating registry: #encodeForHTML(cfcatch.message)#", type: "danger" }>
          </cfcatch>
        </cftry>
      </cflock>
    </cfif>

  <cfelseif form._action EQ "toggleSidebar">
    <cfset _modId = lCase(trim(form._moduleId & ""))>
    <cfif len(_modId)>
      <cflock name="moduleRegistryWrite" type="exclusive" timeout="10">
        <cftry>
          <cfset _regPath    = expandPath("/data/modules/registry.json")>
          <cfset _regParsed  = deserializeJSON(fileRead(_regPath, "UTF-8"))>
          <cfset _toggled    = false>
          <cfset _newState   = true>
          <cfloop from="1" to="#arrayLen(_regParsed)#" index="_ri">
            <cfif structKeyExists(_regParsed[_ri], "id") AND lCase(trim(_regParsed[_ri].id & "")) EQ _modId>
              <cfif NOT structKeyExists(_regParsed[_ri], "nav") OR NOT isStruct(_regParsed[_ri].nav)>
                <cfset _regParsed[_ri].nav = {}>
              </cfif>
              <cfset _currentSidebarState = !structKeyExists(_regParsed[_ri].nav, "showInSidebar") OR _regParsed[_ri].nav.showInSidebar EQ true>
              <cfset _regParsed[_ri].nav.showInSidebar = NOT _currentSidebarState>
              <cfset _newState = _regParsed[_ri].nav.showInSidebar>
              <cfset _toggled  = true>
              <cfbreak>
            </cfif>
          </cfloop>
          <cfif _toggled>
            <cffile action="write" file="#_regPath#" output="#serializeJSON(_regParsed)#" charset="UTF-8">
            <cfset application.moduleRegistry         = _regParsed>
            <cfset application.moduleRegistryLoadTime = now()>
            <cfset _flash = { msg: "Module '#encodeForHTML(_modId)#' sidebar visibility set to #_newState ? 'shown' : 'hidden'#.", type: "success" }>
          <cfelse>
            <cfset _flash = { msg: "Module '#encodeForHTML(_modId)#' not found in registry.", type: "warning" }>
          </cfif>
          <cfcatch type="any">
            <cfset _flash = { msg: "Error updating sidebar visibility: #encodeForHTML(cfcatch.message)#", type: "danger" }>
          </cfcatch>
        </cftry>
      </cflock>
    </cfif>

  <cfelseif form._action EQ "moveSidebarOrder">
    <cfset _modId = lCase(trim(form._moduleId & ""))>
    <cfset _direction = lCase(trim(form._direction & ""))>
    <cfif len(_modId) AND listFindNoCase("up,down", _direction)>
      <cflock name="moduleRegistryWrite" type="exclusive" timeout="10">
        <cftry>
          <cfset _regPath    = expandPath("/data/modules/registry.json")>
          <cfset _regParsed  = deserializeJSON(fileRead(_regPath, "UTF-8"))>
          <cfset _updated    = false>
          <cfset _targetGroup = "">
          <cfset _groupItems = []>
          <cfset _targetPosition = 0>
          <cfset _swapPosition = 0>
          <cfset _groupItem = {}>

          <cfloop from="1" to="#arrayLen(_regParsed)#" index="_ri">
            <cfif structKeyExists(_regParsed[_ri], "id") AND lCase(trim(_regParsed[_ri].id & "")) EQ _modId>
              <cfif structKeyExists(_regParsed[_ri], "nav") AND isStruct(_regParsed[_ri].nav)>
                <cfset _targetGroup = structKeyExists(_regParsed[_ri].nav, "group") ? lCase(trim(_regParsed[_ri].nav.group & "")) : "">
              </cfif>
              <cfbreak>
            </cfif>
          </cfloop>

          <cfif len(_targetGroup)>
            <cfloop from="1" to="#arrayLen(_regParsed)#" index="_ri">
              <cfif structKeyExists(_regParsed[_ri], "nav") AND isStruct(_regParsed[_ri].nav)>
                <cfif structKeyExists(_regParsed[_ri].nav, "group") AND lCase(trim(_regParsed[_ri].nav.group & "")) EQ _targetGroup>
                  <cfset arrayAppend(_groupItems, {
                    registryIndex: _ri,
                    id: structKeyExists(_regParsed[_ri], "id") ? lCase(trim(_regParsed[_ri].id & "")) : "",
                    sortOrder: structKeyExists(_regParsed[_ri].nav, "sortOrder") ? int(val(_regParsed[_ri].nav.sortOrder)) : 99
                  })>
                </cfif>
              </cfif>
            </cfloop>

            <cfif arrayLen(_groupItems) GT 1>
              <cfset arraySort(_groupItems, function(leftItem, rightItem) {
                if (leftItem.sortOrder LT rightItem.sortOrder) return -1;
                if (leftItem.sortOrder GT rightItem.sortOrder) return 1;
                if (leftItem.id LT rightItem.id) return -1;
                if (leftItem.id GT rightItem.id) return 1;
                return 0;
              })>

              <cfloop from="1" to="#arrayLen(_groupItems)#" index="_gi">
                <cfif _groupItems[_gi].id EQ _modId>
                  <cfset _targetPosition = _gi>
                  <cfbreak>
                </cfif>
              </cfloop>

              <cfif _targetPosition GT 0>
                <cfset _swapPosition = _direction EQ "up" ? (_targetPosition - 1) : (_targetPosition + 1)>
                <cfif _swapPosition GTE 1 AND _swapPosition LTE arrayLen(_groupItems)>
                  <cfset _groupItem = _groupItems[_targetPosition]>
                  <cfset _groupItems[_targetPosition] = _groupItems[_swapPosition]>
                  <cfset _groupItems[_swapPosition] = _groupItem>

                  <cfloop from="1" to="#arrayLen(_groupItems)#" index="_gi">
                    <cfset _regParsed[_groupItems[_gi].registryIndex].nav.sortOrder = _gi * 10>
                  </cfloop>
                  <cfset _updated = true>
                </cfif>
              </cfif>
            </cfif>
          </cfif>

          <cfif _updated>
            <cffile action="write" file="#_regPath#" output="#serializeJSON(_regParsed)#" charset="UTF-8">
            <cfset application.moduleRegistry         = _regParsed>
            <cfset application.moduleRegistryLoadTime = now()>
            <cfset _flash = { msg: "Sidebar order updated for module '#encodeForHTML(_modId)#'.", type: "success" }>
          <cfelse>
            <cfset _flash = { msg: "Sidebar order could not be changed for module '#encodeForHTML(_modId)#'.", type: "warning" }>
          </cfif>
          <cfcatch type="any">
            <cfset _flash = { msg: "Error updating sidebar order: #encodeForHTML(cfcatch.message)#", type: "danger" }>
          </cfcatch>
        </cftry>
      </cflock>
    </cfif>

  <cfelseif form._action EQ "togglePanel">
    <cfset _modId = lCase(trim(form._moduleId & ""))>
    <cfset _panelId = lCase(trim(form._panelId & ""))>
    <cfif len(_modId) AND len(_panelId)>
      <cflock name="moduleRegistryWrite" type="exclusive" timeout="10">
        <cftry>
          <cfset _regPath    = expandPath("/data/modules/registry.json")>
          <cfset _regParsed  = deserializeJSON(fileRead(_regPath, "UTF-8"))>
          <cfset _toggled    = false>
          <cfset _newState   = false>
          <cfloop from="1" to="#arrayLen(_regParsed)#" index="_ri">
            <cfif structKeyExists(_regParsed[_ri], "id") AND lCase(trim(_regParsed[_ri].id & "")) EQ _modId>
              <cfif structKeyExists(_regParsed[_ri], "dashboard") AND isStruct(_regParsed[_ri].dashboard) AND structKeyExists(_regParsed[_ri].dashboard, "panels") AND isArray(_regParsed[_ri].dashboard.panels)>
                <cfloop from="1" to="#arrayLen(_regParsed[_ri].dashboard.panels)#" index="_pi">
                  <cfif structKeyExists(_regParsed[_ri].dashboard.panels[_pi], "id") AND lCase(trim(_regParsed[_ri].dashboard.panels[_pi].id & "")) EQ _panelId>
                    <cfset _currentState = !structKeyExists(_regParsed[_ri].dashboard.panels[_pi], "enabled") OR _regParsed[_ri].dashboard.panels[_pi].enabled EQ true>
                    <cfset _regParsed[_ri].dashboard.panels[_pi].enabled = NOT _currentState>
                    <cfset _newState = _regParsed[_ri].dashboard.panels[_pi].enabled>
                    <cfset _toggled = true>
                    <cfbreak>
                  </cfif>
                </cfloop>
              </cfif>
              <cfbreak>
            </cfif>
          </cfloop>
          <cfif _toggled>
            <cffile action="write" file="#_regPath#" output="#serializeJSON(_regParsed)#" charset="UTF-8">
            <cfset application.moduleRegistry         = _regParsed>
            <cfset application.moduleRegistryLoadTime = now()>
            <cfset _flash = { msg: "Panel '#encodeForHTML(_panelId)#' for module '#encodeForHTML(_modId)#' set to #_newState ? 'enabled' : 'disabled'#.", type: "success" }>
          <cfelse>
            <cfset _flash = { msg: "Panel '#encodeForHTML(_panelId)#' for module '#encodeForHTML(_modId)#' was not found.", type: "warning" }>
          </cfif>
          <cfcatch type="any">
            <cfset _flash = { msg: "Error updating dashboard panel: #encodeForHTML(cfcatch.message)#", type: "danger" }>
          </cfcatch>
        </cftry>
      </cflock>
    </cfif>

  <cfelseif form._action EQ "savePanelOrder">
    <cfset _modId = lCase(trim(form._moduleId & ""))>
    <cfset _panelOrder = trim(form._panelOrder & "")>
    <cfif len(_modId) AND len(_panelOrder)>
      <cflock name="moduleRegistryWrite" type="exclusive" timeout="10">
        <cftry>
          <cfset _regPath    = expandPath("/data/modules/registry.json")>
          <cfset _regParsed  = deserializeJSON(fileRead(_regPath, "UTF-8"))>
          <cfset _updated    = false>
          <cfset _panelOrderList = listToArray(_panelOrder)>
          <cfset _panelOrderMap = structNew()>
          <cfset _existingPanels = []>
          <cfset _reorderedPanels = []>
          <cfset _panelItem = {}>
          <cfset _panelLookupId = "">
          <cfset _orderIndex = 0>
          <cfloop from="1" to="#arrayLen(_panelOrderList)#" index="_poi">
            <cfset _panelOrderMap[lCase(trim(_panelOrderList[_poi] & ""))] = _poi>
          </cfloop>
          <cfloop from="1" to="#arrayLen(_regParsed)#" index="_ri">
            <cfif structKeyExists(_regParsed[_ri], "id") AND lCase(trim(_regParsed[_ri].id & "")) EQ _modId>
              <cfif structKeyExists(_regParsed[_ri], "dashboard") AND isStruct(_regParsed[_ri].dashboard) AND structKeyExists(_regParsed[_ri].dashboard, "panels") AND isArray(_regParsed[_ri].dashboard.panels)>
                <cfset _existingPanels = _regParsed[_ri].dashboard.panels>
                <cfset arraySort(_existingPanels, function(leftPanel, rightPanel) {
                  var leftId = structKeyExists(leftPanel, "id") ? lCase(trim(leftPanel.id & "")) : "";
                  var rightId = structKeyExists(rightPanel, "id") ? lCase(trim(rightPanel.id & "")) : "";
                  var leftPos = structKeyExists(_panelOrderMap, leftId) ? _panelOrderMap[leftId] : 9999;
                  var rightPos = structKeyExists(_panelOrderMap, rightId) ? _panelOrderMap[rightId] : 9999;
                  if (leftPos LT rightPos) return -1;
                  if (leftPos GT rightPos) return 1;
                  return 0;
                })>
                <cfset _reorderedPanels = []>
                <cfloop from="1" to="#arrayLen(_existingPanels)#" index="_pi">
                  <cfset _panelItem = duplicate(_existingPanels[_pi])>
                  <cfset _orderIndex = _pi * 10>
                  <cfset _panelItem.sortOrder = _orderIndex>
                  <cfset arrayAppend(_reorderedPanels, _panelItem)>
                </cfloop>
                <cfset _regParsed[_ri].dashboard.panels = _reorderedPanels>
                <cfset _updated = true>
              </cfif>
              <cfbreak>
            </cfif>
          </cfloop>
          <cfif _updated>
            <cffile action="write" file="#_regPath#" output="#serializeJSON(_regParsed)#" charset="UTF-8">
            <cfset application.moduleRegistry         = _regParsed>
            <cfset application.moduleRegistryLoadTime = now()>
            <cfset _flash = { msg: "Dashboard panel order saved for module '#encodeForHTML(_modId)#'.", type: "success" }>
          <cfelse>
            <cfset _flash = { msg: "Dashboard panels for module '#encodeForHTML(_modId)#' were not found.", type: "warning" }>
          </cfif>
          <cfcatch type="any">
            <cfset _flash = { msg: "Error saving panel sort order: #encodeForHTML(cfcatch.message)#", type: "danger" }>
          </cfcatch>
        </cftry>
      </cflock>
    </cfif>

  <cfelseif form._action EQ "reload">
    <cftry>
      <cfset _regPath = expandPath("/data/modules/registry.json")>
      <cfif fileExists(_regPath)>
        <cfset _reloaded = deserializeJSON(fileRead(_regPath, "UTF-8"))>
        <cfset application.moduleRegistry = isArray(_reloaded) ? _reloaded : []>
      <cfelse>
        <cfset application.moduleRegistry = []>
      </cfif>
      <cfset application.moduleRegistryLoadTime = now()>
      <cfset _flash = { msg: "Registry reloaded from disk (#arrayLen(application.moduleRegistry)# module(s)).", type: "success" }>
      <cfcatch type="any">
        <cfset _flash = { msg: "Reload failed: #encodeForHTML(cfcatch.message)#", type: "danger" }>
      </cfcatch>
    </cftry>

  <cfelseif form._action EQ "generatePublicToken">
    <cfset _modId = lCase(trim(form._moduleId & ""))>
    <cfif len(_modId)>
      <cftry>
        <cfset _foundPublicModule = {}>
        <cfif structKeyExists(application, "moduleRegistry") AND isArray(application.moduleRegistry)>
          <cfloop array="#application.moduleRegistry#" index="_regModule">
            <cfif structKeyExists(_regModule, "id") AND lCase(trim(_regModule.id & "")) EQ _modId>
              <cfset _foundPublicModule = _regModule>
              <cfbreak>
            </cfif>
          </cfloop>
        </cfif>

        <cfif !structCount(_foundPublicModule)>
          <cfset _flash = { msg: "Module '#encodeForHTML(_modId)#' was not found.", type: "warning" }>
        <cfelseif !structKeyExists(application, "tokenService") OR !isObject(application.tokenService)>
          <cfset _flash = { msg: "TokenService is unavailable. Verify MYUHCO_SECRET is configured.", type: "danger" }>
        <cfelseif _foundPublicModule.requiresAuth>
          <cfset _flash = { msg: "Module '#encodeForHTML(_modId)#' requires portal auth and cannot use a public display token.", type: "warning" }>
        <cfelseif !structKeyExists(_foundPublicModule, "publicAccess") OR !isStruct(_foundPublicModule.publicAccess) OR !structKeyExists(_foundPublicModule.publicAccess, "mode") OR lCase(trim(_foundPublicModule.publicAccess.mode & "")) NEQ "token">
          <cfset _flash = { msg: "Module '#encodeForHTML(_modId)#' is not configured for public token access.", type: "warning" }>
        <cfelse>
          <cfset _generatedPublicToken = application.tokenService.signModuleAccessToken(_modId)>
          <cfset _generatedPublicModuleId = _modId>
          <cfset _scheme = (structKeyExists(cgi, "https") AND lCase(trim(cgi.https & "")) EQ "on") OR (structKeyExists(cgi, "server_port_secure") AND int(val(cgi.server_port_secure)) EQ 1) ? "https" : "http">
          <cfset _generatedPublicUrl = _scheme & "://" & cgi.http_host & "/index.cfm?module=" & encodeForURL(_modId) & "&token=" & encodeForURL(_generatedPublicToken)>
          <cfset _flash = { msg: "Generated a new public display URL for '#encodeForHTML(_modId)#'.", type: "success" }>
        </cfif>
        <cfcatch type="any">
          <cfset _flash = { msg: "Error generating public display token: #encodeForHTML(cfcatch.message)#", type: "danger" }>
        </cfcatch>
      </cftry>
    </cfif>
  </cfif>
</cfif>

<!--- ── Read current application state ──────────────────────────────────── --->
<cfset _registry = (structKeyExists(application, "moduleRegistry") AND isArray(application.moduleRegistry))
    ? application.moduleRegistry : []>
<cfset _loadTime = structKeyExists(application, "moduleRegistryLoadTime")
    ? application.moduleRegistryLoadTime : "">
<cfscript>
_displayRegistry = duplicate(_registry);
arraySort(_displayRegistry, function(leftMod, rightMod) {
  var leftGroup = (structKeyExists(leftMod, "nav") AND isStruct(leftMod.nav) AND structKeyExists(leftMod.nav, "group")) ? lCase(trim(leftMod.nav.group & "")) : "zzzz";
  var rightGroup = (structKeyExists(rightMod, "nav") AND isStruct(rightMod.nav) AND structKeyExists(rightMod.nav, "group")) ? lCase(trim(rightMod.nav.group & "")) : "zzzz";
  var leftOrder = (structKeyExists(leftMod, "nav") AND isStruct(leftMod.nav) AND structKeyExists(leftMod.nav, "sortOrder")) ? int(val(leftMod.nav.sortOrder)) : 9999;
  var rightOrder = (structKeyExists(rightMod, "nav") AND isStruct(rightMod.nav) AND structKeyExists(rightMod.nav, "sortOrder")) ? int(val(rightMod.nav.sortOrder)) : 9999;
  var leftName = structKeyExists(leftMod, "name") ? lCase(trim(leftMod.name & "")) : "";
  var rightName = structKeyExists(rightMod, "name") ? lCase(trim(rightMod.name & "")) : "";

  if (leftGroup LT rightGroup) return -1;
  if (leftGroup GT rightGroup) return 1;
  if (leftOrder LT rightOrder) return -1;
  if (leftOrder GT rightOrder) return 1;
  if (leftName LT rightName) return -1;
  if (leftName GT rightName) return 1;
  return 0;
});

_primaryDisplayRegistry = [];
_testDisplayRegistry = [];
for (_displayMod in _displayRegistry) {
  _displayGroup = (structKeyExists(_displayMod, "nav") AND isStruct(_displayMod.nav) AND structKeyExists(_displayMod.nav, "group")) ? lCase(trim(_displayMod.nav.group & "")) : "";
  if (_displayGroup EQ "test") {
    arrayAppend(_testDisplayRegistry, _displayMod);
  } else {
    arrayAppend(_primaryDisplayRegistry, _displayMod);
  }
}

_moduleTableConfigs = [];
if (arrayLen(_primaryDisplayRegistry)) {
  arrayAppend(_moduleTableConfigs, {
    title: "Registered Modules",
    items: _primaryDisplayRegistry
  });
}
if (arrayLen(_testDisplayRegistry)) {
  arrayAppend(_moduleTableConfigs, {
    title: "Test Modules",
    items: _testDisplayRegistry
  });
}

_navMoveMeta = {};
_navGroups = {};
for (_registryMod in _displayRegistry) {
  if (!structKeyExists(_registryMod, "nav") || !isStruct(_registryMod.nav)) {
    continue;
  }
  _groupKey = structKeyExists(_registryMod.nav, "group") ? lCase(trim(_registryMod.nav.group & "")) : "";
  if (!len(_groupKey)) {
    continue;
  }
  if (!structKeyExists(_navGroups, _groupKey)) {
    _navGroups[_groupKey] = [];
  }
  arrayAppend(_navGroups[_groupKey], {
    id: structKeyExists(_registryMod, "id") ? lCase(trim(_registryMod.id & "")) : "",
    sortOrder: structKeyExists(_registryMod.nav, "sortOrder") ? int(val(_registryMod.nav.sortOrder)) : 99
  });
}

for (_navGroupKey in _navGroups) {
  arraySort(_navGroups[_navGroupKey], function(leftItem, rightItem) {
    if (leftItem.sortOrder LT rightItem.sortOrder) return -1;
    if (leftItem.sortOrder GT rightItem.sortOrder) return 1;
    if (leftItem.id LT rightItem.id) return -1;
    if (leftItem.id GT rightItem.id) return 1;
    return 0;
  });

  for (_navIndex = 1; _navIndex LTE arrayLen(_navGroups[_navGroupKey]); _navIndex = _navIndex + 1) {
    _navItemId = _navGroups[_navGroupKey][_navIndex].id;
    _navMoveMeta[_navItemId] = {
      canMoveUp: _navIndex GT 1,
      canMoveDown: _navIndex LT arrayLen(_navGroups[_navGroupKey]),
      position: _navIndex,
      total: arrayLen(_navGroups[_navGroupKey])
    };
  }
}
</cfscript>

<!--- ── Type label helper ───────────────────────────────────────────────── --->
<cffunction name="_typeLabel" output="false" returntype="string">
  <cfargument name="t" type="numeric" required="true">
  <cfswitch expression="#arguments.t#">
    <cfcase value="1"><cfreturn "Viewer (CF include)"></cfcase>
    <cfcase value="2"><cfreturn "Dual CF"></cfcase>
    <cfcase value="3"><cfreturn "Coupled CF"></cfcase>
    <cfcase value="4"><cfreturn "External redirect"></cfcase>
    <cfdefaultcase><cfreturn "Type #arguments.t#"></cfdefaultcase>
  </cfswitch>
</cffunction>

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MyUHCO — Module Registry Admin</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
  <link rel="stylesheet" href="/assets/plugins/fontawesome-free/css/all.min.css">
  <link rel="stylesheet" href="/assets/css/dist/myuhco/admin.css">
  <link rel="stylesheet" href="/css/admin-module-registry.css?v=20260517-1">
</head>
<body class="module-registry-page">
<cfset portalUser = session.user>
<cfset roleDisplay = "">
<cfset gradYearDisplay = "">
<cfset canViewSettings = false>
<cfset canViewAdminDashboard = false>
<div class="portal-shell">
<cfinclude template="/includes/admin-sidebar.cfm">
<div class="mainContainer flex-grow-1" id="main">
<cfinclude template="/includes/portal-header.cfm">
<cfoutput>
<div class="border-bottom bg-white px-4 py-3 d-flex align-items-center justify-content-between">
  <h6 class="mb-0 fw-bold">Module Registry</h6>
  <div class="d-flex align-items-center gap-2">
    <form method="post" action="index.cfm" style="margin:0">
      <input type="hidden" name="_action" value="reload">
      <button type="submit" class="btn btn-reload">&##8635; Reload from Disk</button>
    </form>
    <a href="/admin/dashboard.cfm" class="btn btn-sm btn-outline-secondary">&larr; Admin</a>
  </div>
</div>

<div class="dash-body">
  <cfif len(_flash.msg)>
    <div class="flash flash-#encodeForHTML(_flash.type)#">#_flash.msg#</div>
  </cfif>

  <div class="meta-bar">
    <span><strong>#arrayLen(_registry)#</strong> module(s) in registry</span>
    <cfif isDate(_loadTime)>
      <span>Loaded: <strong>#dateTimeFormat(_loadTime, "mmm d, yyyy")# at #timeFormat(_loadTime, "h:nn:ss tt")#</strong></span>
    <cfelse>
      <span style="color:##c00">Registry load time unavailable &mdash; reinit required</span>
    </cfif>
    <span>Source: <code>data/modules/registry.json</code></span>
  </div>

  <cfif len(_generatedPublicUrl)>
    <div class="flash flash-success">
      <div><strong>Public display URL generated for #encodeForHTML(_generatedPublicModuleId)#.</strong></div>
      <div class="public-token-output">
        <label for="generatedDisplayUrl">Display URL</label>
        <input id="generatedDisplayUrl" type="text" value="#encodeForHTMLAttribute(_generatedPublicUrl)#" readonly onclick="this.select();">
      </div>
      <div class="public-token-output">
        <label for="generatedDisplayToken">Token</label>
        <input id="generatedDisplayToken" type="text" value="#encodeForHTMLAttribute(_generatedPublicToken)#" readonly onclick="this.select();">
      </div>
    </div>
  </cfif>

  <cfif arrayLen(_moduleTableConfigs)>
    <cfloop array="#_moduleTableConfigs#" index="_moduleTableConfig">
      <div class="panel module-registry-panel">
        <div class="panel-title">#encodeForHTML(_moduleTableConfig.title)#</div>
      <table class="module-registry-table">
        <thead>
          <tr>
            <th>ID</th>
            <th>Name</th>
            <th>Type</th>
            <th>Auth / Permissions</th>
            <th>Nav Group</th>
            <th>Sidebar</th>
            <th>Dashboard Panels</th>
            <th>Entry Point</th>
            <th>Ver</th>
            <th>Status</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody>
          <cfloop array="#_moduleTableConfig.items#" index="_mod">
            <cfset _modId      = structKeyExists(_mod, "id")          ? trim(_mod.id & "")                 : "">
            <cfset _modName    = structKeyExists(_mod, "name")        ? trim(_mod.name & "")               : "">
            <cfset _modType    = structKeyExists(_mod, "type")        ? int(val(_mod.type))                : 0>
            <cfset _modEP      = structKeyExists(_mod, "entryPoint")  ? trim(_mod.entryPoint & "")         : "">
            <cfset _modVer     = structKeyExists(_mod, "version")     ? trim(_mod.version & "")            : "">
            <cfset _modEnabled = structKeyExists(_mod, "enabled")     AND _mod.enabled>
            <cfset _modAuth    = structKeyExists(_mod, "requiresAuth") AND _mod.requiresAuth>
            <cfset _modPerms   = (structKeyExists(_mod, "permissions") AND isArray(_mod.permissions)) ? _mod.permissions : []>
            <cfset _modNavGrp  = (structKeyExists(_mod, "nav") AND isStruct(_mod.nav) AND structKeyExists(_mod.nav, "group")) ? trim(_mod.nav.group & "") : "">
            <cfset _modSidebarVisible = (structKeyExists(_mod, "nav") AND isStruct(_mod.nav) AND structKeyExists(_mod.nav, "showInSidebar")) ? (_mod.nav.showInSidebar EQ true) : true>
            <cfset _dashCfg = (structKeyExists(_mod, "dashboard") AND isStruct(_mod.dashboard)) ? _mod.dashboard : {}>
            <cfset _dashPanels = (structCount(_dashCfg) AND structKeyExists(_dashCfg, "panels") AND isArray(_dashCfg.panels)) ? _dashCfg.panels : []>
            <cfset _publicAccessCfg = (structKeyExists(_mod, "publicAccess") AND isStruct(_mod.publicAccess)) ? _mod.publicAccess : {}>
            <cfset _requiresPublicToken = structCount(_publicAccessCfg) AND structKeyExists(_publicAccessCfg, "mode") AND lCase(trim(_publicAccessCfg.mode & "")) EQ "token" AND (!structKeyExists(_publicAccessCfg, "required") OR _publicAccessCfg.required EQ true)>
            <cfset _navMoveInfo = structKeyExists(_navMoveMeta, lCase(_modId)) ? _navMoveMeta[lCase(_modId)] : { canMoveUp: false, canMoveDown: false, position: 1, total: 1 }>
            <cfscript>
              _sortedDashPanels = duplicate(_dashPanels);
              _dashPanelOrderIds = [];
              if (arrayLen(_sortedDashPanels)) {
                arraySort(_sortedDashPanels, function(leftPanel, rightPanel) {
                  var leftOrder = structKeyExists(leftPanel, "sortOrder") ? int(val(leftPanel.sortOrder)) : 99;
                  var rightOrder = structKeyExists(rightPanel, "sortOrder") ? int(val(rightPanel.sortOrder)) : 99;
                  return leftOrder - rightOrder;
                });
                for (_sortedDashPanel in _sortedDashPanels) {
                  if (isStruct(_sortedDashPanel) AND structKeyExists(_sortedDashPanel, "id")) {
                    arrayAppend(_dashPanelOrderIds, trim(_sortedDashPanel.id & ""));
                  }
                }
              }
              _dashPanelOrderValue = arrayToList(_dashPanelOrderIds, ",");
            </cfscript>
            <tr>
              <td><code>#encodeForHTML(_modId)#</code></td>
              <td>#encodeForHTML(_modName)#</td>
              <td><span class="badge b-type#_modType#">#_typeLabel(_modType)#</span></td>
              <td>
                <cfif _modAuth>
                  <span class="badge b-auth">auth required</span><br>
                </cfif>
                <cfif arrayLen(_modPerms)>
                  <cfloop array="#_modPerms#" index="_perm">
                    <span class="badge b-perm">#encodeForHTML(_perm)#</span>
                  </cfloop>
                <cfelseif NOT _modAuth>
                  <span style="color:##aaa;font-size:.78rem">public</span>
                </cfif>
              </td>
              <td class="nav-group">#len(_modNavGrp) ? encodeForHTML(_modNavGrp) : '<span style="color:##aaa">—</span>'#</td>
              <td><span class="badge #_modSidebarVisible ? 'b-enabled' : 'b-disabled'#">#_modSidebarVisible ? 'Shown' : 'Hidden'#</span></td>
              <td>
                <cfif arrayLen(_sortedDashPanels)>
                  <div class="panel-list panel-list--draggable" data-panel-list="true" data-module-id="#encodeForHTMLAttribute(_modId)#">
                    <cfloop array="#_sortedDashPanels#" index="_dashPanel">
                      <cfset _dashPanelId = structKeyExists(_dashPanel, "id") ? trim(_dashPanel.id & "") : "">
                      <cfset _dashPanelTitle = structKeyExists(_dashPanel, "title") ? trim(_dashPanel.title & "") : _dashPanelId>
                      <cfset _dashPanelEnabled = !structKeyExists(_dashPanel, "enabled") OR _dashPanel.enabled EQ true>
                      <div class="panel-item" draggable="true" data-panel-id="#encodeForHTMLAttribute(_dashPanelId)#">
                        <div class="panel-item-row">
                          <div>
                            <div><i class="fas fa-grip-vertical panel-drag-handle"></i>#encodeForHTML(_dashPanelTitle)#</div>
                            <div class="panel-id">#encodeForHTML(_dashPanelId)#</div>
                            <div class="panel-meta">#encodeForHTML(structKeyExists(_dashPanel, 'type') ? (_dashPanel.type & '') : 'link-list')# • #encodeForHTML(structKeyExists(_dashPanel, 'column') ? (_dashPanel.column & '') : 'main')#</div>
                          </div>
                          <span class="badge #_dashPanelEnabled ? 'b-enabled' : 'b-disabled'#">#_dashPanelEnabled ? 'Enabled' : 'Disabled'#</span>
                        </div>
                        <div class="panel-actions mt-2">
                          <form method="post" action="index.cfm" style="margin:0">
                            <input type="hidden" name="_action" value="togglePanel">
                            <input type="hidden" name="_moduleId" value="#encodeForHTMLAttribute(_modId)#">
                            <input type="hidden" name="_panelId" value="#encodeForHTMLAttribute(_dashPanelId)#">
                            <button type="submit" class="btn #_dashPanelEnabled ? 'btn-disable' : 'btn-enable'#">#_dashPanelEnabled ? 'Disable' : 'Enable'#</button>
                          </form>
                        </div>
                      </div>
                    </cfloop>
                  </div>
                  <div class="panel-order-wrap">
                    <form method="post" action="index.cfm" style="margin:0" data-panel-order-form="true">
                      <input type="hidden" name="_action" value="savePanelOrder">
                      <input type="hidden" name="_moduleId" value="#encodeForHTMLAttribute(_modId)#">
                      <input type="hidden" name="_panelOrder" value="#encodeForHTMLAttribute(_dashPanelOrderValue)#" data-panel-order-input="true">
                      <button type="submit" class="btn btn-panel">Save Panel Order</button>
                    </form>
                  </div>
                <cfelse>
                  <span style="color:##aaa">—</span>
                </cfif>
              </td>
              <td class="ep-cell">
                #encodeForHTML(_modEP)#
                <cfif _modType LT 4 AND len(_modId)>
                  <a href="/index.cfm?module=#encodeForURL(_modId)#" target="_blank" class="test-link">[test &nearr;]</a>
                </cfif>
              </td>
              <td>#encodeForHTML(_modVer)#</td>
              <td><span class="badge #_modEnabled ? 'b-enabled' : 'b-disabled'#">#_modEnabled ? 'Enabled' : 'Disabled'#</span></td>
              <td>
                <div style="display:flex; gap:6px; flex-wrap:wrap;">
                  <cfif len(_modNavGrp)>
                    <form method="post" action="index.cfm" style="margin:0">
                      <input type="hidden" name="_action" value="moveSidebarOrder">
                      <input type="hidden" name="_moduleId" value="#encodeForHTMLAttribute(_modId)#">
                      <input type="hidden" name="_direction" value="up">
                      <button type="submit" class="btn btn-panel" #NOT _navMoveInfo.canMoveUp ? 'disabled="disabled"' : ''# title="Move up within #encodeForHTMLAttribute(_modNavGrp)#">
                        &uarr;
                      </button>
                    </form>
                    <form method="post" action="index.cfm" style="margin:0">
                      <input type="hidden" name="_action" value="moveSidebarOrder">
                      <input type="hidden" name="_moduleId" value="#encodeForHTMLAttribute(_modId)#">
                      <input type="hidden" name="_direction" value="down">
                      <button type="submit" class="btn btn-panel" #NOT _navMoveInfo.canMoveDown ? 'disabled="disabled"' : ''# title="Move down within #encodeForHTMLAttribute(_modNavGrp)#">
                        &darr;
                      </button>
                    </form>
                  </cfif>
                  <form method="post" action="index.cfm" style="margin:0">
                    <input type="hidden" name="_action"   value="toggle">
                    <input type="hidden" name="_moduleId" value="#encodeForHTMLAttribute(_modId)#">
                    <button type="submit" class="btn #_modEnabled ? 'btn-disable' : 'btn-enable'#">
                      #_modEnabled ? 'Disable' : 'Enable'#
                    </button>
                  </form>
                  <form method="post" action="index.cfm" style="margin:0">
                    <input type="hidden" name="_action"   value="toggleSidebar">
                    <input type="hidden" name="_moduleId" value="#encodeForHTMLAttribute(_modId)#">
                    <button type="submit" class="btn btn-reload">
                      #_modSidebarVisible ? 'Hide Nav' : 'Show Nav'#
                    </button>
                  </form>
                  <cfif _requiresPublicToken AND NOT _modAuth>
                    <form method="post" action="index.cfm" style="margin:0">
                      <input type="hidden" name="_action" value="generatePublicToken">
                      <input type="hidden" name="_moduleId" value="#encodeForHTMLAttribute(_modId)#">
                      <button type="submit" class="btn btn-panel">Generate Display URL</button>
                    </form>
                  </cfif>
                </div>
              </td>
            </tr>
          </cfloop>
        </tbody>
      </table>
      </div>
    </cfloop>
  <cfelse>
    <div class="panel module-registry-panel">
      <div class="panel-title">Registered Modules</div>
      <div class="no-data">
        No modules registered. Add entries to <code>data/modules/registry.json</code> and click <strong>Reload from Disk</strong>.
      </div>
    </div>
  </cfif>
</div>
</cfoutput>
</div>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
<script>
document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function(el) { new bootstrap.Tooltip(el); });
(function () {
  if (localStorage.getItem('sidebarCollapsed') === 'true') { document.body.classList.add('sidebar-collapsed'); }
  var btn = document.getElementById('sidebarToggle');
  if (btn) {
    btn.addEventListener('click', function () {
      if (window.innerWidth <= 991) { document.body.classList.toggle('sidebar-open'); return; }
      var collapsed = document.body.classList.toggle('sidebar-collapsed');
      localStorage.setItem('sidebarCollapsed', String(collapsed));
    });
  }

  document.querySelectorAll('[data-panel-list="true"]').forEach(function (listEl) {
    var draggedItem = null;
    var orderForm = listEl.parentElement.querySelector('[data-panel-order-form="true"]');
    var orderInput = orderForm ? orderForm.querySelector('[data-panel-order-input="true"]') : null;

    function syncOrder() {
      if (!orderInput) {
        return;
      }
      var orderedIds = Array.prototype.map.call(listEl.querySelectorAll('[data-panel-id]'), function (itemEl) {
        return itemEl.getAttribute('data-panel-id') || '';
      }).filter(function (value) {
        return value.length > 0;
      });
      orderInput.value = orderedIds.join(',');
    }

    listEl.querySelectorAll('[data-panel-id]').forEach(function (itemEl) {
      itemEl.addEventListener('dragstart', function () {
        draggedItem = itemEl;
        itemEl.classList.add('is-dragging');
      });

      itemEl.addEventListener('dragend', function () {
        itemEl.classList.remove('is-dragging');
        draggedItem = null;
        syncOrder();
      });

      itemEl.addEventListener('dragover', function (event) {
        event.preventDefault();
        if (!draggedItem || draggedItem === itemEl) {
          return;
        }
        var rect = itemEl.getBoundingClientRect();
        var insertBefore = event.clientY < rect.top + (rect.height / 2);
        if (insertBefore) {
          listEl.insertBefore(draggedItem, itemEl);
        } else {
          listEl.insertBefore(draggedItem, itemEl.nextSibling);
        }
      });
    });

    syncOrder();
  });
}());
</script>
</body>
</html>
