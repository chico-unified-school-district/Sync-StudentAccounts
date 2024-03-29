SELECT DISTINCT
 s.SC AS departmentNumber,
 s.ID AS employeeid,
 s.GR AS grade,
 s.GR AS gecos,
 s.LN AS sn,
 s.FN AS givenname,
 FORMAT (s.BD,'yyMMdd') AS dob,
 s.U12 AS gSuiteStatus,
 s.SEM AS homePage,
'True' AS Enabled
FROM STU AS s
 INNER JOIN
 (
    select id,tg,min(sc) AS minsc
    from stu group by id,tg having tg = ' '
    ) AS gs
 ON ( s.id = gs.id and s.sc = gs.minsc )
--  INNER JOIN ENR AS e
--  e.sn = s.sn
WHERE
(s.FN IS NOT NULL AND s.LN IS NOT NULL)
AND s.SC IN ( 1,2,3,5,6,7,8,9,10,11,12,13,16,17,18,19,20,21,23,24,25,26,27,28,42,43,91,999 )
AND ( (s.del = 0) OR (s.del IS NULL) ) AND  ( s.tg = ' ' )
--AND s.ID IN (12345,12346)
ORDER by s.id;