# Cloud Coaching:  Oracle Autonomous Database Features for Supporting Application Development Across Cloud Services

Derrick Cameron, Steve Nichols
July, 2023

## **Related Recordings**

- [DBMS_CLOUD Package](https://www.youtube.com/watch?v=RvIPCXiz_vE)
- [ORDS Install and Config](https://www.youtube.com/watch?v=RvIPCXiz_vE)
- [Autonomous Database for Legacy Database Developers](https://www.youtube.com/watch?v=EbrG4-K-TzY)

## **Export Data to Object Storage in csv Format and Query Data in Object Storage** 

```
<copy>
-- list objects in object storage bucket
SELECT * FROM DBMS_CLOUD.LIST_OBJECTS('API_TOKEN', '<object storage bucket URL>');

-- export table data to object storage bucket
BEGIN
  DBMS_CLOUD.EXPORT_DATA(
    credential_name => 'API_TOKEN',
    file_uri_list   => '<object storage bucket URL>/o/sales.csv',
    query           => 'SELECT 777 project_id, sysdate shapshot_date, s.* FROM sales s',
    format          => JSON_OBJECT('type' value 'csv', 'delimiter' value ',','maxfilesize' value 999999999,'header' value true)    
    );
END;
/

-- sample delete object code
begin
dbms_cloud.delete_object(
    credential_name => 'API_TOKEN',
    object_uri => '<object storage bucket URL>/o/sales_1_20230706T221507652863Z.csv');
end;
/

-- create external_table on top of sales files
begin
dbms_cloud.create_external_table (
table_name => 'sales_ext',
credential_name => 'api_token',
file_uri_list => '<object storage bucket url>/o/sales_1_*.csv',
format => json_object('delimiter' value ',','type' value 'csv', 'skipheaders' value '1','logretention' value 2),
column_list => 'project_id number,
    snapshot_date date,
    prod_id number,
    cust_id number,
    time_id date,
    channel_id number,
    promo_id number,
    quantity_sold number,
    amount_sold number(20,2),
    employee_id number');
end;
/
</copy>
```

## **Process Parquet Files in Object Storage**

[**Blog on this topic**](https://blogs.oracle.com/datawarehousing/post/oracle-autonomous-data-warehouse-access-parquet-files-in-object-stores)

The point of this exercise is to show:
- Parquet files are easier to work with since the table structure is embedded in the file.
- Parquet files are in compressed binary format and are smaller and more efficient to query than csv.
- Querying individual columns in parquet files reduces IO compared with csv files, which scan the entire file even when only a single column is retrieved.


```
<copy>
- Install parq using snap - A tool for exploring parquet files

- view file definition using parq (metadata and data are part of parquet files)
parq schema sales_extended.parquet

-- output
Column Name     Data Type  
Prod_id         int32      
Cust_id         int32      
Time_id         string     
Channel_id      int32      
Promo_id        int32      
Quantity_sold   int32      
Amount_sold     string     
Gender          string     
City            string     
State_province  string     
Income_level    string     

-- view first few rows of parquet file
parq head sales_extended.parquet 

-- output
   Prod_id  Cust_id  Time_id     Channel_id  Promo_id  Quantity_sold  Amount_sold  Gender  City              State_province         Income_level          
0  13       987      1998-01-10  3           999       1              �P        M       Adelaide          South Australia        K: 250,000 - 299,999  
1  13       1660     1998-01-10  3           999       1              �P        M       Dolores           CO                     L: 300,000 and above  
2  13       1762     1998-01-10  3           999       1              �P        M       Cayuga            ND                     F: 110,000 - 129,999  
3  13       1843     1998-01-10  3           999       1              �P        F       Bergen op Zoom    Noord-Brabant          C: 50,000 - 69,999    
4  13       1948     1998-01-10  3           999       1              �P        F       Neuss             Nordrhein-Westfalen    J: 190,000 - 249,999  
5  13       2273     1998-01-10  3           999       1              �P        F       Darwin            Northern Territory     F: 110,000 - 129,999  
6  13       2380     1998-01-10  3           999       1              �P        M       Sabadell          Barcelona              K: 250,000 - 299,999  
7  13       2683     1998-01-10  3           999       1              �P        F       Orangeville       IL                     C: 50,000 - 69,999    
8  13       2865     1998-01-10  3           999       1              �P        M       Gennevilliers     Ile-de-France          D: 70,000 - 89,999    
9  13       4663     1998-01-10  3           999       1              �P        F       Henley-on-Thames  England - Oxfordshire  A: Below 30,000

-- create external table from parquet file.  Note that no specification of the column formats are required.
begin
    dbms_cloud.create_external_table (
       table_name =>'sales_extended_parquet_ext',
       credential_name =>'API_TOKEN',
       file_uri_list =>'<object storage bucket URL>/o/sales_extended.parquet',
       format =>  '{"type":"parquet",  "schema": "first"}'
    );
end;
/

-- create table in database
CREATE TABLE SALES_EXTENDED
   (  PROD_ID NUMBER, 
  CUST_ID NUMBER, 
  TIME_ID VARCHAR2(30), 
  CHANNEL_ID NUMBER, 
  PROMO_ID NUMBER, 
  QUANTITY_SOLD NUMBER(10,0), 
  AMOUNT_SOLD NUMBER(10,2), 
  GENDER VARCHAR2(1), 
  CITY VARCHAR2(30), 
  STATE_PROVINCE VARCHAR2(40), 
  INCOME_LEVEL VARCHAR2(30)
   );
   
-- copy data from parquet file to Oracle table
begin
 dbms_cloud.copy_data(
    table_name => 'SALES_EXTENDED',
    credential_name =>'API_TOKEN',
    file_uri_list =>'<object storage bucket URL/o/sales_extended.parquet',
    format =>  '{"type":"parquet",  "schema": "first"}'
 );
 end;
 /

 -- create copy of sales data in object storage to show how much larger csv (63mb) versus parquet (8mb)
BEGIN
  DBMS_CLOUD.EXPORT_DATA(
    credential_name => 'API_TOKEN',
    file_uri_list   => '<object storage bucket URL>/o/sales_extended.csv',
    query           => 'SELECT * FROM sales_extended s',
    format          => JSON_OBJECT('type' value 'csv', 'delimiter' value ',','maxfilesize' value 999999999,'header' value true)    
    );
END;
/

-- create external table on csv file in object storage to compare with parquet file (size, performance/IO)
begin
dbms_cloud.create_external_table (
table_name => 'sales_extended_csv_ext',
credential_name => 'api_token',
file_uri_list => '<object storage bucket URL>/o/sales_extended.csv',
format => json_object('delimiter' value ',','type' value 'csv', 'skipheaders' value '1','logretention' value 2,'rejectlimit' value 9999999,'ignoremissingcolumns' value 'true'),
column_list => 'prod_id number,
    cust_id number,
    time_id varchar2(30),
    channel_id number,
    promo_id number,
    quantity_sold number(10,0),
    amount_sold number(10,2),
    gender varchar2(100),
    city varchar2(100),
    state_province varchar2(100),
    income_level varchar2(100)');
end;
/

- Open performance hub in the ADB console, then select ASH Analytics, then view the latest sql query to view I/I prior to running this query.  Refesh this after each of the following sql statements.

select count(*) from sales_extended_csv_ext;
create table sales_test_pq1 as select /* MONITOR NO_RESULT_CACHE */ prod_id from sales_extended_csv_ext; -- 78mb
create table sales_test_pq2 as select /* MONITOR NO_RESULT_CACHE */ * from sales_extended_csv_ext; -- 84.5mb
create table sales_test_pq3 as select /* MONITOR NO_RESULT_CACHE */ prod_id from sales_extended_parquet_ext; -- 4.9mb
</copy>
```

## **Cloud Links**

This registers table SALES_EXTENDED in schema DEMO in database dgcadw (source database) and we will set up schema DGC in target datbase SKWNDB to access the data.

```
<copy>
-- as admin in source database
grant execute on DBMS_CLOUD_LINK to demo; -- demo is schema

BEGIN
DBMS_CLOUD_LINK_ADMIN.GRANT_REGISTER(
   username => 'DEMO',
   scope    => 'MY$TENANCY');
END;
/

-- as demo in the source db, registering table SALES_EXTENDED
BEGIN
   DBMS_CLOUD_LINK.REGISTER(
    schema_name => 'DEMO',
    schema_object  => 'SALES_EXTENDED',
    namespace   => 'DGCADW', 
    name        => 'SALES_EXTENDED',
    description => 'My sales_extended table in dgcadw',
    scope       => 'MY$TENANCY' );
END;
/

-- revoke (if you wish to later)
BEGIN
   DBMS_CLOUD_LINK.UNREGISTER(
    namespace      => 'DGCADW', 
    name           => 'SALES_EXTENDED');
END;
/

-- as admin in the target skwndb this is priviledge to access registered data sets
EXEC DBMS_CLOUD_LINK_ADMIN.GRANT_READ('DGC'); 	-- for dgc schema, also needed for admin if needbe

-- as dgc in the target db, find available data sets in your ADB (registered in other dbs):
set serveroutput on
DECLARE
   result CLOB DEFAULT NULL;
BEGIN
   DBMS_CLOUD_LINK.FIND('SALES', result); -- contains word sales
    DBMS_OUTPUT.PUT_LINE(result);
END;
/

-- output
[{"name":"SALES_EXTENDED","namespace":"DGCADW","description":"My sales_extended table in dgcadw"}]
PL/SQL procedure successfully completed.

-- query remote table through link using schema DGC in SWKWDB.
select count(*) from dgcadw.sales_extended@cloud$link;

-- output
916039

-- as admin in the target db view subscribed links:
SELECT * FROM DBA_CLOUD_LINK_ACCESS;

-- output
clprdtestns1	clprdtestn1	12-MAY-23 06.38.33.922941000 AM	12-MAY-23 06.38.33.922941000 AM		
Testdsnm200	Testds200	27-MAR-23 08.35.01.917232000 PM	27-MAR-23 08.35.01.917232000 PM		
covid19	cdc_data	27-MAR-23 08.35.11.782836000 PM	27-MAR-23 08.35.11.782836000 PM		
dsnm1232	ds1232	30-MAY-23 12.21.43.000000000 PM	30-MAY-23 12.21.43.000000000 PM	N	
DGCADW	SALES_EXTENDED	07-JUL-23 05.41.31.000000000 PM	07-JUL-23 05.41.31.000000000 PM	N

</copy>

```

- Usage notes/restrictions (significant)

https://docs.oracle.com/en/cloud/paas/autonomous-database/adbsa/autonomous-cloud-links.html#GUID-5CABFB6F-370D-4B9E-BC88-DB94D221CE53


## **Persistent Pipes**

```
<copy>

-- as admin
grant execute on dbms_pipe to demo;

-- as demo, this needs to be executed after EVERY database reboot
BEGIN
    DBMS_PIPE.SET_CREDENTIAL_NAME('api_token');
    DBMS_PIPE.SET_LOCATION_URI('<object storage bucket URL>/'); 
END;
/

-- send message to file in object storage bucket.  Note has a binary format and cannot be read by a text editor.  
DECLARE
  l_result  integer;
  l_prod_id integer;
  l_cust_id integer;
  l_time_id varchar2(30);
  l_channel_id integer;
  l_promo_id integer;
  l_quantity_sold integer;
  l_amount_sold number(9,2);
  l_gender varchar2(1);
  l_city varchar2(4000);
  l_state_province varchar2(4000);
  l_income_level varchar2(4000);
BEGIN
  dbms_pipe.pack_message(999); -- message1 prod_id
  dbms_pipe.pack_message(999); -- message2 cust_id
  dbms_pipe.pack_message('15-JUN-2023'); -- message3 time_id
  dbms_pipe.pack_message(999); -- message4 channel_id
  dbms_pipe.pack_message(999); -- message5 promo_id
  dbms_pipe.pack_message(100); -- message6 quantity_sold
  dbms_pipe.pack_message(1000.00); -- message 7 amount_sold
  dbms_pipe.pack_message('M'); -- message8 gender
  dbms_pipe.pack_message('Ridgefield'); -- message9 city
  dbms_pipe.pack_message('WA'); -- message10 state
  dbms_pipe.pack_message('0 - 100000'); -- message11 income
 
  l_result := dbms_pipe.send_message(
	pipename => 'order_pipe',
	credential_name => dbms_pipe.get_credential_name,
	location_uri => dbms_pipe.get_location_uri);
     
  if l_result = 0 then
	dbms_output.put_line('dbms_pipe sent order successfully');
  end if;
end;
/

-- retrieve the message back into original database (after which the file is automatically deleted) and insert into a table.
DECLARE
  message1 integer;
  message2 integer;
  message3 varchar2(30);
  message4 integer;
  message5 integer;
  message6 integer;
  message7 number(9,2);
  message8 varchar2(1);
  message9 varchar2(4000);
  message10 varchar2(4000);
  message11 varchar2(4000);
  l_result integer;
BEGIN
  dbms_pipe.set_credential_name('api_token');
  dbms_pipe.set_location_uri('<object storage bucket URL>/'); 
  l_result := dbms_pipe.receive_message (
	pipename => 'order_pipe',
	timeout  => dbms_pipe.maxwait,
	credential_name => dbms_pipe.get_credential_name,
	location_uri => dbms_pipe.get_location_uri);
  IF l_result = 0 THEN
	dbms_pipe.unpack_message(message1);
        dbms_pipe.unpack_message(message2);
        dbms_pipe.unpack_message(message3);
        dbms_pipe.unpack_message(message4);
        dbms_pipe.unpack_message(message5);
        dbms_pipe.unpack_message(message6);
        dbms_pipe.unpack_message(message7);
        dbms_pipe.unpack_message(message8);
	dbms_pipe.unpack_message(message9);
	dbms_pipe.unpack_message(message10);
	dbms_pipe.unpack_message(message11);
    END IF;
    insert into sales_extended (
        prod_id,
        cust_id,
        time_id,
        channel_id,
        promo_id,
        quantity_sold,
        amount_sold,
        gender,
	city,
	state_province,
	income_level)
        values (
        message1,
        message2,
        message3,
        message4,
        message5,
        message6,
        message7,
        message8,
	message9,
	message10,
	message11);
	--
        commit;
END;
/

----------------------
-- skwndb database
----------------------

-- as admin
grant execute on dbms_pipe to dgc;

-- as dgc
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'oci_cred',
    username => 'dgcameron',
    password => '<credential to access object storage buckets>'
  );
END;
/

-- create pipe (same name as source)
DECLARE
  r_status INTEGER;
BEGIN
    r_status := DBMS_PIPE.CREATE_PIPE(pipename => 'ORDER_PIPE');
END;
/

-- as admin verify pipe
SELECT ownerid, name, type FROM v$db_pipes WHERE name = 'ORDER_PIPE';

-- as dgc
BEGIN
    DBMS_PIPE.SET_CREDENTIAL_NAME('oci_cred');
    DBMS_PIPE.SET_LOCATION_URI('<object storage bucket URL>/'); 
END;
/


-- Now retrieve message from a different datbase.  Re-create message on SOURCE DB and send to file in object storage bucket.
DECLARE
  l_result  integer;
  l_prod_id integer;
  l_cust_id integer;
  l_time_id varchar2(30);
  l_channel_id integer;
  l_promo_id integer;
  l_quantity_sold integer;
  l_amount_sold number(9,2);
  l_gender varchar2(1);
  l_city varchar2(4000);
  l_state_province varchar2(4000);
  l_income_level varchar2(4000);
BEGIN
  dbms_pipe.pack_message(999); -- message1 prod_id
  dbms_pipe.pack_message(999); -- message2 cust_id
  dbms_pipe.pack_message('15-JUN-2023'); -- message3 time_id
  dbms_pipe.pack_message(999); -- message4 channel_id
  dbms_pipe.pack_message(999); -- message5 promo_id
  dbms_pipe.pack_message(100); -- message6 quantity_sold
  dbms_pipe.pack_message(1000.00); -- message 7 amount_sold
  dbms_pipe.pack_message('M'); -- message8 gender
  dbms_pipe.pack_message('Ridgefield'); -- message9 city
  dbms_pipe.pack_message('WA'); -- message10 state
  dbms_pipe.pack_message('0 - 100000'); -- message11 income
 
  l_result := dbms_pipe.send_message(
	pipename => 'order_pipe',
	credential_name => dbms_pipe.get_credential_name,
	location_uri => dbms_pipe.get_location_uri);
     
  if l_result = 0 then
	dbms_output.put_line('dbms_pipe sent order successfully');
  end if;
end;
/

-- retrieve message on remote skwndb.  Rather than insert into a table we'll just view the output in SQLDeveloper.
set serveroutput on

DECLARE
  message1 integer;
  message2 integer;
  message3 varchar2(30);
  message4 integer;
  message5 integer;
  message6 integer;
  message7 number(9,2);
  message8 varchar2(1);
  message9 varchar2(4000);
  message10 varchar2(4000);
  message11 varchar2(4000);
  l_result integer;
BEGIN
  dbms_pipe.set_credential_name('oci_cred');
  dbms_pipe.set_location_uri('<object storage bucket URL>/'); 
  l_result := dbms_pipe.receive_message (
	pipename => 'order_pipe',
	timeout  => dbms_pipe.maxwait,
	credential_name => dbms_pipe.get_credential_name,
	location_uri => dbms_pipe.get_location_uri);
  IF l_result = 0 THEN
	dbms_pipe.unpack_message(message1);
        dbms_pipe.unpack_message(message2);
        dbms_pipe.unpack_message(message3);
        dbms_pipe.unpack_message(message4);
        dbms_pipe.unpack_message(message5);
        dbms_pipe.unpack_message(message6);
        dbms_pipe.unpack_message(message7);
        dbms_pipe.unpack_message(message8);
	dbms_pipe.unpack_message(message9);
	dbms_pipe.unpack_message(message10);
	dbms_pipe.unpack_message(message11);
        DBMS_OUTPUT.put_line('prod_id: ' || message1);
        DBMS_OUTPUT.put_line('cust_id: ' || message2);
        DBMS_OUTPUT.put_line('time_id: ' || message3);
        DBMS_OUTPUT.put_line('channel_id: ' || message4);
        DBMS_OUTPUT.put_line('promo_id: ' || message5);
        DBMS_OUTPUT.put_line('quantity sold: ' || message6);
        DBMS_OUTPUT.put_line('amount sold: ' || message7);
        DBMS_OUTPUT.put_line('gender: ' || message8);
        DBMS_OUTPUT.put_line('city: ' || message9);
        DBMS_OUTPUT.put_line('state: ' || message10);
        DBMS_OUTPUT.put_line('income level: ' || message11);
    END IF;
END;
/

</copy>

```

