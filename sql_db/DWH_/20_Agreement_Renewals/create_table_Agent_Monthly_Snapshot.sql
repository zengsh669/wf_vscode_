CREATE TABLE SILVER.dbo.Agent_Monthly_Snapshot (
    [SnapshotMonth]         DATE           NOT NULL,
    [Agent ID]              DECIMAL(9,0)   NOT NULL,
    [Agent Name]            VARCHAR(60)    NULL,
    [Commencement Date]     DATE           NULL,
    [Termination Date]      VARCHAR(20)    NULL,
    [Create Date]           DATE           NULL,
    [create_operator]       CHAR(16)       NULL,
    [Update Date]           DATE           NULL,
    [update_operator]       CHAR(16)       NULL,
    CONSTRAINT PK_Agent_Monthly_Snapshot PRIMARY KEY ([SnapshotMonth], [Agent ID])
);
GO
