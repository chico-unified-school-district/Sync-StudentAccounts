UPDATE [DRI] SET [DRI].[SCL] = [STU].[SC]
FROM (SELECT [STU].* FROM STU WHERE DEL = 0)
 STU RIGHT JOIN ((SELECT [DRA].* FROM DRA WHERE DEL = 0)
 DRA LEFT JOIN (SELECT [DRI].* FROM DRI WHERE DEL = 0)
 DRI ON [DRI].[RID] = [DRA].[RID] AND [DRI].[RIN] = [DRA].[RIN]) ON [STU].[ID] = [DRA].[ID]
WHERE
 DRA.RD IS NULL
 AND DRA.ID = 