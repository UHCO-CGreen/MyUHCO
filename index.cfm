<cfsetting showdebugoutput="false">
<cfscript>
if (!structKeyExists(session, "portalUser")) {
  location("/login.cfm", false);
}

portalUser = session.portalUser;
currentUserId = "";
if (structKeyExists(portalUser, "userId") AND len(trim(portalUser.userId & ""))) {
  currentUserId = trim(portalUser.userId & "");
} else if (structKeyExists(portalUser, "username") AND len(trim(portalUser.username & ""))) {
  currentUserId = trim(portalUser.username & "");
}
if (!len(currentUserId)) {
  currentUserId = "anonymous";
}

linksFlashMessage = "";
linksFlashStatus = "";
if (structKeyExists(url, "linksMessage")) {
  linksFlashMessage = trim(url.linksMessage & "");
}
if (structKeyExists(url, "linksStatus")) {
  linksFlashStatus = lCase(trim(url.linksStatus & ""));
}

if (cgi.request_method EQ "POST" AND structKeyExists(form, "linkAction")) {
  action = lCase(trim(form.linkAction & ""));
  flashMessage = "";
  flashStatus = "error";
  returnOtherLinksPage = 1;

  if (structKeyExists(form, "olPage")) {
    returnOtherLinksPage = val(form.olPage);
  }
  if (returnOtherLinksPage LT 1) {
    returnOtherLinksPage = 1;
  }

  if (action EQ "create") {
    titleValue = trim((structKeyExists(form, "linkTitle") ? form.linkTitle : "") & "");
    hrefValue = trim((structKeyExists(form, "linkHref") ? form.linkHref : "") & "");
    saveResult = application.linkService.saveUserLink(
      userId = currentUserId,
      title = titleValue,
      href = hrefValue
    );
    if (saveResult.success) {
      flashStatus = "success";
      flashMessage = "Link saved.";
    } else {
      flashMessage = len(saveResult.message) ? saveResult.message : "Unable to save link.";
    }
  } else if (action EQ "delete") {
    linkIdValue = trim((structKeyExists(form, "linkId") ? form.linkId : "") & "");
    deleteResult = application.linkService.deleteUserLink(
      userId = currentUserId,
      linkId = linkIdValue
    );
    if (deleteResult.success) {
      flashStatus = "success";
      flashMessage = "Link deleted.";
    } else {
      flashMessage = len(deleteResult.message) ? deleteResult.message : "Unable to delete link.";
    }
  } else {
    flashMessage = "Unknown link action.";
  }

  location(
    "index.cfm?linksStatus=" & urlEncodedFormat(flashStatus) & "&linksMessage=" & urlEncodedFormat(flashMessage) & "&olPage=" & urlEncodedFormat(returnOtherLinksPage),
    false
  );
}

roleLabel = "";
roleDisplay = "";
flagsRaw = "";
gradYearDisplay = "";
organizationsRaw = "";
canViewSettings = false;

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

documentResult = {
  success = false,
  message = "Documents have not loaded.",
  items = [],
  quickDocsFolderUrl = ""
};

linksResult = {
  success = false,
  message = "Links have not loaded.",
  links = []
};

try {
  documentResult = application.documentService.getDocuments();
} catch (any e) {
  documentResult = {
    success = false,
    message = "Document service unavailable.",
    items = [],
    quickDocsFolderUrl = ""
  };
  cflog(file = "myuhco-api", type = "error", text = "Index document section failed: #e.message#");
}

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
documentsCount = arrayLen(documentResult.items);
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

quickDocs = [];
facultyDocs = [];
staffDocs = [];
studentDocs = [];

collegeFormsLinks = [];
otherLinks = [];

if (documentResult.success) {
  for (docItem in documentResult.items) {
    docSection = lCase(trim((structKeyExists(docItem, "section") ? docItem.section : "") & ""));
    if (docSection EQ "quick-docs" OR docSection EQ "quick docs") {
      arrayAppend(quickDocs, docItem);
    } else if (docSection EQ "faculty") {
      if (canSeeAllUserTypeDocs OR userTypeKey EQ "faculty") {
        arrayAppend(facultyDocs, docItem);
      }
    } else if (docSection EQ "staff") {
      if (canSeeAllUserTypeDocs OR userTypeKey EQ "staff") {
        arrayAppend(staffDocs, docItem);
      }
    } else if (docSection EQ "students" OR docSection EQ "student") {
      if (canSeeAllUserTypeDocs OR userTypeKey EQ "students") {
        arrayAppend(studentDocs, docItem);
      }
    } else {
      arrayAppend(quickDocs, docItem);
    }
  }
}

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

quickDocs = limitItems(quickDocs, docsPageSize);
facultyDocs = limitItems(facultyDocs, docsPageSize);
staffDocs = limitItems(staffDocs, docsPageSize);
studentDocs = limitItems(studentDocs, docsPageSize);

quickDocsPage = paginateItems(quickDocs, "qdPage", docsPageSize);
facultyDocsPage = paginateItems(facultyDocs, "fdPage", docsPageSize);
staffDocsPage = paginateItems(staffDocs, "sdPage", docsPageSize);
studentDocsPage = paginateItems(studentDocs, "stdPage", docsPageSize);
collegeFormsPage = paginateItems(collegeFormsLinks, "cfPage", linksPageSize);
otherLinksPage = paginateItems(otherLinks, "olPage", linksPageSize);
</cfscript>
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
    <link rel="stylesheet" href="css/portal-style.css">

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

    <div class="mainContainer" id="main">
      <header class="portal-header border-bottom">
        <nav class="navbar navbar-expand-lg py-2">
          <div class="container-xxl">
            <a class="navbar-brand" href="##" aria-label="MyUHCO Home">
              <img
                id="siteLogo"
                src="assets/images/optopmetry-college-of-optometry-tertiary.svg"
                class="img-fluid portal-logo"
                alt="University of Houston College of Optometry">
            </a>

            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="##portalNav" aria-controls="portalNav" aria-expanded="false" aria-label="Toggle navigation">
              <span class="navbar-toggler-icon"></span>
            </button>

            <div class="collapse navbar-collapse justify-content-end" id="portalNav">
              <ul class="navbar-nav align-items-lg-center gap-lg-2">
                <li class="nav-item d-none d-lg-block">
                  <a class="nav-link p-1" href="/my-uhco/applications/accessuh" target="_blank" data-bs-toggle="tooltip" data-bs-title="Go To AccessUH" aria-label="AccessUH">
                    <img src="assets/images/46904E6A-93E9-1182-D5CC96AA4A79783F.png" class="ql-images" alt="AccessUH">
                  </a>
                </li>
                <li class="nav-item d-none d-lg-block">
                  <a class="nav-link p-1" href="/my-uhco/applications/microsoft-365" target="_blank" data-bs-toggle="tooltip" data-bs-title="Go To Microsoft 365" aria-label="Microsoft 365">
                    <img src="assets/images/46ABFF34-C534-BCDD-7C1AA910244CFBB6.png" class="ql-images" alt="Microsoft 365">
                  </a>
                </li>
                <li class="nav-item d-none d-lg-block">
                  <a class="nav-link p-1" href="/my-uhco/applications/microsoft-teams" target="_blank" data-bs-toggle="tooltip" data-bs-title="Go To Microsoft Teams" aria-label="Microsoft Teams">
                    <img src="assets/images/46B6BA2A-F944-46D8-8B7664D3348269DC.png" class="ql-images" alt="Microsoft Teams">
                  </a>
                </li>
                <li class="nav-item ms-lg-2">
                  <div class="dropdown">
                    <button class="btn btn-link nav-link dropdown-toggle p-0 d-flex align-items-center gap-2" type="button" data-bs-toggle="dropdown" aria-expanded="false" aria-label="User menu">
                      <cfif structKeyExists(portalUser, "webThumbImage") AND len(portalUser.webThumbImage)>
                        <img src="#encodeForHTML(portalUser.webThumbImage)#" alt="Profile" class="rounded-circle" style="width: 32px; height: 32px; object-fit: cover;">
                      <cfelse>
                        <i class="fa-solid fa-circle-user" style="font-size: 24px;"></i>
                      </cfif>
                      <span class="d-none d-lg-inline text-dark small">#encodeForHTML(portalUser.displayName)#</span>
                    </button>

                    <ul class="dropdown-menu dropdown-menu-end">
                      <li>
                        <h6 class="dropdown-header">#encodeForHTML(portalUser.displayName)#</h6>
                      </li>
                      <li>
                        <span class="dropdown-item-text small text-muted">#encodeForHTML(portalUser.email)#</span>
                      </li>
                      <cfif structKeyExists(portalUser, "title") AND len(portalUser.title)>
                        <li>
                          <span class="dropdown-item-text small text-muted">#encodeForHTML(portalUser.title)#</span>
                        </li>
                      </cfif>
                      <cfif structKeyExists(portalUser, "department") AND len(portalUser.department)>
                        <li>
                          <span class="dropdown-item-text small text-muted">#encodeForHTML(portalUser.department)#</span>
                        </li>
                      </cfif>
                      <cfif len(roleDisplay)>
                        <li>
                          <span class="dropdown-item-text small text-muted">#encodeForHTML(roleDisplay & gradYearDisplay)#</span>
                        </li>
                      </cfif>
                      <li><hr class="dropdown-divider"></li>
                      <li>
                        <a class="dropdown-item" href="profile.cfm">
                          <i class="fa-solid fa-user me-2"></i>View Profile
                        </a>
                      </li>
                      <cfif canViewSettings>
                        <li>
                          <a class="dropdown-item" href="##">
                            <i class="fa-solid fa-gear me-2"></i>Settings
                          </a>
                        </li>
                      </cfif>
                      <li><hr class="dropdown-divider"></li>
                      <li>
                        <a class="dropdown-item text-danger" href="logout.cfm">
                          <i class="fa-solid fa-right-from-bracket me-2"></i>Logout
                        </a>
                      </li>
                    </ul>
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </nav>
      </header>

      <main class="portal-main py-4 py-lg-5">
        <div class="container-xxl">
          <div class="card border-0 shadow-sm portal-card mb-4">
            <div class="card-body p-4 p-md-5">
              <h1 class="display-6 fw-semibold mb-2">Welcome to MyUHCO</h1>
              <p class="lead text-secondary mb-0">Your applications, links, and account tools are now loaded from live service-backed sources.</p>
            </div>
          </div>

          <div class="row g-4">
            <div class="col-12">
              <section class="card border-0 shadow-sm portal-card">
                <div class="card-body p-4">
                  <div class="d-flex justify-content-between align-items-center mb-3">
                    <h2 class="h4 mb-0">Directory</h2>
                  </div>
                  <div class="btn-group mb-3" role="group" aria-label="Directory groups">
                    <button type="button" class="btn btn-outline-primary btn-sm directory-group-btn" data-group="faculty">Faculty</button>
                    <button type="button" class="btn btn-outline-primary btn-sm directory-group-btn" data-group="staff">Staff</button>
                    <button type="button" class="btn btn-outline-primary btn-sm directory-group-btn" data-group="students">Students</button>
                    <button type="button" class="btn btn-outline-primary btn-sm directory-group-btn" data-group="alumni">Alumni</button>
                  </div>

                  <div id="dirGradFilterWrap" class="mb-2" style="display:none;">
                    <label class="small mb-1" for="dirGradFilter">Class of</label>
                    <select id="dirGradFilter" class="form-select form-select-sm" aria-label="Select class year">
                      <option value="">Select class year to load...</option>
                    </select>
                  </div>

                  <div id="directoryStatus" class="alert alert-secondary py-2" role="status">Click a group to load.</div>
                  <div id="directoryTableWrap" style="display:none;">
                    <div class="mb-2">
                      <input type="search" id="dirSearch" class="form-control form-control-sm" placeholder="Search by last name..." autocomplete="off">
                    </div>
                    <div class="d-flex justify-content-between align-items-center mb-2">
                      <div class="small text-muted" id="dirPageInfo"></div>
                      <div class="d-flex align-items-center gap-2">
                        <label class="small mb-0" for="dirPageSize">Per page:</label>
                        <select id="dirPageSize" class="form-select form-select-sm" style="width:auto;">
                          <option value="10">10</option>
                          <option value="25" selected>25</option>
                          <option value="50">50</option>
                          <option value="200">All</option>
                        </select>
                      </div>
                    </div>
                    <div class="table-responsive">
                      <table id="directoryTable" class="table table-sm table-hover align-middle mb-2">
                        <thead id="directoryThead"></thead>
                        <tbody id="directoryTbody"></tbody>
                      </table>
                    </div>
                    <div id="dirPagination" class="d-flex justify-content-center mt-1"></div>
                  </div>

                  <div class="modal fade" id="dirProfileModal" tabindex="-1" aria-labelledby="dirProfileModalLabel" aria-hidden="true">
                    <div class="modal-dialog modal-dialog-centered">
                      <div class="modal-content">
                        <div class="modal-header">
                          <h5 class="modal-title" id="dirProfileModalLabel">Profile</h5>
                          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                        </div>
                        <div class="modal-body" id="dirProfileModalBody"></div>
                      </div>
                    </div>
                  </div>
                </div>
              </section>
            </div>

            <div class="col-12 col-xl-6">
              <section class="card border-0 shadow-sm portal-card h-100">
                <div class="card-body p-4">
                  <div class="d-flex justify-content-between align-items-center mb-3">
                    <h2 class="h4 mb-0">Documents</h2>
                    <span class="badge bg-light text-dark">#documentResult.success ? documentsCount : 0# loaded</span>
                  </div>

                  <cfif NOT documentResult.success>
                    <div class="alert alert-danger mb-0" role="alert">
                      <strong>Error:</strong> #encodeForHTML(documentResult.message)#
                    </div>
                  <cfelseif arrayLen(quickDocs) EQ 0 AND arrayLen(facultyDocs) EQ 0 AND arrayLen(staffDocs) EQ 0 AND arrayLen(studentDocs) EQ 0>
                    <div class="alert alert-secondary mb-0" role="alert">
                      <strong>Empty:</strong> No documents are available.
                    </div>
                  <cfelse>
                    <div class="mb-4">
                      <div class="d-flex justify-content-between align-items-center mb-2">
                        <h3 class="h6 text-uppercase text-muted mb-0">Quick Docs</h3>
                        <cfif structKeyExists(documentResult, "quickDocsFolderUrl") AND len(trim(documentResult.quickDocsFolderUrl & ""))>
                          <a href="documents.cfm?section=quick-docs" class="btn btn-sm btn-outline-secondary">View All Quick Docs</a>
                        </cfif>
                      </div>
                      <cfif quickDocsPage.totalItems EQ 0>
                        <p class="small text-secondary mb-0">No quick docs are available.</p>
                      <cfelse>
                        <div class="list-group list-group-flush">
                          <cfloop array="#quickDocsPage.items#" index="docItem">
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
                        <cfif quickDocsPage.totalPages GT 1>
                          <div class="d-flex justify-content-between align-items-center mt-2">
                            <a href="#encodeForHTMLAttribute(buildPageUrl('qdPage', quickDocsPage.prevPage))#" class="btn btn-sm btn-outline-secondary #quickDocsPage.hasPrev ? '' : 'disabled'#">Previous</a>
                            <span class="small text-muted">Page #quickDocsPage.currentPage# of #quickDocsPage.totalPages#</span>
                            <a href="#encodeForHTMLAttribute(buildPageUrl('qdPage', quickDocsPage.nextPage))#" class="btn btn-sm btn-outline-secondary #quickDocsPage.hasNext ? '' : 'disabled'#">Next</a>
                          </div>
                        </cfif>
                      </cfif>
                    </div>

                    <cfif canSeeAllUserTypeDocs OR userTypeKey EQ "faculty">
                      <div class="mb-4">
                        <div class="d-flex justify-content-between align-items-center mb-2">
                          <h3 class="h6 text-uppercase text-muted mb-0">Faculty Documents</h3>
                          <a href="documents.cfm?section=faculty" class="btn btn-sm btn-outline-secondary">View All Faculty Docs</a>
                        </div>
                        <cfif facultyDocsPage.totalItems EQ 0>
                          <p class="small text-secondary mb-0">No faculty documents available.</p>
                        <cfelse>
                          <div class="list-group list-group-flush">
                            <cfloop array="#facultyDocsPage.items#" index="docItem">
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
                          <cfif facultyDocsPage.totalPages GT 1>
                            <div class="d-flex justify-content-between align-items-center mt-2">
                              <a href="#encodeForHTMLAttribute(buildPageUrl('fdPage', facultyDocsPage.prevPage))#" class="btn btn-sm btn-outline-secondary #facultyDocsPage.hasPrev ? '' : 'disabled'#">Previous</a>
                              <span class="small text-muted">Page #facultyDocsPage.currentPage# of #facultyDocsPage.totalPages#</span>
                              <a href="#encodeForHTMLAttribute(buildPageUrl('fdPage', facultyDocsPage.nextPage))#" class="btn btn-sm btn-outline-secondary #facultyDocsPage.hasNext ? '' : 'disabled'#">Next</a>
                            </div>
                          </cfif>
                        </cfif>
                      </div>
                    </cfif>

                    <cfif canSeeAllUserTypeDocs OR userTypeKey EQ "staff">
                      <div class="mb-4">
                        <div class="d-flex justify-content-between align-items-center mb-2">
                          <h3 class="h6 text-uppercase text-muted mb-0">Staff Documents</h3>
                          <a href="documents.cfm?section=staff" class="btn btn-sm btn-outline-secondary">View All Staff Docs</a>
                        </div>
                        <cfif staffDocsPage.totalItems EQ 0>
                          <p class="small text-secondary mb-0">No staff documents available.</p>
                        <cfelse>
                          <div class="list-group list-group-flush">
                            <cfloop array="#staffDocsPage.items#" index="docItem">
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
                          <cfif staffDocsPage.totalPages GT 1>
                            <div class="d-flex justify-content-between align-items-center mt-2">
                              <a href="#encodeForHTMLAttribute(buildPageUrl('sdPage', staffDocsPage.prevPage))#" class="btn btn-sm btn-outline-secondary #staffDocsPage.hasPrev ? '' : 'disabled'#">Previous</a>
                              <span class="small text-muted">Page #staffDocsPage.currentPage# of #staffDocsPage.totalPages#</span>
                              <a href="#encodeForHTMLAttribute(buildPageUrl('sdPage', staffDocsPage.nextPage))#" class="btn btn-sm btn-outline-secondary #staffDocsPage.hasNext ? '' : 'disabled'#">Next</a>
                            </div>
                          </cfif>
                        </cfif>
                      </div>
                    </cfif>

                    <cfif canSeeAllUserTypeDocs OR userTypeKey EQ "students">
                      <div>
                        <div class="d-flex justify-content-between align-items-center mb-2">
                          <h3 class="h6 text-uppercase text-muted mb-0">Student Documents</h3>
                          <a href="documents.cfm?section=students" class="btn btn-sm btn-outline-secondary">View All Student Docs</a>
                        </div>
                        <cfif studentDocsPage.totalItems EQ 0>
                          <p class="small text-secondary mb-0">No student documents available.</p>
                        <cfelse>
                          <div class="list-group list-group-flush">
                            <cfloop array="#studentDocsPage.items#" index="docItem">
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
                          <cfif studentDocsPage.totalPages GT 1>
                            <div class="d-flex justify-content-between align-items-center mt-2">
                              <a href="#encodeForHTMLAttribute(buildPageUrl('stdPage', studentDocsPage.prevPage))#" class="btn btn-sm btn-outline-secondary #studentDocsPage.hasPrev ? '' : 'disabled'#">Previous</a>
                              <span class="small text-muted">Page #studentDocsPage.currentPage# of #studentDocsPage.totalPages#</span>
                              <a href="#encodeForHTMLAttribute(buildPageUrl('stdPage', studentDocsPage.nextPage))#" class="btn btn-sm btn-outline-secondary #studentDocsPage.hasNext ? '' : 'disabled'#">Next</a>
                            </div>
                          </cfif>
                        </cfif>
                      </div>
                    </cfif>

                    <cfif NOT canSeeAllUserTypeDocs AND NOT len(userTypeKey)>
                      <div>
                        <p class="small text-secondary mb-0">No role-specific document panel is available for this account.</p>
                      </div>
                    </cfif>
                  </cfif>
                </div>
              </section>
            </div>

            <div class="col-12 col-xl-6">
              <section class="card border-0 shadow-sm portal-card h-100">
                <div class="card-body p-4">
                  <div class="d-flex justify-content-between align-items-center mb-3">
                    <h2 class="h4 mb-0">Links</h2>
                    <span class="badge bg-light text-dark">#linksResult.success ? linksCount : 0# loaded</span>
                  </div>

                  <cfif len(linksFlashMessage)>
                    <div class="alert #linksFlashStatus EQ "success" ? "alert-success" : "alert-danger"# py-2" role="alert">#encodeForHTML(linksFlashMessage)#</div>
                  </cfif>

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
                      <form method="post" action="index.cfm" class="row g-2 mb-3">
                        <input type="hidden" name="linkAction" value="create">
                        <input type="hidden" name="olPage" value="#otherLinksPage.currentPage#">
                        <div class="col-12 col-md-5">
                          <input type="text" name="linkTitle" class="form-control" maxlength="120" placeholder="Link title" required>
                        </div>
                        <div class="col-12 col-md-5">
                          <input type="url" name="linkHref" class="form-control" maxlength="1000" placeholder="https://example.com" required>
                        </div>
                        <div class="col-12 col-md-2 d-grid">
                          <button type="submit" class="btn btn-primary">Save</button>
                        </div>
                      </form>

                      <cfif otherLinksPage.totalItems EQ 0>
                        <p class="small text-secondary mb-0">No other links are configured.</p>
                      <cfelse>
                        <ul class="list-group list-group-flush">
                          <cfloop array="#otherLinksPage.items#" index="linkItem">
                            <li class="list-group-item px-0 d-flex align-items-center justify-content-between gap-2">
                              <a href="#encodeForHTMLAttribute(linkItem.href)#" class="text-decoration-none" target="_blank" rel="noopener noreferrer">#encodeForHTML(linkItem.title)#</a>
                              <div class="d-flex align-items-center gap-2">
                                <span class="badge #linkItem.source EQ "user" ? "text-bg-primary" : "text-bg-light"#">#encodeForHTML(linkItem.source)#</span>
                                <cfif linkItem.source EQ "user">
                                  <form method="post" action="index.cfm" class="m-0">
                                    <input type="hidden" name="linkAction" value="delete">
                                    <input type="hidden" name="linkId" value="#encodeForHTMLAttribute(linkItem.id)#">
                                    <input type="hidden" name="olPage" value="#otherLinksPage.currentPage#">
                                    <button type="submit" class="btn btn-sm btn-outline-danger">Delete</button>
                                  </form>
                                </cfif>
                              </div>
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
      </main>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
      document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (el) {
        new bootstrap.Tooltip(el);
      });

      (function () {
        var STUDENT_YEAR_OPTIONS = #serializeJSON(studentGradYears)#;
        var ALUMNI_YEAR_OPTIONS = #serializeJSON(alumniGradYears)#;

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
        var profileModal = new bootstrap.Modal(document.getElementById('dirProfileModal'));
        var profileTitle = document.getElementById('dirProfileModalLabel');
        var profileBody  = document.getElementById('dirProfileModalBody');

        var STUDENT_GROUPS = ['students', 'alumni'];

        var state = {
          group:    null,
          allData:  [],
          search:   '',
          gradYear: '',
          sort:     { col: 'lastname', dir: 'asc' },
          page:     1,
          pageSize: 25
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
          buildHead(cols);
          buildBody(pageData, cols);
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

          var url = 'directory-data.cfm?group=' + encodeURIComponent(group);
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
      })();
    </script>
  </body>
</html>
</cfoutput>
