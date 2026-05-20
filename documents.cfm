<cfsetting showdebugoutput="false">
<cfscript>
redirectUrl = "/index.cfm?module=documents";
if (structKeyExists(url, "section") AND len(trim(url.section & ""))) {
  redirectUrl &= "&section=" & urlEncodedFormat(trim(url.section & ""));
}
if (structKeyExists(url, "page") AND len(trim(url.page & ""))) {
  redirectUrl &= "&page=" & urlEncodedFormat(trim(url.page & ""));
}
location(redirectUrl, false);
</cfscript>
