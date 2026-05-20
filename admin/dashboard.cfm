<cfsetting showdebugoutput="false">
<!---
  admin/dashboard.cfm — Main Admin Hub
  Central landing page for all administrative sections.
  Requires portal login + portal.admin permission.
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

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MyUHCO — Admin</title>
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

<div class="container-fluid py-4 px-4">
  <h5 class="fw-bold mb-4">Admin</h5>
  <div class="row g-3">

    <div class="col-auto">
      <a href="/admin/auth/" class="text-decoration-none">
        <div class="card border-0 shadow-sm admin-nav-tile">
          <div class="card-body d-flex gap-3 align-items-start">
            <div class="rounded-3 p-2 flex-shrink-0 admin-nav-tile-icon-auth">
              <i class="fas fa-shield-alt admin-nav-tile-glyph"></i>
            </div>
            <div>
              <div class="fw-semibold text-dark small">Auth Dashboard</div>
              <div class="text-muted admin-nav-tile-copy">Active sessions, event feed, and force logout.</div>
            </div>
          </div>
        </div>
      </a>
    </div>

    <div class="col-auto">
      <a href="/admin/modules/" class="text-decoration-none">
        <div class="card border-0 shadow-sm admin-nav-tile">
          <div class="card-body d-flex gap-3 align-items-start">
            <div class="rounded-3 p-2 flex-shrink-0 admin-nav-tile-icon-modules">
              <i class="fas fa-puzzle-piece admin-nav-tile-glyph"></i>
            </div>
            <div>
              <div class="fw-semibold text-dark small">Module Registry</div>
              <div class="text-muted admin-nav-tile-copy">Enable/disable modules and reload the registry.</div>
            </div>
          </div>
        </div>
      </a>
    </div>

    <div class="col-auto">
      <a href="/admin/pages/" class="text-decoration-none">
        <div class="card border-0 shadow-sm admin-nav-tile">
          <div class="card-body d-flex gap-3 align-items-start">
            <div class="rounded-3 p-2 flex-shrink-0 admin-nav-tile-icon-pages">
              <i class="fas fa-file-alt admin-nav-tile-glyph"></i>
            </div>
            <div>
              <div class="fw-semibold text-dark small">Pages</div>
              <div class="text-muted admin-nav-tile-copy">Create and manage portal-native pages.</div>
            </div>
          </div>
        </div>
      </a>
    </div>

  </div>
</div>
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
