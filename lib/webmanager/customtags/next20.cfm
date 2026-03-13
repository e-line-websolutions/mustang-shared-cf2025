<cfsetting enablecfoutputonly="Yes">

<cfscript>
  /* cfparam equivalents */
  if( not isDefined( "attributes.sQueryName" ))                 { attributes.sQueryName                 = "qry_sel_data" ; }

  /* Input variables */
  if( not isDefined( "attributes.sIndexQuery" ))                { attributes.sIndexQuery                = request.site.s_NOT_SET; }
  if( not isDefined( "attributes.sIDColumn" ))                  { attributes.sIDColumn                  = request.site.s_NOT_SET; }
  if( not isDefined( "attributes.sSelectQuery" ))               { attributes.sSelectQuery               = request.site.s_NOT_SET; }
  if( not isDefined( "attributes.nResultsPerPage" ))            { attributes.nResultsPerPage            = 20; }
  if( not isDefined( "attributes.nCurrentPage" ))               { attributes.nCurrentPage               =  1; }

  if( not isNumeric( attributes.nCurrentPage ) or attributes.nCurrentPage lte 0 )
  {
    attributes.nCurrentPage = 1;
  }

  if( not isNumeric( attributes.nResultsPerPage ) or attributes.nResultsPerPage lte 0 )
  {
    attributes.nResultsPerPage = 20;
  }
  else
  {
    attributes.nResultsPerPage = int( attributes.nResultsPerPage );
  }

  /* Return variables */
  if( not isDefined( "attributes.sReturnTotalRecordCount" ))    { attributes.sReturnTotalRecordCount    = "nTotalRecordCount"; }
  if( not isDefined( "attributes.sReturnCurrentRecordCount" ))  { attributes.sReturnCurrentRecordCount  = "nCurrentRecordCount"; }
  if( not isDefined( "attributes.sReturnTotalPageCount" ))      { attributes.sReturnTotalPageCount      = "nTotalPageCount"; }
  if( not isDefined( "attributes.sReturnExecutionTime" ))       { attributes.sReturnExecutionTime       = "nExecutionTime"; }
  nTotalRecordCount = 0;
  nTotalPageCount = 0;
  nOffsetRows = 0;
</cfscript>

<!--- [rvl] //
            // Sanity check. If we are missing some vital arguments, we'll just
            // throw an error and see what happens (evil developer!)
            //
--->
<cfif ( attributes.sIndexQuery  eq request.site.s_NOT_SET ) or
      ( attributes.sSelectQuery eq request.site.s_NOT_SET ) or
      ( attributes.sIDColumn    eq request.site.s_NOT_SET )
>
  <cfthrow message="no index and/or select query specified" />
</cfif>

<!---
  Stateless pagination for SQL Server:
  1) count rows using sIndexQuery
  2) fetch page using ORDER BY + OFFSET/FETCH
--->
<cfquery datasource="#request.db.s_DSN#" name="qry_next20_count" blockfactor="100">
  SELECT COUNT_BIG( 1 ) AS totalRecordCount
  #preserveSingleQuotes( attributes.sIndexQuery )#
</cfquery>

<cfscript>
  if( qry_next20_count.recordCount and isNumeric( qry_next20_count.totalRecordCount[ 1 ] ) )
  {
    nTotalRecordCount = val( qry_next20_count.totalRecordCount[ 1 ] );
  }

  if( nTotalRecordCount gt 0 )
  {
    nTotalPageCount = ceiling( nTotalRecordCount / attributes.nResultsPerPage );
  }

  if( nTotalPageCount lte 0 )
  {
    attributes.nCurrentPage = 1;
    nOffsetRows = 0;
  }
  else
  {
    if( attributes.nCurrentPage gt nTotalPageCount )
    {
      attributes.nCurrentPage = nTotalPageCount;
    }
    nOffsetRows = ( attributes.nCurrentPage - 1 ) * attributes.nResultsPerPage;
  }
</cfscript>

<!--- [rvl] Do the actual select query (MS SQL Server OFFSET/FETCH) --->
<cfquery datasource="#request.db.s_DSN#" name="_tmp_query" blockfactor="#attributes.nResultsPerPage#">
  #preserveSingleQuotes( attributes.sSelectQuery )#

  <cfif structKeyExists( attributes, "xOrderByClause" ) and
        isArray( attributes.xOrderByClause ) and
        arrayLen( attributes.xOrderByClause )>
    ORDER BY
    <cfloop from="1" to="#arrayLen( attributes.xOrderByClause )#" index="i">
      #attributes.xOrderByClause[i][1]# #iif( attributes.xOrderByClause[i][2], de( "ASC" ), de( "DESC" ))#
      <cfif i neq arrayLen( attributes.xOrderByClause )>,</cfif>
    </cfloop>
  <cfelse>
    ORDER BY #attributes.sIDColumn# ASC
  </cfif>

  OFFSET <cfqueryparam value="#nOffsetRows#" cfsqltype="cf_sql_integer"> ROWS
  FETCH NEXT <cfqueryparam value="#attributes.nResultsPerPage#" cfsqltype="cf_sql_integer"> ROWS ONLY
</cfquery>

<cfscript>
  /*
   * We will now return some 'extra' information about the set of results that
   * we have found here. This can be used by a navigation system to accompany
   * the retrieved data with some information about the query.
   */
  "caller.#attributes.sQueryName#"                 = _tmp_query;
  "caller.#attributes.sReturnTotalRecordCount#"    = nTotalRecordCount;
  "caller.#attributes.sReturnCurrentRecordCount#"  = _tmp_query.recordCount;
  "caller.#attributes.sReturnTotalPageCount#"      = nTotalPageCount;
  "caller.#attributes.sReturnExecutionTime#"       = cfquery.executionTime;
</cfscript>

<cfsetting enablecfoutputonly="No">
