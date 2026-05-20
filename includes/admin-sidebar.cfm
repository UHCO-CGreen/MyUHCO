<!---
  includes/admin-sidebar.cfm
  Admin navigation sidebar.
  Detects the current admin section from cgi.script_name to highlight the active link.
--->
<cfset _adminSect = "">
<cfif findNoCase("/admin/auth", cgi.script_name)>
  <cfset _adminSect = "auth">
<cfelseif findNoCase("/admin/pages", cgi.script_name)>
  <cfset _adminSect = "pages">
<cfelseif findNoCase("/admin/modules", cgi.script_name)>
  <cfset _adminSect = "modules">
</cfif>
<aside class="main-sidebar" id="mainSidebar" aria-label="Admin sidebar">
  <div class="main-sidebar-inner">
    <div class="sidebar-brand uhco-logo">
      <img src="/assets/images/UH-Primary-College-of-Optometry-horizontal.webp" alt="College of Optometry" class="img-fluid">
    </div>
    <div class="sidebar-brand uh-logo">
      <img src="/assets/images/uh.png" alt="University of Houston" class="img-fluid">
    </div>
    <nav class="nav flex-column sidebar-nav">
      <a class="nav-link<cfif NOT len(_adminSect)> active</cfif>" href="/admin/dashboard.cfm">
        <i class="fas fa-tachometer-alt"></i>
        <span class="sidebar-link-text">Admin</span>
      </a>
      <a class="nav-link<cfif _adminSect EQ 'auth'> active</cfif>" href="/admin/auth/">
        <i class="fas fa-shield-alt"></i>
        <span class="sidebar-link-text">Auth Dashboard</span>
      </a>
      <a class="nav-link<cfif _adminSect EQ 'modules'> active</cfif>" href="/admin/modules/">
        <i class="fas fa-puzzle-piece"></i>
        <span class="sidebar-link-text">Module Registry</span>
      </a>
      <a class="nav-link<cfif _adminSect EQ 'pages'> active</cfif>" href="/admin/pages/">
        <i class="fas fa-file-alt"></i>
        <span class="sidebar-link-text">Pages</span>
      </a>
    </nav>
  </div>
</aside>
