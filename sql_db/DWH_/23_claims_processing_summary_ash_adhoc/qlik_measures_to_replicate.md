## datetime
Max(update_datetime)

## Total Claims in the Bucket
Count({<Date=,[Bucket Claims] = {'Bucket claims'},[Bucket Type] = {'Hospital'}>}distinct[Claim ID])
+
Count({<Date=,[Bucket Claims] = {'Bucket claims'},[Bucket Type] = {'General'}>}distinct[Claim ID])
+
Count({<Date=,MaxStatus={"Received","Received and Checked"},[Bucket Type] = {'Medical'}>}distinct[Claim ID])

## Medical Claims in the Bucket
Count({<Date=,MaxStatus={"Received","Received and Checked"},[Bucket Type] = {'Medical'}>}distinct[Claim ID])

## Hospital Claims in the Bucket
Count({<Date=,[Bucket Claims] = {'Bucket claims'},[Bucket Type] = {'Hospital'}>}distinct[Claim ID])

## General Claims in the Bucket
Count({<Date=,[Bucket Claims] = {'Bucket claims'},[Bucket Type] = {'General'}>}distinct[Claim ID])

## Date1
min({<Date=,MaxStatus={"*Received*"},[Bucket Type] = {'Medical'}>}[Date])

## Date2
min({<Date=,MaxStatus = {'Received and Logged'},[Bucket Claims] = {'Bucket claims'},[Bucket Type] = {'Hospital'}>}[Date])

## Date3
min({<Date=,MaxStatus = {'Received and Logged'},[Bucket Claims] = {'Bucket claims'},[Bucket Type] = {'General'}>}[Date])

## Avg Days Til Verified (Medical)
Avg({<Date=,claim_type = {'Medical'}>}[Days to Verify Claim])

## Avg Days Til Verified (Hospital)
Avg({<Date=,claim_type = {'Hospital'}>}[Days to Verify Claim])

## Avg Days Til Verified (General)
Avg({<Date=,claim_type = {'General'}>}[Days to Verify Claim])

## Claims Added to Bucket - Medical
=count({<Status=-{"*Paid*","*Cancelled*","*Verified*","*Assessed but not Verified*","*Till Verify*","Quot*"},[Bucket Type] = {'Medical'}>}distinct [Claim ID])

## Claims Added to Bucket - Hospital
Count({<Status = {'Received and Logged'}, [Bucket Type] = {'Hospital'}>}distinct [Claim ID])

## General Claims Logged
Count({<Status = {'Received and Logged'}, [Bucket Type] = {'General'}>}distinct [Claim ID])

## Medical Claims Processed
Count({<Status = {'Verified','Assessed but not Verified','Till Verify'}, 
[Final Operator] =- {'HICAPS','IBA','WEB','Web/Mobile Claim','System Account'}, claim_type = {'Medical'}>}distinct [Claim ID])

## Processed excl. Electronic
Count({<Status = {'Verified','Assessed but not Verified','Till Verify'},
[Claim Operator] =- {"HICAPS","System Account","IBA","ECLIPSE","Web/Mobile Claims","WEB"},claim_type = {'Hospital'}>}distinct [Claim ID])

## General Claims Processed
Count({<Status = {'Verified','Assessed but not Verified','Till Verify'}, 
[Final Operator] =- {'HICAPS','IBA','WEB','Web/Mobile Claim','System Account'}, [Bucket Type] = {'General'}>}distinct [Claim ID])


## Status

## Claim Lines
Count({<[Status] =- {'Paid'}>}[Claim Line])


