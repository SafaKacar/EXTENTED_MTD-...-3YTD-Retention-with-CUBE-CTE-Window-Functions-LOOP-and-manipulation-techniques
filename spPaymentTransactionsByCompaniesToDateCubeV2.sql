/*
---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---
EXECUTE THIS QUERY FOR DAILY ETL PLAN:

	DECLARE @DailySPDate AS DATE = CAST(GETDATE() AS DATE)
	EXEC [DBO].[spPaymentTransactionsByCompaniesToDateCubeV2] @DailySPDate

--Note: You can use any date by replacing "@DailySPDate" with a date, e.g. 'yyyy-MM-dd' that included on the tables used in query
---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---
SOME DETAILS :
	Hourly transaction summary Metrics for DTH, MTD, QTD, SemiYTD & YTD using CUBE, Window Functions, UPDATE, LOOP, CTE and parameters with T-SQL.
	It includes several metrics: UU, Transaction Count, Transaction Volume, Tenure by Year, Average Age; Retention UU and Retention Rates in terms of time periods (Month, Quarter, Semi Year, Year).
	The table outputs will be showing on Tableau Report with several filters which provided by cube function.
	DTH = Date-to-Hour
	MTD = Month-to-Date
	QTD = Quarter-to-Date
	SemiYTD = Semi-Year-to-Date
	YTD = Year-to-Date
	2YTD = Last-2-Years-to-Date
	3YTD = Last-3-Years-to-Date
	FeatureLaunchedTD = All the time
---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---	---
*/
USE DWH_Workspace
GO
CREATE PROCEDURE [dbo].[spPaymentTransactionsByCompaniesToDateCubeV2] (@BaseDay DATE) AS
DROP TABLE IF EXISTS #TempDateHours,#ReadyToUpdateData
DECLARE
--		@BaseDay as Date =	CAST(GETDATE() AS DATE),
		@inc	 as INT  =  1,
--		@d       as INT  =  1,
		@y		 as INT  =  0,
		@m		 as INT  =  1
declare @DailySP as Date SET @DailySP = DATEADD(DAY,-@d,@BaseDay)				
	    IF YEAR(@BaseDay) != YEAR(DATEADD(DAY,-1,@BaseDay))
		   BEGIN
		   SET @y = @y + 1
		   END
		IF DAY(@BaseDay) = 1
		   BEGIN
		   SET @m = @m + 1
		   END
		DECLARE @Param_MTDIndicator	    AS DATE =					 Dateadd(Day,1,EOMonth(dateadd(MONTH,-@m,@BaseDay))),
--				@Param_2MTDIndicator	AS DATE = DATEFROMPARTS(YEAR(Dateadd(day,-@m,@BaseDay)),(((MONTH(dateadd(day,-@m,@BaseDay)))-1)/2)*2+1,1),
			    @Param_QTDIndicator	    AS DATE = DATEFROMPARTS(YEAR(Dateadd(day,-@m,@BaseDay)), ((MONTH(dateadd(day,-@m,@BaseDay)) -1)/3)*3+1,1),
			    @Param_SemiYTDIndicator AS DATE = DATEFROMPARTS(YEAR(Dateadd(day,-@m,@BaseDay)),(((MONTH(dateadd(day,-@m,@BaseDay)))-1)/6)*6+1,1),
			    @Param_YTDIndicator	    AS DATE = DATEFROMPARTS(YEAR(Dateadd(day,-@y,@BaseDay)),1,1),
				@Param_2YTDIndicator	AS DATE = DATEFROMPARTS(YEAR(Dateadd(day,-@y,@BaseDay))-1,1,1),
				@Param_3YTDIndicator	AS DATE = DATEFROMPARTS(YEAR(Dateadd(day,-@y,@BaseDay))-2,1,1),
				@Param_FirstPaymentTxDate AS DATE = '2020-01-20'
CREATE TABLE #TempDateHours (HourlyDateTime DATETIME);
DECLARE	 @StartDateParameter AS DATETIME = @Param_FirstPaymentTxDate--DATEFROMPARTS(YEAR(DATEADD(DAY,-@y,cast(@BaseDay as DATETIME))),1,1)--DATEADD(DAY,-1,cast(@BaseDay as DATETIME))
DECLARE  @StartDate			 AS DATETIME = DATEADD(DAY,-1,cast(@StartDateParameter as DATETIME))
		WHILE @StartDate <= @BaseDay
			BEGIN
				IF(@inc <= 23)
					BEGIN
					INSERT INTO #TempDateHours
						SELECT
							DATEADD(hour,@inc,@StartDate) HourlyDateTime
						SET @inc = @inc + 1
					END
				ELSE
					BEGIN
						SET @inc = 0
						SET @StartDate = DATEADD(DAY,1,@StartDate)
					END
			END
			SET @StartDate = @StartDateParameter;
DELETE FROM #TempDateHours WHERE @BaseDay	< HourlyDateTime
DELETE FROM #TempDateHours WHERE @StartDate > HourlyDateTime;
DELETE FROM  DWH_Workspace.[\skacar].[FACT_PaymentTransactionsByCompaniesToDateCubeV2] WHERE [DateHour] >= @DailySP AND [DateHour] < @BaseDay
;
WITH CustomerBasedCTE AS
(
		select
			   DATEFROMPARTS(YEAR(CreatedAt),(((MONTH(CreatedAt))-1)/6)*6+1,1) SemiYearIndicator
			  ,DATEPART(q,CreatedAt)										 QuarterNumber
			  ,cast(CreatedAt as date)			   							 [Date]
			  ,dateadd(hour,(datepart(hour, DATEADD(HH,0,CreatedAt))),dateadd(day, 0, datediff(day,  0, CreatedAt)))	ContributedDateHour
--			  ,DATEFROMPARTS(YEAR(CreatedAt),(((MONTH(CreatedAt))-1)/2)*2+1,1) Indicator_2MTD
			  ,count(Id)							    TxCount
			  ,sum(Amount)							    TotalVolume
			  ,MAX(Age)									Age 
			  ,MAX(TenureByYear)						TenureByYear
			  ,CustomerKey
			  ,ISNULL(PaymentType	,10000)	PaymentType
			  ,ISNULL(CompanyId		,10000)	CompanyId
		--	  ,ISNULL(CustomerType			,10000)	CustomerType
		--	  ,ISNULL(cast([StandardizedProductName] as VARCHAR(120)),'(Overall)') [StandardizedProductName]
		from (
				select   l.Id,l.CreatedAt,l.CustomerKey,l.Amount
						,ISNULL(cast(PaymentType as int),-100)				 PaymentType
						,ISNULL(cast(l.CompanyId  as int),-100)				 CompanyId
			--			,ISNULL(cast(l.[StandardizedProductName] as VARCHAR(120)),'N/A')	[StandardizedProductName]
			--			,UTH.CustomerType
			--			,ROW_NUMBER() OVER (PARTITION BY UTH.CustomerKey ORDER BY UTH.CreatedAt DESC) CustomerTypeHistoryRanker
						,DATEDIFF(MINUTE,U.CreatedAt,l.CreatedAt)/(365.25*24*60)		  TenureByYear		
						,CASE WHEN YEAR(DateOfBirth) >= 1900 AND YEAR(DateOfBirth) < 2020 THEN DATEDIFF(DAY,DateOfBirth,l.CreatedAt) ELSE NULL END/365.25		Age		
				FROM (select l.Id,l.CustomerKey,l.Amount,l.CreatedAt, IIF(l.CompanyId IS NULL,-80,L.CompanyId) CompanyId/*, IIF(l.[StandardizedProductName] IS NULL,'NULL',REPLACE(REPLACE(l.[StandardizedProductName],'ödemesi','Payment'),'payment','Payment')) [StandardizedProductName]*/
							,IIF(ECA.PaymentType IS NULL,-80,ECA.PaymentType) PaymentType
					  from [DWH_]..[FACT_Transaction] l WITH (Nolock)
					  left join _billpayment..DIM_Company eca with (nolock) on eca.Id = l.CompanyId
					  where EntryType = 17 AND IsCancellation = 0 AND OperatorCustomerKey IS NULL AND l.CreatedAt >= @Param_FirstPaymentTxDate/*YEAR(l.CreatedAt) >= YEAR(DATEADD(YEAR,-@y,@BaseDay))*/ AND l.CreatedAt < @BaseDay) L
				JOIN [DWH_]..[DIM_Customers] u with (nolock)  on u.Customer_Key = l.CustomerKey
			--	JOIN  DWH_..DIM_CustomerTypeHistory UTH WITH (NOLOCK) ON UTH.CustomerKey = l.CustomerKey AND l.CreatedAt >= UTH.CreatedAt
			 ) m1
		group by  CustomerKey
				 ,DATEFROMPARTS(YEAR(CreatedAt),(((MONTH(CreatedAt))-1)/6)*6+1,1)
				 ,DATEPART(q,CreatedAt)
				 ,cast(m1.CreatedAt as date)
				 ,dateadd(hour,(datepart(hour, DATEADD(HH,0,CreatedAt))),dateadd(day, 0, datediff(day,  0, CreatedAt)))
--				 ,DATEFROMPARTS(YEAR(CreatedAt),(((MONTH(CreatedAt))-1)/2)*2+1,1)
				 ,cube(PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/)
), DailyWithAndWithoutNonDistinctToDateCalculations AS
(
					Select
						 ContributedDateHour
						,[Date]
						,QuarterNumber
						PaymentType
						,CompanyId
						/*,[StandardizedProductName]*/
						/*,CustomerType*/
						,COUNT(DISTINCT CustomerKey) UUHourly
						,SUM(TxCount)			 TxCountHourly
						,SUM(ABS(TotalVolume))	 TxVolumeHourly
						,SUM(SUM(TxCount))			  OVER (PARTITION BY [Date]PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxCountDTH
						,SUM(SUM(ABS(TotalVolume)))	  OVER (PARTITION BY [Date]PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxVolumeDTH
						,SUM(Age)/count(case when Age IS NOT NULL THEN 1 else NULL END) AvgAgeHourly
						,AVG(TenureByYear)												AvgTenureByYearHourly
						,SUM(SUM(Age))													   OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when Age IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgAgeDTH
						,SUM(SUM(Age))													   OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when Age IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgAgeMTD
						,SUM(SUM(Age))													   OVER (PARTITION BY YEAR([Date]),QuarterNumberPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when Age IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),QuarterNumberPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgAgeQTD
						,SUM(SUM(Age))													   OVER (PARTITION BY YEAR([Date]),SemiYearIndicatorPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when Age IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),SemiYearIndicatorPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgAgeSemiYTD
						,SUM(SUM(Age))													   OVER (PARTITION BY YEAR([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when Age IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgAgeYTD
						,SUM(SUM(TenureByYear))														OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when TenureByYear IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgTenureByYearDTH
						,SUM(SUM(TenureByYear))														OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when TenureByYear IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgTenureByYearMTD
						,SUM(SUM(TenureByYear))														OVER (PARTITION BY YEAR([Date]),QuarterNumberPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when TenureByYear IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),QuarterNumberPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgTenureByYearQTD
						,SUM(SUM(TenureByYear))														OVER (PARTITION BY YEAR([Date]),SemiYearIndicatorPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when TenureByYear IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),SemiYearIndicatorPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgTenureByYearSemiYTD
						,SUM(SUM(TenureByYear))														OVER (PARTITION BY YEAR([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
								SUM(count(case when TenureByYear IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgTenureByYearYTD
						,SUM(SUM(TxCount))			OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxCountMTD
						,SUM(SUM(ABS(TotalVolume))) OVER (PARTITION BY YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxVolumeMTD
						,SUM(SUM(TxCount))			OVER (PARTITION BY YEAR([Date]),QuarterNumber,				PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxCountQTD
						,SUM(SUM(ABS(TotalVolume))) OVER (PARTITION BY YEAR([Date]),QuarterNumber,				PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxVolumeQTD
						,SUM(SUM(TxCount))			OVER (PARTITION BY YEAR([Date]),SemiYearIndicator,			PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxCountSemiYTD
						,SUM(SUM(ABS(TotalVolume))) OVER (PARTITION BY YEAR([Date]),SemiYearIndicator,			PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxVolumeSemiYTD
						,SUM(SUM(TxCount))			OVER (PARTITION BY YEAR([Date]),							PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxCountYTD
						,SUM(SUM(ABS(TotalVolume))) OVER (PARTITION BY YEAR([Date]),							PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxVolumeYTD
						--,SUM(SUM(Age))													   OVER (PARTITION BY YEAR([Date]),Indicator_2MTDPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
						--		SUM(count(case when Age IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),Indicator_2MTDPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgAge2MTD

						--,SUM(SUM(TenureByYear))														OVER (PARTITION BY YEAR([Date]),Indicator_2MTDPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour)*1.0 / 
						--		SUM(count(case when TenureByYear IS NOT NULL THEN 1 else NULL END)) OVER (PARTITION BY YEAR([Date]),Indicator_2MTDPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) AvgTenureByYear2MTD


						--,SUM(SUM(TxCount))			OVER (PARTITION BY YEAR([Date]),Indicator_2MTDPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxCount2MTD
						--,SUM(SUM(ABS(TotalVolume))) OVER (PARTITION BY YEAR([Date]),Indicator_2MTDPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ ORDER BY ContributedDateHour) TxVolume2MTD

					From CustomerBasedCTE
					WHERE ContributedDateHour < @BaseDay AND ContributedDateHour >= @Param_YTDIndicator
					Group By [Date],ContributedDateHour,SemiYearIndicator,QuarterNumber/*,Indicator_2MTD*/PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
					)
 , DailyUniqueCustomerCalculation AS
 (
 select
							ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UUDTH
 from
		(
			select	
				 ContributedDateHour
				,CustomerKey
				PaymentType
				,CompanyId
				/*,[StandardizedProductName]*/
				/*,CustomerType*/
				,RANK() OVER (Partition by YEAR(ContributedDateHour),MONTH(ContributedDateHour),DAY(ContributedDateHour)PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
			from
					(
					Select
						 MIN(ContributedDateHour) ContributedDateHour
						, CustomerKey
						, PaymentType
						, CompanyId
						/*,[StandardizedProductName]*/
					From CustomerBasedCTE
					WHERE [Date]>=@DailySP and [Date] < @BaseDay
					Group By CustomerKeyPaymentType,CompanyId/*,[StandardizedProductName]*/
					) M
		) R
 GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/

 )
 , DailyWithQTDForUU AS
(
					SELECT  ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UUQTD
					FROM
							(
							select
								 
								 ContributedDateHour
								,CustomerKey
								PaymentType
								,CompanyId
								/*,[StandardizedProductName]*/
								/*,CustomerType*/
								,RANK() OVER (Partition by YEAR([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
							from
									(
									select MIN(ContributedDateHour) ContributedDateHour
										  ,MIN([Date]) [Date]
										  ,CustomerKey
										  PaymentType
										  ,CompanyId
										  /*,[StandardizedProductName]*/
										  /*,CustomerType*/
									from CustomerBasedCTE
									where	[Date] >= @Param_QTDIndicator
										and [Date] <  @BaseDay
									group by CustomerKeyPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
									) z
							  ) T
					GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
)
 , DailyWithSemiYTDForUU AS
(
					SELECT  ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UUSemiYTD
					FROM
							(
							select
								 
								 ContributedDateHour
								,CustomerKey
								PaymentType
								,CompanyId
								/*,[StandardizedProductName]*/
								/*,CustomerType*/
								,RANK() OVER (Partition by YEAR([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
							from
									(
									select MIN(ContributedDateHour) ContributedDateHour
										  ,MIN([Date]) [Date]
										  ,CustomerKey
										  PaymentType
										  ,CompanyId
										  /*,[StandardizedProductName]*/
										  /*,CustomerType*/
									from CustomerBasedCTE
									where	[Date] >= @Param_SemiYTDIndicator
										and [Date] <  @BaseDay
									group by CustomerKeyPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
									) z
							  ) T
					GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
)
 , DailyWithMTDForUU  AS
				    (
					SELECT  ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UUMTD
					FROM
							(
							select
								 ContributedDateHour
								,CustomerKey
								PaymentType
								,CompanyId
								/*,[StandardizedProductName]*/
								/*,CustomerType*/
								,RANK() OVER (Partition by YEAR([Date]),MONTH([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
							from
									(
									select MIN(ContributedDateHour) ContributedDateHour
										  ,MIN([Date]) [Date]
										  ,CustomerKey
										  PaymentType
										  ,CompanyId
										  /*,[StandardizedProductName]*/
										  /*,CustomerType*/
									from CustomerBasedCTE
									where	[Date] >= @Param_MTDIndicator
										and [Date] <  @BaseDay
									group by CustomerKeyPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
									) z
							  ) T
					GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
				    )
 /*, DailyWith2MTDForUU  AS
				    (
					SELECT  ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UU2MTD
					FROM
							(
							select
								 ContributedDateHour
								,CustomerKey
								PaymentType
								,CompanyId
								/*,[StandardizedProductName]*/
								/*,CustomerType*/
								,RANK() OVER (Partition by YEAR([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
							from
									(
									select MIN(ContributedDateHour) ContributedDateHour
										  ,MIN([Date]) [Date]
										  ,CustomerKey
										  PaymentType
										  ,CompanyId
										  /*,[StandardizedProductName]*/
										  /*,CustomerType*/
									from CustomerBasedCTE
									where	[Date] >= @Param_2MTDIndicator
										and [Date] <  @BaseDay
									group by CustomerKeyPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
									) z
							  ) T
					GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
				    )*/
 , DailyWithYTDForUU  AS
				    (
					SELECT ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UUYTD
					FROM
							(
							select
								 ContributedDateHour
								,CustomerKey
								PaymentType
								,CompanyId
								/*,[StandardizedProductName]*/
								/*,CustomerType*/
								,RANK() OVER (Partition by YEAR([Date])PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
							from
									(
									select MIN(ContributedDateHour) ContributedDateHour
										  ,MIN([Date]) [Date]
										  ,CustomerKey
										  PaymentType
										  ,CompanyId
										  /*,[StandardizedProductName]*/
										  /*,CustomerType*/
									from CustomerBasedCTE
									where [Date] <=  @BaseDay
									  AND [Date] >=  @Param_YTDIndicator
									group by PaymentType,CustomerKey,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
									) z
							  ) T
					GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
				    )
 , DailyWith2YTDForUU  AS
				    (
					SELECT ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UU2YTD
					FROM
							(
							select
								 ContributedDateHour
								,CustomerKey
								PaymentType
								,CompanyId
								/*,[StandardizedProductName]*/
								/*,CustomerType*/
								,RANK() OVER (Partition by PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
							from
									(
									select MIN(ContributedDateHour) ContributedDateHour
										  ,MIN([Date]) [Date]
										  ,CustomerKey
										  PaymentType
										  ,CompanyId
										  /*,[StandardizedProductName]*/
										  /*,CustomerType*/
									from CustomerBasedCTE
									where [Date] <=  @BaseDay
									  AND [Date] >=  @Param_2YTDIndicator
									group by PaymentType,CustomerKey,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
									) z
							  ) T
					GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
				    )
 , DailyWith3YTDForUU  AS
				    (
					SELECT ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UU3YTD
					FROM
							(
							select
								 ContributedDateHour
								,CustomerKey
								PaymentType
								,CompanyId
								/*,[StandardizedProductName]*/
								/*,CustomerType*/
								,RANK() OVER (Partition by PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
							from
									(
									select MIN(ContributedDateHour) ContributedDateHour
										  ,MIN([Date]) [Date]
										  ,CustomerKey
										  PaymentType
										  ,CompanyId
										  /*,[StandardizedProductName]*/
										  /*,CustomerType*/
									from CustomerBasedCTE
									where [Date] <=  @BaseDay
									  AND [Date] >=  @Param_3YTDIndicator
									group by PaymentType,CustomerKey,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
									) z
							  ) T
					GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
				    )
 , DailyWithFeatureLaunchedTDForUU  AS
				    (
					SELECT ContributedDateHour
						   PaymentType
						   ,CompanyId
						   /*,[StandardizedProductName]*/
						   /*,CustomerType*/
						   ,MAX(Ranker) UUFeatureLaunchedTD
					FROM
							(
							select
								 ContributedDateHour
								,CustomerKey
								PaymentType
								,CompanyId
								/*,[StandardizedProductName]*/
								/*,CustomerType*/
								,RANK() OVER (Partition by PaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/ Order By ContributedDateHour,CustomerKey) Ranker
							from
									(
									select MIN(ContributedDateHour) ContributedDateHour
										  ,MIN([Date]) [Date]
										  ,CustomerKey
										  PaymentType
										  ,CompanyId
										  /*,[StandardizedProductName]*/
										  /*,CustomerType*/
									from CustomerBasedCTE
									where [Date] <=  @BaseDay
									  AND [Date] >=  @Param_FirstPaymentTxDate
									group by PaymentType,CustomerKey,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
									) z
							  ) T
					GROUP BY ContributedDateHourPaymentType,CompanyId/*,[StandardizedProductName]*//*,CustomerType*/
				    )
, CrossJoiningWithLargestCTEPart_DailyWithYTDForUU AS
		(
		SELECT 
			DH.HourlyDateTime [DateHour],CompanyId/*,CustomerType*//*,Product*/PaymentType
		FROM (SELECT DISTINCT CompanyId/*,CustomerType*//*,Product*/PaymentType FROM DailyWithYTDForUU WHERE ContributedDateHour >= @StartDate AND ContributedDateHour < @BaseDay) x
		CROSS JOIN #TempDateHours DH WITH (NOLOCK)
		WHERE DH.HourlyDateTime >= @StartDate AND DH.HourlyDateTime < @BaseDay
		)

, CombiningDummyDataWithFundamental AS
					(
				    select m1.[DateHour]
						  ,m1.PaymentType
						  ,m1.CompanyId
						--  ,m1.CustomerType
						--  ,m1.[StandardizedProductName] Product
						  ,ISNULL(L1.UUHourly		,0) UUHourly
						  ,ISNULL(L1.TxCountHourly	,0) TxCountHourly
						  ,ISNULL(L1.TxVolumeHourly	,0) TxVolumeHourly
						  ,c1.UUDTH
						  ,l1.TxCountDTH
						  ,l1.TxVolumeDTH
						  ,l1.AvgAgeHourly
						  ,l1.AvgTenureByYearHourly
						  ,m2.UUMTD
						  ,l1.TxCountMTD
						  ,l1.TxVolumeMTD
						  --,a1.UU2MTD
						  --,l1.TxCount2MTD
						  --,l1.TxVolume2MTD
						  ,l1.TxCountQTD
						  ,l1.TxVolumeQTD
						  ,l1.TxCountSemiYTD
						  ,l1.TxVolumeSemiYTD
						  ,l1.TxCountYTD
						  ,l1.TxVolumeYTD
						  ,G1.UUYTD
						  ,m3.UUSemiYTD
						  ,m4.UUQTD
						  ,l1.AvgAgeDTH
						  ,l1.AvgAgeMTD
						  --,l1.AvgAge2MTD
						  ,l1.AvgAgeQTD
						  ,l1.AvgAgeSemiYTD
						  ,l1.AvgAgeYTD
						  ,l1.AvgTenureByYearDTH
						  ,l1.AvgTenureByYearMTD
						  --,l1.AvgTenureByYear2MTD
						  ,l1.AvgTenureByYearQTD
						  ,l1.AvgTenureByYearSemiYTD
						  ,l1.AvgTenureByYearYTD
						  ,L11.UU2YTD
						  ,L12.UU3YTD
						  ,L13.UUFeatureLaunchedTD
				--	INTO DWH_Workspace..[FACT_PaymentTransactionsAndCompanyToDateCube]
					from CrossJoiningWithLargestCTEPart_DailyWithYTDForUU M1
					LEFT JOIN DailyWithYTDForUU								   G1  on m1.DateHour = G1.ContributedDateHour   and m1.PaymentType =  G1.PaymentType  and m1.CompanyId =  G1.CompanyId --and m1.[StandardizedProductName]=m3.[StandardizedProductName]--and m1.CustomerType = m3.CustomerType
					LEFT join DailyWithSemiYTDForUU							   m3  on m1.DateHour = m3.ContributedDateHour   and m1.PaymentType =  m3.PaymentType  and m1.CompanyId =  m3.CompanyId --and m1.[StandardizedProductName]=m3.[StandardizedProductName]--and m1.CustomerType = m3.CustomerType
					LEFT join DailyWithQTDForUU								   m4  on m1.DateHour = m4.ContributedDateHour   and m1.PaymentType =  m4.PaymentType  and m1.CompanyId =  m4.CompanyId --and m1.[StandardizedProductName]=m4.[StandardizedProductName]--and m1.CustomerType = m4.CustomerType
					--LEFT join DailyWith2MTDForUU							   a1  on m1.DateHour = a1.ContributedDateHour   and m1.PaymentType =  a1.PaymentType  and M1.CompanyId =  a1.CompanyId --and m1.[StandardizedProductName]=L1.[StandardizedProductName]--and m1.CustomerType = L1.CustomerType
					LEFT join DailyWithMTDForUU								   m2  on m1.DateHour = m2.ContributedDateHour   and m1.PaymentType =  m2.PaymentType  and m1.CompanyId =  m2.CompanyId --and m1.[StandardizedProductName]=m2.[StandardizedProductName]--and m1.CustomerType = m2.CustomerType
					LEFT join DailyUniqueCustomerCalculation					   c1  on M1.DateHour = c1.ContributedDateHour   and m1.PaymentType =  c1.PaymentType  and m1.CompanyId =  c1.CompanyId --and m1.[StandardizedProductName]=c1.[StandardizedProductName]
					LEFT join DailyWithAndWithoutNonDistinctToDateCalculations L1  on m1.DateHour = L1.ContributedDateHour   and m1.PaymentType =  L1.PaymentType  and M1.CompanyId =  L1.CompanyId --and m1.[StandardizedProductName]=L1.[StandardizedProductName]--and m1.CustomerType = L1.CustomerType
					LEFT join DailyWith2YTDForUU							   L11 on m1.DateHour = L11.ContributedDateHour  and m1.PaymentType = L11.PaymentType  and M1.CompanyId = L11.CompanyId
					LEFT join DailyWith3YTDForUU							   L12 on m1.DateHour = L12.ContributedDateHour  and m1.PaymentType = L12.PaymentType  and M1.CompanyId = L12.CompanyId
					LEFT join DailyWithFeatureLaunchedTDForUU				   L13 on m1.DateHour = L13.ContributedDateHour  and m1.PaymentType = L13.PaymentType  and M1.CompanyId = L13.CompanyId
					--where m1.ContributedDateHour >= @DailySP
				)
	select *
	INTO #ReadyToUpdateData
	from CombiningDummyDataWithFundamental
PRINT 'A - RAW DATA IS READY- READY TO LOOP SETTINGS AND UPDATES - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30))
PRINT ('1.1-UUDTH LOOP SETTINGS PREPARING - STARTED')
		UPDATE  #ReadyToUpdateData
			SET UUDTH = 0
		FROM  #ReadyToUpdateData
		WHERE UUDTH is null AND DateHour = @DailySP
PRINT ('1.2-UUDTH LOOP SETTINGS PREPARING - FINISHED- FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('2.1-TxCountDTH LOOP SETTINGS PREPARING - STARTED- FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  #ReadyToUpdateData
			SET TxCountDTH = 0
		FROM  #ReadyToUpdateData
		WHERE TxCountDTH is null AND DateHour = @DailySP
PRINT ('2.2-TxCountDTH LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('3.1-TxVolumeDTH LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  #ReadyToUpdateData
			SET TxVolumeDTH = 0
		FROM  #ReadyToUpdateData
		WHERE TxVolumeDTH is null AND DateHour = @DailySP
PRINT ('3.2-TxVolumeDTH LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('4.1-AvgAgeDTH LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '   +cast(@DailySP as varchar(30)))
		UPDATE  #ReadyToUpdateData
			SET AvgAgeDTH = 0
		FROM  #ReadyToUpdateData
		WHERE AvgAgeDTH is null AND DateHour = @DailySP
PRINT ('4.2-AvgAgeDTH LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('5.1-AvgTenureByYearDTH LOOP SETTINGS PREPARING - STARTED- FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  #ReadyToUpdateData
			SET AvgTenureByYearDTH = 0
		FROM  #ReadyToUpdateData
		WHERE AvgTenureByYearDTH is null AND DateHour = @DailySP
PRINT ('6.2-AvgTenureByYearDTH LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('7.1-UUMTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET UUMTD = ISNULL(IIF(@DailySP = @Param_MTDIndicator,0,L.UUMTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(UUMTD) UUMTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND UUMTD IS NOT NULL and DateHour >= @Param_MTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId AND /*K.Product = L.Product AND*/ K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.UUMTD is null AND K.DateHour = @DailySP
PRINT ('7.2-UUMTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('8.1-TxCountMTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxCountMTD = ISNULL(IIF(@DailySP = @Param_MTDIndicator,0,L.TxCountMTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxCountMTD) TxCountMTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxCountMTD IS NOT NULL and DateHour >= @Param_MTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxCountMTD is null AND K.DateHour = @DailySP
PRINT ('8.2-TxCountMTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('9.1-TxVolumeMTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxVolumeMTD = ISNULL(IIF(@DailySP = @Param_MTDIndicator,0,L.TxVolumeMTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxVolumeMTD) TxVolumeMTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxVolumeMTD IS NOT NULL and DateHour >= @Param_MTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxVolumeMTD is null AND K.DateHour = @DailySP
PRINT ('9.2-TxVolumeMTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('10.1-UUQTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET UUQTD = ISNULL(IIF(@DailySP = @Param_QTDIndicator ,0,L.UUQTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(UUQTD) UUQTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND UUQTD IS NOT NULL and DateHour >= @Param_QTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.UUQTD is null AND K.DateHour = @DailySP
PRINT ('10.2-UUQTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('11.1-TxCountQTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxCountQTD = ISNULL(IIF(@DailySP = @Param_QTDIndicator ,0,L.TxCountQTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxCountQTD) TxCountQTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxCountQTD IS NOT NULL and DateHour >= @Param_QTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxCountQTD is null AND K.DateHour = @DailySP
PRINT ('11.2-TxCountQTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('12.1-TxVolumeQTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxVolumeQTD = ISNULL(IIF(@DailySP = @Param_QTDIndicator ,0,L.TxVolumeQTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxVolumeQTD) TxVolumeQTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxVolumeQTD IS NOT NULL and DateHour >= @Param_QTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxVolumeQTD is null AND K.DateHour = @DailySP
PRINT ('12.2-TxVolumeQTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('13.1-UUSemiYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '	  +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET UUSemiYTD = ISNULL(IIF(@DailySP = @Param_SemiYTDIndicator,0,L.UUSemiYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(UUSemiYTD) UUSemiYTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND UUSemiYTD IS NOT NULL and DateHour >= @Param_SemiYTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.UUSemiYTD is null AND K.DateHour = @DailySP
PRINT ('13.2-UUSemiYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT ('14.1-TxCountSemiYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxCountSemiYTD = ISNULL(IIF(@DailySP = @Param_SemiYTDIndicator,0,L.TxCountSemiYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxCountSemiYTD) TxCountSemiYTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxCountSemiYTD IS NOT NULL and DateHour >= @Param_SemiYTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxCountSemiYTD is null AND K.DateHour = @DailySP
PRINT ('14.2-TxCountSemiYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('15.1-TxVolumeSemiYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxVolumeSemiYTD = ISNULL(IIF(@DailySP = @Param_SemiYTDIndicator,0,L.TxVolumeSemiYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxVolumeSemiYTD) TxVolumeSemiYTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxVolumeSemiYTD IS NOT NULL and DateHour >= @Param_SemiYTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxVolumeSemiYTD is null AND K.DateHour = @DailySP
PRINT ('15.2-TxVolumeSemiYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('16.1-UUYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '			  +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET UUYTD = ISNULL(IIF(@DailySP = @Param_YTDIndicator,0,L.UUYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(UUYTD) UUYTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND UUYTD IS NOT NULL and DateHour >= @Param_YTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.UUYTD is null AND K.DateHour = @DailySP
PRINT ('16.2-UUYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT ('17.1-TxCountYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxCountYTD = ISNULL(IIF(@DailySP = @Param_YTDIndicator,0,L.TxCountYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxCountYTD) TxCountYTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxCountYTD IS NOT NULL and DateHour >= @Param_YTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxCountYTD is null AND K.DateHour = @DailySP
PRINT ('17.2-TxCountYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('18.1-TxVolumeYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxVolumeYTD = ISNULL(IIF(@DailySP = @Param_YTDIndicator,0,L.TxVolumeYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxVolumeYTD) TxVolumeYTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxVolumeYTD IS NOT NULL and DateHour >= @Param_YTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxVolumeYTD is null AND K.DateHour = @DailySP
PRINT ('18.2-TxVolumeYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('19.1-AvgAgeMTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '	  +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgAgeMTD = ISNULL(IIF(@DailySP = @Param_MTDIndicator,0,L.AvgAgeMTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgAgeMTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgAgeMTD IS NOT NULL and DateHour >= @Param_MTDIndicator
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgAgeMTD is null AND K.DateHour = @DailySP
PRINT ('19.2-AvgAgeMTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('20.1-AvgAgeQTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : ' +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgAgeQTD = ISNULL(IIF(@DailySP = @Param_QTDIndicator,0,L.AvgAgeQTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgAgeQTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgAgeQTD IS NOT NULL and DateHour >= @Param_QTDIndicator
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgAgeQTD is null AND K.DateHour = @DailySP
PRINT ('20.2-AvgAgeQTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '   +cast(@DailySP as varchar(30)))
PRINT ('21.1-AvgAgeSemiYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgAgeSemiYTD = ISNULL(IIF(@DailySP = @Param_SemiYTDIndicator,0,L.AvgAgeSemiYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgAgeSemiYTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgAgeSemiYTD IS NOT NULL and DateHour >= @Param_SemiYTDIndicator
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgAgeSemiYTD is null AND K.DateHour = @DailySP
PRINT ('21.2-AvgAgeSemiYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('22.1-AvgAgeYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '		+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgAgeYTD = ISNULL(IIF(@DailySP = @Param_YTDIndicator,0,L.AvgAgeYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgAgeYTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgAgeYTD IS NOT NULL and DateHour >= @Param_YTDIndicator
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgAgeYTD is null AND K.DateHour = @DailySP
PRINT ('22.2-AvgAgeYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '		+cast(@DailySP as varchar(30)))
PRINT ('23.1-AvgTenureByYearMTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgTenureByYearMTD = ISNULL(IIF(@DailySP = @Param_MTDIndicator,0,L.AvgTenureByYearMTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgTenureByYearMTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgTenureByYearMTD IS NOT NULL and DateHour >= @Param_MTDIndicator
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgTenureByYearMTD is null AND K.DateHour = @DailySP
PRINT ('23.2-AvgTenureByYearMTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('24.1-AvgTenureByYearQTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : ' +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgTenureByYearQTD = ISNULL(IIF(@DailySP = @Param_QTDIndicator,0,L.AvgTenureByYearQTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgTenureByYearQTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgTenureByYearQTD IS NOT NULL and DateHour >= @Param_QTDIndicator
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgTenureByYearQTD is null AND K.DateHour = @DailySP
PRINT ('24.2-AvgTenureByYearQTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT ('25.1-AvgTenureByYearSemiYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgTenureByYearSemiYTD = ISNULL(IIF(@DailySP = @Param_SemiYTDIndicator,0,L.AvgTenureByYearSemiYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgTenureByYearSemiYTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgTenureByYearSemiYTD IS NOT NULL and DateHour >= @Param_SemiYTDIndicator
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgTenureByYearSemiYTD is null AND K.DateHour = @DailySP
PRINT ('25.2-AvgTenureByYearSemiYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('26.1-AvgTenureByYearYTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgTenureByYearYTD = ISNULL(IIF(@DailySP = @Param_YTDIndicator,0,L.AvgTenureByYearYTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgTenureByYearYTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgTenureByYearYTD IS NOT NULL and DateHour >= @Param_YTDIndicator
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgTenureByYearYTD is null AND K.DateHour = @DailySP
PRINT ('26.2-AvgTenureByYearYTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
/*
PRINT ('27.1-AvgTenureByYear2MTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgTenureByYear2MTD = ISNULL(IIF(@DailySP = @Param_2MTDIndicator,0,L.AvgTenureByYear2MTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgTenureByYear2MTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgTenureByYear2MTD IS NOT NULL
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgTenureByYear2MTD is null AND K.DateHour = @DailySP
PRINT ('27.2-AvgTenureByYear2MTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('28.1-AvgAge2MTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET AvgAge2MTD = ISNULL(IIF(@DailySP = @Param_2MTDIndicator,0,L.AvgAge2MTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					select
						MaxDateHour,P.CompanyId,P.PaymentType,P.AvgAge2MTD
					from #ReadyToUpdateData P
					Join
						(
							SELECT MAX(DateHour) MaxDateHour,CompanyId/*,Product*/PaymentType /*,CustomerType*/
							FROM #ReadyToUpdateData
							WHERE DateHour < @DailySP AND AvgAge2MTD IS NOT NULL
							GROUP BY CompanyId/*,Product*/PaymentType
						) M ON M.MaxDateHour = P.DateHour AND M.PaymentType = P.PaymentType AND M.CompanyId = P.CompanyId
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.AvgAge2MTD is null AND K.DateHour = @DailySP
PRINT ('28.2-AvgAge2MTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('29.1-TxCount2MTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxCount2MTD = ISNULL(IIF(@DailySP = @Param_2MTDIndicator,0,L.TxCount2MTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxCount2MTD) TxCount2MTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxCount2MTD IS NOT NULL
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxCount2MTD is null AND K.DateHour = @DailySP
PRINT ('29.2-TxCount2MTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('30.1-TxVolume2MTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		UPDATE  K
			SET TxVolume2MTD = ISNULL(IIF(@DailySP = @Param_2MTDIndicator,0,L.TxVolume2MTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(TxVolume2MTD) TxVolume2MTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND TxVolume2MTD IS NOT NULL
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.TxVolume2MTD is null AND K.DateHour = @DailySP
PRINT ('30.2-TxVolume2MTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT ('31.1-UU2MTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '	   +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET UU2MTD = ISNULL(IIF(@DailySP = @Param_2MTDIndicator,0,L.UU2MTD),0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(UU2MTD) UU2MTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND UU2MTD IS NOT NULL
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.UU2MTD is null AND K.DateHour = @DailySP
PRINT ('31.2-UU2MTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
*/
PRINT ('27.1-UU2YTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '			  +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET UU2YTD = ISNULL(L.UU2YTD,0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(UU2YTD) UU2YTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND UU2YTD IS NOT NULL and DateHour >= @Param_2YTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.UU2YTD is null AND K.DateHour = @DailySP
PRINT ('27.2-UU2YTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT ('28.1-UU3YTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '			  +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET UU3YTD = ISNULL(L.UU3YTD,0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(UU3YTD) UU3YTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND UU3YTD IS NOT NULL and DateHour >= @Param_3YTDIndicator
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.UU3YTD is null AND K.DateHour = @DailySP
PRINT ('28.2-UU3YTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT ('29.1-UUFeatureLaunchedTD LOOP SETTINGS PREPARING - STARTED - FOR' + 'DailySP Date : '			  +cast(@DailySP as varchar(30)))
		UPDATE  K
			SET UUFeatureLaunchedTD = ISNULL(L.UUFeatureLaunchedTD,0)
		FROM  #ReadyToUpdateData K
		LEFT JOIN  (
					SELECT MAX(UUFeatureLaunchedTD) UUFeatureLaunchedTD,CompanyId/*,Product*/PaymentType /*,CustomerType*/
					FROM #ReadyToUpdateData
					WHERE DateHour < @DailySP AND UUFeatureLaunchedTD IS NOT NULL and DateHour >= @Param_FirstPaymentTxDate
					GROUP BY CompanyId/*,Product*/PaymentType
					) L
		ON K.CompanyId = L.CompanyId /*AND K.Product = L.Product*/ AND K.PaymentType = L.PaymentType /*AND K.CustomerType = L.CustomerType*/
		WHERE K.UUFeatureLaunchedTD is null AND K.DateHour = @DailySP
PRINT ('29.2-UUFeatureLaunchedTD LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT ('END - LOOP SETTINGS PREPARING - FINISHED - FOR' + 'DailySP Date : '		 +cast(@DailySP as varchar(30)))
PRINT('1A-UUMTD LOOPING STARTED!')
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UUMTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UUMTD = R2.UUMTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UUMTD is null AND R2.UUMTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @Param_MTDIndicator AND R2.DateHour < @BaseDay
		end
PRINT('1B-UUMTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT('2A-TxCountMTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxCountMTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxCountMTD = R2.TxCountMTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxCountMTD is null AND R2.TxCountMTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('2B-TxCountMTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('3A-TxVolumeMTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxVolumeMTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxVolumeMTD = R2.TxVolumeMTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxVolumeMTD is null AND R2.TxVolumeMTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('3B-TxVolumeMTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('4A-UUDTH LOOPING STARTED! - FOR' + 'DailySP Date : '		  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UUDTH IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UUDTH = R2.UUDTH   
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UUDTH is null AND R2.UUDTH IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		END
PRINT('4B-UUDTH LOOPING FINISHED! - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT('5A-TxCountDTH LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxCountDTH IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxCountDTH = R2.TxCountDTH    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxCountDTH is null AND R2.TxCountDTH IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('5B-TxCountDTH LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('6A-TxVolumeDTH LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxVolumeDTH IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxVolumeDTH = R2.TxVolumeDTH   
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxVolumeDTH is null AND R2.TxVolumeDTH IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('7B-TxVolumeDTH LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('8A-UUQTD LOOPING STARTED! - FOR' + 'DailySP Date : '		  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UUQTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UUQTD = R2.UUQTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UUQTD is null AND R2.UUQTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('8B-UUQTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
PRINT('9A-TxVolumeQTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxVolumeQTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxVolumeQTD = R2.TxVolumeQTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxVolumeQTD is null AND R2.TxVolumeQTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('9B-TxVolumeQTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('10A-UUSemiYTD LOOPING STARTED! - FOR' + 'DailySP Date : '  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UUSemiYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UUSemiYTD = R2.UUSemiYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UUSemiYTD is null AND R2.UUSemiYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('10B-UUSemiYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
PRINT('11A-TxCountSemiYTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxCountSemiYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxCountSemiYTD = R2.TxCountSemiYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxCountSemiYTD is null AND R2.TxCountSemiYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('11B-TxCountSemiYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('12A-TxVolumeSemiYTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxVolumeSemiYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxVolumeSemiYTD = R2.TxVolumeSemiYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxVolumeSemiYTD is null AND R2.TxVolumeSemiYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('12B-TxVolumeSemiYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('13A-UUYTD LOOPING STARTED! - FOR' + 'DailySP Date : '		   +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UUYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UUYTD = R2.UUYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UUYTD is null AND R2.UUYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('13B-UUYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
PRINT('14A-TxCountYTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxCountYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxCountYTD = R2.TxCountYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxCountYTD is null AND R2.TxCountYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('13B-TxCountYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('14A-TxVolumeYTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxVolumeYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxVolumeYTD = R2.TxVolumeYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxVolumeYTD is null AND R2.TxVolumeYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('13B-TxVolumeYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('14A-TxCountQTD LOOPING STARTED! - FOR' + 'DailySP Date : '  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxCountQTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxCountQTD = R2.TxCountQTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxCountQTD is null AND R2.TxCountQTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('14B-TxCountQTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('15A-AvgAgeDTH LOOPING STARTED! - FOR' + 'DailySP Date : '  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgAgeDTH IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgAgeDTH = R2.AvgAgeDTH   
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgAgeDTH is null AND R2.AvgAgeDTH IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		END
PRINT('15B-AvgAgeDTH LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('16A-AvgAgeMTD LOOPING STARTED! - FOR' + 'DailySP Date : ' +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgAgeMTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgAgeMTD = R2.AvgAgeMTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgAgeMTD is null AND R2.AvgAgeMTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @Param_MTDIndicator AND R2.DateHour < @BaseDay
		end
PRINT('16B-AvgAgeMTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('17A-AvgAgeQTD LOOPING STARTED! - FOR' + 'DailySP Date : ' +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgAgeQTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgAgeQTD = R2.AvgAgeQTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgAgeQTD is null AND R2.AvgAgeQTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('17B-AvgAgeQTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	+cast(@DailySP as varchar(30)))
PRINT('18A-AvgAgeSemiYTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgAgeSemiYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgAgeSemiYTD = R2.AvgAgeSemiYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgAgeSemiYTD is null AND R2.AvgAgeSemiYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('18B-AvgAgeSemiYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('19A-AvgAgeYTD LOOPING STARTED! - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgAgeYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgAgeYTD = R2.AvgAgeYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgAgeYTD is null AND R2.AvgAgeYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('19B-AvgAgeYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '		 +cast(@DailySP as varchar(30)))
PRINT('20A-AvgTenureByYearDTH LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgTenureByYearDTH IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgTenureByYearDTH = R2.AvgTenureByYearDTH   
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgTenureByYearDTH is null AND R2.AvgTenureByYearDTH IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		END
PRINT('20B-AvgTenureByYearDTH LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('21A-AvgTenureByYearMTD LOOPING STARTED! - FOR' + 'DailySP Date : ' +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgTenureByYearMTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgTenureByYearMTD = R2.AvgTenureByYearMTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgTenureByYearMTD is null AND R2.AvgTenureByYearMTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @Param_MTDIndicator AND R2.DateHour < @BaseDay
		end
PRINT('22B-AvgTenureByYearMTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('23A-AvgTenureByYearQTD LOOPING STARTED! - FOR' + 'DailySP Date : ' +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgTenureByYearQTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgTenureByYearQTD = R2.AvgTenureByYearQTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgTenureByYearQTD is null AND R2.AvgTenureByYearQTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('24B-AvgTenureByYearQTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
PRINT('25A-AvgTenureByYearSemiYTD LOOPING STARTED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgTenureByYearSemiYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgTenureByYearSemiYTD = R2.AvgTenureByYearSemiYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgTenureByYearSemiYTD is null AND R2.AvgTenureByYearSemiYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('25B-AvgTenureByYearSemiYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)))
PRINT('26A-AvgTenureByYearYTD LOOPING STARTED! - FOR' + 'DailySP Date : '	  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgTenureByYearYTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgTenureByYearYTD = R2.AvgTenureByYearYTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgTenureByYearYTD is null AND R2.AvgTenureByYearYTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('26B-AvgTenureByYearYTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)) + ' AND FOR BaseDay : ' +cast(@BaseDay as varchar(30)))
PRINT('27A-UU2YTD LOOPING STARTED! - FOR' + 'DailySP Date : '		   +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UU2YTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UU2YTD = R2.UU2YTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UU2YTD is null AND R2.UU2YTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('27B-UU2YTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
PRINT('28A-UU3YTD LOOPING STARTED! - FOR' + 'DailySP Date : '		   +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UU3YTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UU3YTD = R2.UU3YTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UU3YTD is null AND R2.UU3YTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('28B-UU3YTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
PRINT('29A-UUFeatureLaunchedTD LOOPING STARTED! - FOR' + 'DailySP Date : '		   +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UUFeatureLaunchedTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UUFeatureLaunchedTD = R2.UUFeatureLaunchedTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UUFeatureLaunchedTD is null AND R2.UUFeatureLaunchedTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('29B-UUFeatureLaunchedTD LOOPING FINISHED! - FOR' + 'DailySP Date : '	 +cast(@DailySP as varchar(30)))
/*
PRINT('27A-AvgAge2MTD LOOPING STARTED! - FOR' + 'DailySP Date : '	  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgAge2MTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgAge2MTD = R2.AvgAge2MTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgAge2MTD is null AND R2.AvgAge2MTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('27B-AvgAge2MTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)) + ' AND FOR BaseDay : ' +cast(@BaseDay as varchar(30)))
--INSERT INTO DWH_Workspace.[\skacar].[FACT_PaymentTransactionsByCompaniesToDateCubeV2]
select*from #ReadyToUpdateData where DateHour >= @DailySP and DateHour < @BaseDay 
PRINT('28A-AvgTenureByYear2MTD LOOPING STARTED! - FOR' + 'DailySP Date : '	  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE AvgTenureByYear2MTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.AvgTenureByYear2MTD = R2.AvgTenureByYear2MTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.AvgTenureByYear2MTD is null AND R2.AvgTenureByYear2MTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('28B-AvgTenureByYear2MTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)) + ' AND FOR BaseDay : ' +cast(@BaseDay as varchar(30)))
PRINT('29A-TxCount2MTD LOOPING STARTED! - FOR' + 'DailySP Date : '	  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxCount2MTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxCount2MTD = R2.TxCount2MTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxCount2MTD is null AND R2.TxCount2MTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('29B-TxCount2MTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)) + ' AND FOR BaseDay : ' +cast(@BaseDay as varchar(30)))
PRINT('30A-TxVolume2MTD LOOPING STARTED! - FOR' + 'DailySP Date : '	  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE TxVolume2MTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.TxVolume2MTD = R2.TxVolume2MTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.TxVolume2MTD is null AND R2.TxVolume2MTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('30B-TxVolume2MTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)) + ' AND FOR BaseDay : ' +cast(@BaseDay as varchar(30)))
PRINT('31A-UU2MTD LOOPING STARTED! - FOR' + 'DailySP Date : '	  +cast(@DailySP as varchar(30)))
		WHILE (SELECT COUNT(DateHour) FROM  #ReadyToUpdateData WHERE UU2MTD IS NULL AND DateHour >= @DailySP AND DateHour < @BaseDay) != 0
		BEGIN
		UPDATE R1
		set R1.UU2MTD = R2.UU2MTD    
		from  #ReadyToUpdateData R1
		join  #ReadyToUpdateData R2 on dateadd(HOUR,1,R2.DateHour) = R1.DateHour AND R1.CompanyId = R2.CompanyId AND /*R1.Product = R2.Product AND*/ R1.PaymentType = R2.PaymentType /*AND R1.CustomerType = R2.CustomerType*/
		where  R1.UU2MTD is null AND R2.UU2MTD IS NOT NULL and R1.DateHour >= @DailySP AND R1.DateHour < @BaseDay and R2.DateHour >= @DailySP AND R2.DateHour < @BaseDay
		end
PRINT('31B-UU2MTD LOOPING FINISHED! - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)) + ' AND FOR BaseDay : ' +cast(@BaseDay as varchar(30)))
*/

/*FINAL CALCULATIONS*/
PRINT('FINAL CALCULATIONS - FOR' + 'DailySP Date : '+cast(@DailySP as varchar(30)) + ' AND FOR BaseDay : ' +cast(@BaseDay as varchar(30)))
;
WITH  MonthVsParticipatedQTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUQTD) PreviousUUQTDBeforeMonth
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_MTDIndicator AND DATEPART(q,DateHour) = DATEPART(q,@Param_QTDIndicator)
							GROUP BY PaymentType,CompanyId
						)
	, MonthVsParticipatedSemiYTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUSemiYTD) PreviousUUSemiYTDBeforeMonth
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_MTDIndicator AND DATEFROMPARTS(YEAR(DateHour),(((MONTH(DateHour))-1)/6)*6+1,1) = @Param_SemiYTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, MonthVsParticipatedYTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUYTD) PreviousUUYTDBeforeMonth
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_MTDIndicator AND YEAR(DateHour) = YEAR(@Param_YTDIndicator)
							GROUP BY PaymentType,CompanyId
						)
	,  QuarterVsParticipatedSemiYTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUSemiYTD) PreviousUUSemiYTDBeforeQuarter
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_QTDIndicator AND DATEFROMPARTS(YEAR(DateHour),(((MONTH(DateHour))-1)/6)*6+1,1) = @Param_SemiYTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, QuarterVsParticipatedYTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUYTD) PreviousUUYTDBeforeQuarter
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_QTDIndicator AND YEAR(DateHour) = YEAR(@Param_SemiYTDIndicator)
							GROUP BY PaymentType,CompanyId
						)
	, SemiYTDVsParticipatedYTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUYTD) PreviousUUYTDBeforeSemiYTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_SemiYTDIndicator AND YEAR(DateHour) = YEAR(@Param_SemiYTDIndicator)
							GROUP BY PaymentType,CompanyId
						)
	, MonthVsParticipated2YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU2YTD) PreviousUU2YTDBeforeMonth
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_MTDIndicator AND DateHour >= @Param_2YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, QuarterVsParticipated2YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU2YTD) PreviousUU2YTDBeforeQuarter
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_QTDIndicator AND DateHour >= @Param_2YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, SemiYTDVsParticipated2YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU2YTD) PreviousUU2YTDBeforeSemiYTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_SemiYTDIndicator AND DateHour >= @Param_2YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, YTDVsParticipated2YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU2YTD) PreviousUU2YTDBeforeYTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_YTDIndicator AND DateHour >= @Param_2YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, MonthVsParticipated3YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU3YTD) PreviousUU3YTDBeforeMonth
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_MTDIndicator AND DateHour >= @Param_3YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, QuarterVsParticipated3YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU3YTD) PreviousUU3YTDBeforeQuarter
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_QTDIndicator AND DateHour >= @Param_3YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, SemiYTDVsParticipated3YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU3YTD) PreviousUU3YTDBeforeSemiYTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_SemiYTDIndicator AND DateHour >= @Param_3YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, YTDVsParticipated3YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU3YTD) PreviousUU3YTDBeforeYTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_YTDIndicator AND DateHour >= @Param_3YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, YTD2VsParticipated3YTDPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UU3YTD) PreviousUU3YTD2YTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_2YTDIndicator AND DateHour >= @Param_3YTDIndicator
							GROUP BY PaymentType,CompanyId
						)
	, MonthVsParticipatedFeatureLaunchedPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUFeatureLaunchedTD) PreviousUUFeatureLaunchedTDBeforeMonth
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_MTDIndicator AND DateHour >= @Param_FirstPaymentTxDate
							GROUP BY PaymentType,CompanyId
						)
	, QuarterVsParticipatedFeatureLaunchedPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUFeatureLaunchedTD) PreviousUUFeatureLaunchedTDBeforeQuarter
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_QTDIndicator AND DateHour >= @Param_FirstPaymentTxDate
							GROUP BY PaymentType,CompanyId
						)
	, SemiYTDVsParticipatedFeatureLaunchedPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUFeatureLaunchedTD) PreviousUUFeatureLaunchedTDBeforeSemiYTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_SemiYTDIndicator AND DateHour >= @Param_FirstPaymentTxDate
							GROUP BY PaymentType,CompanyId
						)
	, YTDVsParticipatedFeatureLaunchedPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUFeatureLaunchedTD) PreviousUUFeatureLaunchedTDBeforeYTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_YTDIndicator AND DateHour >= @Param_FirstPaymentTxDate
							GROUP BY PaymentType,CompanyId
						)
	, YTD2VsParticipatedFeatureLaunchedPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUFeatureLaunchedTD) PreviousUUFeatureLaunchedTD2YTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_2YTDIndicator AND DateHour >= @Param_FirstPaymentTxDate
							GROUP BY PaymentType,CompanyId
						)
	, YTD3VsParticipatedFeatureLaunchedPreviousNumber_CTE AS
						(
							SELECT
								 PaymentType
								,CompanyId
								,max(UUFeatureLaunchedTD) PreviousUUFeatureLaunchedTD3YTD
								,1 JoinMeColumn
							FROM #ReadyToUpdateData
							WHERE DateHour < @Param_3YTDIndicator AND DateHour >= @Param_FirstPaymentTxDate
							GROUP BY PaymentType,CompanyId
						)
	, ReadyToUpdateDataToAnalyzingData AS
	(
		SELECT 1 JoinMeColumn,*from #ReadyToUpdateData where DateHour >= @DailySP and DateHour < @BaseDay
	)
	INSERT INTO DWH_Workspace.[\skacar].[FACT_PaymentTransactionsByCompaniesToDateCubeV2]
	SELECT
		  A1.DateHour
		 ,A1.PaymentType
		 ,A1.CompanyId
		 ,A1.UUHourly
		 ,A1.TxCountHourly
		 ,A1.TxVolumeHourly
		 ,A1.UUDTH
		 ,A1.TxCountDTH
		 ,A1.TxVolumeDTH
		 ,A1.AvgAgeHourly
		 ,A1.AvgTenureByYearHourly
		 ,A1.UUMTD
		 ,A1.TxCountMTD
		 ,A1.TxVolumeMTD
		 ,A1.TxCountQTD
		 ,A1.TxVolumeQTD
		 ,A1.TxCountSemiYTD
		 ,A1.TxVolumeSemiYTD
		 ,A1.TxCountYTD
		 ,A1.TxVolumeYTD
		 ,A1.UUYTD
		 ,A1.UUSemiYTD
		 ,A1.UUQTD
		 ,A1.AvgAgeDTH
		 ,A1.AvgAgeMTD
		 ,A1.AvgAgeQTD
		 ,A1.AvgAgeSemiYTD
		 ,A1.AvgAgeYTD
		 ,A1.AvgTenureByYearDTH
		 ,A1.AvgTenureByYearMTD
		 ,A1.AvgTenureByYearQTD
		 ,A1.AvgTenureByYearSemiYTD
		 ,A1.AvgTenureByYearYTD
		 ,A1.UUQTD     - PreviousUUQTDBeforeMonth		 [HourlyContributerUUThisMonthToTheQuarter]
		 ,A1.UUSemiYTD - PreviousUUSemiYTDBeforeMonth		 [HourlyContributerUUThisMonthToTheSemiYear]
		 ,A1.UUYTD     - PreviousUUYTDBeforeMonth		 [HourlyContributerUUThisMonthToTheYear]
		 ,A1.UUSemiYTD - PreviousUUSemiYTDBeforeQuarter	 	 [HourlyContributerUUThisQuarterToTheSemiYear]
		 ,A1.UUYTD     - PreviousUUYTDBeforeQuarter		 [HourlyContributerUUThisQuarterToTheYear]
		 ,A1.UUYTD     - PreviousUUYTDBeforeSemiYTD		 [HourlyContributerUUThisSemiYTDToTheYear]
		 ,UU2YTD
		 ,UU3YTD
		 ,UUFeatureLaunchedTD
		 ,UU2YTD - PreviousUU2YTDBeforeMonth						 [HourlyContributerUUThisMonthToThe2YTD]
		 ,UU2YTD - PreviousUU2YTDBeforeQuarter						 [HourlyContributerUUThisQuarterToThe2YTD]
		 ,UU2YTD - PreviousUU2YTDBeforeSemiYTD						 [HourlyContributerUUThisSemiYTDToThe2YTD]
		 ,UU2YTD - PreviousUU2YTDBeforeYTD						 [HourlyContributerUUThisYTDToThe2YTD]
		 ,UU3YTD - PreviousUU3YTDBeforeMonth						 [HourlyContributerUUThisMonthToThe3YTD]
		 ,UU3YTD - PreviousUU3YTDBeforeQuarter						 [HourlyContributerUUThisQuarterToThe3YTD]
		 ,UU3YTD - PreviousUU3YTDBeforeSemiYTD						 [HourlyContributerUUThisSemiYTDToThe3YTD]
		 ,UU3YTD - PreviousUU3YTDBeforeYTD						 [HourlyContributerUUThisYTDToThe3YTD]
		 ,UU3YTD - PreviousUU3YTD2YTD							 [HourlyContributerUUThis2YTDToThe3YTD]
		 ,UUFeatureLaunchedTD - PreviousUUFeatureLaunchedTDBeforeMonth			 [HourlyContributerUUThisMonthToTheUUFeatureLaunchedTD]
		 ,UUFeatureLaunchedTD - PreviousUUFeatureLaunchedTDBeforeQuarter		 [HourlyContributerUUThisQuarterToTheUUFeatureLaunchedTD]
		 ,UUFeatureLaunchedTD - PreviousUUFeatureLaunchedTDBeforeSemiYTD		 [HourlyContributerUUThisSemiYTDToTheUUFeatureLaunchedTD]
		 ,UUFeatureLaunchedTD - PreviousUUFeatureLaunchedTDBeforeYTD			 [HourlyContributerUUThisYTDToTheUUFeatureLaunchedTD]
		 ,UUFeatureLaunchedTD - PreviousUUFeatureLaunchedTD2YTD				 [HourlyContributerUUThis2YTDToTheUUFeatureLaunchedTD]
		 ,UUFeatureLaunchedTD - PreviousUUFeatureLaunchedTD3YTD				 [HourlyContributerUUThis3YTDToTheUUFeatureLaunchedTD]
		,	ISNULL(UUMTD - A1.UUQTD	    + PreviousUUQTDBeforeMonth      ,NULL) [HourlyRetainedUUThisMonthWithinTheQuarter]
		,	ISNULL(UUMTD - A1.UUSemiYTD + PreviousUUSemiYTDBeforeMonth  ,NULL) [HourlyRetainedUUThisMonthWithinTheSemiYear]
		,	ISNULL(UUMTD - A1.UUYTD	    + PreviousUUYTDBeforeMonth      ,NULL) [HourlyRetainedUUThisMonthWithinTheYear]
		,	ISNULL(UUQTD - A1.UUSemiYTD + PreviousUUSemiYTDBeforeQuarter,NULL) [HourlyRetainedUUThisQuarterWithinTheSemiYear]
		,	ISNULL(UUQTD - A1.UUYTD	    + PreviousUUYTDBeforeQuarter    ,NULL) [HourlyRetainedUUThisQuarterWithinTheYear]
		,	ISNULL(UUSemiYTD - A1.UUYTD + PreviousUUYTDBeforeSemiYTD    ,NULL) [HourlyRetainedUUThisSemiYearWithinTheYear]
		,COALESCE((UUMTD - A1.UUQTD	+ PreviousUUQTDBeforeMonth	) * 1.0 / NULLIF(PreviousUUQTDBeforeMonth	,0),0) [HourlyRetentionRateThisMonthWithinTheQuarter]
		,COALESCE((UUMTD - A1.UUSemiYTD + PreviousUUSemiYTDBeforeMonth  ) * 1.0 / NULLIF(PreviousUUSemiYTDBeforeMonth	,0),0) [HourlyRetentionRateThisMonthWithinTheSemiYear]
		,COALESCE((UUMTD - A1.UUYTD	+ PreviousUUYTDBeforeMonth	) * 1.0 / NULLIF(PreviousUUYTDBeforeMonth	,0),0) [HourlyRetentionRateThisMonthWithinTheYear]
		,COALESCE((UUQTD - A1.UUSemiYTD + PreviousUUSemiYTDBeforeQuarter) * 1.0 / NULLIF(PreviousUUSemiYTDBeforeQuarter	,0),0) [HourlyRetentionRateThisQuarterWithinTheSemiYear]
		,COALESCE((UUQTD - A1.UUYTD	+ PreviousUUYTDBeforeQuarter	) * 1.0 / NULLIF(PreviousUUYTDBeforeQuarter	,0),0) [HourlyRetentionRateThisQuarterWithinTheYear]
		,COALESCE((UUSemiYTD - A1.UUYTD	+ PreviousUUYTDBeforeSemiYTD	) * 1.0 / NULLIF(PreviousUUYTDBeforeSemiYTD	,0),0) [HourlyRetentionRateThisSemiYTDWithinTheYear]
		,	ISNULL(UUMTD	   - UU2YTD			     + PreviousUU2YTDBeforeMonth				,NULL) [HourlyRetainUUThisMonthToThe2YTD]
		,	ISNULL(UUQTD	   - UU2YTD			     + PreviousUU2YTDBeforeQuarter				,NULL) [HourlyRetainUUThisQuarterToThe2YTD]
		,	ISNULL(UUSemiYTD   - UU2YTD			     + PreviousUU2YTDBeforeSemiYTD				,NULL) [HourlyRetainUUThisSemiYTDToThe2YTD]
		,	ISNULL(UUYTD	   - UU2YTD			     + PreviousUU2YTDBeforeYTD	 				,NULL) [HourlyRetainUUThisYTDToThe2YTD]
		,	ISNULL(UUMTD	   - UU3YTD			     + PreviousUU3YTDBeforeMonth	 			,NULL) [HourlyRetainUUThisMonthToThe3YTD]
		,	ISNULL(UUQTD	   - UU3YTD			     + PreviousUU3YTDBeforeQuarter				,NULL) [HourlyRetainUUThisQuarterToThe3YTD]
		,	ISNULL(UUSemiYTD   - UU3YTD			     + PreviousUU3YTDBeforeSemiYTD				,NULL) [HourlyRetainUUThisSemiYTDToThe3YTD]
		,	ISNULL(UUYTD	   - UU3YTD			     + PreviousUU3YTDBeforeYTD	 				,NULL) [HourlyRetainUUThisYTDToThe3YTD]
		,	ISNULL(UU3YTD	   - UU3YTD			     + PreviousUU3YTD2YTD		 			,NULL) [HourlyRetainUUThis2YTDToThe3YTD]
		,	ISNULL(UUMTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTDBeforeMonth   ,NULL) [HourlyRetainUUThisMonthToTheUUFeatureLaunchedTD]
		,	ISNULL(UUQTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTDBeforeQuarter ,NULL) [HourlyRetainUUThisQuarterToTheUUFeatureLaunchedTD]
		,	ISNULL(UUSemiYTD   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTDBeforeSemiYTD ,NULL) [HourlyRetainUUThisSemiYTDToTheUUFeatureLaunchedTD]
		,	ISNULL(UUYTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTDBeforeYTD	    ,NULL) [HourlyRetainUUThisYTDToTheUUFeatureLaunchedTD]
		,	ISNULL(UU3YTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTD2YTD	    ,NULL) [HourlyRetainUUThis2YTDToTheUUFeatureLaunchedTD]
		,	ISNULL(UU3YTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTD3YTD	    ,NULL) [HourlyRetainUUThis3YTDToTheUUFeatureLaunchedTD]
		,COALESCE((UUMTD	   - UU2YTD			     + PreviousUU2YTDBeforeMonth				) * 1.0 / NULLIF(PreviousUU2YTDBeforeMonth		,0),0)	[HourlyRetentionRateThisMonthToThe2YTD]			
		,COALESCE((UUQTD	   - UU2YTD			     + PreviousUU2YTDBeforeQuarter				) * 1.0 / NULLIF(PreviousUU2YTDBeforeQuarter		,0),0)	[HourlyRetentionRateThisQuarterToThe2YTD]
		,COALESCE((UUSemiYTD   	   - UU2YTD			     + PreviousUU2YTDBeforeSemiYTD				) * 1.0 / NULLIF(PreviousUU2YTDBeforeSemiYTD		,0),0)	[HourlyRetentionRateThisSemiYTDToThe2YTD]
		,COALESCE((UUYTD	   - UU2YTD			     + PreviousUU2YTDBeforeYTD	 				) * 1.0 / NULLIF(PreviousUU2YTDBeforeYTD	 	,0),0)	[HourlyRetentionRateThisYTDToThe2YTD]
		,COALESCE((UUMTD	   - UU3YTD			     + PreviousUU3YTDBeforeMonth	 			) * 1.0 / NULLIF(PreviousUU3YTDBeforeMonth	 	,0),0)	[HourlyRetentionRateThisMonthToThe3YTD]
		,COALESCE((UUQTD	   - UU3YTD			     + PreviousUU3YTDBeforeQuarter				) * 1.0 / NULLIF(PreviousUU3YTDBeforeQuarter		,0),0)	[HourlyRetentionRateThisQuarterToThe3YTD]
		,COALESCE((UUSemiYTD       - UU3YTD			     + PreviousUU3YTDBeforeSemiYTD				) * 1.0 / NULLIF(PreviousUU3YTDBeforeSemiYTD		,0),0)	[HourlyRetentionRateThisSemiYTDToThe3YTD]
		,COALESCE((UUYTD	   - UU3YTD			     + PreviousUU3YTDBeforeYTD	 				) * 1.0 / NULLIF(PreviousUU3YTDBeforeYTD	 	,0),0)	[HourlyRetentionRateThisYTDToThe3YTD]
		,COALESCE((UU2YTD	   - UU3YTD			     + PreviousUU3YTD2YTD		 			) * 1.0 / NULLIF(PreviousUU3YTD2YTD		 					,0),0)	[HourlyRetentionRateThis2YTDToThe3YTD]
		,COALESCE((UUMTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTDBeforeMonth   ) * 1.0 / NULLIF(PreviousUUFeatureLaunchedTDBeforeMonth   ,0),0)	[HourlyRetentionRateThisMonthToTheUUFeatureLaunchedTD]
		,COALESCE((UUQTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTDBeforeQuarter ) * 1.0 / NULLIF(PreviousUUFeatureLaunchedTDBeforeQuarter ,0),0)	[HourlyRetentionRateThisQuarterToTheUUFeatureLaunchedTD]
		,COALESCE((UUSemiYTD   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTDBeforeSemiYTD	    ) * 1.0 / NULLIF(PreviousUUFeatureLaunchedTDBeforeSemiYTD ,0),0)	[HourlyRetentionRateThisSemiYTDToTheUUFeatureLaunchedTD]
		,COALESCE((UUYTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTDBeforeYTD	    ) * 1.0 / NULLIF(PreviousUUFeatureLaunchedTDBeforeYTD     ,0),0)	[HourlyRetentionRateThisYTDToTheUUFeatureLaunchedTD]
		,COALESCE((UU2YTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTD2YTD	    ) * 1.0 / NULLIF(PreviousUUFeatureLaunchedTD2YTD          ,0),0)	[HourlyRetentionRateThis2YTDToTheUUFeatureLaunchedTD]
		,COALESCE((UU3YTD	   - UUFeatureLaunchedTD + PreviousUUFeatureLaunchedTD3YTD	    ) * 1.0 / NULLIF(PreviousUUFeatureLaunchedTD3YTD 	      ,0),0)	[HourlyRetentionRateThis3YTDToTheUUFeatureLaunchedTD]
	FROM ReadyToUpdateDataToAnalyzingData				  A1
	LEFT JOIN MonthVsParticipatedQTDPreviousNumber_CTE		  B1 ON A1.JoinMeColumn =  B1.JoinMeColumn AND A1.PaymentType = B1.PaymentType  AND A1.CompanyId = B1.CompanyId
	LEFT JOIN MonthVsParticipatedSemiYTDPreviousNumber_CTE		  B2 ON A1.JoinMeColumn =  B2.JoinMeColumn AND A1.PaymentType = B2.PaymentType  AND A1.CompanyId = B2.CompanyId
	LEFT JOIN MonthVsParticipatedYTDPreviousNumber_CTE		  B3 ON A1.JoinMeColumn =  B3.JoinMeColumn AND A1.PaymentType = B3.PaymentType  AND A1.CompanyId = B3.CompanyId
	LEFT JOIN QuarterVsParticipatedSemiYTDPreviousNumber_CTE	  B4 ON A1.JoinMeColumn =  B4.JoinMeColumn AND A1.PaymentType = B4.PaymentType  AND A1.CompanyId = B4.CompanyId
	LEFT JOIN QuarterVsParticipatedYTDPreviousNumber_CTE		  B5 ON A1.JoinMeColumn =  B5.JoinMeColumn AND A1.PaymentType = B5.PaymentType  AND A1.CompanyId = B5.CompanyId
	LEFT JOIN SemiYTDVsParticipatedYTDPreviousNumber_CTE		  B6 ON A1.JoinMeColumn =  B6.JoinMeColumn AND A1.PaymentType = B6.PaymentType  AND A1.CompanyId = B6.CompanyId
	LEFT JOIN MonthVsParticipated2YTDPreviousNumber_CTE		  B7 ON A1.JoinMeColumn =  B7.JoinMeColumn AND A1.PaymentType = B7.PaymentType  AND A1.CompanyId = B7.CompanyId
	LEFT JOIN QuarterVsParticipated2YTDPreviousNumber_CTE 		  B8 ON A1.JoinMeColumn =  B8.JoinMeColumn AND A1.PaymentType = B8.PaymentType  AND A1.CompanyId = B8.CompanyId
	LEFT JOIN SemiYTDVsParticipated2YTDPreviousNumber_CTE 		  B9 ON A1.JoinMeColumn =  B9.JoinMeColumn AND A1.PaymentType = B9.PaymentType  AND A1.CompanyId = B9.CompanyId
	LEFT JOIN YTDVsParticipated2YTDPreviousNumber_CTE		 B10 ON A1.JoinMeColumn = B10.JoinMeColumn AND A1.PaymentType = B10.PaymentType AND A1.CompanyId = B10.CompanyId
	LEFT JOIN MonthVsParticipated3YTDPreviousNumber_CTE 		 B11 ON A1.JoinMeColumn = B11.JoinMeColumn AND A1.PaymentType = B11.PaymentType AND A1.CompanyId = B11.CompanyId
	LEFT JOIN QuarterVsParticipated3YTDPreviousNumber_CTE 		 B12 ON A1.JoinMeColumn = B12.JoinMeColumn AND A1.PaymentType = B12.PaymentType AND A1.CompanyId = B12.CompanyId
	LEFT JOIN SemiYTDVsParticipated3YTDPreviousNumber_CTE 		 B13 ON A1.JoinMeColumn = B13.JoinMeColumn AND A1.PaymentType = B13.PaymentType AND A1.CompanyId = B13.CompanyId
	LEFT JOIN YTDVsParticipated3YTDPreviousNumber_CTE 		 B14 ON A1.JoinMeColumn = B14.JoinMeColumn AND A1.PaymentType = B14.PaymentType AND A1.CompanyId = B14.CompanyId
	LEFT JOIN YTD2VsParticipated3YTDPreviousNumber_CTE 		 B15 ON A1.JoinMeColumn = B15.JoinMeColumn AND A1.PaymentType = B15.PaymentType AND A1.CompanyId = B15.CompanyId
	LEFT JOIN MonthVsParticipatedFeatureLaunchedPreviousNumber_CTE 	 B16 ON A1.JoinMeColumn = B16.JoinMeColumn AND A1.PaymentType = B16.PaymentType AND A1.CompanyId = B16.CompanyId
	LEFT JOIN QuarterVsParticipatedFeatureLaunchedPreviousNumber_CTE B17 ON A1.JoinMeColumn = B17.JoinMeColumn AND A1.PaymentType = B17.PaymentType AND A1.CompanyId = B17.CompanyId
	LEFT JOIN SemiYTDVsParticipatedFeatureLaunchedPreviousNumber_CTE B18 ON A1.JoinMeColumn = B18.JoinMeColumn AND A1.PaymentType = B18.PaymentType AND A1.CompanyId = B18.CompanyId
	LEFT JOIN YTDVsParticipatedFeatureLaunchedPreviousNumber_CTE 	 B19 ON A1.JoinMeColumn = B19.JoinMeColumn AND A1.PaymentType = B19.PaymentType AND A1.CompanyId = B19.CompanyId
	LEFT JOIN YTD2VsParticipatedFeatureLaunchedPreviousNumber_CTE 	 B20 ON A1.JoinMeColumn = B20.JoinMeColumn AND A1.PaymentType = B20.PaymentType AND A1.CompanyId = B20.CompanyId
	LEFT JOIN YTD3VsParticipatedFeatureLaunchedPreviousNumber_CTE 	 B21 ON A1.JoinMeColumn = B21.JoinMeColumn AND A1.PaymentType = B21.PaymentType AND A1.CompanyId = B21.CompanyId
	WHERE DateHour >= @DailySP
