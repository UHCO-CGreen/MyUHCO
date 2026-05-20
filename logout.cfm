<cfset application.portalAuthService.logout()>

<!--- Expire MYUHCO_TOKEN cookie so external modules detect the logout --->
<cfset _cookieDomainOk = structKeyExists(application, "cookieDomain") AND len(application.cookieDomain) AND right(cgi.server_name, len(application.cookieDomain)-1) EQ right(application.cookieDomain, len(application.cookieDomain)-1)>
<cfif _cookieDomainOk>
  <cfcookie name="MYUHCO_TOKEN" value="" expires="now" path="/" domain="#application.cookieDomain#">
<cfelse>
  <cfcookie name="MYUHCO_TOKEN" value="" expires="now">
</cfif>

<cflocation url="login.cfm" addtoken="false">
