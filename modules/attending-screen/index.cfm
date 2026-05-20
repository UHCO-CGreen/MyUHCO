<cfscript>
attendees = [];
fetchError = "";

try {
    cfhttp(
        url = "https://portal.opt.uh.edu/api/v1/quickpulls/attending?token=uhcs_265898cb-912c-08c4-08040b05623bc8c34c84b9e4",
        method = "get",
        result = "quickpullResponse",
        timeout = 30
    );

    if (structKeyExists(quickpullResponse, "statusCode") && left(quickpullResponse.statusCode, 3) == "200") {
        quickpullPayload = deserializeJSON(quickpullResponse.fileContent);

        if (isStruct(quickpullPayload) && structKeyExists(quickpullPayload, "DATA") && isArray(quickpullPayload.DATA)) {
            attendees = quickpullPayload.DATA;
        } else {
            fetchError = "Unexpected attendee response.";
        }
    } else {
        fetchError = "Unable to load attendees.";
    }
} catch (any error) {
    fetchError = "Unable to load attendees.";
}
</cfscript>
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <title>Attendees List</title>
    <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
    <style>
        .list-group-item {
            margin-bottom: 10px;
			font-size:19.5px;
			border:0px;
			font-weight:500;
        }
        .attendee-degrees {
            font-size: 0.8em;
        }
		.attendee-error {
			color: #842029;
			font-size: 1rem;
			font-weight: 600;
		}
		#de{
			display:none;
		}
    </style>
</head>
<body>
<cfoutput>
    <div class='container mt-4'>
        <div class='row gx-1' id='attendee-columns'>
            <cfif len(fetchError)>
                <div class='col-12'>
                    <p class='attendee-error'>#encodeForHtml(fetchError)#</p>
                </div>
            <cfelse>
                <cfloop index='columnIndex' from='1' to='3'>
                    <div class='col-md-4'>
                        <ul class='list-group'>
                            <cfloop index='attendeeIndex' from='#columnIndex#' to='#arrayLen(attendees)#' step='3'>
                                <cfset attendee = attendees[attendeeIndex]>
                                <cfset fullName = ''>
                                <cfset degrees = ''>

                                <cfif structKeyExists(attendee, 'NAMES') and isArray(attendee.NAMES) and arrayLen(attendee.NAMES)>
                                    <cfset fullName = attendee.NAMES[1].FULL>
                                </cfif>
                                <cfif structKeyExists(attendee, 'DEGREES')>
                                    <cfset degrees = attendee.DEGREES>
                                </cfif>

                                <li class='list-group-item'>
                                    <span>#encodeForHtml(fullName)#</span><cfif len(degrees)>, <span class='attendee-degrees'>#encodeForHtml(degrees)#</span></cfif>
                                </li>
                            </cfloop>
                        </ul>
                    </div>
                </cfloop>
            </cfif>
        </div>
    </div>
</cfoutput>
</body>
</html>
