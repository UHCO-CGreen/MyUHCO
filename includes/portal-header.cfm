<!---
  includes/portal-header.cfm
  Shared portal navigation header. Included by index.cfm, directory.cfm, etc.

  Expects the following page-scope variables to be set before cfinclude:
    portalUser          — session.user struct (session.portalUser alias also set)
    roleDisplay         — string (may be empty)
    gradYearDisplay     — string (may be empty)
    canViewSettings     — boolean
    canViewAdminDashboard — boolean
--->
<cfoutput>
<header class="portal-header border-bottom">
  <nav class="navbar navbar-expand-lg py-2">
    <div class="container-fluid">
      <button class="btn btn-outline-secondary btn-sm me-2" type="button" id="sidebarToggle" aria-label="Toggle sidebar">
        <i class="fas fa-bars"></i>
      </button>

      <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="##portalNav" aria-controls="portalNav" aria-expanded="false" aria-label="Toggle navigation">
        <span class="navbar-toggler-icon"></span>
      </button>

      <div class="collapse navbar-collapse justify-content-end" id="portalNav">
        <ul class="navbar-nav align-items-lg-center gap-lg-2">
          <li class="nav-item d-none d-lg-block">
            <a class="nav-link p-1" href="/my-uhco/applications/accessuh" target="_blank" data-bs-toggle="tooltip" data-bs-title="Go To AccessUH" aria-label="AccessUH">
              <img src="/assets/images/46904E6A-93E9-1182-D5CC96AA4A79783F.png" class="ql-images" alt="AccessUH">
            </a>
          </li>
          <li class="nav-item d-none d-lg-block">
            <a class="nav-link p-1" href="/my-uhco/applications/microsoft-365" target="_blank" data-bs-toggle="tooltip" data-bs-title="Go To Microsoft 365" aria-label="Microsoft 365">
              <img src="/assets/images/46ABFF34-C534-BCDD-7C1AA910244CFBB6.png" class="ql-images" alt="Microsoft 365">
            </a>
          </li>
          <li class="nav-item d-none d-lg-block">
            <a class="nav-link p-1" href="/my-uhco/applications/microsoft-teams" target="_blank" data-bs-toggle="tooltip" data-bs-title="Go To Microsoft Teams" aria-label="Microsoft Teams">
              <img src="/assets/images/46B6BA2A-F944-46D8-8B7664D3348269DC.png" class="ql-images" alt="Microsoft Teams">
            </a>
          </li>
          <li class="nav-item ms-lg-2">
            <div class="dropdown">
              <button class="btn btn-link nav-link dropdown-toggle p-0 d-flex align-items-center gap-2" type="button" data-bs-toggle="dropdown" aria-expanded="false" aria-label="User menu">
                <cfif structKeyExists(portalUser, "webThumbImage") AND len(portalUser.webThumbImage)>
                  <img src="#encodeForHTML(portalUser.webThumbImage)#" alt="Profile" class="rounded-circle portal-user-avatar">
                <cfelse>
                  <i class="fas fa-user-circle portal-user-avatar-fallback"></i>
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
                  <a class="dropdown-item" href="/profile.cfm">
                    <i class="fas fa-user me-2"></i>View Profile
                  </a>
                </li>
                <cfif canViewSettings>
                  <li>
                    <a class="dropdown-item" href="##">
                      <i class="fas fa-cog me-2"></i>Settings
                    </a>
                  </li>
                </cfif>
                <cfif canViewAdminDashboard>
                  <li>
                    <a class="dropdown-item" href="/admin/dashboard.cfm">
                      <i class="fas fa-shield-alt me-2"></i>Admin
                    </a>
                  </li>
                </cfif>
                <li><hr class="dropdown-divider"></li>
                <li>
                  <a class="dropdown-item text-danger" href="/logout.cfm">
                    <i class="fas fa-sign-out-alt me-2"></i>Logout
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
</cfoutput>