
 SELECT
 s.ID
 ,s.SC
 ,s.GR
 ,s.LN
 ,s.FN
 ,FORMAT (s.BD,'yyMMdd') AS BD
 ,s.U12 AS gmailActive
 ,s.SEM AS gmail
FROM STU AS s
 INNER JOIN
 (
   -- Determine minimum Site Code min(sc) to prevent reprocessing loop
   -- for students assigned to multiple school sites
    SELECT
     ID
     ,TG
     ,min(SC) AS minimumSitecode
    FROM STU
    WHERE DEL = 0
     GROUP BY ID,TG having TG = ' '
    ) AS gs
 ON ( s.ID = gs.ID AND s.SC = gs.minimumSitecode )
WHERE
(s.FN IS NOT NULL AND s.LN IS NOT NULL AND s.BD IS NOT NULL AND s.GR IS NOT NULL AND s.SC IS NOT NULL)
AND s.SC IN ( 1,2,3,5,6,7,8,9,10,11,12,13,16,17,18,19,20,21,23,24,25,26,27,28,30,42,43,91,999 )
AND ( (s.DEL = 0) OR (s.DEL IS NULL) ) AND  ( s.TG = ' ' )
ORDER by s.ID;