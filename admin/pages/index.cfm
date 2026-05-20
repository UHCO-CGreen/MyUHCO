<cfsetting showdebugoutput="false">
<!---
  admin/pages/index.cfm — Pages Admin (P1)
  Requires portal login + portal.admin permission.
  Manages portal-native pages backed by the PortalPages DB table.
--->

<cfif NOT (
    structKeyExists(session, "user")
    AND structKeyExists(session.user, "userID")
    AND isNumeric(session.user.userID)
    AND session.user.userID GT 0
)>
  <cflocation url="/login.cfm" addtoken="false">
</cfif>
<cfset application.accessService.requirePermission("portal.admin")>

<cfset _flash = { msg: "", type: "" }>
<cfset _selectedPageId = 0>
<cfset _pageList = { success: false, message: "", pages: [] }>
<cfset _currentPage = { pageId = 0, slug = "", title = "", navLabel = "", summary = "", bodyHtml = "", isPublished = false, showInNav = false, navSortOrder = 100 }>
<cfset _serviceReady = structKeyExists(application, "pageService") AND isObject(application.pageService)>
<cfset _tableStatus = {
  ready = false,
  exists = false,
  datasource = structKeyExists(application, "myuhcoDatasource") ? application.myuhcoDatasource : "",
  tableName = "PortalPages",
  errorMessage = _serviceReady ? "" : "PageService is not available."
}>

<cfif _serviceReady>
  <cfset _tableStatus = application.pageService.getTableStatus()>
  <cfset _currentPage = application.pageService.defaultPageRecord()>
</cfif>

<cfif cgi.request_method EQ "POST" AND _serviceReady AND _tableStatus.ready AND _tableStatus.exists>
  <cfparam name="form._action" default="save">
  <cfparam name="form.pageId" default="0">
  <cfset _selectedPageId = int(val(form.pageId))>

  <cfif form._action EQ "rowSettings">
    <cfparam name="form.returnPageId" default="0">
    <cfset _rowPageResult = application.pageService.getPage(_selectedPageId)>
    <cfif _rowPageResult.success AND _rowPageResult.found>
      <cfset _rowSaveResult = application.pageService.savePage({
        pageId = _rowPageResult.page.pageId,
        slug = _rowPageResult.page.slug,
        title = _rowPageResult.page.title,
        navLabel = _rowPageResult.page.navLabel,
        summary = _rowPageResult.page.summary,
        bodyHtml = _rowPageResult.page.bodyHtml,
        isPublished = structKeyExists(form, "isPublished") ? 1 : 0,
        showInNav = structKeyExists(form, "showInNav") ? 1 : 0,
        navSortOrder = _rowPageResult.page.navSortOrder
      }, session.user.userID)>

      <cfif _rowSaveResult.success>
        <cfset _flash = { msg: "Page settings updated.", type: "success" }>
      <cfelse>
        <cfset _flash = { msg: "Settings update failed: #encodeForHTML(_rowSaveResult.message)#", type: "danger" }>
      </cfif>
    <cfelse>
      <cfset _flash = { msg: "Settings update failed: page not found.", type: "danger" }>
    </cfif>
    <cfset _selectedPageId = int(val(form.returnPageId))>
  <cfelseif form._action EQ "delete">
    <cfset _deleteResult = application.pageService.deletePage(_selectedPageId)>
    <cfif _deleteResult.success>
      <cfset _flash = { msg: "Page deleted.", type: "success" }>
      <cfset _selectedPageId = 0>
      <cfset _currentPage = application.pageService.defaultPageRecord()>
    <cfelse>
      <cfset _flash = { msg: "Delete failed: #encodeForHTML(_deleteResult.message)#", type: "danger" }>
    </cfif>
  <cfelse>
    <cfset _saveResult = application.pageService.savePage({
      pageId = form.pageId,
      slug = form.slug,
      title = form.title,
      navLabel = form.navLabel,
      summary = form.summary,
      bodyHtml = form.bodyHtml,
      isPublished = structKeyExists(form, "isPublished") ? 1 : 0,
      showInNav = structKeyExists(form, "showInNav") ? 1 : 0,
      navSortOrder = form.navSortOrder
    }, session.user.userID)>

    <cfif _saveResult.success>
      <cfset _flash = { msg: "Page saved.", type: "success" }>
      <cfset _selectedPageId = _saveResult.pageId>
    <cfelse>
      <cfset _flash = { msg: "Save failed: #encodeForHTML(_saveResult.message)#", type: "danger" }>
      <cfset _currentPage = {
        pageId = int(val(form.pageId)),
        slug = trim(form.slug & ""),
        title = trim(form.title & ""),
        navLabel = trim(form.navLabel & ""),
        summary = trim(form.summary & ""),
        bodyHtml = form.bodyHtml & "",
        isPublished = structKeyExists(form, "isPublished"),
        showInNav = structKeyExists(form, "showInNav"),
        navSortOrder = int(val(form.navSortOrder))
      }>
    </cfif>
  </cfif>
</cfif>

<cfif int(val(url.id ?: 0)) GT 0>
  <cfset _selectedPageId = int(val(url.id))>
</cfif>

<cfif _serviceReady AND _tableStatus.ready AND _tableStatus.exists>
  <cfset _pageList = application.pageService.listPages(true)>
  <cfif _pageList.success AND _selectedPageId GT 0>
    <cfset _pageResult = application.pageService.getPage(_selectedPageId)>
    <cfif _pageResult.success AND _pageResult.found>
      <cfset _currentPage = _pageResult.page>
    </cfif>
  </cfif>
</cfif>

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MyUHCO — Pages Admin</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/quill@1.3.7/dist/quill.snow.css">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
  <link rel="stylesheet" href="/assets/plugins/fontawesome-free/css/all.min.css">
  <link rel="stylesheet" href="/assets/css/dist/myuhco/admin.css">
  <link rel="stylesheet" href="/css/pages-platform.css">
  <link rel="stylesheet" href="/css/admin-pages.css">
</head>
<body>
<cfset portalUser = session.user>
<cfset roleDisplay = "">
<cfset gradYearDisplay = "">
<cfset canViewSettings = false>
<cfset canViewAdminDashboard = false>
<div class="portal-shell">
<cfinclude template="/includes/admin-sidebar.cfm">
<div class="mainContainer flex-grow-1" id="main">
<cfinclude template="/includes/portal-header.cfm">

<div class="container-fluid py-4 px-4 pages-admin-shell">
  <div class="d-flex flex-column flex-lg-row justify-content-between align-items-lg-center gap-3 mb-4">
    <div>
      <h5 class="fw-bold mb-1">Pages</h5>
      <p class="text-muted mb-0">Portal-native page CRUD for the upcoming Pages platform track.</p>
    </div>
    <div class="pages-admin-meta">
      <span class="badge text-bg-light border">Datasource: <cfoutput>#encodeForHTML(_tableStatus.datasource & "")#</cfoutput></span>
      <span class="badge text-bg-light border">Table: <cfoutput>#encodeForHTML(_tableStatus.tableName & "")#</cfoutput></span>
    </div>
  </div>

  <cfif len(_flash.msg)>
    <div class="alert alert-#encodeForHTMLAttribute(_flash.type)# pages-admin-alert" role="alert"><cfoutput>#_flash.msg#</cfoutput></div>
  </cfif>

  <cfif NOT _serviceReady>
    <div class="alert alert-danger" role="alert">PageService is not available in application scope.</div>
  <cfelseif NOT _tableStatus.ready>
    <div class="alert alert-warning" role="alert">The MyUHCO datasource is not configured, so Pages CRUD is not available yet.</div>
  <cfelseif NOT _tableStatus.exists>
    <div class="alert alert-warning" role="alert">
      The <strong>PortalPages</strong> table was not found in the configured datasource. Apply the schema script at
      <span class="pages-admin-path">_dev/Pages/PORTAL_PAGES_SCHEMA.sql</span>
      and reload this screen.
      <cfif len(_tableStatus.errorMessage)>
        <div class="small mt-2 text-muted"><cfoutput>#encodeForHTML(_tableStatus.errorMessage)#</cfoutput></div>
      </cfif>
    </div>
  </cfif>

  <div class="row g-4">
    <div class="col-12 col-xl-7">
      <div class="card border-0 shadow-sm pages-admin-card">
        <div class="card-body p-4">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <div>
              <h6 class="fw-semibold mb-1"><cfoutput>#_currentPage.pageId GT 0 ? "Edit Page" : "New Page"#</cfoutput></h6>
              <div class="text-muted small">Quill powers page content editing. Publishing controls live in the Saved Pages panel.</div>
            </div>
            <cfif _currentPage.pageId GT 0>
              <a href="/admin/pages/" class="btn btn-outline-secondary btn-sm">New</a>
            </cfif>
          </div>

          <form method="post" action="/admin/pages/" class="pages-admin-form" id="pageAdminForm">
            <input type="hidden" name="_action" id="pageFormAction" value="save">
            <input type="hidden" name="pageId" value="<cfoutput>#_currentPage.pageId#</cfoutput>">

            <div class="row g-3">
              <div class="col-12 col-md-6">
                <label for="title" class="form-label">Title</label>
                <input type="text" class="form-control" id="title" name="title" maxlength="200" value="<cfoutput>#encodeForHTMLAttribute(_currentPage.title & "")#</cfoutput>" <cfif NOT (_serviceReady AND _tableStatus.ready AND _tableStatus.exists)>disabled</cfif> required>
              </div>
              <div class="col-12 col-md-6">
                <label for="slug" class="form-label">Slug</label>
                <div class="input-group">
                  <span class="input-group-text">/index.cfm?page=</span>
                  <input type="text" class="form-control" id="slug" name="slug" maxlength="120" value="<cfoutput>#encodeForHTMLAttribute(_currentPage.slug & "")#</cfoutput>" <cfif NOT (_serviceReady AND _tableStatus.ready AND _tableStatus.exists)>disabled</cfif> required>
                </div>
              </div>

              <div class="col-12">
                <div class="pages-admin-collapsible">
                  <button
                    class="btn btn-outline-secondary btn-sm pages-admin-collapse-toggle"
                    type="button"
                    data-bs-toggle="collapse"
                    data-bs-target="#pageAdminMetaFields"
                    aria-expanded="<cfoutput>#_currentPage.pageId GT 0 ? "false" : "true"#</cfoutput>"
                    aria-controls="pageAdminMetaFields">
                    Page Metadata
                  </button>
                  <div class="collapse<cfif _currentPage.pageId EQ 0> show</cfif> pages-admin-meta-collapse" id="pageAdminMetaFields">
                    <div class="row g-3 pt-3">
                      <div class="col-12 col-md-8">
                        <label for="navLabel" class="form-label">Nav Label</label>
                        <input type="text" class="form-control" id="navLabel" name="navLabel" maxlength="120" value="<cfoutput>#encodeForHTMLAttribute(_currentPage.navLabel & "")#</cfoutput>" <cfif NOT (_serviceReady AND _tableStatus.ready AND _tableStatus.exists)>disabled</cfif>>
                      </div>
                      <div class="col-12 col-md-4">
                        <label for="navSortOrder" class="form-label">Nav Sort Order</label>
                        <input type="number" class="form-control" id="navSortOrder" name="navSortOrder" value="<cfoutput>#int(val(_currentPage.navSortOrder))#</cfoutput>" <cfif NOT (_serviceReady AND _tableStatus.ready AND _tableStatus.exists)>disabled</cfif>>
                      </div>
                      <div class="col-12">
                        <label for="summary" class="form-label">Summary</label>
                        <textarea class="form-control" id="summary" name="summary" rows="2" maxlength="500" <cfif NOT (_serviceReady AND _tableStatus.ready AND _tableStatus.exists)>disabled</cfif>><cfoutput>#encodeForHTML(_currentPage.summary & "")#</cfoutput></textarea>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
              <div class="col-12">
                <label for="bodyHtml" class="form-label">Body HTML</label>
                <input type="hidden" id="bodyHtml" name="bodyHtml" value="<cfoutput>#encodeForHTMLAttribute(_currentPage.bodyHtml & "")#</cfoutput>">
                <div class="pages-editor-shell">
                  <div id="adminPageEditor"><cfoutput>#_currentPage.bodyHtml#</cfoutput></div>
                </div>
                <div class="form-text">Quill editor content is saved as HTML.</div>
              </div>
            </div>

            <div class="d-flex flex-wrap gap-2 mt-4">
              <button type="submit" class="btn btn-primary" onclick="document.getElementById('pageFormAction').value='save';" <cfif NOT (_serviceReady AND _tableStatus.ready AND _tableStatus.exists)>disabled</cfif>>Save Page</button>
              <cfif _currentPage.pageId GT 0>
                <button type="submit" class="btn btn-outline-danger" onclick="document.getElementById('pageFormAction').value='delete'; return confirm('Delete this page?');" <cfif NOT (_serviceReady AND _tableStatus.ready AND _tableStatus.exists)>disabled</cfif>>Delete</button>
              </cfif>
            </div>
          </form>
        </div>
      </div>
    </div>

    <div class="col-12 col-xl-5">
      <div class="card border-0 shadow-sm pages-admin-card">
        <div class="card-body p-4">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <div>
              <h6 class="fw-semibold mb-1">Saved Pages</h6>
              <div class="text-muted small">Drafts and published pages from the `PortalPages` table. Publishing switches save immediately per page.</div>
            </div>
            <span class="badge text-bg-light border"><cfoutput>#arrayLen(_pageList.pages)#</cfoutput></span>
          </div>

          <cfif _serviceReady AND _tableStatus.ready AND _tableStatus.exists AND _pageList.success>
            <cfif arrayLen(_pageList.pages)>
              <div class="table-responsive">
                <table class="table align-middle pages-admin-table mb-0">
                  <thead>
                    <tr>
                      <th>Page</th>
                      <th>Publishing</th>
                      <th class="text-end">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <cfloop array="#_pageList.pages#" index="_pageItem">
                      <tr>
                        <td>
                          <div class="fw-semibold"><cfoutput>#encodeForHTML(_pageItem.title & "")#</cfoutput></div>
                          <div class="small text-muted">/<cfoutput>#encodeForHTML(_pageItem.slug & "")#</cfoutput></div>
                          <cfif len(_pageItem.summary & "")>
                            <div class="small text-muted mt-1"><cfoutput>#encodeForHTML(_pageItem.summary & "")#</cfoutput></div>
                          </cfif>
                        </td>
                        <td>
                          <form method="post" action="/admin/pages/" class="pages-admin-row-form">
                            <input type="hidden" name="_action" value="rowSettings">
                            <input type="hidden" name="pageId" value="<cfoutput>#int(val(_pageItem.pageId))#</cfoutput>">
                            <input type="hidden" name="returnPageId" value="<cfoutput>#int(val(_currentPage.pageId))#</cfoutput>">
                            <div class="form-check form-switch">
                              <input class="form-check-input" type="checkbox" role="switch" id="rowPublished<cfoutput>#int(val(_pageItem.pageId))#</cfoutput>" name="isPublished" value="1" <cfif _pageItem.isPublished>checked</cfif> onchange="this.form.requestSubmit();">
                              <label class="form-check-label" for="rowPublished<cfoutput>#int(val(_pageItem.pageId))#</cfoutput>">Published</label>
                            </div>
                            <div class="form-check form-switch mt-2">
                              <input class="form-check-input" type="checkbox" role="switch" id="rowShowInNav<cfoutput>#int(val(_pageItem.pageId))#</cfoutput>" name="showInNav" value="1" <cfif _pageItem.showInNav>checked</cfif> onchange="this.form.requestSubmit();">
                              <label class="form-check-label" for="rowShowInNav<cfoutput>#int(val(_pageItem.pageId))#</cfoutput>">Show in nav</label>
                            </div>
                            <div class="small text-muted mt-2">Nav order: <cfoutput>#int(val(_pageItem.navSortOrder))#</cfoutput></div>
                          </form>
                        </td>
                        <td class="text-end">
                          <a class="btn btn-sm btn-outline-primary" href="/admin/pages/?id=<cfoutput>#int(val(_pageItem.pageId))#</cfoutput>">Edit</a>
                        </td>
                      </tr>
                    </cfloop>
                  </tbody>
                </table>
              </div>
            <cfelse>
              <div class="pages-admin-empty">No pages have been created yet.</div>
            </cfif>
          <cfelseif _serviceReady AND _tableStatus.ready AND _tableStatus.exists>
            <div class="alert alert-danger mb-0" role="alert">Page listing failed: <cfoutput>#encodeForHTML(_pageList.message & "")#</cfoutput></div>
          <cfelse>
            <div class="pages-admin-empty">Create the database table first, then this list will populate.</div>
          </cfif>
        </div>
      </div>
    </div>
  </div>
</div>
</div>
</div>

<script src="https://cdn.jsdelivr.net/npm/quill@1.3.7/dist/quill.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
<script>
(function () {
  var bodyField = document.getElementById('bodyHtml');
  var editorHost = document.getElementById('adminPageEditor');
  var adminEditor = null;

  if (editorHost && bodyField) {
    adminEditor = new Quill(editorHost, {
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

  document.querySelector('.pages-admin-form')?.addEventListener('submit', function () {
    if (adminEditor && bodyField) {
      bodyField.value = adminEditor.root.innerHTML;
    }
  });

  if (localStorage.getItem('sidebarCollapsed') === 'true') { document.body.classList.add('sidebar-collapsed'); }
  var btn = document.getElementById('sidebarToggle');
  if (btn) {
    btn.addEventListener('click', function () {
      if (window.innerWidth <= 991) { document.body.classList.toggle('sidebar-open'); return; }
      var collapsed = document.body.classList.toggle('sidebar-collapsed');
      localStorage.setItem('sidebarCollapsed', String(collapsed));
    });
  }
}());
</script>

</body>
</html>