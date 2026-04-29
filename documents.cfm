<cfsetting showdebugoutput="false">
<cfscript>
if (!structKeyExists(session, "portalUser")) {
  location("/login.cfm", false);
}

requestedSection = lCase(trim((structKeyExists(url, "section") ? url.section : "quick-docs") & ""));
if (!listFindNoCase("quick-docs,faculty,staff,students", requestedSection)) {
  requestedSection = "quick-docs";
}

sectionTitleMap = {
  "quick-docs" = "Quick Docs",
  "faculty" = "Faculty Documents",
  "staff" = "Staff Documents",
  "students" = "Student Documents"
};
sectionTitle = sectionTitleMap[requestedSection];

page = val((structKeyExists(url, "page") ? url.page : 1));
if (page LT 1) page = 1;
pageSize = 25;

result = {
  success = false,
  message = "",
  docs = [],
  totalItems = 0,
  totalPages = 1,
  currentPage = 1,
  hasPrev = false,
  hasNext = false,
  prevPage = 1,
  nextPage = 1
};

try {
  docResult = application.documentService.getDocuments();
  if (docResult.success) {
    for (d in docResult.items) {
      docSection = lCase(trim((structKeyExists(d, "section") ? d.section : "") & ""));
      if ((requestedSection EQ "quick-docs" AND (docSection EQ "quick-docs" OR docSection EQ "quick docs")) OR docSection EQ requestedSection) {
        arrayAppend(result.docs, d);
      }
    }

    result.totalItems = arrayLen(result.docs);
    result.totalPages = max(1, ceiling(result.totalItems / pageSize));
    if (page GT result.totalPages) page = result.totalPages;

    startIndex = ((page - 1) * pageSize) + 1;
    endIndex = min(result.totalItems, page * pageSize);
    paged = [];
    if (result.totalItems GT 0) {
      for (i = startIndex; i LTE endIndex; i = i + 1) {
        arrayAppend(paged, result.docs[i]);
      }
    }

    result.success = true;
    result.currentPage = page;
    result.hasPrev = page GT 1;
    result.hasNext = page LT result.totalPages;
    result.prevPage = result.hasPrev ? page - 1 : 1;
    result.nextPage = result.hasNext ? page + 1 : result.totalPages;
    result.docs = paged;
  } else {
    result.message = len(docResult.message) ? docResult.message : "Unable to load documents.";
  }
} catch (any e) {
  result.message = "Unable to load documents.";
  cflog(file = "myuhco-api", type = "error", text = "documents.cfm error: #e.message# | #e.detail#");
}

function buildPageUrl(required numeric pageNum) {
  return "documents.cfm?section=" & urlEncodedFormat(requestedSection) & "&page=" & urlEncodedFormat(pageNum);
}
</cfscript>
<cfoutput>
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>#encodeForHTML(sectionTitle)# | myUHCO</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
    <link rel="stylesheet" href="css/portal-style.css">
  </head>
  <body>
    <main class="container py-4">
      <nav aria-label="breadcrumb" class="mb-2">
        <ol class="breadcrumb mb-0">
          <li class="breadcrumb-item"><a href="index.cfm">Portal</a></li>
          <li class="breadcrumb-item"><a href="documents.cfm?section=quick-docs">Documents</a></li>
          <li class="breadcrumb-item active" aria-current="page">#encodeForHTML(sectionTitle)#</li>
        </ol>
      </nav>

      <div class="d-flex justify-content-between align-items-center mb-3 border-bottom pb-2">
        <div>
          <h1 class="h3 mb-0">#encodeForHTML(sectionTitle)#</h1>
          <div class="small text-muted">myUHCO Document Center</div>
        </div>
        <a href="index.cfm" class="btn btn-outline-secondary btn-sm">Back to Portal</a>
      </div>

      <cfif NOT result.success>
        <div class="alert alert-danger" role="alert">
          <strong>Error:</strong> #encodeForHTML(result.message)#
        </div>
      <cfelseif result.totalItems EQ 0>
        <div class="alert alert-secondary" role="alert">
          No documents found for #encodeForHTML(sectionTitle)#.
        </div>
      <cfelse>
        <div class="small text-muted mb-2">#result.totalItems# document(s)</div>
        <div class="list-group list-group-flush">
          <cfloop array="#result.docs#" index="docItem">
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

        <cfif result.totalPages GT 1>
          <div class="d-flex justify-content-between align-items-center mt-3">
            <a href="#encodeForHTMLAttribute(buildPageUrl(result.prevPage))#" class="btn btn-sm btn-outline-secondary #result.hasPrev ? '' : 'disabled'#">Previous</a>
            <span class="small text-muted">Page #result.currentPage# of #result.totalPages#</span>
            <a href="#encodeForHTMLAttribute(buildPageUrl(result.nextPage))#" class="btn btn-sm btn-outline-secondary #result.hasNext ? '' : 'disabled'#">Next</a>
          </div>
        </cfif>
      </cfif>
    </main>
  </body>
</html>
</cfoutput>
