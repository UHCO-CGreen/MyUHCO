<cfsetting showdebugoutput="false">
<cfscript>
hasPortalSession = structKeyExists(session, "user");
portalUser = hasPortalSession ? session.user : {};
currentUserId = "";
if (hasPortalSession AND structKeyExists(portalUser, "userId") AND len(trim(portalUser.userId & ""))) {
  currentUserId = trim(portalUser.userId & "");
} else if (hasPortalSession AND structKeyExists(portalUser, "username") AND len(trim(portalUser.username & ""))) {
  currentUserId = trim(portalUser.username & "");
}
if (!len(currentUserId)) {
  currentUserId = "anonymous";
}

dashboardPanels = [];
dashboardMainPanels = [];
dashboardSidebarPanels = [];
dashboardStylesheets = [];
dashboardScripts = [];
standaloneModuleRequest = false;
publicModuleTokenRequired = false;
publicModuleTokenValid = true;
publicModuleTokenFailureMessage = "";
pageInlineFlashMessage = "";
pageInlineFlashType = "success";
pageInlineEditing = false;
pageInlineAdminAllowed = hasPortalSession
  AND structKeyExists(application, "accessService")
  AND isObject(application.accessService)
  AND application.accessService.hasPermission("portal.admin");

// ── Module dispatch resolution ──────────────────────────────────────────────────────
dispatchMode = "dashboard";
activeModule = {};
activePage = {};
if (structKeyExists(url, "module") AND len(trim(url.module & ""))) {
  _reqModID = lCase(trim(url.module));
  _foundMod = {};
  if (structKeyExists(application, "moduleRegistry") AND isArray(application.moduleRegistry)) {
    for (_reg in application.moduleRegistry) {
      if (structKeyExists(_reg, "id") AND lCase(trim(_reg.id)) EQ _reqModID) {
        _foundMod = _reg;
        break;
      }
    }
  }
  if (!structCount(_foundMod)) {
    dispatchMode = "error-404";
  } else if (!_foundMod.enabled) {
    dispatchMode = "error-503";
  } else if (_foundMod.requiresAuth AND !hasPortalSession) {
    location("/login.cfm", false);
  } else {
    _hasAccess = true;
    if (
      _foundMod.requiresAuth
      AND structKeyExists(application, "accessService")
      AND isObject(application.accessService)
      AND isArray(_foundMod.permissions)
      AND arrayLen(_foundMod.permissions)
    ) {
      _hasAccess = false;
      for (_perm in _foundMod.permissions) {
        if (application.accessService.hasPermission(_perm)) {
          _hasAccess = true;
          break;
        }
      }
    }
    if (!_hasAccess) {
      dispatchMode = "error-403";
    } else if (int(val(_foundMod.type)) EQ 4) {
      location("/auth/redirect.cfm?to=" & urlEncodedFormat(_foundMod.entryPoint), false);
    } else {
      dispatchMode = "module-include";
      activeModule = _foundMod;
      standaloneModuleRequest = structKeyExists(_foundMod, "renderMode")
        AND lCase(trim(_foundMod.renderMode & "")) EQ "standalone";

      if (
        !_foundMod.requiresAuth
        AND structKeyExists(_foundMod, "publicAccess")
        AND isStruct(_foundMod.publicAccess)
        AND structKeyExists(_foundMod.publicAccess, "mode")
        AND lCase(trim(_foundMod.publicAccess.mode & "")) EQ "token"
        AND structKeyExists(_foundMod.publicAccess, "required")
        AND _foundMod.publicAccess.required EQ true
      ) {
        publicModuleTokenRequired = true;
        publicModuleTokenValid = false;

        if (!structKeyExists(url, "token") OR !len(trim(url.token & ""))) {
          publicModuleTokenFailureMessage = "Display unavailable.";
        } else if (!structKeyExists(application, "tokenService") OR !isObject(application.tokenService)) {
          publicModuleTokenFailureMessage = "Display unavailable.";
        } else {
          _publicModuleTokenCheck = application.tokenService.verifyModuleAccessToken(trim(url.token & ""), _foundMod.id);
          publicModuleTokenValid = _publicModuleTokenCheck.valid;
          if (!publicModuleTokenValid) {
            publicModuleTokenFailureMessage = "Display unavailable.";
          }
        }
      }
    }
  }

} else if (structKeyExists(url, "page") AND len(trim(url.page & ""))) {
  _requestedPageSlug = lCase(trim(url.page & ""));
  if (!hasPortalSession) {
    location("/login.cfm", false);
  } else if (!structKeyExists(application, "pageService") OR !isObject(application.pageService)) {
    dispatchMode = "error-503";
  } else {
    _pageLookup = application.pageService.getPublishedPageBySlug(_requestedPageSlug);
    if (!_pageLookup.success) {
      dispatchMode = "error-503";
    } else if (_pageLookup.isDraft) {
      dispatchMode = "error-503";
    } else if (!_pageLookup.found) {
      dispatchMode = "error-404";
    } else {
      dispatchMode = "page-render";
      activePage = _pageLookup.page;
    }
  }
}

if (
  dispatchMode EQ "page-render"
  AND cgi.request_method EQ "POST"
  AND structKeyExists(form, "_pageInlineAction")
  AND form._pageInlineAction EQ "saveInlinePage"
  AND pageInlineAdminAllowed
) {
  _inlineSaveResult = application.pageService.savePage({
    pageId = structKeyExists(form, "pageId") ? form.pageId : 0,
    slug = structKeyExists(form, "slug") ? form.slug : "",
    title = structKeyExists(form, "title") ? form.title : "",
    navLabel = structKeyExists(form, "navLabel") ? form.navLabel : "",
    summary = structKeyExists(form, "summary") ? form.summary : "",
    bodyHtml = structKeyExists(form, "bodyHtml") ? form.bodyHtml : "",
    isPublished = structKeyExists(form, "isPublished") ? 1 : 0,
    showInNav = structKeyExists(form, "showInNav") ? 1 : 0,
    navSortOrder = structKeyExists(form, "navSortOrder") ? form.navSortOrder : 100
  }, session.user.userID);

  if (_inlineSaveResult.success) {
    _pageLookup = application.pageService.getPublishedPageBySlug(_requestedPageSlug);
    if (_pageLookup.success AND _pageLookup.found) {
      activePage = _pageLookup.page;
      pageInlineFlashMessage = "Page saved.";
      pageInlineFlashType = "success";
      pageInlineEditing = false;
    } else {
      location("/index.cfm?page=" & urlEncodedFormat(_requestedPageSlug), false);
    }
  } else {
    pageInlineFlashMessage = _inlineSaveResult.message;
    pageInlineFlashType = "danger";
    pageInlineEditing = true;
    activePage = {
      pageId = int(val(structKeyExists(form, "pageId") ? form.pageId : 0)),
      slug = trim(structKeyExists(form, "slug") ? form.slug : ""),
      title = trim(structKeyExists(form, "title") ? form.title : ""),
      navLabel = trim(structKeyExists(form, "navLabel") ? form.navLabel : ""),
      summary = trim(structKeyExists(form, "summary") ? form.summary : ""),
      bodyHtml = structKeyExists(form, "bodyHtml") ? form.bodyHtml & "" : "",
      isPublished = structKeyExists(form, "isPublished"),
      showInNav = structKeyExists(form, "showInNav"),
      navSortOrder = int(val(structKeyExists(form, "navSortOrder") ? form.navSortOrder : 100))
    };
  }
}

</cfscript>
<cfif standaloneModuleRequest AND publicModuleTokenRequired AND NOT publicModuleTokenValid>
  <cfheader statuscode="403">
  <!doctype html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Display Unavailable</title>
    <style>
      body { margin: 0; font-family: Arial, sans-serif; background: #111827; color: #f3f4f6; display: flex; min-height: 100vh; align-items: center; justify-content: center; }
      .display-denied { padding: 24px 28px; border: 1px solid #374151; border-radius: 12px; background: #1f2937; font-size: 1.1rem; }
    </style>
  </head>
  <body>
    <div class="display-denied"><cfoutput>#encodeForHTML(publicModuleTokenFailureMessage)#</cfoutput></div>
  </body>
  </html>
  <cfabort>
</cfif>
<cfif standaloneModuleRequest>
  <cfinclude template="/#activeModule.entryPoint#">
  <cfabort>
</cfif>
<cfscript>

if (!hasPortalSession) {
  location("/login.cfm", false);
}

linksFlashMessage = "";
linksFlashStatus = "";
if (structKeyExists(url, "linksMessage")) {
  linksFlashMessage = trim(url.linksMessage & "");
}
if (structKeyExists(url, "linksStatus")) {
  linksFlashStatus = lCase(trim(url.linksStatus & ""));
}

roleLabel = "";
roleDisplay = "";
flagsRaw = "";
gradYearDisplay = "";
organizationsRaw = "";
canViewSettings = false;
canViewAdminDashboard = false;

if (structKeyExists(portalUser, "flags")) {
  if (isSimpleValue(portalUser.flags)) {
    flagsRaw = trim(portalUser.flags & "");
  } else {
    flagsRaw = serializeJSON(portalUser.flags);
  }
}
roleLabel = lCase(flagsRaw);

if (structKeyExists(portalUser, "organizations")) {
  if (isSimpleValue(portalUser.organizations)) {
    organizationsRaw = lCase(trim(portalUser.organizations & ""));
  } else {
    organizationsRaw = lCase(serializeJSON(portalUser.organizations));
  }
}

if (findNoCase("web services", organizationsRaw) OR findNoCase("web-services", organizationsRaw)) {
  canViewSettings = true;
}

canViewAdminDashboard = (structKeyExists(application, "accessService") AND isObject(application.accessService))
                      ? application.accessService.hasPermission("portal.admin")
                      : false;

canSeeAllUserTypeDocs = canViewSettings;
userTypeKey = "";

if (findNoCase("current-student", roleLabel) OR findNoCase("current student", roleLabel)) {
  roleDisplay = "Current Student";
} else if (findNoCase("faculty-adjunct", roleLabel) OR findNoCase("faculty adjunct", roleLabel)) {
  roleDisplay = "Faculty-Adjunct";
} else if (
  findNoCase("faculty-fulltime", roleLabel)
  OR findNoCase("faculty fulltime", roleLabel)
  OR (findNoCase("faculty", roleLabel) AND findNoCase("full", roleLabel))
) {
  roleDisplay = "Faculty-Fulltime";
} else if (findNoCase("faculty", roleLabel)) {
  roleDisplay = "Faculty";
} else if (findNoCase("staff", roleLabel)) {
  roleDisplay = "Staff";
}

if (left(roleDisplay, 7) EQ "Faculty") {
  userTypeKey = "faculty";
} else if (roleDisplay EQ "Staff") {
  userTypeKey = "staff";
} else if (roleDisplay EQ "Current Student") {
  userTypeKey = "students";
} else if (findNoCase("faculty", roleLabel)) {
  userTypeKey = "faculty";
} else if (findNoCase("staff", roleLabel)) {
  userTypeKey = "staff";
} else if (findNoCase("student", roleLabel)) {
  userTypeKey = "students";
}

if (
  roleDisplay EQ "Current Student"
  AND structKeyExists(portalUser, "currentGradYear")
  AND len(trim(portalUser.currentGradYear & ""))
) {
  gradYearDisplay = " (" & trim(portalUser.currentGradYear & "") & ")";
}

// ── Registry nav items ────────────────────────────────────────────────────────
_navItems = [];
_navActiveModule = structKeyExists(url, "module") ? lCase(trim(url.module & "")) : "";
_navActivePage = structKeyExists(url, "page") ? lCase(trim(url.page & "")) : "";
if (structKeyExists(application, "moduleRegistry") AND isArray(application.moduleRegistry)) {
  for (_navMod in application.moduleRegistry) {
    if (!_navMod.enabled) continue;
    if (!structKeyExists(_navMod, "nav")) continue;
    _navShowInSidebar = !structKeyExists(_navMod.nav, "showInSidebar") OR _navMod.nav.showInSidebar EQ true;
    if (!_navShowInSidebar) continue;
    if (_navMod.requiresAuth) {
      _navGranted = true;
      if (isArray(_navMod.permissions) AND arrayLen(_navMod.permissions)) {
        _navGranted = false;
        if (
          structKeyExists(application, "accessService")
          AND isObject(application.accessService)
        ) {
          for (_navPerm in _navMod.permissions) {
            if (application.accessService.hasPermission(_navPerm)) {
              _navGranted = true;
              break;
            }
          }
        }
      }
      if (!_navGranted) continue;
    }
    arrayAppend(_navItems, {
      type:      "module",
      id:        _navMod.id,
      label:     _navMod.nav.label,
      icon:      _navMod.nav.icon,
      group:     structKeyExists(_navMod.nav, "group")     ? trim(_navMod.nav.group & "")        : "",
      sortOrder: structKeyExists(_navMod.nav, "sortOrder") ? int(val(_navMod.nav.sortOrder)) : 99,
      href:      "index.cfm?module=" & _navMod.id,
      target:    int(val(_navMod.type)) EQ 4 ? "_blank" : "",
      rel:       int(val(_navMod.type)) EQ 4 ? "noopener noreferrer" : ""
    });
  }
}
if (structKeyExists(application, "pageService") AND isObject(application.pageService)) {
  _pageNavResult = application.pageService.listNavPages();
  if (_pageNavResult.success AND isArray(_pageNavResult.pages)) {
    for (_navPage in _pageNavResult.pages) {
      arrayAppend(_navItems, {
        type:      "page",
        id:        _navPage.slug,
        label:     len(trim(_navPage.navLabel & "")) ? trim(_navPage.navLabel & "") : trim(_navPage.title & ""),
        icon:      "fas fa-file-alt",
        group:     "Pages",
        sortOrder: int(val(_navPage.navSortOrder)),
        href:      "/index.cfm?page=" & urlEncodedFormat(_navPage.slug)
      });
    }
  }
}
arraySort(_navItems, function(a, b) {
  if (a.group LT b.group) return -1;
  if (a.group GT b.group) return 1;
  return a.sortOrder - b.sortOrder;
});

</cfscript>
<cfif dispatchMode EQ "dashboard">
<cfscript>
directoryResult = {
  success = true,
  message = "Click a group below to load directory members.",
  groups = {
    faculty = [],
    staff = [],
    students = [],
    alumni = []
  }
};

linksResult = {
  success = false,
  message = "Links have not loaded.",
  links = []
};

try {
  linksResult = application.linkService.getMergedLinks(userId = currentUserId);
} catch (any e) {
  linksResult = {
    success = false,
    message = "Link service unavailable.",
    links = []
  };
  cflog(file = "myuhco-api", type = "error", text = "Index links section failed: #e.message#");
}

directoryCount = arrayLen(directoryResult.groups.faculty)
  + arrayLen(directoryResult.groups.staff)
  + arrayLen(directoryResult.groups.students)
  + arrayLen(directoryResult.groups.alumni);
linksCount = arrayLen(linksResult.links);

gradYearWindow = application.dateHelper.getGradYearWindow();
studentGradYears = [];
alumniGradYears = [];
alumniStartYear = 1955;
alumniEndYear = gradYearWindow.startYear - 1;

for (y = gradYearWindow.startYear; y LTE gradYearWindow.endYear; y = y + 1) {
  arrayAppend(studentGradYears, y);
}

if (alumniEndYear LT alumniStartYear) {
  alumniEndYear = alumniStartYear;
}

for (y = alumniEndYear; y GTE alumniStartYear; y = y - 1) {
  arrayAppend(alumniGradYears, y);
}

dashboardPanels = [];
dashboardMainPanels = [];
dashboardSidebarPanels = [];
dashboardStylesheets = [];
dashboardScripts = [];
uhcoNewsItems = [];

collegeFormsLinks = [];
otherLinks = [];

if (linksResult.success) {
  for (linkItem in linksResult.links) {
    linkSection = lCase(trim((structKeyExists(linkItem, "section") ? linkItem.section : "") & ""));
    if (linkSection EQ "college-forms" OR linkSection EQ "college forms") {
      arrayAppend(collegeFormsLinks, linkItem);
    } else {
      arrayAppend(otherLinks, linkItem);
    }
  }
}

if (structKeyExists(application, "moduleRegistry") AND isArray(application.moduleRegistry)) {
  for (_dashMod in application.moduleRegistry) {
    if (!_dashMod.enabled) {
      continue;
    }
    if (!structKeyExists(_dashMod, "dashboard") OR !isStruct(_dashMod.dashboard) OR !_dashMod.dashboard.enabled) {
      continue;
    }

    _dashGranted = true;
    if (_dashMod.requiresAuth AND isArray(_dashMod.permissions) AND arrayLen(_dashMod.permissions)) {
      _dashGranted = false;
      if (structKeyExists(application, "accessService") AND isObject(application.accessService)) {
        for (_dashPerm in _dashMod.permissions) {
          if (application.accessService.hasPermission(_dashPerm)) {
            _dashGranted = true;
            break;
          }
        }
      }
    }
    if (!_dashGranted) {
      continue;
    }

    _dashProviderType = structKeyExists(_dashMod.dashboard, "providerType") ? lCase(trim(_dashMod.dashboard.providerType & "")) : "";
    _dashProvider = structKeyExists(_dashMod.dashboard, "provider") ? trim(_dashMod.dashboard.provider & "") : "";
    _dashMethod = structKeyExists(_dashMod.dashboard, "method") ? trim(_dashMod.dashboard.method & "") : "getPanels";
    _dashPanelDefs = (structKeyExists(_dashMod.dashboard, "panels") AND isArray(_dashMod.dashboard.panels)) ? duplicate(_dashMod.dashboard.panels) : [];

    if (_dashProviderType NEQ "component" OR !len(_dashProvider)) {
      continue;
    }

    try {
      _dashProviderInstance = createObject("component", _dashProvider);
      dashboardProviderResult = invoke(_dashProviderInstance, _dashMethod, {
        context = {
          module = _dashMod,
          panelDefinitions = _dashPanelDefs,
          userTypeKey = userTypeKey,
          includeAllSpecificDocs = canSeeAllUserTypeDocs,
          currentUserId = currentUserId
        }
      });

      if (!isStruct(dashboardProviderResult) OR !structKeyExists(dashboardProviderResult, "success") OR !dashboardProviderResult.success) {
        if (isStruct(dashboardProviderResult) AND structKeyExists(dashboardProviderResult, "message") AND len(trim(dashboardProviderResult.message & ""))) {
          cflog(file = "myuhco-api", type = "warning", text = "Dashboard provider '#_dashMod.id#' returned no panels: #dashboardProviderResult.message#");
        }
        continue;
      }
      if (!structKeyExists(dashboardProviderResult, "panels") OR !isArray(dashboardProviderResult.panels)) {
        continue;
      }

      if (structKeyExists(dashboardProviderResult, "assets") AND isStruct(dashboardProviderResult.assets)) {
        if (structKeyExists(dashboardProviderResult.assets, "stylesheets") AND isArray(dashboardProviderResult.assets.stylesheets)) {
          for (_dashboardStylesheetHref in dashboardProviderResult.assets.stylesheets) {
            _dashboardStylesheetHref = trim(_dashboardStylesheetHref & "");
            if (len(_dashboardStylesheetHref) AND !arrayFindNoCase(dashboardStylesheets, _dashboardStylesheetHref)) {
              arrayAppend(dashboardStylesheets, _dashboardStylesheetHref);
            }
          }
        }
        if (structKeyExists(dashboardProviderResult.assets, "scripts") AND isArray(dashboardProviderResult.assets.scripts)) {
          for (_dashboardScriptSrc in dashboardProviderResult.assets.scripts) {
            _dashboardScriptSrc = trim(_dashboardScriptSrc & "");
            if (len(_dashboardScriptSrc) AND !arrayFindNoCase(dashboardScripts, _dashboardScriptSrc)) {
              arrayAppend(dashboardScripts, _dashboardScriptSrc);
            }
          }
        }
      }

      for (_dashPanel in dashboardProviderResult.panels) {
        if (!isStruct(_dashPanel)) {
          continue;
        }

        _dashPanelId = structKeyExists(_dashPanel, "panelId") ? lCase(trim(_dashPanel.panelId & "")) : "";
        if (!len(_dashPanelId)) {
          continue;
        }

        _dashPanelDef = {};
        for (_panelDef in _dashPanelDefs) {
          if (isStruct(_panelDef) AND structKeyExists(_panelDef, "id") AND lCase(trim(_panelDef.id & "")) EQ _dashPanelId) {
            _dashPanelDef = _panelDef;
            break;
          }
        }
        if (structCount(_dashPanelDef) AND structKeyExists(_dashPanelDef, "enabled") AND !_dashPanelDef.enabled) {
          continue;
        }

        if (!structKeyExists(_dashPanel, "moduleId")) {
          _dashPanel.moduleId = _dashMod.id;
        }
        if (!structKeyExists(_dashPanel, "title") OR !len(trim(_dashPanel.title & ""))) {
          _dashPanel.title = structCount(_dashPanelDef) AND structKeyExists(_dashPanelDef, "title") ? trim(_dashPanelDef.title & "") : trim(_dashMod.name & "");
        }
        if (!structKeyExists(_dashPanel, "type") OR !len(trim(_dashPanel.type & ""))) {
          _dashPanel.type = structCount(_dashPanelDef) AND structKeyExists(_dashPanelDef, "type") ? trim(_dashPanelDef.type & "") : "link-list";
        }
        if (!structKeyExists(_dashPanel, "viewAllHref") OR !len(trim(_dashPanel.viewAllHref & ""))) {
          _dashPanel.viewAllHref = structCount(_dashPanelDef) AND structKeyExists(_dashPanelDef, "viewAllHref") ? trim(_dashPanelDef.viewAllHref & "") : ("index.cfm?module=" & _dashMod.id);
        }
        if (!structKeyExists(_dashPanel, "emptyMessage") OR !len(trim(_dashPanel.emptyMessage & ""))) {
          _dashPanel.emptyMessage = "No items are available.";
        }
        if (!structKeyExists(_dashPanel, "items") OR !isArray(_dashPanel.items)) {
          _dashPanel.items = [];
        }
        _dashPanel.column = structCount(_dashPanelDef) AND structKeyExists(_dashPanelDef, "column") ? lCase(trim(_dashPanelDef.column & "")) : (structKeyExists(_dashPanel, "column") ? lCase(trim(_dashPanel.column & "")) : "main");
        if (_dashPanel.column NEQ "sidebar") {
          _dashPanel.column = "main";
        }
        _dashPanel.sortOrder = structCount(_dashPanelDef) AND structKeyExists(_dashPanelDef, "sortOrder") ? int(val(_dashPanelDef.sortOrder)) : (structKeyExists(_dashPanel, "sortOrder") ? int(val(_dashPanel.sortOrder)) : 99);
        _dashPanel.itemCount = structKeyExists(_dashPanel, "itemCount") ? int(val(_dashPanel.itemCount)) : arrayLen(_dashPanel.items);
        arrayAppend(dashboardPanels, _dashPanel);
      }
    } catch (any e) {
      cflog(file = "myuhco-api", type = "error", text = "Dashboard provider '#_dashMod.id#' failed: #e.message# | #e.detail#");
    }
  }
}

function appendUhcoNewsItem(required array targetItems, any title = "", any href = "", any publishedAt = "") {
  var safeTitle = trim(arguments.title & "");
  var safeHref = trim(arguments.href & "");
  var safePublishedAt = trim(arguments.publishedAt & "");

  if (!len(safeTitle) OR !len(safeHref)) {
    return;
  }

  arrayAppend(arguments.targetItems, {
    title = safeTitle,
    href = safeHref,
    publishedAt = safePublishedAt
  });
}

function getXmlChildValue(required any itemNode, required string childName) {
  var xmlChild = "";
  var xmlChildren = [];
  var normalizedName = lCase(trim(arguments.childName & ""));
  var currentName = "";
  var xmlTextValue = "";

  try {
    xmlChildren = arguments.itemNode.xmlChildren;
  } catch (any e) {
    return "";
  }

  if (!isArray(xmlChildren)) {
    return "";
  }

  for (xmlChild in xmlChildren) {
    try {
      currentName = lCase(listLast(xmlChild.xmlName, ":"));
    } catch (any e) {
      continue;
    }

    if (currentName EQ normalizedName) {
      xmlTextValue = "";
      try {
        xmlTextValue = trim(xmlChild.xmlText & "");
      } catch (any e) {}
      if (len(xmlTextValue)) {
        return xmlTextValue;
      }

      try {
        xmlTextValue = trim(xmlChild.xmlValue & "");
      } catch (any e) {}
      if (len(xmlTextValue)) {
        return xmlTextValue;
      }

      try {
        if (isArray(xmlChild.xmlChildren) AND arrayLen(xmlChild.xmlChildren) GTE 1) {
          xmlTextValue = trim(xmlChild.xmlChildren[1].xmlValue & "");
          if (len(xmlTextValue)) {
            return xmlTextValue;
          }
        }
      } catch (any e) {}

      try {
        xmlTextValue = trim(toString(xmlChild) & "");
      } catch (any e) {}
      if (len(xmlTextValue)) {
        xmlTextValue = reReplace(xmlTextValue, "(?is)^<[^>]+>|</[^>]+>$", "", "all");
        xmlTextValue = trim(xmlTextValue);
        if (len(xmlTextValue)) {
          return xmlTextValue;
        }
      }
    }
  }

  return "";
}

function getXmlAttributeValue(required any itemNode, required string attributeName) {
  var xmlAttributes = {};
  var attrKey = "";
  var normalizedName = lCase(trim(arguments.attributeName & ""));

  try {
    xmlAttributes = arguments.itemNode.xmlAttributes;
  } catch (any e) {
    return "";
  }

  if (!isStruct(xmlAttributes)) {
    return "";
  }

  if (structKeyExists(xmlAttributes, normalizedName)) {
    return trim(xmlAttributes[normalizedName] & "");
  }

  for (attrKey in xmlAttributes) {
    if (lCase(attrKey) EQ normalizedName) {
      return trim(xmlAttributes[attrKey] & "");
    }
  }

  return "";
}

function normalizeUhcoNewsHref(any hrefValue = "") {
  var rawHref = trim(arguments.hrefValue & "");
  if (!len(rawHref)) {
    return "";
  }
  if (left(rawHref, 1) EQ "/") {
    return "https://www.opt.uh.edu" & rawHref;
  }
  return rawHref;
}

function extractItemBlocksFromXml(required string xmlRaw) {
  var blocks = [];
  var searchPos = 1;
  var openPos = 0;
  var closePos = 0;
  var closeTag = "</item>";
  var blockEnd = 0;

  while (true) {
    openPos = findNoCase("<item", arguments.xmlRaw, searchPos);
    if (openPos LTE 0) {
      break;
    }

    closePos = findNoCase(closeTag, arguments.xmlRaw, openPos);
    if (closePos LTE 0) {
      break;
    }

    blockEnd = closePos + len(closeTag) - 1;
    arrayAppend(blocks, mid(arguments.xmlRaw, openPos, (blockEnd - openPos) + 1));
    searchPos = blockEnd + 1;
  }

  return blocks;
}

function extractTagValueFromXmlBlock(required string blockXml, required string tagName) {
  var openTag = "<" & lCase(trim(arguments.tagName & "")) & ">";
  var closeTag = "</" & lCase(trim(arguments.tagName & "")) & ">";
  var searchSource = lCase(arguments.blockXml);
  var startPos = findNoCase(openTag, searchSource);
  var contentStart = 0;
  var endPos = 0;

  if (startPos LTE 0) {
    return "";
  }

  contentStart = startPos + len(openTag);
  endPos = findNoCase(closeTag, searchSource, contentStart);
  if (endPos LTE 0) {
    return "";
  }

  return trim(mid(arguments.blockXml, contentStart, endPos - contentStart));
}

function extractAttributeValueFromItemBlock(required string blockXml, required string attributeName) {
  var itemStart = findNoCase("<item", arguments.blockXml);
  var itemEnd = 0;
  var itemTag = "";
  var attrPos = 0;
  var scanPos = 0;
  var quoteChar = "";
  var endPos = 0;

  if (itemStart LTE 0) {
    return "";
  }

  itemEnd = find(">", arguments.blockXml, itemStart);
  if (itemEnd LTE 0) {
    return "";
  }

  itemTag = mid(arguments.blockXml, itemStart, (itemEnd - itemStart) + 1);
  attrPos = findNoCase(arguments.attributeName, itemTag);
  if (attrPos LTE 0) {
    return "";
  }

  scanPos = attrPos + len(arguments.attributeName);
  while (scanPos LTE len(itemTag) AND trim(mid(itemTag, scanPos, 1)) EQ "") {
    scanPos = scanPos + 1;
  }
  if (scanPos GT len(itemTag) OR mid(itemTag, scanPos, 1) NEQ "=") {
    return "";
  }

  scanPos = scanPos + 1;
  while (scanPos LTE len(itemTag) AND trim(mid(itemTag, scanPos, 1)) EQ "") {
    scanPos = scanPos + 1;
  }
  if (scanPos GT len(itemTag)) {
    return "";
  }

  quoteChar = mid(itemTag, scanPos, 1);
  if (quoteChar NEQ chr(34) AND quoteChar NEQ chr(39)) {
    return "";
  }

  endPos = find(quoteChar, itemTag, scanPos + 1);
  if (endPos LTE 0) {
    return "";
  }

  return trim(mid(itemTag, scanPos + 1, endPos - scanPos - 1));

  return "";
}

newsFeedUrl = "https://www.opt.uh.edu/_resources/data/news.xml";
</cfscript>
<cftry>
  <cfhttp url="#newsFeedUrl#" method="get" result="uhcoNewsHttpResult" throwonerror="false" timeout="20" charset="utf-8"></cfhttp>
  <cfscript>
    if (
      isStruct(uhcoNewsHttpResult)
      AND structKeyExists(uhcoNewsHttpResult, "statusCode")
      AND left(trim(uhcoNewsHttpResult.statusCode & ""), 3) EQ "200"
      AND structKeyExists(uhcoNewsHttpResult, "fileContent")
      AND len(trim(uhcoNewsHttpResult.fileContent & ""))
    ) {
      newsRawXml = uhcoNewsHttpResult.fileContent & "";
      newsItemBlocks = extractItemBlocksFromXml(newsRawXml);

      if (isArray(newsItemBlocks) AND arrayLen(newsItemBlocks) GT 0) {
        for (newsItemBlock in newsItemBlocks) {
          newsItemHref = trim(extractAttributeValueFromItemBlock(newsItemBlock, "href") & "");
          newsItemTitle = trim(extractTagValueFromXmlBlock(newsItemBlock, "title") & "");
          newsItemPubDate = trim(extractTagValueFromXmlBlock(newsItemBlock, "pubDate") & "");
          newsItemFullHref = normalizeUhcoNewsHref(newsItemHref);

          if (len(newsItemTitle) AND len(newsItemFullHref)) {
            arrayAppend(uhcoNewsItems, {
              title = newsItemTitle,
              href = newsItemFullHref,
              publishedAt = newsItemPubDate
            });
          }
        }
      }

      cflog(file = "myuhco-news", type = "information", text = "Index UHCO news parsed items count: #arrayLen(uhcoNewsItems)#");
    } else {
      cflog(file = "myuhco-news", type = "error", text = "Index UHCO news cfhttp returned non-200 or empty payload. status=#structKeyExists(uhcoNewsHttpResult, 'statusCode') ? (uhcoNewsHttpResult.statusCode & '') : 'unknown'#");
    }
  </cfscript>
  <cfcatch type="any">
    <cflog file="myuhco-news" type="error" text="Index UHCO news cfhttp/xml parse failed: #cfcatch.message# #cfcatch.detail#">
  </cfcatch>
</cftry>
<cfscript>

docsPageSize = 5;
linksPageSize = 6;

function limitItems(required array items, numeric maxItems = 5) {
  var out = [];
  var i = 0;
  var maxCount = arguments.maxItems;
  if (maxCount LT 1) {
    maxCount = 1;
  }
  for (i = 1; i LTE arrayLen(arguments.items) AND i LTE maxCount; i = i + 1) {
    arrayAppend(out, arguments.items[i]);
  }
  return out;
}

function getNumericUrlPage(required string paramName) {
  var pageValue = 1;
  if (structKeyExists(url, arguments.paramName)) {
    pageValue = val(url[arguments.paramName]);
  }
  if (pageValue LT 1) {
    pageValue = 1;
  }
  return pageValue;
}

function paginateItems(required array items, required string pageParam, numeric pageSize = 5) {
  var totalItems = arrayLen(arguments.items);
  var totalPages = 1;
  var currentPage = 1;
  var startIndex = 1;
  var endIndex = 0;
  var i = 0;
  var pagedItems = [];

  if (totalItems GT 0) {
    totalPages = ceiling(totalItems / arguments.pageSize);
  }

  currentPage = getNumericUrlPage(arguments.pageParam);
  if (currentPage GT totalPages) {
    currentPage = totalPages;
  }

  if (totalItems GT 0) {
    startIndex = ((currentPage - 1) * arguments.pageSize) + 1;
    endIndex = min(startIndex + arguments.pageSize - 1, totalItems);
    for (i = startIndex; i LTE endIndex; i = i + 1) {
      arrayAppend(pagedItems, arguments.items[i]);
    }
  }

  return {
    items = pagedItems,
    currentPage = currentPage,
    totalPages = totalPages,
    totalItems = totalItems,
    hasPrev = (currentPage GT 1),
    hasNext = (currentPage LT totalPages),
    prevPage = (currentPage GT 1 ? currentPage - 1 : 1),
    nextPage = (currentPage LT totalPages ? currentPage + 1 : totalPages)
  };
}

function buildPageUrl(required string pageParam, required numeric pageValue) {
  var params = {};
  var keyName = "";
  var queryParts = [];
  var resultUrl = "index.cfm";

  params = duplicate(url);
  params[arguments.pageParam] = arguments.pageValue;

  if (structKeyExists(params, "fieldnames")) {
    structDelete(params, "fieldnames");
  }

  for (keyName in params) {
    arrayAppend(queryParts, urlEncodedFormat(keyName) & "=" & urlEncodedFormat(params[keyName] & ""));
  }

  if (arrayLen(queryParts)) {
    resultUrl = resultUrl & "?" & arrayToList(queryParts, "&");
  }

  return resultUrl;
}

function isPdfDocument(required struct docItem) {
  var hrefValue = "";
  var categoryValue = "";
  var sizeValue = "";

  if (structKeyExists(arguments.docItem, "href")) {
    hrefValue = lCase(trim(arguments.docItem.href & ""));
  }
  if (structKeyExists(arguments.docItem, "category")) {
    categoryValue = lCase(trim(arguments.docItem.category & ""));
  }
  if (structKeyExists(arguments.docItem, "size")) {
    sizeValue = lCase(trim(arguments.docItem.size & ""));
  }

  if (findNoCase("/modules/documents/view.cfm", hrefValue) OR findNoCase("document-view.cfm", hrefValue) OR findNoCase(".pdf", hrefValue)) {
    return true;
  }
  if (categoryValue EQ "pdf" OR findNoCase("pdf", sizeValue)) {
    return true;
  }
  return false;
}

function buildDocumentLink(required struct docItem) {
  var hrefValue = "";

  if (structKeyExists(arguments.docItem, "href")) {
    hrefValue = trim(arguments.docItem.href & "");
  }

  if (!len(hrefValue) OR hrefValue EQ "##") {
    return hrefValue;
  }
  if (findNoCase("/modules/documents/view.cfm", hrefValue) OR findNoCase("document-view.cfm", hrefValue)) {
    return hrefValue;
  }
  if (isPdfDocument(arguments.docItem)) {
    return "/modules/documents/view.cfm?url=" & urlEncodedFormat(hrefValue);
  }
  return hrefValue;
}

function applyDocumentLinks(required array docs) {
  var i = 0;
  for (i = 1; i LTE arrayLen(arguments.docs); i = i + 1) {
    if (isStruct(arguments.docs[i])) {
      arguments.docs[i].href = buildDocumentLink(arguments.docs[i]);
    }
  }
}

function getDocumentIconClass(required struct docItem) {
  var hrefValue = "";
  var titleValue = "";
  var categoryValue = "";
  var haystack = "";

  if (structKeyExists(arguments.docItem, "href")) {
    hrefValue = lCase(arguments.docItem.href & "");
  }
  if (structKeyExists(arguments.docItem, "title")) {
    titleValue = lCase(arguments.docItem.title & "");
  }
  if (structKeyExists(arguments.docItem, "category")) {
    categoryValue = lCase(arguments.docItem.category & "");
  }

  haystack = hrefValue & " " & titleValue & " " & categoryValue;

  if (findNoCase("pdf", haystack)) {
    return "fas fa-file-pdf";
  }
  if (findNoCase("doc", haystack) OR findNoCase("docx", haystack)) {
    return "fas fa-file-word";
  }
  if (findNoCase("xls", haystack) OR findNoCase("xlsx", haystack) OR findNoCase("csv", haystack)) {
    return "fas fa-file-excel";
  }
  if (findNoCase("ppt", haystack) OR findNoCase("pptx", haystack)) {
    return "fas fa-file-powerpoint";
  }
  if (findNoCase("zip", haystack) OR findNoCase("rar", haystack) OR findNoCase("7z", haystack)) {
    return "fas fa-file-archive";
  }
  if (findNoCase("image", haystack) OR findNoCase("jpg", haystack) OR findNoCase("jpeg", haystack) OR findNoCase("png", haystack) OR findNoCase("gif", haystack) OR findNoCase("webp", haystack)) {
    return "fas fa-file-image";
  }
  return "fas fa-file-alt";
}

function getShortUpdatedLabel(required struct docItem) {
  var updatedRaw = "";
  var dateToken = "";
  var dateParts = [];
  var ymdParts = [];

  if (structKeyExists(arguments.docItem, "updatedAt")) {
    updatedRaw = trim(arguments.docItem.updatedAt & "");
  }

  if (!len(updatedRaw)) {
    return "";
  }

  dateToken = listFirst(updatedRaw, " ");

  if (reFind("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$", dateToken)) {
    dateParts = listToArray(dateToken, "/");
    if (arrayLen(dateParts) EQ 3) {
      return "Upd " & dateParts[1] & "/" & dateParts[2] & "/" & right(dateParts[3], 2);
    }
  }

  if (reFind("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", dateToken)) {
    ymdParts = listToArray(dateToken, "-");
    if (arrayLen(ymdParts) EQ 3) {
      return "Upd " & ymdParts[2] & "/" & ymdParts[3] & "/" & right(ymdParts[1], 2);
    }
  }

  if (len(dateToken) GT 10) {
    dateToken = left(dateToken, 10);
  }
  return "Upd " & dateToken;
}

function toTitleCaseWords(required string value) {
  var cleanedValue = trim(arguments.value & "");
  var words = [];
  var resultWords = [];
  var i = 0;
  var wordValue = "";

  if (!len(cleanedValue)) {
    return "";
  }

  words = listToArray(cleanedValue, " ");
  for (i = 1; i LTE arrayLen(words); i = i + 1) {
    wordValue = trim(words[i]);
    if (len(wordValue)) {
      arrayAppend(resultWords, uCase(left(wordValue, 1)) & lCase(mid(wordValue, 2, len(wordValue))));
    }
  }

  return arrayToList(resultWords, " ");
}

function getQuickDocDisplayTitle(required struct docItem, numeric maxLen = 20) {
  var rawTitle = "";
  var normalizedTitle = "";
  var truncatedTitle = "";
  var maxChars = arguments.maxLen;

  if (structKeyExists(arguments.docItem, "title")) {
    rawTitle = trim(arguments.docItem.title & "");
  }

  normalizedTitle = reReplace(rawTitle, "[-_]", " ", "all");
  normalizedTitle = reReplace(normalizedTitle, "\s+", " ", "all");
  normalizedTitle = toTitleCaseWords(normalizedTitle);

  if (!len(normalizedTitle)) {
    normalizedTitle = "Untitled Document";
  }

  truncatedTitle = normalizedTitle;
  if (len(normalizedTitle) GT maxChars) {
    truncatedTitle = left(normalizedTitle, maxChars) & "...";
  }

  return {
    fullTitle = normalizedTitle,
    shortTitle = truncatedTitle
  };
}

function getRosterSortYear(required struct docItem) {
  var titleValue = "";
  var matchData = {};

  if (structKeyExists(arguments.docItem, "title")) {
    titleValue = trim(arguments.docItem.title & "");
  }

  if (!len(titleValue)) {
    return 0;
  }

  matchData = reFindNoCase("(19|20)\d{2}", titleValue, 1, true);
  if (structKeyExists(matchData, "match") AND arrayLen(matchData.match) GTE 1 AND len(matchData.match[1])) {
    return val(matchData.match[1]);
  }

  return 0;
}

function sortRosterDocs(required array docs) {
  var sortedDocs = duplicate(arguments.docs);

  arraySort(sortedDocs, function(leftDoc, rightDoc) {
    var leftYear = getRosterSortYear(leftDoc);
    var rightYear = getRosterSortYear(rightDoc);

    if (leftYear LT rightYear) {
      return -1;
    }
    if (leftYear GT rightYear) {
      return 1;
    }
    return compareNoCase(
      structKeyExists(leftDoc, "title") ? (leftDoc.title & "") : "",
      structKeyExists(rightDoc, "title") ? (rightDoc.title & "") : ""
    );
  });

  return sortedDocs;
}

for (_dashboardPanel in dashboardPanels) {
  if (structKeyExists(_dashboardPanel, "column") AND _dashboardPanel.column EQ "sidebar") {
    arrayAppend(dashboardSidebarPanels, _dashboardPanel);
  } else {
    arrayAppend(dashboardMainPanels, _dashboardPanel);
  }
}

arraySort(dashboardMainPanels, function(leftPanel, rightPanel) {
  return leftPanel.sortOrder - rightPanel.sortOrder;
});
arraySort(dashboardSidebarPanels, function(leftPanel, rightPanel) {
  return leftPanel.sortOrder - rightPanel.sortOrder;
});

// sort newest to oldest by publishedAt (mm/dd/yyyy)
uhcoNewsItems.sort(function(a, b) {
  var dA = 0;
  var dB = 0;
  try { dA = createDate(listLast(a.publishedAt,"/"), listFirst(a.publishedAt,"/"), listGetAt(a.publishedAt,2,"/")); } catch(any e) {}
  try { dB = createDate(listLast(b.publishedAt,"/"), listFirst(b.publishedAt,"/"), listGetAt(b.publishedAt,2,"/")); } catch(any e) {}
  return dateCompare(dB, dA);
});
uhcoNewsItems = limitItems(uhcoNewsItems, 5);

collegeFormsPage = paginateItems(collegeFormsLinks, "cfPage", linksPageSize);
otherLinksPage = paginateItems(otherLinks, "olPage", linksPageSize);
</cfscript>
</cfif>
<cfoutput>
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="##">
    <meta name="keywords" content="##">
    <meta name="generator" content="">

    <title>MyUHCO</title>

    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <link rel="stylesheet" href="assets/plugins/fontawesome-free/css/all.min.css">
    <link rel="stylesheet" href="/assets/css/dist/myuhco/portal.css">
    <cfif dispatchMode EQ "page-render">
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/quill@1.3.7/dist/quill.snow.css">
    </cfif>

    <cfloop array="#dashboardStylesheets#" index="dashboardStylesheetHref">
      <link rel="stylesheet" href="#encodeForHTMLAttribute(dashboardStylesheetHref)#">
    </cfloop>

    <meta property="og:url" content="##" />
    <meta property="og:site_name" content="##" />
    <meta property="og:title" content="##" />
    <meta property="og:description" content="##" />
    <meta property="og:image" content="##" />
    <meta property="og:image:width" content="1600" />
    <meta property="og:image:height" content="900" />
    <meta property="og:type" content="website" />

    <link rel="shortcut icon" href="assets/images/46904E6A-93E9-1182-D5CC96AA4A79783F.png">
  </head>
  <body id="MyUHCO">
    <a name="Top" id="Top"></a>

    <div class="portal-shell">
      <aside class="main-sidebar" id="mainSidebar" aria-label="Main sidebar">
        <div class="main-sidebar-inner">
          <div class="sidebar-brand uhco-logo"><img src="assets/images/UH-Primary-College-of-Optometry-horizontal.webp" alt="College of Optometry Logo" class="img-fluid"></div>
          <div class="sidebar-brand uh-logo"><img src="assets/images/uh.png" alt="University of Houston Logo" class="img-fluid"></div>
          <nav class="nav flex-column sidebar-nav">
            <a class="nav-link #dispatchMode EQ 'dashboard' ? 'active' : ''#" href="index.cfm">
              <i class="fas fa-home"></i>
              <span class="sidebar-link-text">Home</span>
            </a>
            <cfif arrayLen(_navItems)>
              <cfset _navCurrentGroup = chr(0)>
              <cfloop array="#_navItems#" index="_navItem">
                <cfif _navItem.group NEQ _navCurrentGroup AND len(_navItem.group)>
                  <cfset _navCurrentGroup = _navItem.group>
                  <div class="sidebar-nav-group-label">#encodeForHTML(_navCurrentGroup)#</div>
                </cfif>
                <a class="nav-link #((_navItem.type EQ 'module' AND _navItem.id EQ _navActiveModule) OR (_navItem.type EQ 'page' AND _navItem.id EQ _navActivePage)) ? 'active' : ''#" href="#encodeForHTMLAttribute(_navItem.href)#"<cfif structKeyExists(_navItem, "target") AND len(trim(_navItem.target & ""))> target="#encodeForHTMLAttribute(_navItem.target)#" rel="#encodeForHTMLAttribute(structKeyExists(_navItem, "rel") ? (_navItem.rel & "") : "noopener noreferrer")#"</cfif>>
                  <i class="#encodeForHTML(_navItem.icon)#"></i>
                  <span class="sidebar-link-text">#encodeForHTML(_navItem.label)#</span>
                </a>
              </cfloop>
            </cfif>
          </nav>
          
        </div>
      </aside>

      <div class="mainContainer flex-grow-1" id="main">
      <cfinclude template="/includes/portal-header.cfm">

      <main class="portal-main py-3 py-lg-5">
      <cfif dispatchMode EQ "module-include">
        <cfinclude template="/#activeModule.entryPoint#">
      <cfelseif dispatchMode EQ "page-render">
        <div class="container-xxl">
          <div class="card border-0 shadow-sm portal-card pages-platform-card pages-platform-shell">
            <div class="card-body p-4 p-md-5">
              <div class="pages-inline-toolbar">
                <div>
                  <cfif len(trim(activePage.summary & ""))>
                    <div class="text-uppercase small text-muted fw-semibold mb-2">Pages</div>
                  </cfif>
                  <h1 class="h3 mb-2">#encodeForHTML(activePage.title & "")#</h1>
                  <cfif len(trim(activePage.summary & ""))>
                    <p class="lead mb-0">#encodeForHTML(activePage.summary & "")#</p>
                  </cfif>
                </div>
                <cfif pageInlineAdminAllowed>
                  <div class="d-flex gap-2 align-items-center">
                    <div class="pages-inline-meta">Admin page tools</div>
                    <button type="button" class="btn btn-outline-primary btn-sm" id="inlinePageEditToggle"<cfif pageInlineEditing> hidden</cfif>>Quick Edit</button>
                  </div>
                </cfif>
              </div>
              <cfif len(pageInlineFlashMessage)>
                <div class="alert alert-#pageInlineFlashType#" role="alert">#encodeForHTML(pageInlineFlashMessage)#</div>
              </cfif>
              <cfif NOT pageInlineEditing>
                <div class="page-content" id="inlinePageRenderedContent">
                  #activePage.bodyHtml#
                </div>
              </cfif>
              <cfif pageInlineAdminAllowed>
                <div class="pages-inline-editor" id="inlinePageEditorPanel"<cfif NOT pageInlineEditing> hidden</cfif>>
                  <div class="pages-inline-editor-header">
                    <div class="fw-semibold">Inline Page Editor</div>
                    <div class="small text-muted">This uses the same save pipeline as the admin Pages screen.</div>
                  </div>
                  <div class="pages-inline-editor-body">
                    <form method="post" action="/index.cfm?page=#urlEncodedFormat(activePage.slug)#" class="pages-inline-form">
                      <input type="hidden" name="_pageInlineAction" value="saveInlinePage">
                      <input type="hidden" name="pageId" value="#activePage.pageId#">
                      <input type="hidden" name="slug" value="#encodeForHTMLAttribute(activePage.slug & '')#">
                      <input type="hidden" name="navLabel" value="#encodeForHTMLAttribute(activePage.navLabel & '')#">
                      <input type="hidden" name="navSortOrder" value="#int(val(activePage.navSortOrder))#">
                      <input type="hidden" name="summary" value="#encodeForHTMLAttribute(activePage.summary & '')#">
                      <cfif activePage.isPublished>
                        <input type="hidden" name="isPublished" value="1">
                      </cfif>
                      <cfif activePage.showInNav>
                        <input type="hidden" name="showInNav" value="1">
                      </cfif>
                      <input type="hidden" name="bodyHtml" id="inlinePageBodyHtml" value="#encodeForHTMLAttribute(activePage.bodyHtml & '')#">

                      <div class="row g-3">
                        <div class="col-12">
                          <label for="inlinePageTitle" class="form-label">Title</label>
                          <input type="text" class="form-control" id="inlinePageTitle" name="title" maxlength="200" value="#encodeForHTMLAttribute(activePage.title & '')#" required>
                        </div>
                        <div class="col-12">
                          <label class="form-label">Body Content</label>
                          <div class="pages-editor-shell">
                            <div id="inlinePageEditor">#activePage.bodyHtml#</div>
                          </div>
                        </div>
                      </div>

                      <div class="pages-inline-editor-footer d-flex flex-wrap gap-2 mt-4">
                        <button type="submit" class="btn btn-primary">Save Page</button>
                        <button type="button" class="btn btn-outline-secondary" id="inlinePageEditorCancel">Cancel</button>
                        <a href="/admin/pages/?id=#activePage.pageId#" class="btn btn-outline-dark">Open In Admin</a>
                      </div>
                    </form>
                  </div>
                </div>
              </cfif>
            </div>
          </div>
        </div>
      <cfelseif dispatchMode NEQ "dashboard">
        <div class="container-fluid">
          <div class="row justify-content-center mt-5">
            <div class="col-md-6">
              <div class="alert #(dispatchMode EQ 'error-403') ? 'alert-danger' : 'alert-warning'#" role="alert">
                <cfif dispatchMode EQ "error-404">
                  <strong>404 &mdash; Not Found.</strong> The page you requested does not exist.
                <cfelseif dispatchMode EQ "error-503">
                  <strong>503 &mdash; Unavailable.</strong> This page is temporarily disabled for maintenance.
                <cfelse>
                  <strong>403 &mdash; Access Denied.</strong> You do not have permission to access this page.
                </cfif>
                <div class="mt-2"><a href="index.cfm" class="alert-link">Return to Dashboard</a></div>
              </div>
            </div>
          </div>
        </div>
      <cfelse>
        <div class="container-fluid">
          <div class="row g-4 mb-3">
            <div class="col-12">
              <section class="card border-0 shadow-sm portal-card">
                <div class="card-body p-4">
                  <h1 class="h3 mb-3"></h1>
                  <p class="mb-0">Specific User Messaging</p>
                </div>
              </section>
            </div>
          </div>
          <div class="row g-4">
            <div class="col-9">
              <cfloop array="#dashboardMainPanels#" index="dashboardPanel">
                <section class="card border-0 shadow-sm portal-card mb-4">
                  <div class="card-body p-4">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                      <h2 class="h4 mb-0">#encodeForHTML(dashboardPanel.title)#</h2>
                      <div class="d-flex align-items-center gap-2">
                        <span class="badge bg-light text-dark">#dashboardPanel.itemCount# item(s)</span>
                        <cfif len(trim(dashboardPanel.viewAllHref & ""))>
                          <a href="#encodeForHTMLAttribute(dashboardPanel.viewAllHref)#" class="btn btn-sm btn-outline-secondary">View All</a>
                        </cfif>
                      </div>
                    </div>

                    <cfif dashboardPanel.type EQ "quick-docs-carousel">
                      <cfif arrayLen(dashboardPanel.items) EQ 0>
                        <div class="alert alert-secondary mb-0" role="alert">#encodeForHTML(dashboardPanel.emptyMessage)#</div>
                      <cfelse>
                        <div class="quick-docs-slider-wrap dashboard-carousel" data-dashboard-carousel="true">
                          <button type="button" class="btn btn-outline-secondary quick-docs-slider-btn" data-dashboard-carousel-prev aria-label="Scroll panel left">
                            <i class="fas fa-chevron-left"></i>
                          </button>
                          <div class="quick-docs-track" data-dashboard-carousel-track aria-label="#encodeForHTMLAttribute(dashboardPanel.title)#">
                            <cfloop array="#dashboardPanel.items#" index="panelItem">
                              <article class="quick-docs-item">
                                <a href="#encodeForHTMLAttribute(panelItem.href)#" class="quick-docs-link" target="#encodeForHTMLAttribute(structKeyExists(panelItem, 'target') ? panelItem.target : '_self')#" rel="noopener noreferrer" title="#encodeForHTMLAttribute(structKeyExists(panelItem, 'fullTitle') ? panelItem.fullTitle : panelItem.title)#" aria-label="#encodeForHTMLAttribute(structKeyExists(panelItem, 'fullTitle') ? panelItem.fullTitle : panelItem.title)#">
                                  <div class="quick-docs-tile">
                                    <cfif structKeyExists(panelItem, "icon") AND len(trim(panelItem.icon & ""))>
                                      <div class="quick-docs-icon"><i class="#encodeForHTML(panelItem.icon)#"></i></div>
                                    </cfif>
                                    <div class="quick-docs-name fw-semibold">#encodeForHTML(structKeyExists(panelItem, 'shortTitle') ? panelItem.shortTitle : panelItem.title)#</div>
                                    <cfif structKeyExists(panelItem, "updatedShort") AND len(trim(panelItem.updatedShort & ""))>
                                      <div class="quick-docs-updated">#encodeForHTML(panelItem.updatedShort)#</div>
                                    </cfif>
                                  </div>
                                </a>
                              </article>
                            </cfloop>
                          </div>
                          <button type="button" class="btn btn-outline-secondary quick-docs-slider-btn" data-dashboard-carousel-next aria-label="Scroll panel right">
                            <i class="fas fa-chevron-right"></i>
                          </button>
                        </div>
                      </cfif>
                    <cfelseif dashboardPanel.type EQ "link-list" OR dashboardPanel.type EQ "news-feed">
                      <cfif arrayLen(dashboardPanel.items) EQ 0>
                        <div class="alert alert-secondary mb-0" role="alert">#encodeForHTML(dashboardPanel.emptyMessage)#</div>
                      <cfelse>
                        <ul class="list-group list-group-flush">
                          <cfloop array="#dashboardPanel.items#" index="panelItem">
                            <li class="list-group-item px-0">
                              <a href="#encodeForHTMLAttribute(panelItem.href)#" class="text-decoration-none d-flex justify-content-between align-items-start gap-3" target="#encodeForHTMLAttribute(structKeyExists(panelItem, 'target') ? panelItem.target : '_self')#" rel="noopener noreferrer">
                                <div class="d-flex align-items-start gap-3">
                                  <cfif structKeyExists(panelItem, "icon") AND len(trim(panelItem.icon & ""))>
                                    <i class="#encodeForHTML(panelItem.icon)# text-muted mt-1"></i>
                                  </cfif>
                                  <div>
                                    <div class="fw-semibold">#encodeForHTML(panelItem.title)#</div>
                                    <cfif structKeyExists(panelItem, "description") AND len(trim(panelItem.description & ""))>
                                      <div class="small text-secondary">#encodeForHTML(panelItem.description)#</div>
                                    </cfif>
                                    <cfif structKeyExists(panelItem, "publishedAt") AND len(trim(panelItem.publishedAt & ""))>
                                      <div class="small text-muted mt-1">#encodeForHTML(panelItem.publishedAt)#</div>
                                    </cfif>
                                  </div>
                                </div>
                                <cfif structKeyExists(panelItem, "badge") AND len(trim(panelItem.badge & ""))>
                                  <span class="badge text-bg-light">#encodeForHTML(panelItem.badge)#</span>
                                </cfif>
                              </a>
                            </li>
                          </cfloop>
                        </ul>
                      </cfif>
                    <cfelse>
                      <div class="alert alert-secondary mb-0" role="alert">Unsupported panel type.</div>
                    </cfif>
                  </div>
                </section>
              </cfloop>

              <section class="card border-0 shadow-sm portal-card mt-4">
                <div class="card-body p-4">
                  <div class="d-flex justify-content-between align-items-center mb-3">
                    <h2 class="h4 mb-0">UHCO News</h2>
                    <span class="badge bg-light text-dark">#arrayLen(uhcoNewsItems)# loaded</span>
                  </div>

                  <cfif arrayLen(uhcoNewsItems) EQ 0>
                    <div class="alert alert-secondary mb-0" role="alert">
                      <strong>Unavailable:</strong> No news items are available right now.
                    </div>
                  <cfelse>
                    <ul class="list-group list-group-flush">
                      <cfloop array="#uhcoNewsItems#" index="newsItem">
                        <li class="list-group-item px-0">
                          <a href="#encodeForHTMLAttribute(newsItem.href)#" class="text-decoration-none fw-semibold" target="_blank" rel="noopener noreferrer">#encodeForHTML(newsItem.title)#</a>
                          <cfif len(newsItem.publishedAt)>
                            <div class="small text-muted mt-1">#encodeForHTML(newsItem.publishedAt)#</div>
                          </cfif>
                        </li>
                      </cfloop>
                    </ul>
                  </cfif>
                </div>
              </section>
            </div>
            <div class="col-3">
              <cfloop array="#dashboardSidebarPanels#" index="dashboardPanel">
                <section class="card border-0 shadow-sm portal-card mb-4">
                  <div class="card-body p-4">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                      <h2 class="h4 mb-0">#encodeForHTML(dashboardPanel.title)#</h2>
                      <cfif len(trim(dashboardPanel.viewAllHref & ""))>
                        <a href="#encodeForHTMLAttribute(dashboardPanel.viewAllHref)#" class="btn btn-sm btn-outline-secondary">View All</a>
                      </cfif>
                    </div>

                    <cfif dashboardPanel.type EQ "roster-grid">
                      <cfif arrayLen(dashboardPanel.items) EQ 0>
                        <div class="alert alert-secondary mb-0" role="alert">#encodeForHTML(dashboardPanel.emptyMessage)#</div>
                      <cfelse>
                        <div class="roster-doc-grid">
                          <cfloop array="#dashboardPanel.items#" index="panelItem">
                            <a href="#encodeForHTMLAttribute(panelItem.href)#" class="roster-doc-link" target="#encodeForHTMLAttribute(structKeyExists(panelItem, 'target') ? panelItem.target : '_self')#" rel="noopener noreferrer" title="#encodeForHTMLAttribute(structKeyExists(panelItem, 'fullTitle') ? panelItem.fullTitle : panelItem.title)#" aria-label="#encodeForHTMLAttribute(structKeyExists(panelItem, 'fullTitle') ? panelItem.fullTitle : panelItem.title)#">
                              <div class="roster-doc-panel">
                                <cfif structKeyExists(panelItem, "icon") AND len(trim(panelItem.icon & ""))>
                                  <div class="roster-doc-icon"><i class="#encodeForHTML(panelItem.icon)#"></i></div>
                                </cfif>
                                <div class="roster-doc-title fw-semibold">#encodeForHTML(structKeyExists(panelItem, 'fullTitle') ? panelItem.fullTitle : panelItem.title)#</div>
                                <cfif structKeyExists(panelItem, "updatedShort") AND len(trim(panelItem.updatedShort & ""))>
                                  <div class="roster-doc-updated">#encodeForHTML(panelItem.updatedShort)#</div>
                                </cfif>
                              </div>
                            </a>
                          </cfloop>
                        </div>
                      </cfif>
                    <cfelseif arrayLen(dashboardPanel.items) EQ 0>
                      <div class="alert alert-secondary mb-0" role="alert">#encodeForHTML(dashboardPanel.emptyMessage)#</div>
                    <cfelse>
                      <ul class="list-group list-group-flush">
                        <cfloop array="#dashboardPanel.items#" index="panelItem">
                          <li class="list-group-item px-0">
                            <a href="#encodeForHTMLAttribute(panelItem.href)#" class="text-decoration-none d-flex justify-content-between align-items-start gap-2" target="#encodeForHTMLAttribute(structKeyExists(panelItem, 'target') ? panelItem.target : '_self')#" rel="noopener noreferrer">
                              <div>
                                <div class="fw-semibold">#encodeForHTML(panelItem.title)#</div>
                                <cfif structKeyExists(panelItem, "description") AND len(trim(panelItem.description & ""))>
                                  <div class="small text-secondary">#encodeForHTML(panelItem.description)#</div>
                                </cfif>
                                <cfif structKeyExists(panelItem, "publishedAt") AND len(trim(panelItem.publishedAt & ""))>
                                  <div class="small text-muted mt-1">#encodeForHTML(panelItem.publishedAt)#</div>
                                </cfif>
                              </div>
                              <cfif structKeyExists(panelItem, "badge") AND len(trim(panelItem.badge & ""))>
                                <span class="badge text-bg-light">#encodeForHTML(panelItem.badge)#</span>
                              </cfif>
                            </a>
                          </li>
                        </cfloop>
                      </ul>
                    </cfif>
                  </div>
                </section>
              </cfloop>

              <section class="card border-0 shadow-sm portal-card mt-4">
                <div class="card-body p-4">
                  <div class="d-flex justify-content-between align-items-center mb-3">
                    <h2 class="h4 mb-0">Links</h2>
                    <div class="d-flex align-items-center gap-2">
                      <span class="badge bg-light text-dark">#linksResult.success ? linksCount : 0# loaded</span>
                      <a href="index.cfm?module=links" class="btn btn-sm btn-outline-secondary">View All</a>
                    </div>
                  </div>

                  <cfif NOT linksResult.success>
                    <div class="alert alert-danger mb-0" role="alert">
                      <strong>Error:</strong> #encodeForHTML(linksResult.message)#
                    </div>
                  <cfelseif arrayLen(collegeFormsLinks) EQ 0 AND arrayLen(otherLinks) EQ 0>
                    <div class="alert alert-secondary mb-0" role="alert">
                      <strong>Empty:</strong> No links are configured.
                    </div>
                  <cfelse>
                    <div class="mb-4">
                      <h3 class="h6 text-uppercase text-muted mb-2">College Forms</h3>
                      <cfif collegeFormsPage.totalItems EQ 0>
                        <p class="small text-secondary mb-0">No college forms are configured.</p>
                      <cfelse>
                        <ul class="list-group list-group-flush">
                          <cfloop array="#collegeFormsPage.items#" index="linkItem">
                            <li class="list-group-item px-0 d-flex align-items-center justify-content-between gap-2">
                              <a href="#encodeForHTMLAttribute(linkItem.href)#" class="text-decoration-none" target="_blank" rel="noopener noreferrer">#encodeForHTML(linkItem.title)#</a>
                              <span class="badge text-bg-light">form</span>
                            </li>
                          </cfloop>
                        </ul>
                        <cfif collegeFormsPage.totalPages GT 1>
                          <div class="d-flex justify-content-between align-items-center mt-2">
                            <a href="#encodeForHTMLAttribute(buildPageUrl('cfPage', collegeFormsPage.prevPage))#" class="btn btn-sm btn-outline-secondary #collegeFormsPage.hasPrev ? '' : 'disabled'#">Previous</a>
                            <span class="small text-muted">Page #collegeFormsPage.currentPage# of #collegeFormsPage.totalPages#</span>
                            <a href="#encodeForHTMLAttribute(buildPageUrl('cfPage', collegeFormsPage.nextPage))#" class="btn btn-sm btn-outline-secondary #collegeFormsPage.hasNext ? '' : 'disabled'#">Next</a>
                          </div>
                        </cfif>
                      </cfif>
                    </div>

                    <div>
                      <h3 class="h6 text-uppercase text-muted mb-2">Other Links</h3>
                      <cfif otherLinksPage.totalItems EQ 0>
                        <p class="small text-secondary mb-0">No other links are configured.</p>
                      <cfelse>
                        <ul class="list-group list-group-flush">
                          <cfloop array="#otherLinksPage.items#" index="linkItem">
                            <li class="list-group-item px-0 d-flex align-items-center justify-content-between gap-2">
                              <a href="#encodeForHTMLAttribute(linkItem.href)#" class="text-decoration-none" target="_blank" rel="noopener noreferrer">#encodeForHTML(linkItem.title)#</a>
                              <span class="badge #linkItem.source EQ "user" ? "text-bg-primary" : "text-bg-light"#">#encodeForHTML(linkItem.source)#</span>
                            </li>
                          </cfloop>
                        </ul>
                        <cfif otherLinksPage.totalPages GT 1>
                          <div class="d-flex justify-content-between align-items-center mt-2">
                            <a href="#encodeForHTMLAttribute(buildPageUrl('olPage', otherLinksPage.prevPage))#" class="btn btn-sm btn-outline-secondary #otherLinksPage.hasPrev ? '' : 'disabled'#">Previous</a>
                            <span class="small text-muted">Page #otherLinksPage.currentPage# of #otherLinksPage.totalPages#</span>
                            <a href="#encodeForHTMLAttribute(buildPageUrl('olPage', otherLinksPage.nextPage))#" class="btn btn-sm btn-outline-secondary #otherLinksPage.hasNext ? '' : 'disabled'#">Next</a>
                          </div>
                        </cfif>
                      </cfif>
                    </div>
                  </cfif>
                </div>
              </section>
            </div>
          </div>
        </div>
      </cfif><!--- end dispatch branch --->
      </main>
      </div>
    </div>

    <cfif dispatchMode EQ "page-render">
      <script src="https://cdn.jsdelivr.net/npm/quill@1.3.7/dist/quill.min.js"></script>
    </cfif>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
    <cfloop array="#dashboardScripts#" index="dashboardScriptSrc">
      <script src="#encodeForHTMLAttribute(dashboardScriptSrc)#"></script>
    </cfloop>
    <script>
      document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (el) {
        new bootstrap.Tooltip(el);
      });

      (function () {
        var inlineEditorHost = document.getElementById('inlinePageEditor');
        var inlineBodyField = document.getElementById('inlinePageBodyHtml');
        var inlineForm = document.querySelector('.pages-inline-form');
        var inlinePanel = document.getElementById('inlinePageEditorPanel');
        var inlineToggle = document.getElementById('inlinePageEditToggle');
        var inlineCancel = document.getElementById('inlinePageEditorCancel');
        var inlineRenderedContent = document.getElementById('inlinePageRenderedContent');
        var inlineEditor = null;

        if (inlineEditorHost && inlineBodyField && typeof Quill !== 'undefined') {
          inlineEditor = new Quill(inlineEditorHost, {
            theme: 'snow',
            modules: {
              toolbar: [
                [{ header: [1, 2, 3, false] }],
                ['bold', 'italic', 'underline', 'strike'],
                [{ list: 'ordered' }, { list: 'bullet' }],
                ['link', 'blockquote', 'code-block'],
                [{ align: [] }],
                ['clean']
              ]
            }
          });
        }

        if (inlineForm) {
          inlineForm.addEventListener('submit', function () {
            if (inlineEditor && inlineBodyField) {
              inlineBodyField.value = inlineEditor.root.innerHTML;
            }
          });
        }

        if (inlineToggle && inlinePanel) {
          inlineToggle.addEventListener('click', function () {
            inlinePanel.hidden = false;
            inlineToggle.hidden = true;
            if (inlineRenderedContent) {
              inlineRenderedContent.hidden = true;
            }
          });
        }

        if (inlineCancel && inlinePanel && inlineToggle) {
          inlineCancel.addEventListener('click', function () {
            inlinePanel.hidden = true;
            inlineToggle.hidden = false;
            if (inlineRenderedContent) {
              inlineRenderedContent.hidden = false;
            }
          });
        }

        var STUDENT_YEAR_OPTIONS = <cfif dispatchMode EQ "dashboard">#serializeJSON(studentGradYears)#<cfelse>[]</cfif>;
        var ALUMNI_YEAR_OPTIONS  = <cfif dispatchMode EQ "dashboard">#serializeJSON(alumniGradYears)#<cfelse>[]</cfif>;

        var statusEl     = document.getElementById('directoryStatus');
        var wrapEl       = document.getElementById('directoryTableWrap');
        var theadEl      = document.getElementById('directoryThead');
        var tbodyEl      = document.getElementById('directoryTbody');
        var pageInfoEl   = document.getElementById('dirPageInfo');
        var pagCtrlEl    = document.getElementById('dirPagination');
        var pagSizeEl    = document.getElementById('dirPageSize');
        var searchEl     = document.getElementById('dirSearch');
        var gradFilterWrapEl = document.getElementById('dirGradFilterWrap');
        var gradFilterEl = document.getElementById('dirGradFilter');
        var viewTableBtn = document.getElementById('dirViewTable');
        var viewCardsBtn = document.getElementById('dirViewCards');
        var cardGridEl   = document.getElementById('dirCardGrid');
        var tableEl      = document.getElementById('directoryTable');
        var profileModalEl = document.getElementById('dirProfileModal');
        var profileModal = profileModalEl ? new bootstrap.Modal(profileModalEl) : null;
        var profileTitle = document.getElementById('dirProfileModalLabel');
        var profileBody  = document.getElementById('dirProfileModalBody');

        var hasDirectoryUi = !!(
          statusEl && wrapEl && theadEl && tbodyEl && pageInfoEl && pagCtrlEl &&
          pagSizeEl && searchEl && gradFilterWrapEl && gradFilterEl && viewTableBtn &&
          viewCardsBtn && cardGridEl && tableEl && profileModal && profileTitle && profileBody
        );

        if (hasDirectoryUi) {

        var STUDENT_GROUPS = ['students', 'alumni'];

        var state = {
          group:    null,
          allData:  [],
          search:   '',
          gradYear: '',
          sort:     { col: 'lastname', dir: 'asc' },
          page:     1,
          pageSize: 25,
          viewMode: 'table'
        };

        function setStatus(kind, msg) {
          statusEl.className = 'alert py-2' +
            (kind === 'error' ? ' alert-danger' : kind === 'success' ? ' alert-success' : ' alert-secondary');
          statusEl.textContent = msg;
        }

        function normPerson(raw) {
          var p = {};
          Object.keys(raw).forEach(function (k) { p[k.toLowerCase()] = raw[k]; });
          return p;
        }

        function getLastName(name) {
          var parts = (name || '').trim().split(/\s+/);
          return (parts.length > 1 ? parts[parts.length - 1] : parts[0] || '').toLowerCase();
        }

        function getName(p) {
          return p.fullname || p.displayname || p.name || p.username || '';
        }

        function getNameWithDegrees(p) {
          var name = getName(p);
          var deg  = p.degrees || p.degree || '';
          return deg ? name + ', ' + deg : name;
        }

        function getGradYear(p) {
          return (p.currentgradyear || p.gradyear || '').trim();
        }

        function isStudentGroup(group) {
          return STUDENT_GROUPS.indexOf(group) >= 0;
        }

        function buildGradYearOptions(group) {
          var years = [];
          gradFilterEl.innerHTML = '<option value="">Select class year to load...</option>';

          if (group === 'students') {
            years = STUDENT_YEAR_OPTIONS;
          } else if (group === 'alumni') {
            years = ALUMNI_YEAR_OPTIONS;
          }

          years.forEach(function (year) {
            var opt = document.createElement('option');
            opt.value = String(year);
            opt.textContent = String(year);
            gradFilterEl.appendChild(opt);
          });
        }

        function getFacultyType(p) {
          var raw = (p.facultytype || p.faculty_type || p.facultyrole || '').toLowerCase();
          var flags = (p.flags || '').toLowerCase();
          var combined = raw + ' ' + flags;
          if (combined.indexOf('emerit') >= 0)  return 'Professor Emeritus';
          if (combined.indexOf('adjunct') >= 0) return 'Adjunct Faculty';
          if (combined.indexOf('fulltime') >= 0 || combined.indexOf('full-time') >= 0) return 'Faculty';
          return raw ? (raw.charAt(0).toUpperCase() + raw.slice(1)) : 'Faculty';
        }

        function colDefs(group) {
          if (STUDENT_GROUPS.indexOf(group) >= 0) {
            return [
              { key: 'photo',     label: '',          sortKey: null },
              { key: 'fullname',  label: 'Name',      sortKey: 'lastname' },
              { key: 'program',   label: 'Program',   sortKey: 'program' },
              { key: 'gradyear',  label: 'Class of',  sortKey: 'gradyear' }
            ];
          }
          if (group === 'faculty') {
            return [
              { key: 'photo',       label: '',           sortKey: null },
              { key: 'fullname',    label: 'Name',       sortKey: 'lastname' },
              { key: 'facultytype', label: 'Type',       sortKey: 'facultytype' },
              { key: 'title1',      label: 'Title',      sortKey: 'title1' },
              { key: 'email',       label: 'Email',      sortKey: 'email' },
              { key: 'phone',       label: 'Phone',      sortKey: 'phone' }
            ];
          }
          // staff
          return [
            { key: 'photo',    label: '',       sortKey: null },
            { key: 'fullname', label: 'Name',   sortKey: 'lastname' },
            { key: 'title1',   label: 'Title',  sortKey: 'title1' },
            { key: 'email',    label: 'Email',  sortKey: 'email' },
            { key: 'phone',    label: 'Phone',  sortKey: 'phone' }
          ];
        }

        function sortData(data) {
          var col = state.sort.col, dir = state.sort.dir;
          return data.slice().sort(function (a, b) {
            var va = '', vb = '';
            if (col === 'lastname') {
              va = getLastName(getName(a));
              vb = getLastName(getName(b));
            } else if (col === 'email') {
              va = (a.emailprimary || a.email || a.mail || '').toLowerCase();
              vb = (b.emailprimary || b.email || b.mail || '').toLowerCase();
            } else if (col === 'phone') {
              va = a.phone || a.telephonenumber || '';
              vb = b.phone || b.telephonenumber || '';
            } else if (col === 'gradyear') {
              va = String(a.currentgradyear || a.gradyear || '');
              vb = String(b.currentgradyear || b.gradyear || '');
            } else if (col === 'program') {
              va = (a.program || '').toLowerCase();
              vb = (b.program || '').toLowerCase();
            } else if (col === 'title1') {
              va = (a.title1 || a.title || '').toLowerCase();
              vb = (b.title1 || b.title || '').toLowerCase();
            } else if (col === 'facultytype') {
              va = getFacultyType(a).toLowerCase();
              vb = getFacultyType(b).toLowerCase();
            }
            if (va < vb) return dir === 'asc' ? -1 : 1;
            if (va > vb) return dir === 'asc' ? 1 : -1;
            return 0;
          });
        }

        function buildHead(cols) {
          var tr = document.createElement('tr');
          cols.forEach(function (col) {
            var th = document.createElement('th');
            th.scope = 'col';
            if (col.key === 'photo') {
              th.style.width = '48px';
            } else if (col.sortKey) {
              th.style.cursor = 'pointer';
              th.style.userSelect = 'none';
              var arrow = state.sort.col === col.sortKey
                ? (state.sort.dir === 'asc' ? ' \u25b2' : ' \u25bc')
                : ' \u21c5';
              th.textContent = col.label + arrow;
              (function (key) {
                th.addEventListener('click', function () {
                  if (state.sort.col === key) {
                    state.sort.dir = state.sort.dir === 'asc' ? 'desc' : 'asc';
                  } else {
                    state.sort.col = key;
                    state.sort.dir = 'asc';
                  }
                  state.page = 1;
                  renderCurrent();
                });
              }(col.sortKey));
            } else {
              th.textContent = col.label;
            }
            tr.appendChild(th);
          });
          theadEl.innerHTML = '';
          theadEl.appendChild(tr);
        }

        function buildBody(pageData, cols) {
          tbodyEl.innerHTML = '';
          pageData.forEach(function (p) {
            var tr = document.createElement('tr');
            tr.style.cursor = 'pointer';
            tr.addEventListener('click', function () { openProfile(p); });
            cols.forEach(function (col) {
              var td = document.createElement('td');
              if (col.key === 'photo') {
                var thumb = p.webthumburl || p.webthumbimage || p.thumburl || p.thumbnail || '';
                if (thumb) {
                  var img = document.createElement('img');
                  img.src = thumb;
                  img.alt = '';
                  img.className = 'rounded-circle';
                  img.style.cssText = 'width:36px;height:36px;object-fit:cover;';
                  img.onerror = function () { this.style.display = 'none'; };
                  td.appendChild(img);
                }
              } else if (col.key === 'fullname') {
                if (state.group === 'faculty') {
                  var deg = p.degrees || p.degree || '';
                  var nameSpan = document.createElement('span');
                  nameSpan.textContent = getName(p);
                  td.appendChild(nameSpan);
                  if (deg) {
                    var degSpan = document.createElement('span');
                    degSpan.textContent = ', ' + deg;
                    degSpan.className = 'text-muted';
                    td.appendChild(degSpan);
                  }
                } else {
                  td.textContent = getName(p);
                }
                td.className = 'fw-semibold';
              } else if (col.key === 'facultytype') {
                td.textContent = getFacultyType(p);
              } else if (col.key === 'title1') {
                td.textContent = p.title1 || p.title || '';
              } else if (col.key === 'email') {
                var eml = p.emailprimary || p.email || p.mail || '';
                if (eml) {
                  var a = document.createElement('a');
                  a.href = 'mailto:' + eml;
                  a.textContent = eml;
                  a.className = 'text-decoration-none';
                  a.addEventListener('click', function (ev) { ev.stopPropagation(); });
                  td.appendChild(a);
                }
              } else if (col.key === 'phone') {
                td.textContent = p.phone || p.telephonenumber || p.telephone || '';
              } else if (col.key === 'gradyear') {
                td.textContent = p.currentgradyear || p.gradyear || '';
              } else if (col.key === 'program') {
                td.textContent = p.program || '';
              }
              tr.appendChild(td);
            });
            tbodyEl.appendChild(tr);
          });
        }

        function buildPagination(total, page, pageSize) {
          var totalPages = Math.max(1, Math.ceil(total / pageSize));
          var from = Math.min((page - 1) * pageSize + 1, total);
          var to   = Math.min(page * pageSize, total);
          pageInfoEl.textContent = total ? ('Showing ' + from + '\u2013' + to + ' of ' + total) : '';
          pagCtrlEl.innerHTML = '';
          if (totalPages <= 1) return;

          var ul = document.createElement('ul');
          ul.className = 'pagination pagination-sm mb-0';

          function mkLi(label, target, disabled, active) {
            var li  = document.createElement('li');
            li.className = 'page-item' + (disabled || active ? ' disabled' : '') + (active ? ' active' : '');
            var btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'page-link';
            btn.innerHTML = label;
            if (!disabled && !active) {
              btn.addEventListener('click', function () { state.page = target; renderCurrent(); });
            }
            li.appendChild(btn);
            return li;
          }

          ul.appendChild(mkLi('&laquo;', 1, page <= 1, false));
          ul.appendChild(mkLi('&lsaquo;', page - 1, page <= 1, false));
          var start = Math.max(1, page - 2);
          var end   = Math.min(totalPages, start + 4);
          start     = Math.max(1, end - 4);
          for (var i = start; i <= end; i++) {
            ul.appendChild(mkLi(String(i), i, false, i === page));
          }
          ul.appendChild(mkLi('&rsaquo;', page + 1, page >= totalPages, false));
          ul.appendChild(mkLi('&raquo;', totalPages, page >= totalPages, false));
          pagCtrlEl.appendChild(ul);
        }

        function makeInitialsAvatar(name) {
          var parts = (name || '').trim().split(/\s+/);
          var initials = parts.length >= 2
            ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
            : (parts[0] ? parts[0][0].toUpperCase() : '?');
          var div = document.createElement('div');
          div.className = 'rounded d-flex align-items-center justify-content-center mb-2 mx-auto text-white fw-semibold';
          div.style.cssText = 'width:64px;height:64px;font-size:20px;background-color:##6c757d;';
          div.textContent = initials;
          return div;
        }

        function buildCards(pageData) {
          cardGridEl.innerHTML = '';
          pageData.forEach(function (p) {
            var col = document.createElement('div');
            col.className = 'col-6 col-md-4 col-lg-3';
            var card = document.createElement('div');
            card.className = 'card h-100 shadow-sm';
            card.style.cursor = 'pointer';
            card.addEventListener('click', function () { openProfile(p); });
            var cardBody = document.createElement('div');
            cardBody.className = 'card-body text-center p-3';
            var thumb = p.webthumburl || p.webthumbimage || p.thumburl || p.thumbnail || '';
            if (thumb) {
              var img = document.createElement('img');
              img.src = thumb;
              img.alt = '';
              img.className = 'rounded mb-2 d-block mx-auto';
              img.style.cssText = 'width:64px;height:64px;object-fit:cover;';
              (function (imgEl, personName) {
                imgEl.onerror = function () { imgEl.replaceWith(makeInitialsAvatar(personName)); };
              }(img, getName(p)));
              cardBody.appendChild(img);
            } else {
              cardBody.appendChild(makeInitialsAvatar(getName(p)));
            }
            var nameEl = document.createElement('div');
            nameEl.className = 'fw-semibold small';
            nameEl.textContent = state.group === 'faculty' ? getNameWithDegrees(p) : getName(p);
            cardBody.appendChild(nameEl);
            // Title line (always shown when available)
            var titleVal = p.title1 || p.title || p.jobtitle || '';
            if (isStudentGroup(state.group)) {
              var gy = p.currentgradyear || p.gradyear || '';
              titleVal = (p.program || '') + (gy ? ((p.program ? ' \u2022 ' : '') + 'Class of ' + gy) : '');
            }
            if (titleVal) {
              var titleEl = document.createElement('div');
              titleEl.className = 'text-muted small mt-1';
              titleEl.textContent = titleVal;
              cardBody.appendChild(titleEl);
            }
            // Email
            var eml = p.emailprimary || p.email || p.mail || '';
            if (eml) {
              var emlEl = document.createElement('div');
              emlEl.className = 'small mt-1';
              var emlA = document.createElement('a');
              emlA.href = 'mailto:' + eml;
              emlA.className = 'text-decoration-none text-truncate d-block';
              emlA.style.maxWidth = '100%';
              emlA.textContent = eml;
              emlA.addEventListener('click', function (ev) { ev.stopPropagation(); });
              emlEl.appendChild(emlA);
              cardBody.appendChild(emlEl);
            }
            // Phone
            var phone = p.phone || p.telephonenumber || p.telephone || '';
            if (phone) {
              var phoneEl = document.createElement('div');
              phoneEl.className = 'small text-muted mt-1';
              phoneEl.textContent = phone;
              cardBody.appendChild(phoneEl);
            }
            card.appendChild(cardBody);
            col.appendChild(card);
            cardGridEl.appendChild(col);
          });
        }

        function renderCurrent() {
          var term    = state.search.toLowerCase();
          var filtered = state.allData.filter(function (p) {
            var matchesName = !term || getLastName(getName(p)).indexOf(term) >= 0;
            return matchesName;
          });
          var sorted     = sortData(filtered);
          var cols       = colDefs(state.group);
          var totalPages = Math.max(1, Math.ceil(sorted.length / state.pageSize));
          if (state.page > totalPages) state.page = totalPages;
          var startIdx   = (state.page - 1) * state.pageSize;
          var pageData   = sorted.slice(startIdx, startIdx + state.pageSize);
          if (state.viewMode === 'cards') {
            tableEl.style.display = 'none';
            cardGridEl.style.display = '';
            buildCards(pageData);
            theadEl.innerHTML = '';
            tbodyEl.innerHTML = '';
          } else {
            tableEl.style.display = '';
            cardGridEl.style.display = 'none';
            buildHead(cols);
            buildBody(pageData, cols);
          }
          buildPagination(sorted.length, state.page, state.pageSize);
          wrapEl.style.display = '';
        }

        function openProfile(p) {
          var name = getName(p) || '(Unknown)';
          profileTitle.textContent = name;
          var thumb = p.webthumburl || p.webthumbimage || p.thumburl || '';
          var html = '';
          if (thumb) {
            html += '<div class="text-center mb-3"><img src="' + thumb + '" class="rounded-circle" style="width:80px;height:80px;object-fit:cover;" onerror="this.style.display=\'none\'"></div>';
          }
          function row(label, val) {
            return val ? '<dt class="col-sm-4 text-muted fw-normal">' + label + '</dt><dd class="col-sm-8">' + val + '</dd>' : '';
          }
          html += '<dl class="row mb-0">';
          html += row('Email',        p.emailprimary || p.email || p.mail || '');
          html += row('Phone',        p.phone || p.telephonenumber || '');
          html += row('Title',        p.title1 || p.title || p.jobtitle || '');
          html += row('Type',         getFacultyType(p) !== 'Faculty' || p.facultytype ? getFacultyType(p) : '');
          html += row('Degrees',      p.degrees || p.degree || '');
          html += row('Department',   p.department || p.dept || '');
          html += row('Class of',      p.currentgradyear || p.gradyear || '');
          html += row('Program',        p.program || '');
          html += row('User ID',        p.userid || '');
          html += '</dl>';
          profileBody.innerHTML = html;
          profileModal.show();
        }

        function loadDirectoryGroup(group, gradYear) {
          setStatus('info', 'Loading ' + group + '...');
          wrapEl.style.display = 'none';
          tbodyEl.innerHTML = '';

          var url = '/modules/directory/data.cfm?group=' + encodeURIComponent(group);
          if (isStudentGroup(group) && gradYear) {
            url += '&gradyear=' + encodeURIComponent(gradYear);
          }

          fetch(url, { credentials: 'same-origin' })
            .then(function (res) { return res.json(); })
            .then(function (data) {
              var d = {};
              Object.keys(data).forEach(function (k) { d[k.toLowerCase()] = data[k]; });

              var items = d.items || [];
              state.group    = group;
              state.allData  = items.map(normPerson);
              state.search   = '';
              state.gradYear = gradYear || '';
              searchEl.value = '';
              if (isStudentGroup(group)) {
                gradFilterWrapEl.style.display = '';
                gradFilterEl.value = state.gradYear;
              } else {
                gradFilterWrapEl.style.display = 'none';
                gradFilterEl.value = '';
              }
              state.page     = 1;
              state.sort     = { col: 'lastname', dir: 'asc' };
              state.pageSize = parseInt(pagSizeEl.value, 10) || 25;

              if (d.success) {
                if (items.length) {
                  setStatus('success', (group.charAt(0).toUpperCase() + group.slice(1)) + ' \u2014 ' + items.length + ' members loaded.');
                  renderCurrent();
                } else {
                  setStatus('info', d.message || 'No members returned.');
                }
              } else {
                setStatus('error', d.message || 'Directory request failed.');
              }
            })
            .catch(function (err) {
              setStatus('error', 'Directory request failed: ' + err.message);
            });
        }

        viewTableBtn.addEventListener('click', function () {
          if (state.viewMode === 'table') return;
          state.viewMode = 'table';
          viewTableBtn.classList.add('active');
          viewCardsBtn.classList.remove('active');
          if (state.allData.length) renderCurrent();
        });

        viewCardsBtn.addEventListener('click', function () {
          if (state.viewMode === 'cards') return;
          state.viewMode = 'cards';
          viewCardsBtn.classList.add('active');
          viewTableBtn.classList.remove('active');
          if (state.allData.length) renderCurrent();
        });

        pagSizeEl.addEventListener('change', function () {
          state.pageSize = parseInt(pagSizeEl.value, 10) || 25;
          state.page = 1;
          if (state.allData.length) renderCurrent();
        });

        searchEl.addEventListener('input', function () {
          state.search = searchEl.value.trim();
          state.page = 1;
          if (state.allData.length) renderCurrent();
        });

        gradFilterEl.addEventListener('change', function () {
          state.gradYear = gradFilterEl.value;
          state.page = 1;
          if (!isStudentGroup(state.group)) return;
          if (!state.gradYear) {
            state.allData = [];
            wrapEl.style.display = 'none';
            tbodyEl.innerHTML = '';
            setStatus('info', 'Select class year to load ' + state.group + '.');
            return;
          }
          loadDirectoryGroup(state.group, state.gradYear);
        });

        document.querySelectorAll('.directory-group-btn').forEach(function (btn) {
          btn.addEventListener('click', function () {
            var group = btn.getAttribute('data-group');
            document.querySelectorAll('.directory-group-btn').forEach(function (b) { b.classList.remove('active'); });
            btn.classList.add('active');

            state.group = group;
            state.search = '';
            searchEl.value = '';
            state.page = 1;

            if (isStudentGroup(group)) {
              buildGradYearOptions(group);
              gradFilterWrapEl.style.display = '';
              if (!gradFilterEl.value) {
                state.allData = [];
                wrapEl.style.display = 'none';
                tbodyEl.innerHTML = '';
                setStatus('info', 'Select class year to load ' + group + '.');
                return;
              }
              loadDirectoryGroup(group, gradFilterEl.value);
              return;
            }

            gradFilterWrapEl.style.display = 'none';
            gradFilterEl.value = '';
            state.gradYear = '';
            loadDirectoryGroup(group, '');
          });
        });
        }

        var sidebarToggle = document.getElementById('sidebarToggle');
        if (sidebarToggle) {
          sidebarToggle.addEventListener('click', function () {
            if (window.innerWidth <= 991) {
              document.body.classList.toggle('sidebar-open');
              return;
            }
            document.body.classList.toggle('sidebar-collapsed');
          });
        }

      })();
    </script>
  </body>
</html>
</cfoutput>
