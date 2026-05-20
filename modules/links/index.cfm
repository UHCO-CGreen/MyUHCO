<cfsetting showdebugoutput="false">
<cfscript>
if (!structKeyExists(session, "user")) {
  location("/login.cfm", false);
}

portalUser = session.user;
currentUserId = "";
if (structKeyExists(portalUser, "userId") AND len(trim(portalUser.userId & ""))) {
  currentUserId = trim(portalUser.userId & "");
} else if (structKeyExists(portalUser, "username") AND len(trim(portalUser.username & ""))) {
  currentUserId = trim(portalUser.username & "");
}
if (!len(currentUserId)) {
  currentUserId = "anonymous";
}

linksResult = {
  success = false,
  message = "Links have not loaded.",
  links = []
};
collegeFormsLinks = [];
otherLinks = [];
linksPageSize = 10;

try {
  linksResult = application.linkService.getMergedLinks(userId = currentUserId);
} catch (any e) {
  linksResult = {
    success = false,
    message = "Link service unavailable.",
    links = []
  };
  cflog(file = "myuhco-api", type = "error", text = "Links module load failed: #e.message# | #e.detail#");
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

function linksModuleGetNumericUrlPage(required string paramName) {
  var pageValue = 1;
  if (structKeyExists(url, arguments.paramName)) {
    pageValue = val(url[arguments.paramName]);
  }
  if (pageValue LT 1) {
    pageValue = 1;
  }
  return pageValue;
}

function linksModulePaginateItems(required array items, required string pageParam, numeric pageSize = 10) {
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

  currentPage = linksModuleGetNumericUrlPage(arguments.pageParam);
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

function linksModuleBuildPageUrl(required string pageParam, required numeric pageValue) {
  var params = duplicate(url);
  var keyName = "";
  var queryParts = [];
  var resultUrl = "index.cfm";

  params.module = "links";
  params[arguments.pageParam] = arguments.pageValue;

  if (structKeyExists(params, "fieldnames")) {
    structDelete(params, "fieldnames");
  }

  for (keyName in params) {
    arrayAppend(queryParts, urlEncodedFormat(keyName) & "=" & urlEncodedFormat(params[keyName] & ""));
  }

  if (arrayLen(queryParts)) {
    resultUrl &= "?" & arrayToList(queryParts, "&");
  }

  return resultUrl;
}

collegeFormsPage = linksModulePaginateItems(collegeFormsLinks, "cfPage", linksPageSize);
otherLinksPage = linksModulePaginateItems(otherLinks, "page", linksPageSize);
</cfscript>
<cfoutput>
<div class="container-fluid">
  <div class="row g-4">
    <div class="col-12">
      <section class="card border-0 shadow-sm portal-card">
        <div class="card-body p-4">
          <nav aria-label="breadcrumb" class="mb-2">
            <ol class="breadcrumb mb-0">
              <li class="breadcrumb-item"><a href="index.cfm">Portal</a></li>
              <li class="breadcrumb-item active" aria-current="page">Links</li>
            </ol>
          </nav>

          <div class="d-flex justify-content-between align-items-center mb-3 border-bottom pb-2">
            <div>
              <h1 class="h3 mb-0">Links</h1>
              <div class="small text-muted">College Forms and common links</div>
            </div>
            <a href="index.cfm" class="btn btn-outline-secondary btn-sm">Back to Portal</a>
          </div>
        </div>
      </section>
    </div>

    <div class="col-12 col-xl-5">
      <section class="card border-0 shadow-sm portal-card h-100">
        <div class="card-body p-4">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <h2 class="h4 mb-0">College Forms</h2>
            <span class="badge bg-light text-dark">#collegeFormsPage.totalItems# item(s)</span>
          </div>

          <cfif NOT linksResult.success>
            <div class="alert alert-danger mb-0" role="alert">
              <strong>Error:</strong> #encodeForHTML(linksResult.message)#
            </div>
          <cfelseif collegeFormsPage.totalItems EQ 0>
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
              <div class="d-flex justify-content-between align-items-center mt-3">
                <a href="#encodeForHTMLAttribute(linksModuleBuildPageUrl('cfPage', collegeFormsPage.prevPage))#" class="btn btn-sm btn-outline-secondary #collegeFormsPage.hasPrev ? '' : 'disabled'#">Previous</a>
                <span class="small text-muted">Page #collegeFormsPage.currentPage# of #collegeFormsPage.totalPages#</span>
                <a href="#encodeForHTMLAttribute(linksModuleBuildPageUrl('cfPage', collegeFormsPage.nextPage))#" class="btn btn-sm btn-outline-secondary #collegeFormsPage.hasNext ? '' : 'disabled'#">Next</a>
              </div>
            </cfif>
          </cfif>
        </div>
      </section>
    </div>

    <div class="col-12 col-xl-7">
      <section class="card border-0 shadow-sm portal-card h-100">
        <div class="card-body p-4">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <h2 class="h4 mb-0">Other Links</h2>
            <span class="badge bg-light text-dark">#otherLinksPage.totalItems# item(s)</span>
          </div>

          <cfif NOT linksResult.success>
            <div class="alert alert-danger mb-0" role="alert">
              <strong>Error:</strong> #encodeForHTML(linksResult.message)#
            </div>
          <cfelse>
            <cfif otherLinksPage.totalItems EQ 0>
              <p class="small text-secondary mb-0">No other links are configured.</p>
            <cfelse>
              <ul class="list-group list-group-flush">
                <cfloop array="#otherLinksPage.items#" index="linkItem">
                  <li class="list-group-item px-0 d-flex align-items-center justify-content-between gap-2">
                    <a href="#encodeForHTMLAttribute(linkItem.href)#" class="text-decoration-none" target="_blank" rel="noopener noreferrer">#encodeForHTML(linkItem.title)#</a>
                    <span class="badge #linkItem.source EQ 'user' ? 'text-bg-primary' : 'text-bg-light'#">#encodeForHTML(linkItem.source)#</span>
                  </li>
                </cfloop>
              </ul>
              <cfif otherLinksPage.totalPages GT 1>
                <div class="d-flex justify-content-between align-items-center mt-3">
                  <a href="#encodeForHTMLAttribute(linksModuleBuildPageUrl('page', otherLinksPage.prevPage))#" class="btn btn-sm btn-outline-secondary #otherLinksPage.hasPrev ? '' : 'disabled'#">Previous</a>
                  <span class="small text-muted">Page #otherLinksPage.currentPage# of #otherLinksPage.totalPages#</span>
                  <a href="#encodeForHTMLAttribute(linksModuleBuildPageUrl('page', otherLinksPage.nextPage))#" class="btn btn-sm btn-outline-secondary #otherLinksPage.hasNext ? '' : 'disabled'#">Next</a>
                </div>
              </cfif>
            </cfif>
          </cfif>
        </div>
      </section>
    </div>
  </div>
</div>
</cfoutput>