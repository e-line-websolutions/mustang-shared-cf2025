<cfscript>
  param input.groupId = "";
  param input.documentId = "";
  param input.documentName = "";
  param input.formData = {};
  param input.lSubGroups = "";
  param input.lDontUpload = "";
  param input.bValuesAsText = true;

  docdb.xFieldsToUpdate = {};

  for ( var key in input.formData ) {
    if ( compareNoCase( left( key, 9 ), "DOCDBFLD_" ) == 0 ) {
      docdb.xFieldsToUpdate[ mid( key, 10, len( key ) - 9 ) ] = input.formData[ key ];
    }
  }
</cfscript>

<cfif val( input.documentId ) gt 0>
  <cfquery dataSource="#ds#" name="docdb.qry_sel_groepinfo">
    SELECT    product_x_nGroepID
    FROM      tbl_product
    WHERE     product_nID = <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.documentId#" />
  </cfquery>
  <cfif docdb.qry_sel_groepinfo.recordCount>
    <cfset input.groupId = docdb.qry_sel_groepinfo.product_x_nGroepID />
  </cfif>
</cfif>

<cfif not isNumeric( input.groupId ) or input.groupId lte 0>
  <cfthrow message="Error: missing attribute: <strong>groupId</strong>">
</cfif>

<cfif len( trim( input.documentName ) ) eq 0 and val( input.documentId ) lte 0>
  <cfthrow message="Error: missing attribute: <strong>documentName</strong>">
</cfif>

<cflock name="docdb_update" timeout="30" throwOnTimeout="true" type="exclusive">
  <cftransaction action="BEGIN" isolation="SERIALIZABLE">
    <cftry>
      <cfif not isNumeric( input.documentId ) or input.documentId lte 0>
        <cfquery dataSource="#ds#" name="docdb.qry_insert_document">
          DECLARE @nProductID INT
          SET @nProductID = ( SELECT ISNULL( MAX( product_nID ), 0 ) + 1 FROM tbl_product )

          INSERT INTO tbl_product (
            product_nID,
            product_sNaam,
            product_x_nGroepID,
            product_nBwsID,
            Product_nClickCount
          ) VALUES (
            @nProductID,
            <cfqueryparam cfsqltype="CF_SQL_VARCHAR" value="#input.documentName#">,
            <cfqueryparam cfsqltype="CF_SQL_INTEGER" value="#input.groupId#">,
            <cfqueryparam cfsqltype="CF_SQL_INTEGER" value="#variables.websiteId#">,
            0
          )

          SELECT @nProductID AS nProductID
        </cfquery>
        <cfset input.documentId = docdb.qry_insert_document.nProductID />
      <cfelseif isNumeric( input.documentId ) and input.documentId gt 0 and len( trim( input.documentName ) )>
        <cfquery dataSource="#ds#">
          UPDATE  tbl_product
          SET     product_sNaam = <cfqueryparam cfsqltype="CF_SQL_VARCHAR" value="#input.documentName#">
          WHERE   product_nID = <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.documentId#" />
        </cfquery>
      </cfif>

      <cfif len( trim( input.lSubGroups ) )>
        <cfquery dataSource="#ds#">
          DELETE
          FROM    mid_groepProduct
          WHERE   groepProduct_x_nProductID = <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.documentId#" />
            AND   groepProduct_x_nGroepID IN ( <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.lSubGroups#" list="true" /> )

          <cfloop list="#input.lSubGroups#" index="nSubGroupID">
            INSERT INTO mid_groepProduct (
              groepProduct_x_nGroepID,
              groepProduct_x_nProductID
            ) VALUES (
              <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#nSubGroupID#" />,
              <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.documentId#" />
            )
          </cfloop>
        </cfquery>
      </cfif>

      <cfloop collection="#docdb.xFieldsToUpdate#" item="docdb.formField">
        <cfquery datasource="#ds#" name="docdb.qry_select_fieldID">
          SELECT    eigenschap_nID,
                    eigenschap_x_nTypeID
          FROM      dbo.tbl_eigenschap
          WHERE     eigenschap_nBwsID = <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#variables.websiteId#">
            AND     (
                      LOWER( eigenschap_sNaam ) = <cfqueryparam CFSQLType="CF_SQL_VARCHAR" value="#lCase( docdb.formField )#" /> OR
                      dbo.variableFormat( eigenschap_sNaam ) = <cfqueryparam CFSQLType="CF_SQL_VARCHAR" value="#docdb.formField#" />
                    )
        </cfquery>

        <cfscript>
          docdb.nFieldID    = docdb.qry_select_fieldID.Eigenschap_nID;
          docdb.sFieldValue = docdb.xFieldsToUpdate[ docdb.formField ];
        </cfscript>

        <!--- INVOKE FILE UPLOAD MECHANISM FOR FILE FIELDS --->
        <cfif docdb.qry_select_fieldID.eigenschap_x_nTypeID eq 6 and not listFindNoCase( input.lDontUpload, docdb.formField )>
          <cfif len( trim( docdb.sFieldValue ) )>
            <cffile action="upload"
              destination   = "#variables.config.mediaRoot#/sites/site#variables.websiteId#/images/"
              fileField     = "form.docdbfld_#docdb.formField#"
              nameConflict  = "makeUnique"
            />
            <cfset docdb.sFieldValue = cffile.serverFile />
          <cfelse>
            <cfset docdb.nFieldID = 0 />
          </cfif>
        </cfif>

        <!--- FIND VALUE ID FOR TEXT OPTIONS --->
        <cfif input.bValuesAsText and
              listFind( "1,2,3,7,15", docdb.qry_select_fieldID.eigenschap_x_nTypeID ) and
              listLen( docdb.sFieldValue ) eq 1>
          <cfquery dataSource="#ds#" name="docdb.qry_sel_value">
            SELECT value_nID
            FROM   lst_value
            WHERE  value_sNaam = <cfqueryparam CFSQLType="CF_SQL_VARCHAR" value="#docdb.sFieldValue#" />
          </cfquery>
          <cfif docdb.qry_sel_value.recordCount eq 1>
            <cfset docdb.sFieldValue = docdb.qry_sel_value.value_nID />
          </cfif>
        </cfif>

        <cfif docdb.nFieldID gt 0>
          <cfscript>
            docdb.sFieldName  = "savedData_sNaam";
            docdb.sFieldType  = "CF_SQL_VARCHAR";
            docdb.nFieldLen   = 250;

            switch ( docdb.qry_select_fieldID.eigenschap_x_nTypeID ) {
              case 1:
              case 2:
              case 3:
              case 7:
              case 15:
                docdb.sFieldName  = "savedData_x_nValueID";
                docdb.sFieldType  = "CF_SQL_INTEGER";
                docdb.nFieldLen   = 128;
                break;
              case 5:
                docdb.sFieldName  = "savedData_sText";
                docdb.sFieldType  = "CF_SQL_LONGVARCHAR";
                docdb.nFieldLen   = 1073741823;
                break;
              case 14:
                docdb.sFieldName  = "savedData_dDateTime";
                docdb.sFieldType  = "CF_SQL_TIMESTAMP";
                docdb.nFieldLen   = 128;
                break;
              case 12:
                docdb.sFieldName  = "savedData_x_nLinkedProductID";
                docdb.sFieldType  = "CF_SQL_INTEGER";
                docdb.nFieldLen   = 128;
                break;
            }
          </cfscript>

          <!---
            Special case: when you provide a value like this: +1 or -15 this
            next piece calculates the value that will be saved:
          --->
          <cfif listFind( "+,-", left( docdb.sFieldValue, 1 ) ) and listLen( docdb.sFieldValue ) eq 1>
            <cfquery datasource="#ds#" name="docdb.qry_check_existingData">
              SELECT    #docdb.sFieldName#
              FROM      dbo.tbl_savedData
              WHERE     savedData_x_nProductID    = <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.documentId#" />
                AND     savedData_x_nEigenschapID = <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#docdb.nFieldID#" />
            </cfquery>

            <cftry>
              <cfscript>
                docdb.sFieldValue = evaluate( val( docdb.qry_check_existingData.SavedData_sNaam ) & docdb.sFieldValue );
              </cfscript>
              <cfcatch></cfcatch>
            </cftry>
          </cfif>

          <!--- REMOVE OLD DATA AND INSERT THE NEW: --->
          <cfquery dataSource="#ds#">
            DECLARE @nMaxID INT

            DELETE
            FROM    tbl_SavedData
            WHERE   savedData_x_nEigenschapID = <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#docdb.nFieldID#" />
              AND   savedData_x_nProductID    = <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.documentId#" />

            <cfif docdb.sFieldName contains "_x_">
              <!--- INSERT MULTIPLE VALUES FOR FOREIGN KEY ITEMS --->
              <cfloop list="#docdb.sFieldValue#" index="docdb.listItem">
                <cfscript>
                  docdb.save_value = val( docdb.listItem );
                  docdb.null = docdb.save_value eq 0;
                </cfscript>

                SET @nMaxID = ( SELECT ISNULL( MAX( savedData_nID ), 0 ) + 1 AS nMaxID FROM tbl_SavedData )

                INSERT INTO tbl_SavedData (
                  savedData_nID,
                  #docdb.sFieldName#,
                  savedData_x_nProductID,
                  savedData_x_nEigenschapID
                ) VALUES (
                  @nMaxID,
                  <cfqueryparam CFSQLType="#docdb.sFieldType#" value="#docdb.save_value#" maxLength="#docdb.nFieldLen#" null="#docdb.null#" />,
                  <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.documentId#" />,
                  <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#docdb.nFieldID#" />
                )
              </cfloop>
            <cfelse>
              <cfscript>
                docdb.save_value = docdb.sFieldValue;
                docdb.null = false;

                if ( listFindNoCase( "CF_SQL_LONGVARCHAR,CF_SQL_VARCHAR", docdb.sFieldType ) ) {
                  docdb.save_value = left( preserveSingleQuotes( docdb.save_value ), docdb.nFieldLen );
                  if ( not len( trim( docdb.save_value ) ) ) {
                    docdb.null = true;
                  }
                }

                if ( listFindNoCase( "CF_SQL_INTEGER", docdb.sFieldType ) ) {
                  docdb.save_value = val( docdb.save_value );
                  if ( docdb.save_value eq 0 ) {
                    docdb.null = true;
                  }
                }
              </cfscript>

              SET @nMaxID = ( SELECT ISNULL( MAX( savedData_nID ), 0 ) + 1 AS nMaxID FROM tbl_SavedData )

              INSERT INTO tbl_SavedData (
                savedData_nID,
                #docdb.sFieldName#,
                savedData_x_nProductID,
                savedData_x_nEigenschapID
              ) VALUES (
                @nMaxID,
                <cfqueryparam CFSQLType="#docdb.sFieldType#" value="#docdb.save_value#" maxLength="#docdb.nFieldLen#" null="#docdb.null#" />,
                <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#input.documentId#" />,
                <cfqueryparam CFSQLType="CF_SQL_INTEGER" value="#docdb.nFieldID#" />
              )
            </cfif>
          </cfquery>
        </cfif>
      </cfloop>

      <cftransaction action="commit" />
      <cfcatch>
        <cftransaction action="rollback" />
        <cfdump var="#cfcatch#">
        <cfabort>
      </cfcatch>
    </cftry>
  </cftransaction>
</cflock>
