USE [SILVER]
GO

/****** Object:  Table [dbo].[Member_Daily_Movement] ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[Member_Daily_Movement](
	[run_date] [date] NOT NULL,
	[pre_snapshot_date] [date] NOT NULL,
	[movement_type] [varchar](20) NOT NULL,
	[membership_id] [decimal](9, 0) NOT NULL,
	[status_yday] [char](1) NULL,
	[status_today] [char](1) NOT NULL,
	[effective_join_date] [datetime] NULL,
	[effective_rejoin_date] [datetime] NULL,
	[effective_termination_date] [datetime] NULL,
	[product_info] [nvarchar](max) NULL
) ON [PRIMARY]
GO
