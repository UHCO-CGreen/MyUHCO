<cfsetting showdebugoutput="false">
<cfscript>
if (!structKeyExists(session, "user")) {
  location("/login.cfm", false);
}

requestedSection = lCase(trim((structKeyExists(url, "section") ? url.section : "") & ""));
if (!listFindNoCase("quick-docs,rosters,specific,faculty,staff,students", requestedSection)) {
  requestedSection = "";
}

portalUser = session.user;
currentUserId = "";
roleLabel = "";
organizationsRaw = "";
userTypeKey = "";
canViewSettings = false;
canViewAdminDashboard = false;
canSeeAllSpecificDocs = false;

if (structKeyExists(portalUser, "userId") AND len(trim(portalUser.userId & ""))) {
  currentUserId = trim(portalUser.userId & "");
} else if (structKeyExists(portalUser, "username") AND len(trim(portalUser.username & ""))) {
  currentUserId = trim(portalUser.username & "");
}

if (structKeyExists(portalUser, "flags")) {
  if (isSimpleValue(portalUser.flags)) {
    roleLabel = lCase(trim(portalUser.flags & ""));
  } else {
    roleLabel = lCase(serializeJSON(portalUser.flags));
  }
}

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

canSeeAllSpecificDocs = canViewSettings OR canViewAdminDashboard;

if (findNoCase("faculty", roleLabel)) {
  userTypeKey = "faculty";
} else if (findNoCase("staff", roleLabel)) {
  userTypeKey = "staff";
} else if (findNoCase("student", roleLabel)) {
  userTypeKey = "students";
}

result = {
  success = false,
  message = "",
  quickDocs = [],
  rosterDocs = [],
  facultyDocs = [],
  staffDocs = [],
  studentDocs = []
};

try {
  docResult = application.documentService.getDocuments();
  if (docResult.success) {
    bucketedDocuments = application.documentService.bucketDocuments(
      items = docResult.items,
      userTypeKey = userTypeKey,
      includeAllSpecificDocs = canSeeAllSpecificDocs
    );

    result.quickDocs = bucketedDocuments.quickDocs;
    result.rosterDocs = bucketedDocuments.rosterDocs;
    result.facultyDocs = bucketedDocuments.facultyDocs;
    result.staffDocs = bucketedDocuments.staffDocs;
    result.studentDocs = bucketedDocuments.studentDocs;

    result.success = true;
  } else {
    result.message = len(docResult.message) ? docResult.message : "Unable to load documents.";
  }
} catch (any e) {
  result.message = "Unable to load documents.";
  cflog(file = "myuhco-api", type = "error", text = "modules/documents/index.cfm error: #e.message# | #e.detail#");
}

function documentsModuleIsPdfDocument(required struct docItem) {
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

  if (findNoCase("document-view.cfm", hrefValue) OR findNoCase(".pdf", hrefValue)) {
    return true;
  }
  if (categoryValue EQ "pdf" OR findNoCase("pdf", sizeValue)) {
    return true;
  }
  return false;
}

function documentsModuleBuildDocumentLink(required struct docItem) {
  var hrefValue = "";

  if (structKeyExists(arguments.docItem, "href")) {
    hrefValue = trim(arguments.docItem.href & "");
  }

  if (!len(hrefValue) OR hrefValue EQ "##") {
    return hrefValue;
  }
  if (findNoCase("document-view.cfm", hrefValue)) {
    return hrefValue;
  }
  if (documentsModuleIsPdfDocument(arguments.docItem)) {
    return "document-view.cfm?url=" & urlEncodedFormat(hrefValue);
  }
  return hrefValue;
}

function documentsModuleApplyDocumentLinks(required array docs) {
  var i = 0;
  for (i = 1; i LTE arrayLen(arguments.docs); i = i + 1) {
    if (isStruct(arguments.docs[i])) {
      arguments.docs[i].href = documentsModuleBuildDocumentLink(arguments.docs[i]);
    }
  }
}

function documentsModuleSectionClass(required string sectionName) {
  if (requestedSection EQ arguments.sectionName) {
    return " border border-primary-subtle bg-light-subtle";
  }
  if (arguments.sectionName EQ "specific" AND listFindNoCase("faculty,staff,students,specific", requestedSection)) {
    return " border border-primary-subtle bg-light-subtle";
  }
  return "";
}

documentsModuleApplyDocumentLinks(result.quickDocs);
documentsModuleApplyDocumentLinks(result.rosterDocs);
documentsModuleApplyDocumentLinks(result.facultyDocs);
documentsModuleApplyDocumentLinks(result.staffDocs);
documentsModuleApplyDocumentLinks(result.studentDocs);

specificDocsCount = arrayLen(result.facultyDocs) + arrayLen(result.staffDocs) + arrayLen(result.studentDocs);
</cfscript>
<cfoutput>
<div class="container-fluid">
  <div class="row g-4 mb-3">
    <div class="col-12">
      <section class="card border-0 shadow-sm portal-card">
        <div class="card-body p-4">
          <nav aria-label="breadcrumb" class="mb-2">
            <ol class="breadcrumb mb-0">
              <li class="breadcrumb-item"><a href="index.cfm">Portal</a></li>
              <li class="breadcrumb-item active" aria-current="page">Documents</li>
            </ol>
          </nav>

          <div class="d-flex justify-content-between align-items-center mb-3 border-bottom pb-2">
            <div>
              <h1 class="h3 mb-0">Documents</h1>
              <div class="small text-muted">myUHCO Document Center</div>
            </div>
            <a href="index.cfm" class="btn btn-outline-secondary btn-sm">Back to Portal</a>
          </div>

          <div class="d-flex flex-wrap gap-2">
            <a href="##documents-quick-docs" class="btn btn-sm btn-outline-secondary">Quick Docs</a>
            <a href="##documents-rosters" class="btn btn-sm btn-outline-secondary">Rosters</a>
            <a href="##documents-specific" class="btn btn-sm btn-outline-secondary">Specific Documents</a>
          </div>
        </div>
      </section>
    </div>
  </div>

  <div class="row g-4">
    <div class="col-12">
      <section class="card border-0 shadow-sm portal-card#documentsModuleSectionClass('quick-docs')#" id="documents-quick-docs">
        <div class="card-body p-4">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <h2 class="h4 mb-0">Quick Docs</h2>
            <span class="badge bg-light text-dark">#arrayLen(result.quickDocs)# item(s)</span>
          </div>

          <cfif NOT result.success>
            <div class="alert alert-danger mb-0" role="alert">
              <strong>Error:</strong> #encodeForHTML(result.message)#
            </div>
          <cfelseif arrayLen(result.quickDocs) EQ 0>
            <div class="alert alert-secondary mb-0" role="alert">No quick docs are available.</div>
          <cfelse>
            <div class="list-group list-group-flush">
              <cfloop array="#result.quickDocs#" index="docItem">
                <a href="#encodeForHTMLAttribute(docItem.href)#" class="list-group-item list-group-item-action px-0" target="_blank" rel="noopener noreferrer">
                  <div class="d-flex justify-content-between align-items-start">
                    <div>
                      <div class="fw-semibold">#encodeForHTML(docItem.title)#</div>
                      <div class="small text-secondary">#encodeForHTML(docItem.description)#</div>
                      <div class="small text-muted mt-1">#encodeForHTML(docItem.category)#<cfif len(docItem.updatedAt)> | Updated #encodeForHTML(docItem.updatedAt)#</cfif></div>
                    </div>
                    <span class="badge text-bg-light">#encodeForHTML(docItem.size)#</span>
                  </div>
                </a>
              </cfloop>
            </div>
          </cfif>
        </div>
      </section>
    </div>

    <div class="col-12">
      <section class="card border-0 shadow-sm portal-card#documentsModuleSectionClass('rosters')#" id="documents-rosters">
        <div class="card-body p-4">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <h2 class="h4 mb-0">Rosters</h2>
            <span class="badge bg-light text-dark">#arrayLen(result.rosterDocs)# item(s)</span>
          </div>

          <cfif NOT result.success>
            <div class="alert alert-danger mb-0" role="alert">
              <strong>Error:</strong> #encodeForHTML(result.message)#
            </div>
          <cfelseif arrayLen(result.rosterDocs) EQ 0>
            <div class="alert alert-secondary mb-0" role="alert">No rosters are available.</div>
          <cfelse>
            <div class="list-group list-group-flush">
              <cfloop array="#result.rosterDocs#" index="docItem">
                <a href="#encodeForHTMLAttribute(docItem.href)#" class="list-group-item list-group-item-action px-0" target="_blank" rel="noopener noreferrer">
                  <div class="d-flex justify-content-between align-items-start">
                    <div>
                      <div class="fw-semibold">#encodeForHTML(docItem.title)#</div>
                      <div class="small text-secondary">#encodeForHTML(docItem.description)#</div>
                      <div class="small text-muted mt-1">#encodeForHTML(docItem.category)#<cfif len(docItem.updatedAt)> | Updated #encodeForHTML(docItem.updatedAt)#</cfif></div>
                    </div>
                    <span class="badge text-bg-light">#encodeForHTML(docItem.size)#</span>
                  </div>
                </a>
              </cfloop>
            </div>
          </cfif>
        </div>
      </section>
    </div>

    <div class="col-12">
      <section class="card border-0 shadow-sm portal-card#documentsModuleSectionClass('specific')#" id="documents-specific">
        <div class="card-body p-4">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <h2 class="h4 mb-0">Specific Documents</h2>
            <span class="badge bg-light text-dark">#specificDocsCount# item(s)</span>
          </div>

          <cfif NOT result.success>
            <div class="alert alert-danger mb-0" role="alert">
              <strong>Error:</strong> #encodeForHTML(result.message)#
            </div>
          <cfelseif specificDocsCount EQ 0>
            <div class="alert alert-secondary mb-0" role="alert">
              No specific documents are available for this account.
            </div>
          <cfelse>
            <cfif arrayLen(result.facultyDocs)>
              <div class="mb-4" id="documents-faculty">
                <h3 class="h6 text-uppercase text-muted mb-2">Faculty Documents</h3>
                <div class="list-group list-group-flush">
                  <cfloop array="#result.facultyDocs#" index="docItem">
                    <a href="#encodeForHTMLAttribute(docItem.href)#" class="list-group-item list-group-item-action px-0" target="_blank" rel="noopener noreferrer">
                      <div class="d-flex justify-content-between align-items-start">
                        <div>
                          <div class="fw-semibold">#encodeForHTML(docItem.title)#</div>
                          <div class="small text-secondary">#encodeForHTML(docItem.description)#</div>
                          <div class="small text-muted mt-1">#encodeForHTML(docItem.category)#<cfif len(docItem.updatedAt)> | Updated #encodeForHTML(docItem.updatedAt)#</cfif></div>
                        </div>
                        <span class="badge text-bg-light">#encodeForHTML(docItem.size)#</span>
                      </div>
                    </a>
                  </cfloop>
                </div>
              </div>
            </cfif>

            <cfif arrayLen(result.staffDocs)>
              <div class="mb-4" id="documents-staff">
                <h3 class="h6 text-uppercase text-muted mb-2">Staff Documents</h3>
                <div class="list-group list-group-flush">
                  <cfloop array="#result.staffDocs#" index="docItem">
                    <a href="#encodeForHTMLAttribute(docItem.href)#" class="list-group-item list-group-item-action px-0" target="_blank" rel="noopener noreferrer">
                      <div class="d-flex justify-content-between align-items-start">
                        <div>
                          <div class="fw-semibold">#encodeForHTML(docItem.title)#</div>
                          <div class="small text-secondary">#encodeForHTML(docItem.description)#</div>
                          <div class="small text-muted mt-1">#encodeForHTML(docItem.category)#<cfif len(docItem.updatedAt)> | Updated #encodeForHTML(docItem.updatedAt)#</cfif></div>
                        </div>
                        <span class="badge text-bg-light">#encodeForHTML(docItem.size)#</span>
                      </div>
                    </a>
                  </cfloop>
                </div>
              </div>
            </cfif>

            <cfif arrayLen(result.studentDocs)>
              <div id="documents-students">
                <h3 class="h6 text-uppercase text-muted mb-2">Student Documents</h3>
                <div class="list-group list-group-flush">
                  <cfloop array="#result.studentDocs#" index="docItem">
                    <a href="#encodeForHTMLAttribute(docItem.href)#" class="list-group-item list-group-item-action px-0" target="_blank" rel="noopener noreferrer">
                      <div class="d-flex justify-content-between align-items-start">
                        <div>
                          <div class="fw-semibold">#encodeForHTML(docItem.title)#</div>
                          <div class="small text-secondary">#encodeForHTML(docItem.description)#</div>
                          <div class="small text-muted mt-1">#encodeForHTML(docItem.category)#<cfif len(docItem.updatedAt)> | Updated #encodeForHTML(docItem.updatedAt)#</cfif></div>
                        </div>
                        <span class="badge text-bg-light">#encodeForHTML(docItem.size)#</span>
                      </div>
                    </a>
                  </cfloop>
                </div>
              </div>
            </cfif>
          </cfif>
        </div>
      </section>
    </div>
  </div>
</div>
<cfif len(requestedSection)>
  <script>
    (function () {
      var targetId = '';
      switch ('#encodeForJavaScript(requestedSection)#') {
        case 'quick-docs': targetId = 'documents-quick-docs'; break;
        case 'rosters': targetId = 'documents-rosters'; break;
        case 'specific': targetId = 'documents-specific'; break;
        case 'faculty': targetId = 'documents-faculty'; break;
        case 'staff': targetId = 'documents-staff'; break;
        case 'students': targetId = 'documents-students'; break;
      }
      if (!targetId) {
        return;
      }
      var target = document.getElementById(targetId);
      if (target) {
        target.scrollIntoView({ behavior: 'auto', block: 'start' });
      }
    }());
  </script>
</cfif>
</cfoutput>