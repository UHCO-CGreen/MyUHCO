<!---
  includes/portal-sidebar.cfm
  Portal navigation sidebar with module registry nav items.

  Expects _navActiveModule (string) and optionally _navActivePage (string) set by the including page.
  Defaults to "" (no module/page active) — safe for non-module pages like profile.cfm.
--->
<cfparam name="_navActiveModule" default="">
<cfparam name="_navActivePage" default="">
<cfscript>
_pSidebarItems = [];
if (structKeyExists(application, "moduleRegistry") AND isArray(application.moduleRegistry)) {
  for (_psm in application.moduleRegistry) {
    if (!_psm.enabled) continue;
    if (!structKeyExists(_psm, "nav")) continue;
    _psShowInSidebar = !structKeyExists(_psm.nav, "showInSidebar") OR _psm.nav.showInSidebar EQ true;
    if (!_psShowInSidebar) continue;
    if (_psm.requiresAuth) {
      _psGranted = true;
      if (isArray(_psm.permissions) AND arrayLen(_psm.permissions)) {
        _psGranted = false;
        if (
          structKeyExists(application, "accessService")
          AND isObject(application.accessService)
        ) {
          for (_psPerm in _psm.permissions) {
            if (application.accessService.hasPermission(_psPerm)) {
              _psGranted = true;
              break;
            }
          }
        }
      }
      if (!_psGranted) continue;
    }
    arrayAppend(_pSidebarItems, {
      type:      "module",
      id:        _psm.id,
      label:     _psm.nav.label,
      icon:      _psm.nav.icon,
      group:     structKeyExists(_psm.nav, "group") ? trim(_psm.nav.group & "") : "",
      sortOrder: structKeyExists(_psm.nav, "sortOrder") ? int(val(_psm.nav.sortOrder)) : 99,
      href:      "index.cfm?module=" & _psm.id,
      target:    int(val(_psm.type)) EQ 4 ? "_blank" : "",
      rel:       int(val(_psm.type)) EQ 4 ? "noopener noreferrer" : ""
    });
  }
}
if (structKeyExists(application, "pageService") AND isObject(application.pageService)) {
  _psPageNavResult = application.pageService.listNavPages();
  if (_psPageNavResult.success AND isArray(_psPageNavResult.pages)) {
    for (_psPage in _psPageNavResult.pages) {
      arrayAppend(_pSidebarItems, {
        type:      "page",
        id:        _psPage.slug,
        label:     len(trim(_psPage.navLabel & "")) ? trim(_psPage.navLabel & "") : trim(_psPage.title & ""),
        icon:      "fas fa-file-alt",
        group:     "Pages",
        sortOrder: int(val(_psPage.navSortOrder)),
        href:      "/index.cfm?page=" & urlEncodedFormat(_psPage.slug)
      });
    }
  }
}
arraySort(_pSidebarItems, function(a, b) {
  if (a.group LT b.group) return -1;
  if (a.group GT b.group) return 1;
  return a.sortOrder - b.sortOrder;
});
</cfscript>
<aside class="main-sidebar" id="mainSidebar" aria-label="Main sidebar">
  <div class="main-sidebar-inner">
    <div class="sidebar-brand uhco-logo">
      <img src="/assets/images/UH-Primary-College-of-Optometry-horizontal.webp" alt="College of Optometry" class="img-fluid">
    </div>
    <div class="sidebar-brand uh-logo">
      <img src="/assets/images/uh.png" alt="University of Houston" class="img-fluid">
    </div>
    <nav class="nav flex-column sidebar-nav">
      <a class="nav-link" href="/index.cfm">
        <i class="fas fa-home"></i>
        <span class="sidebar-link-text">Home</span>
      </a>
      <cfif arrayLen(_pSidebarItems)>
        <cfset _psCurrentGroup = chr(0)>
        <cfloop array="#_pSidebarItems#" index="_psItem">
          <cfif _psItem.group NEQ _psCurrentGroup AND len(_psItem.group)>
            <cfset _psCurrentGroup = _psItem.group>
            <cfoutput><div class="sidebar-nav-group-label">#encodeForHTML(_psCurrentGroup)#</div></cfoutput>
          </cfif>
          <cfoutput><a class="nav-link<cfif (_psItem.type EQ 'module' AND _psItem.id EQ _navActiveModule) OR (_psItem.type EQ 'page' AND _psItem.id EQ _navActivePage)> active</cfif>" href="#encodeForHTMLAttribute(_psItem.href)#"<cfif structKeyExists(_psItem, "target") AND len(trim(_psItem.target & ""))> target="#encodeForHTMLAttribute(_psItem.target)#" rel="#encodeForHTMLAttribute(structKeyExists(_psItem, "rel") ? (_psItem.rel & "") : "noopener noreferrer")#"</cfif>>
            <i class="#encodeForHTML(_psItem.icon)#"></i>
            <span class="sidebar-link-text">#encodeForHTML(_psItem.label)#</span>
          </a></cfoutput>
        </cfloop>
      </cfif>
    </nav>
  </div>
</aside>
