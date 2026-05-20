<cfif NOT (
  structKeyExists(session, "user")
  AND structKeyExists(session.user, "userID")
  AND isNumeric(session.user.userID)
  AND session.user.userID GT 0
)>
  <cflocation url="/login.cfm" addtoken="false">
</cfif>

<cfset profileUserId = trim(session.user.userID & "")>
<cfset profileApiToken = "">
<cfset profileApiSecret = "">
<cfset profileApiBaseUrl = "http://127.0.0.1/api/v1">
<cfset profileApiUrl = "">
<cfset profileApiStatus = "">
<cfset profileApiError = "">
<cfset profileApiData = {}>

<cfif structKeyExists(application, "MYUHCO_API_TOKEN")>
  <cfset profileApiToken = trim(application.MYUHCO_API_TOKEN & "")>
</cfif>
<cfif structKeyExists(application, "MYUHCO_API_SECRET")>
  <cfset profileApiSecret = trim(application.MYUHCO_API_SECRET & "")>
</cfif>
<cfif structKeyExists(application, "MYUHCO_API_URL") AND len(trim(application.MYUHCO_API_URL & ""))>
  <cfset profileApiBaseUrl = trim(application.MYUHCO_API_URL & "")>
</cfif>
<cfset profileApiBaseUrl = reReplace(profileApiBaseUrl, "/+$", "", "all")>
<cfset profileApiUrl = profileApiBaseUrl & "/people/" & urlEncodedFormat(profileUserId)>

<cfif NOT len(profileUserId)>
  <cfset profileApiError = "No userId was found in session.user.">
<cfelseif NOT len(profileApiToken) OR NOT len(profileApiSecret)>
  <cfset profileApiError = "API token/secret are not available in application scope.">
<cfelse>
  <cftry>
    <cfhttp
      method="get"
      url="#profileApiUrl#"
      result="profileApiResponse"
      timeout="15">
      <cfhttpparam type="header" name="Authorization" value="Bearer #profileApiToken#">
      <cfhttpparam type="header" name="X-API-Secret" value="#profileApiSecret#">
    </cfhttp>

    <cfset profileApiStatus = profileApiResponse.statusCode>

    <cfif findNoCase("200", profileApiStatus)>
      <cfset profileApiData = deserializeJSON(profileApiResponse.fileContent)>
    <cfelse>
      <cfset profileApiError = "People API request failed. Status: " & profileApiStatus>
    </cfif>

    <cfcatch type="any">
      <cfset profileApiError = "People API error: " & cfcatch.message>
      <cflog file="myuhco-api" type="error" text="People API error for user #profileUserId#: #cfcatch.message# | #cfcatch.detail#">
    </cfcatch>
  </cftry>
</cfif>

<cfset portalUser = session.user>
<cfset roleDisplay = "">
<cfset gradYearDisplay = "">
<cfset canViewSettings = false>
<cfset canViewAdminDashboard = structKeyExists(application, "accessService") AND isObject(application.accessService) AND application.accessService.hasPermission("portal.admin")>

<cfoutput>
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MyUHCO Profile</title>

    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <link rel="stylesheet" href="assets/plugins/fontawesome-free/css/all.min.css">
    <link rel="stylesheet" href="/assets/css/dist/myuhco/portal.css">
    <link rel="shortcut icon" href="assets/images/46904E6A-93E9-1182-D5CC96AA4A79783F.png">
  </head>
  <body id="MyUHCO">
    <div class="portal-shell">
      <cfinclude template="/includes/portal-sidebar.cfm">
      <div class="mainContainer flex-grow-1" id="main">
        <cfinclude template="/includes/portal-header.cfm">
        <main class="portal-main py-4 py-lg-5">
        <div class="container-xxl">
          <div class="card border-0 shadow-sm portal-card">
            <div class="card-body p-4 p-md-5">
              <div class="d-flex flex-column flex-md-row align-items-start align-items-md-center gap-3 mb-4">
                <cfif structKeyExists(session.user, "webProfileImage") AND len(trim(session.user.webProfileImage & ""))>
                  <img src="#encodeForHTML(session.user.webProfileImage)#" alt="Profile" class="rounded-circle" style="width: 84px; height: 84px; object-fit: cover;">
                <cfelseif structKeyExists(session.user, "webThumbImage") AND len(trim(session.user.webThumbImage & ""))>
                  <img src="#encodeForHTML(session.user.webThumbImage)#" alt="Profile" class="rounded-circle" style="width: 84px; height: 84px; object-fit: cover;">
                <cfelse>
                  <i class="fas fa-user-circle text-secondary" style="font-size: 84px;"></i>
                </cfif>
                <div>
                  <h1 class="h3 mb-1">#encodeForHTML(session.user.displayName)#</h1>
                  <p class="text-secondary mb-0">#encodeForHTML(session.user.email)#</p>
                </div>
              </div>

              <div class="row g-3">
                <div class="col-md-6">
                  <div class="border rounded p-3 h-100">
                    <div class="small text-muted">Username</div>
                    <div>#encodeForHTML(session.user.username & "")#</div>
                  </div>
                </div>
                <div class="col-md-6">
                  <div class="border rounded p-3 h-100">
                    <div class="small text-muted">Employee ID</div>
                    <div>#encodeForHTML(session.user.employeeID & "")#</div>
                  </div>
                </div>
                <div class="col-md-6">
                  <div class="border rounded p-3 h-100">
                    <div class="small text-muted">Title</div>
                    <div>#encodeForHTML(session.user.title & "")#</div>
                  </div>
                </div>
                <div class="col-md-6">
                  <div class="border rounded p-3 h-100">
                    <div class="small text-muted">Department</div>
                    <div>#encodeForHTML(session.user.department & "")#</div>
                  </div>
                </div>
                <div class="col-md-6">
                  <div class="border rounded p-3 h-100">
                    <div class="small text-muted">Phone</div>
                    <div>#encodeForHTML(session.user.phone & "")#</div>
                  </div>
                </div>
                <div class="col-md-6">
                  <div class="border rounded p-3 h-100">
                    <div class="small text-muted">Current Grad Year</div>
                    <div>#encodeForHTML(session.user.currentGradYear & "")#</div>
                  </div>
                </div>
              </div>

              <hr class="my-4">

              <h2 class="h5 mb-3">Full Profile API Response</h2>
              <p class="small text-muted mb-3">Endpoint: /api/v1/people/#encodeForHTML(profileUserId)#</p>

              <cfif len(profileApiStatus)>
                <div class="alert alert-secondary py-2" role="status">
                  API Status: #encodeForHTML(profileApiStatus)#
                </div>
              </cfif>

              <cfif len(profileApiError)>
                <div class="alert alert-danger" role="alert">#encodeForHTML(profileApiError)#</div>
              <cfelse>
                <cfif isStruct(profileApiData)>
                  <div class="table-responsive">
                    <table class="table table-sm align-middle mb-0">
                      <thead>
                        <tr>
                          <th style="width: 220px;">Field</th>
                          <th>Value</th>
                        </tr>
                      </thead>
                      <tbody>
                        <cfloop collection="#profileApiData#" item="profileKey">
                          <cfset profileValue = profileApiData[profileKey]>
                          <tr>
                            <td class="text-muted small">#encodeForHTML(profileKey)#</td>
                            <td>
                              <cfif isSimpleValue(profileValue)>
                                #encodeForHTML(profileValue & "")#
                              <cfelseif isArray(profileValue)>
                                <cfif arrayLen(profileValue)>
                                  <div class="small text-secondary mb-2">Array (#arrayLen(profileValue)# items)</div>
                                  <ul class="mb-0 ps-3">
                                    <cfloop from="1" to="#arrayLen(profileValue)#" index="i">
                                      <li>
                                        <cfif isSimpleValue(profileValue[i])>
                                          #encodeForHTML(profileValue[i] & "")#
                                        <cfelse>
                                          <pre class="small mb-0">#encodeForHTML(serializeJSON(profileValue[i]))#</pre>
                                        </cfif>
                                      </li>
                                    </cfloop>
                                  </ul>
                                <cfelse>
                                  <span class="text-muted">(empty array)</span>
                                </cfif>
                              <cfelseif isStruct(profileValue)>
                                <div class="table-responsive">
                                  <table class="table table-borderless table-sm mb-0">
                                    <tbody>
                                      <cfloop collection="#profileValue#" item="nestedKey">
                                        <tr>
                                          <td class="text-muted small" style="width: 180px;">#encodeForHTML(nestedKey)#</td>
                                          <td>
                                            <cfif isSimpleValue(profileValue[nestedKey])>
                                              #encodeForHTML(profileValue[nestedKey] & "")#
                                            <cfelse>
                                              <pre class="small mb-0">#encodeForHTML(serializeJSON(profileValue[nestedKey]))#</pre>
                                            </cfif>
                                          </td>
                                        </tr>
                                      </cfloop>
                                    </tbody>
                                  </table>
                                </div>
                              <cfelse>
                                <pre class="small mb-0">#encodeForHTML(serializeJSON(profileValue))#</pre>
                              </cfif>
                            </td>
                          </tr>
                        </cfloop>
                      </tbody>
                    </table>
                  </div>
                <cfelseif isArray(profileApiData)>
                  <div class="small text-secondary mb-2">Array response (#arrayLen(profileApiData)# items)</div>
                  <div class="table-responsive">
                    <table class="table table-sm mb-0">
                      <thead>
                        <tr>
                          <th style="width: 120px;">Index</th>
                          <th>Value</th>
                        </tr>
                      </thead>
                      <tbody>
                        <cfloop from="1" to="#arrayLen(profileApiData)#" index="arrIndex">
                          <tr>
                            <td class="text-muted small">#arrIndex#</td>
                            <td>
                              <cfif isSimpleValue(profileApiData[arrIndex])>
                                #encodeForHTML(profileApiData[arrIndex] & "")#
                              <cfelse>
                                <pre class="small mb-0">#encodeForHTML(serializeJSON(profileApiData[arrIndex]))#</pre>
                              </cfif>
                            </td>
                          </tr>
                        </cfloop>
                      </tbody>
                    </table>
                  </div>
                <cfelse>
                  <div class="alert alert-warning" role="status">
                    API returned a response that could not be displayed as fields.
                  </div>
                  <pre class="small mb-0">#encodeForHTML(serializeJSON(profileApiData))#</pre>
                </cfif>
              </cfif>
            </div>
          </div>
        </div>
        </main>
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
  }());
  </script>
  </body>
</html>
</cfoutput>
