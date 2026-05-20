<cfsetting showdebugoutput="false">
<!---
  admin/auth/index.cfm — Auth Observability Dashboard
  Requires portal login + portal.admin permission.
  Shows active sessions + real-time auth event feed.
  WebSocket channel "securityEvents" delivers best-effort pushes from SecurityService.auditLog().
  WebSocket is display-only; it does NOT control auth or session state.
--->
<cfif NOT structKeyExists(session, "user")>
  <cflocation url="/login.cfm" addtoken="false">
</cfif>

<cfparam name="url.partial" default="">

<!--- Require portal.admin permission --->
<cfset application.accessService.requirePermission("portal.admin")>

<!--- Query active sessions --->
<cfquery name="qActive" datasource="#application.myuhcoDatasource#">
  SELECT
      s.UserID,
      s.SessionID,
      s.LoginTime,
      s.IPAddress,
      ISNULL(s.LastVisitedPath, '') AS LastVisitedPath,
      COALESCE(sc.LastActivity, s.LoginTime) AS LastActivity
  FROM       dbo.UserSessions       s
  LEFT JOIN  dbo.UserSessionControl sc ON sc.UserID = s.UserID
  WHERE s.IsActive = 1
  ORDER BY LastActivity DESC
</cfquery>

<cfsavecontent variable="activeSessionsMarkup">
  <cfif qActive.recordCount EQ 0>
    <div class="auth-dashboard-no-data">No active sessions.</div>
  <cfelse>
    <table id="activeTbl">
      <thead>
        <tr>
          <th>UserID</th>
          <th>Login Time</th>
          <th>Last Activity</th>
          <th>Last Page</th>
          <th>IP</th>
          <th>Action</th>
        </tr>
      </thead>
      <tbody>
        <cfoutput query="qActive">
          <tr data-userid="#encodeForHTMLAttribute(qActive.UserID)#">
            <td><span class="auth-dashboard-active-dot"></span>#encodeForHTML(qActive.UserID)#</td>
            <td>#dateTimeFormat(qActive.LoginTime, "mm/dd HH:nn")#</td>
            <td>#dateTimeFormat(qActive.LastActivity, "mm/dd HH:nn")#</td>
            <td class="auth-dashboard-detail-cell">#encodeForHTML(qActive.LastVisitedPath)#</td>
            <td>#encodeForHTML(qActive.IPAddress)#</td>
            <td>
              <button class="admin-action-danger"
                onclick="forceLogout(#val(qActive.UserID)#, this)">
                Force Logout
              </button>
            </td>
          </tr>
        </cfoutput>
      </tbody>
    </table>
  </cfif>
</cfsavecontent>

<!--- Query 50 most recent audit events --->
<cfquery name="qEvents" datasource="#application.myuhcoDatasource#">
  SELECT TOP 50
      LogID,
      ISNULL(CAST(UserID AS VARCHAR(20)), '') AS UserID,
      EventType,
      EventTime,
      ISNULL(IPAddress, '') AS IPAddress,
      ISNULL(Details,   '') AS Details
  FROM  dbo.AuthAuditLog
  ORDER BY EventTime DESC
</cfquery>

<cfsavecontent variable="eventFeedRowsMarkup">
  <cfoutput query="qEvents">
    <tr>
      <td class="auth-dashboard-time-cell">#dateTimeFormat(qEvents.EventTime,"HH:nn:ss")#</td>
      <td><span class="badge b-#lCase(encodeForHTMLAttribute(qEvents.EventType))#">#encodeForHTML(qEvents.EventType)#</span></td>
      <td>#encodeForHTML(qEvents.UserID)#</td>
      <td>#encodeForHTML(qEvents.IPAddress)#</td>
      <td class="auth-dashboard-detail-cell">#encodeForHTML(left(qEvents.Details,60))#</td>
    </tr>
  </cfoutput>
</cfsavecontent>

<cfif url.partial EQ "dashboardData">
  <cfheader name="Content-Type" value="application/json; charset=utf-8">
  <cfoutput>#serializeJSON({
    success = true,
    activeHtml = activeSessionsMarkup,
    activeCount = qActive.recordCount,
    eventRowsHtml = eventFeedRowsMarkup
  })#</cfoutput>
  <cfabort>
</cfif>

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MyUHCO — Auth Dashboard</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
  <link rel="stylesheet" href="/assets/plugins/fontawesome-free/css/all.min.css">
  <link rel="stylesheet" href="/assets/css/dist/myuhco/admin.css">
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

<div class="auth-dashboard">
<div class="border-bottom bg-white px-4 py-3 d-flex align-items-center justify-content-between">
  <h6 class="mb-0 fw-bold">Auth Observability Dashboard</h6>
  <div class="d-flex align-items-center gap-2">
    <span id="wsStatusBadge" class="ws-status">WS: connecting...</span>
    <a href="/admin/dashboard.cfm" class="btn btn-sm btn-outline-secondary">&larr; Admin</a>
  </div>
</div>

<div class="auth-dashboard-grid">

  <!--- ── Section 1: Active Sessions ──────────────────────────────────── --->
  <div class="auth-dashboard-panel">
    <div class="auth-dashboard-panel-title">
      Active Sessions
      <span id="activeCount" class="auth-dashboard-meta"></span>
    </div>
    <div class="auth-dashboard-panel-body" id="activeSessionsPanelBody"><cfoutput>#activeSessionsMarkup#</cfoutput></div>
  </div>

  <!--- ── Section 2: Event Feed ────────────────────────────────────────── --->
  <div class="auth-dashboard-panel">
    <div class="auth-dashboard-panel-title">
      Real-Time Event Feed
      <span class="auth-dashboard-meta">(most recent first)</span>
    </div>
    <div class="auth-dashboard-panel-body">
      <table id="eventTbl">
        <thead>
          <tr>
            <th>Time</th>
            <th>Event</th>
            <th>UserID</th>
            <th>IP</th>
            <th>Details</th>
            <td class="session-actions">
        </thead>
        <tbody id="eventBody">
          <cfoutput>#eventFeedRowsMarkup#</cfoutput>
        </tbody>
              <button class="admin-action-warn"
                onclick="forceLogoutReinit(#val(qActive.UserID)#, this)">
                Logout + Reinit
              </button>
      </table>
    </div>
  </div>

  <!--- ── Section 3: Admin Force Logout ───────────────────────────────── --->
  <div class="auth-dashboard-panel auth-dashboard-panel--wide">
    <div class="auth-dashboard-panel-title">Admin Actions</div>
    <div id="forceLogoutForm" class="auth-dashboard-force-form">
      <label class="auth-dashboard-label">Force logout UserID:</label>
      <input type="number" id="flUserID" placeholder="e.g. 12345" min="1">
      <button class="admin-action-danger" onclick="forceLogoutById()">Force Logout</button>
      <button class="admin-action-warn" onclick="forceLogoutReinitById()">Logout + Reinit</button>
      <span id="forceLogoutMsg" class="auth-dashboard-feedback"></span>
    </div>
  </div>

</div><!--- end dash-body --->
</div>
</div>
</div>

<!--- CF WebSocket tag — connects to the securityEvents channel. --->
<cfwebsocket name="secDashWS"
             onMessage="handleSecEvent"
             onOpen="wsOnOpen"
             onClose="wsOnClose"
             onError="wsOnError"
             subscribeTo="securityEvents">

<script>
// ── WebSocket status indicator ────────────────────────────────────────────────
var wsStatusBadge = document.getElementById('wsStatusBadge');

function wsOnOpen(evt) {
  wsStatusBadge.textContent = 'WS: connected';
  wsStatusBadge.className   = 'ws-status connected';
}
function wsOnClose(evt) {
  wsStatusBadge.textContent = 'WS: disconnected';
  wsStatusBadge.className   = 'ws-status';
}
function wsOnError(evt) {
  wsStatusBadge.textContent = 'WS: error';
  wsStatusBadge.className   = 'ws-status error';
}

// ── Incoming event handler ────────────────────────────────────────────────────
function handleSecEvent(msg) {
  var data;
  try {
    var raw = (msg && msg.data) ? msg.data : msg;
    data = (typeof raw === 'string') ? JSON.parse(raw) : raw;
  } catch(e) { return; }

  if (!data || !data.type) return;
  refreshDashboardData();
}

var dashboardRefreshInFlight = false;

function refreshDashboardData() {
  var panelBody = document.getElementById('activeSessionsPanelBody');
  var cntEl = document.getElementById('activeCount');
  var eventBody = document.getElementById('eventBody');
  if (!panelBody || !eventBody || dashboardRefreshInFlight) return;

  dashboardRefreshInFlight = true;

  fetch('/admin/auth/index.cfm?partial=dashboardData', {
    headers: { 'X-Requested-With': 'XMLHttpRequest' }
  })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (!data) return;

      var wasSuccessful = data.success;
      if (typeof wasSuccessful === 'undefined') {
        wasSuccessful = data.SUCCESS;
      }
      if (!wasSuccessful) return;

      panelBody.innerHTML = data.activeHtml || data.ACTIVEHTML || '';
      eventBody.innerHTML = data.eventRowsHtml || data.EVENTROWSHTML || '';
      if (cntEl) {
        cntEl.textContent = String(data.activeCount || data.ACTIVECOUNT || 0) + ' active';
      }
    })
    .catch(function() {
      // Keep the current snapshot if the refresh fails.
    })
    .finally(function() {
      dashboardRefreshInFlight = false;
    });
}

// ── Force logout helpers ──────────────────────────────────────────────────────
function forceLogout(userID, btn) {
  if (!confirm('Force logout UserID ' + userID + '?')) return;
  sendAdminSessionAction('/admin/force-logout.cfm', userID, btn);
}

function forceLogoutReinit(userID, btn) {
  if (!confirm('Force logout and reinit UserID ' + userID + '?')) return;
  sendAdminSessionAction('/admin/force-logout-reinit.cfm', userID, btn);
}

function forceLogoutById() {
  var uid = parseInt(document.getElementById('flUserID').value, 10);
  if (!uid || uid <= 0) {
    document.getElementById('forceLogoutMsg').textContent = 'Enter a valid UserID.';
    return;
  }
  sendAdminSessionAction('/admin/force-logout.cfm', uid, null);
}

function forceLogoutReinitById() {
  var uid = parseInt(document.getElementById('flUserID').value, 10);
  if (!uid || uid <= 0) {
    document.getElementById('forceLogoutMsg').textContent = 'Enter a valid UserID.';
    return;
  }
  sendAdminSessionAction('/admin/force-logout-reinit.cfm', uid, null);
}

function sendAdminSessionAction(endpoint, userID, btn) {
  var msg = document.getElementById('forceLogoutMsg');
  if (msg) msg.textContent = 'Sending...';
  if (btn) btn.disabled = true;

  var fd = new FormData();
  fd.append('targetUserID', userID);

  fetch(endpoint, { method: 'POST', body: fd })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      var wasSuccessful = data && (typeof data.success !== 'undefined' ? data.success : data.SUCCESS);
      var errorMessage = data ? (data.error || data.ERROR || 'unknown') : 'unknown';
      if (msg) msg.textContent = wasSuccessful ? 'Done.' : ('Error: ' + errorMessage);
      if (wasSuccessful) refreshDashboardData();
      if (btn) btn.disabled = false;
    })
    .catch(function() {
      if (msg) msg.textContent = 'Request failed.';
      if (btn) btn.disabled = false;
    });
}

// ── HTML escape helper ────────────────────────────────────────────────────────
function escHtml(s) {
  return String(s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Initial active count ──────────────────────────────────────────────────────
(function() {
  refreshDashboardData();
  window.setInterval(refreshDashboardData, 10000);
})();
</script>

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
