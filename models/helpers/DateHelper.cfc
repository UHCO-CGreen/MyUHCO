<cfcomponent displayname="DateHelper" output="false">

  <!---
      Returns Memorial Day (last Monday of May) for the provided year.
  --->
  <cffunction name="getMemorialDayDate" access="public" returntype="date" output="false">
    <cfargument name="year" type="numeric" required="true">

    <cfset var may31 = createDate(arguments.year, 5, 31)>
    <cfset var dow = dayOfWeek(may31)>
    <cfset var daysBack = (dow - 2 + 7) MOD 7>

    <cfreturn dateAdd("d", -daysBack, may31)>
  </cffunction>

  <!---
      Before May 1: startYear = currentYear
      On/After May 1: startYear = currentYear + 1
      Returns a 4-year current-student window.
  --->
  <cffunction name="getGradYearWindow" access="public" returntype="struct" output="false">
    <cfset var currentYear = year(now())>
    <cfset var cutoffDate = createDate(currentYear, 5, 1)>
    <cfset var startYear = (now() LT cutoffDate) ? currentYear : (currentYear + 1)>

    <cfreturn {
      cutoffDate = cutoffDate,
      startYear = startYear,
      endYear = startYear + 3,
      graduatingYear = startYear
    }>
  </cffunction>

</cfcomponent>