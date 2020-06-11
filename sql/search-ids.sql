SELECT 
 DISTINCT STU.ID as employeeid,
 STU.LN as sn,
 STU.FN as givenname,
 STU.BD as dob,
 STU.SC as departmentNumber,
 STU.U12 as GSuiteStatus,
 STU.GR as grade
FROM STU
WHERE 
 ( (STU.del = 0) OR (STU.del IS NULL) ) AND ( STU.tg = ' ' )
 AND STU.SC IN ( 1,2,3,5,6,7,8,9,10,11,12,13,16,17,18,19,20,21,23,24,25,26,27,28,91,42,43 )
 AND STU.BD IS NOT NULL
 AND STU.FN IS NOT NULL
 AND STU.LN IS NOT NULL
 AND STU.ID IS NOT NULL
 AND STU.ID IN 