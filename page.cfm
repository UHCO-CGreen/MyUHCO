<cfparam name="url.page" default="">
<cflocation url="/index.cfm?page=#urlEncodedFormat(trim(url.page & ''))#" addtoken="false">