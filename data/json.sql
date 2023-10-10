https://docs.oracle.com/en/database/oracle/simple-oracle-document-access/

Simple Oracle Document Access (SODA) is a set of NoSQL-style APIs that let you create and store collections of documents (in particular JSON) in Oracle Database, retrieve them, and query them, without needing to know Structured Query Language (SQL) or how the documents are stored in the database.
        
-------------------------------------------------------
-- Collections
-------------------------------------------------------

1.  Create collection Products Demo (creates table products)

2.  Review table in sqldeveloper.

2.  select * from user_soda_collections

3.  Clone document - review in SQL Developer

4.  Explore SODA Queries:
    {}
    {"PONumber":10}
    {"ShippingInstructions.Address.city": "South San Francisco"}
    {"Requestor":{"$like":"%Trenna%"}}


-------------------------------------------------------
-- SQL Queries
-------------------------------------------------------

alter table products_collection add constraint required_fields 
check (JSON_EXISTS(DATA, '$?(@.title.type() == "string" && @.price.number() > 0)'));

select JSON_Serialize(DATA) from products_collection where rownum < 10;
select JSON_Serialize(DATA returning varchar2 pretty) from products_collection where rownum < 10;


-- dot notation
select JSON_Serialize(DATA)
from products_collection p
where p.DATA.type.string() = 'movie'
and p.DATA.format.string() = 'DVD'
and p.DATA.price.number() > 5;

select p.DATA.title.string(), p.DATA.year.number()
from products_collection p
where p.DATA.type.string() = 'movie'
order by 2 DESC;

-- aggregation
select p.DATA.decade.string(),
       round(avg(p.DATA.price.number()),2)
from products_collection p
where p.DATA.type.string() = 'movie'
group by p.DATA.decade.string();

-- view created in JSON Console
create or replace view product_collection_view as
SELECT
        D.ID,
        D.TYPE,
        D.TITLE,
        D.FORMAT1,
        D.CONDITION,
        D.PRICE,
        D.COMMENT_1,
        D.YEAR,
        D.DECADE,
        D.FORMAT2
    FROM
        PRODUCTS_COLLECTION CT,
        JSON_TABLE ( CT.DATA, '$'
                COLUMNS (
                    ID NUMBER PATH '$."_id"',
                    TYPE VARCHAR2 ( 100 CHAR ) PATH '$."type"',
                    TITLE VARCHAR2 ( 100 CHAR ) PATH '$."title"',
                    FORMAT1 VARCHAR2 ( 100 CHAR ) PATH '$."format"',
                    CONDITION VARCHAR2 ( 100 CHAR ) PATH '$."condition"',
                    PRICE NUMBER PATH '$."price"',
                    COMMENT_1 VARCHAR2 ( 100 CHAR ) PATH '$."comment"',
                    YEAR NUMBER PATH '$."year"',
                    DECADE VARCHAR2 ( 100 CHAR ) PATH '$."decade"',
                    FORMAT2 VARCHAR2 ( 100 CHAR ) PATH '$." format "'
                )
            )
        D;

-------------------------------------------------------
-- Loading DATA
-------------------------------------------------------

-- add credential in json user - can't seem to grant api_token created by admin
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'api_token',
    username => '<OCI username>',
    password => '<credential password>'
  );
END;
/

select * from user_credentials

-- this creates and loads the table
BEGIN 
  DBMS_CLOUD.COPY_COLLECTION(    
    collection_name => 'purchase_order_collection',    
    credential_name => 'API_TOKEN',    
    file_uri_list => 'https://objectstorage.us-ashburn-1.oraclecloud.com/n/natdcshjumpstartprod/b/json/o/POList.json',
    format => '{"recorddelimiter" : "0x''01''", "unpackarrays" : "TRUE", "maxdocsize" : "10240000"}'
  );
END;
/

-- index everything (12.2+), prior to 12.2 a messier text index was used ctxsys
create search index purchase_order_idx on
  purchase_order_collection ( DATA )
  for json;

-- create function based index for the requestor tag
create index purchase_order_requestor_idx on
  purchase_order_collection ( 
    json_value ( 
      DATA, '$.Requestor'    
        error on error
        null on empty
    ) 
  );

select p.DATA.PONumber.string(), p.DATA.Reference.string()
from purchase_order_collection p
where p.DATA.PONumber.string() between '10' and '20'

-- Search for DATA anywhere in the document:
select p.DATA.PONumber.string()
    , p.DATA.Reference.string() 
    , p.DATA.LineItems[0].Part.Description.string()
from   purchase_order_collection p
where  json_textcontains ( DATA, '$', 'Princess' );

-- just be exact match..this does not work
select p.DATA.PONumber.string()
    , p.DATA.Reference.string() 
    , p.DATA.LineItems[0].Part.Description.string()
from   purchase_order_collection p
where  json_textcontains ( DATA, '$', 'Princes' );

-- run explain plan on this - see index above
select p.DATA.PONumber.string(), p.DATA.Reference.string()
from purchase_order_collection p
where p.DATA.Requestor.string() = 'Martha Sullivan'

-------------------------------------------------------
-- DATA Insert
-------------------------------------------------------

insert into purchase_order_collection 
values (
    '1', 
    sysdate,
    sysdate,
    '1',
  utl_raw.cast_to_raw ( '{
  "PONumber": 999,
  "Reference": "Ref123",
  "Requestor": "Derrick Cameron",
  "CostCenter": "A999"
}' )
);
commit;

select p.id, JSON_Serialize(DATA returning varchar2 pretty) jsondata from purchase_order_collection p;

-------------------------------------------------------
-- DATA Update
-------------------------------------------------------

-- one way to update docs..but limited..use json_transform below.

update purchase_order_collection p
set    DATA = json_mergepatch ( 
         DATA, '{"CostCenter" : "A49"}'
         )
where  p.DATA."PONumber".string() = 1;
commit;

-- json_transform
update purchase_order_collection p
set DATA = json_transform(DATA,
               SET '$.ShippingInstructions.Address' =
                   '{"street":"My Street",
                     "city":"Ridgefield",
                     "state":"WA"}'
                   FORMAT JSON
                   IGNORE ON MISSING)
where  p.DATA."PONumber".string() = 1;
commit;

select p.id, JSON_Serialize(DATA returning varchar2 pretty) jsondata from purchase_order_collection p;

Use JSON Transform or JSON Merge Patch To Update a JSON Document

-------------------------------------------------------
-- DATA Guide
-------------------------------------------------------

create table purchase_order_dataguide (dg_val CLOB, check (dg_val is JSON));

-- load json structure into dataguide table
insert into purchase_order_dataguide (dg_val)
select JSON_DATAguide(DATA, dbms_json.FORMAT_HIERARCHICAL)
from purchase_order_collection;
commit;

-- create query view using metadata in dataguide
declare
    dg clob;
BEGIN
    select dg_val into dg from purchase_order_dataguide;
    dbms_json.create_view('purchase_order_view', 'purchase_order_collection', 'DATA', dg, resolveNameConflicts => true);
END;
/

-- Generated PO View

  CREATE OR REPLACE FORCE EDITIONABLE VIEW "JSON"."PURCHASE_ORDER_VIEW" ("CREATED_ON", "ID", "LAST_MODIFIED", "VERSION", "User", "PONumber", "Reference", "Requestor", "CostCenter", "name", "city", "state", "county", "street", "country", "zipCode", "postcode", "Special Instructions", "UPCCode", "UnitPrice", "Description", "Quantity", "ItemNumber", "type", "number") DEFAULT COLLATION "USING_NLS_COMP"  AS 
  SELECT RT."CREATED_ON",RT."ID",RT."LAST_MODIFIED",RT."VERSION",JT."User",JT."PONumber",JT."Reference",JT."Requestor",JT."CostCenter",JT."name",JT."city",JT."state",JT."county",JT."street",JT."country",JT."zipCode",JT."postcode",JT."Special Instructions",JT."UPCCode",JT."UnitPrice",JT."Description",JT."Quantity",JT."ItemNumber",JT."type",JT."number"
FROM "JSON"."PURCHASE_ORDER_COLLECTION" RT,
JSON_TABLE("DATA", '$[*]' COLUMNS 
"User" varchar2(8) path '$.User',
"PONumber" number path '$.PONumber',
 NESTED PATH '$.LineItems[*]' COLUMNS (
"UPCCode" number path '$.Part.UPCCode',
"UnitPrice" number path '$.Part.UnitPrice',
"Description" varchar2(128) path '$.Part.Description',
"Quantity" number path '$.Quantity',
"ItemNumber" number path '$.ItemNumber'),
"Reference" varchar2(32) path '$.Reference',
"Requestor" varchar2(32) path '$.Requestor',
"CostCenter" varchar2(4) path '$.CostCenter',
"name" varchar2(32) path '$.ShippingInstructions.name',
 NESTED PATH '$.ShippingInstructions.Phone[*]' COLUMNS (
"type" varchar2(8) path '$.type',
"number" varchar2(16) path '$.number'),
"city" varchar2(32) path '$.ShippingInstructions.Address.city',
"state" varchar2(2) path '$.ShippingInstructions.Address.state',
"county" varchar2(8) path '$.ShippingInstructions.Address.county',
"street" varchar2(64) path '$.ShippingInstructions.Address.street',
"country" varchar2(32) path '$.ShippingInstructions.Address.country',
"zipCode" number path '$.ShippingInstructions.Address.zipCode',
"postcode" varchar2(8) path '$.ShippingInstructions.Address.postcode',
"Special Instructions" varchar2(32) path '$."Special Instructions"')JT;

-- update column headers:
create or replace view purchase_order_view2 as
SELECT 
    --RT."CREATED_ON"
    --,RT."ID"
    --,RT."LAST_MODIFIED"
    --,RT."VERSION"
    JT."PONumber" ponumber
    ,JT."Reference" reference
    ,JT."Requestor" requestor
    ,JT."User" Userid
    ,JT."CostCenter" costcenter
    ,JT."name" name
    ,JT."street" street
    ,JT."city" city
    ,JT."state" state
    ,JT."county" county
    ,JT."country" country
    ,JT."zipCode" zipcode
    ,JT."postcode" postalcode
    ,JT."Special Instructions" special_instructions
    ,JT."ItemNumber" itemnumber
    ,JT."Description" part_description
    ,JT."UnitPrice" part_unitprice
    ,JT."UPCCode" part_upccode
    ,JT."Quantity" item_quantity
    ,JT."type" phone_type
    ,JT."number" phone_number
FROM "PURCHASE_ORDER_COLLECTION" RT,
JSON_TABLE("DATA", '$[*]' COLUMNS 
"User" varchar2(8) path '$.User',
"PONumber" number path '$.PONumber',
 NESTED PATH '$.LineItems[*]' COLUMNS (
"UPCCode" number path '$.Part.UPCCode',
"UnitPrice" number path '$.Part.UnitPrice',
"Description" varchar2(128) path '$.Part.Description',
"Quantity" number path '$.Quantity',
"ItemNumber" number path '$.ItemNumber'),
"Reference" varchar2(32) path '$.Reference',
"Requestor" varchar2(32) path '$.Requestor',
"CostCenter" varchar2(4) path '$.CostCenter',
"name" varchar2(32) path '$.ShippingInstructions.name',
 NESTED PATH '$.ShippingInstructions.Phone[*]' COLUMNS (
"type" varchar2(8) path '$.type',
"number" varchar2(16) path '$.number'),
"city" varchar2(32) path '$.ShippingInstructions.Address.city',
"state" varchar2(2) path '$.ShippingInstructions.Address.state',
"county" varchar2(8) path '$.ShippingInstructions.Address.county',
"street" varchar2(64) path '$.ShippingInstructions.Address.street',
"country" varchar2(32) path '$.ShippingInstructions.Address.country',
"zipCode" number path '$.ShippingInstructions.Address.zipCode',
"postcode" varchar2(8) path '$.ShippingInstructions.Address.postcode',
"Special Instructions" varchar2(32) path '$."Special Instructions"')JT;

select * from purchase_order_view2

-- query view, returns 6 rows
ponumber = 1

-- create view on path at root level
-- "DATA$PONumber"=1
declare
    dg clob;
BEGIN
    select dg_val into dg from purchase_order_dataguide;
    dbms_json.create_view_on_path('purchase_order_view3', 'purchase_order_collection', 'DATA', '$');
END;
/

declare
    dg clob;
BEGIN
    select dg_val into dg from purchase_order_dataguide;
    dbms_json.create_view_on_path('purchase_order_view4', 'purchase_order_collection', 'DATA', '$.Reference');
END;
/

-- path now Reference - returns 5 rows
declare
    dg clob;
BEGIN
    select dg_val into dg from purchase_order_DATAguide;
    dbms_json.create_view_on_path('purchase_order_view5', 'purchase_order_collection', 'DATA', '$.LineItems');
END;
/

-- query view, returns 5 row
"DATA$PONumber"=1

-- get view sql without creating view:
create table purchase_order_get_sql(viewtext clob);

insert into purchase_order_get_sql(viewtext) 
select dbms_json.get_view_sql(
  'PURCHASE_ORDER_VIEW3'
  , 'PURCHASE_ORDER_COLLECTION'
  , 'DATA'
  , dbms_json.get_index_DATAguide('PURCHASE_ORDER_COLLECTION', 'DATA', dbms_json.format_hierarchical, DBMS_JSON.PRETTY)
  ) 
from dual;
commit;

-- get DATAguide
insert into purchase_order_get_sql(viewtext) 
SELECT DBMS_JSON.GET_INDEX_DATAGUIDE(
  'PURCHASE_ORDER_COLLECTION'
  , 'DATA'
  , DBMS_JSON.FORMAT_HIERARCHICAL
  , DBMS_JSON.PRETTY)
FROM DUAL;
commit;

-------------------------------------------------------
-- External Table
-------------------------------------------------------

-- do NOT use column named 'DATA' -- bug???
BEGIN
  DBMS_CLOUD.CREATE_EXTERNAL_TABLE (
   table_name =>'purchase_order_ext',
   credential_name =>'API_TOKEN',
   file_uri_list =>'https://objectstorage.us-ashburn-1.oraclecloud.com/n/natdcshjumpstartprod/b/json/o/POList.json',
   column_list => 'json_document blob',
   field_list => 'json_document char(5000)'
);
END;
/
  
SELECT JSON_VALUE(json_document,'$.PONumber') as ponumber,
    JSON_VALUE(json_document,'$.Reference') as reference,
    JSON_VALUE(json_document,'$.Requestor') as requestor,
    JSON_VALUE(json_document,'$.User') as userid,
    JSON_VALUE(json_document,'$.CostCenter') as costcenter,
    JSON_VALUE(json_document,'$.ShippingInstructions.name') as shipping_name,
    JSON_VALUE(json_document,'$.ShippingInstructions.Address.street') as shipping_address_street,
    JSON_VALUE(json_document,'$.ShippingInstructions.Address.city') as shipping_address_city,
    JSON_VALUE(json_document,'$.ShippingInstructions.Address.zipCode') as shipping_address_zip,
    JSON_VALUE(json_document,'$.ShippingInstructions.Phone.type') as shipping_phone_type,
    JSON_VALUE(json_document,'$.ShippingInstructions.Phone.number') as shipping_phone_number,
    JSON_VALUE(json_document,'$."Special Instructions"') as specialinstructions,
    json_query(json_document,'$.LineItems.ItemNumber' WITH WRAPPER) as itemnumber,
    json_query(json_document,'$.LineItems.Part.UnitPrice' WITH WRAPPER) as unitprices,
    json_query(json_document,'$.LineItems[0].Part.Description' WITH WRAPPER) lineitem1_part_description,
    json_query(json_document,'$.LineItems.Part.Description' WITH WRAPPER) part_descriptions
FROM purchase_order_ext

BEGIN
  DBMS_CLOUD.VALIDATE_EXTERNAL_TABLE (
    table_name => 'PURCHASE_ORDER_EXT' );
END;
/

-------------------------------------------------------
-- Format relational to JSON
-------------------------------------------------------

select JSON_Object(*) from products;

-- write out relational table to json file in object storage..simple but likely not what you want.
BEGIN
  DBMS_CLOUD.EXPORT_DATA(
    credential_name => 'API_TOKEN',
    file_uri_list   => 'https://objectstorage.us-ashburn-1.oraclecloud.com/n/natdcshjumpstartprod/b/json/o/purchase_order_view.json',
    query           => 'SELECT * FROM purchase_order_view',
    format          => JSON_OBJECT('type' value 'json')    
    );
END;
/

select json_object ( * ) jdoc from purchase_order_view

-- build json for initial root level value pairs - returns five rows for each PO
select 
json_object (
  'PONumber' value p.ponumber,
  'Requestor' value p.requestor,
  'ShippingInstructions' value json_object (
        'name' value p.name,
        'Address' value json_object (
            'Street' value p.street,
            'City' value p.city,
            'State' value p.state,
            'ZipCode' value p.zipcode,
            'country' value p.country),
        'Phone' value json_array (
            json_object(
                'type' value p.phone_type,
                'number' value p.phone_number)
                )
            )
        )
from purchase_order_view2 p

-- build json off view that is distinct - returns one row for every PO.
select json_object (
  'PONumber' value p.ponumber,
  'Requestor' value p.requestor,
  'ShippingInstructions' value json_object (
        'name' value p.name,
        'Address' value json_object (
            'Street' value p.street,
            'City' value p.city,
            'State' value p.state,
            'ZipCode' value p.zipcode,
            'country' value p.country),
        'Phone' value json_array (
            json_object (
            'type' value p.phone_type,
            'number' value p.phone_number))
        ),
    'Special Instructions' value p.special_instructions) string1
from (select distinct 
    ponumber
    , reference
    , requestor
    , userid
    , costcenter
    , name
    , street
    , city
    , state
    , county
    , country
    , zipcode
    , special_instructions
    , phone_type
    , phone_number
from    purchase_order_view2) p
where p.phone_number is not null;

-- list arrays for each PO (one line per PO)
select json_object (
    'LineItems' value json_arrayagg (
    json_object(
        'ItemNumber' value p.itemnumber,
        'Part' value json_object (
            'Description' value p.part_description,
            'UnitPrice' value p.part_unitprice,
            'UPCCode' value p.part_upccode),
        'Quantity' value p.item_quantity)
                )
            )
from purchase_order_view2 p
group by p.ponumber

-- create view with two strings - 1 for root level and another for arrays.
Create or replace view purchase_order_reltojson1 as
select p1.ponumber, p1.string1, p2.string2 from
----------------------------
(select p.ponumber,
   json_object (
  'PONumber' value p.ponumber,
  'Requestor' value p.requestor,
  'ShippingInstructions' value json_object (
        'name' value p.name,
        'Address' value json_object (
            'Street' value p.street,
            'City' value p.city,
            'State' value p.state,
            'ZipCode' value p.zipcode,
            'country' value p.country),
        'Phone' value json_array (
            json_object (
            'type' value p.phone_type,
            'number' value p.phone_number))
        ),
    'Special Instructions' value p.special_instructions) string1
from (select distinct 
    ponumber
    , reference
    , requestor
    , userid
    , costcenter
    , name
    , street
    , city
    , state
    , county
    , country
    , zipcode
    , special_instructions
    , phone_type
    , phone_number
from    purchase_order_view2) p
where p.phone_number is not null) p1,
----------------------------
(select p.ponumber
    , json_object (
    'LineItems' value json_arrayagg (
    json_object(
        'ItemNumber' value p.itemnumber,
        'Part' value json_object (
            'Description' value p.part_description,
            'UnitPrice' value p.part_unitprice,
            'UPCCode' value p.part_upccode),
        'Quantity' value p.item_quantity)
                )
            ) string2
from purchase_order_view2 p
group by p.ponumber) p2
----------------------------
where p1.ponumber = p2.ponumber

create or replace view purchase_order_reltojson2 as
select substr(string1,1,to_number(length(string1)-1))||','||ltrim(string2,'{') myjson
from purchase_order_reltojson1



