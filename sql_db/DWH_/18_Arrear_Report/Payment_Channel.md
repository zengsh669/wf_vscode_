LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
Section3:
Load *,
membership_id&'-'&YearMonth as Key, 
monthname(YearMonth) as MonthYear;
sql SELECT
    r.membership_id,
    FORMAT(DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1), 'dd/MM/yyyy') AS YearMonth,
    rm.receipt_method_type,
    rmt.description,
    SUM(r.receipt_amount) AS TotalReceiptAmount,
    COUNT(r.receipt_id) AS ReceiptCount
FROM memship m
JOIN receipt r 
    ON r.membership_id = m.membership_id
JOIN receipt_method rm
    ON r.receipt_link_id = rm.receipt_link_id
JOIN receipt_method_type rmt
    ON rm.receipt_method_type = rmt.receipt_method_type
WHERE 
    m.memship_status = 'A'
    AND rm.receipt_method_type NOT IN ('l','O','r','m','c','3','d','n','p','v','1','f','V','u','A','R','j')
    AND r.create_datetime >= '2025-01-01'
GROUP BY
    r.membership_id,
    DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1),
    rm.receipt_method_type,
    rmt.description
ORDER BY
    r.membership_id,
    YearMonth;
left join (Section3)
load membership_id&'-'&YearMonth as Key, 
	description as [Dishonour],
	ReceiptCount as DishonourCount;
sql SELECT
    r.membership_id,
    FORMAT(DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1), 'dd/MM/yyyy') AS YearMonth,
    rm.receipt_method_type,
    rmt.description,
    SUM(r.receipt_amount) AS TotalReceiptAmount,
    COUNT(r.receipt_id) AS ReceiptCount
FROM memship m
JOIN receipt r 
    ON r.membership_id = m.membership_id
JOIN receipt_method rm
    ON r.receipt_link_id = rm.receipt_link_id
JOIN receipt_method_type rmt
    ON rm.receipt_method_type = rmt.receipt_method_type
WHERE 
    m.memship_status = 'A'
    AND rm.receipt_method_type = 'A'
    AND r.create_datetime >= '2025-01-01'
GROUP BY
    r.membership_id,
    DATEFROMPARTS(YEAR(r.create_datetime), MONTH(r.create_datetime), 1),
    rm.receipt_method_type,
    rmt.description
ORDER BY
    r.membership_id,
    YearMonth;

Characteristics:
load membership_id&'-'&PriorMonth as Key,
branch_description,
billing_freq_description,
age(rundate, join_date) as LOM,
membership_id,
rundate;
SQL SELECT
    FORMAT(DATEFROMPARTS(
               YEAR(DATEADD(MONTH, -1, rundate)),
               MONTH(DATEADD(MONTH, -1, rundate)),
               1
           ), 'dd/MM/yyyy') AS PriorMonth,
    membership_id,
    billing_freq_description,
    branch_description,
    join_date,
    rundate
FROM group_key_full_by_branch
WHERE rundate >= '2025-01-01';

left join (Characteristics)
load membership_id,
date_of_birth;
sql select pm.membership_id, p.date_of_birth
from person_membership as pm 
join person as p on pm.person_id = p.person_id
where relationship = '1' and pm.status_flag = 'A';

left join (Section3)
load Key,
branch_description,
billing_freq_description,
LOM,
if(LOM <=3, '0-3yrs',
if(LOM >3 and LOM <= 5, '3-5yrs',
if(LOM >5 and LOM <= 10, '5-10yrs',
if(LOM >10, '10yrs+')))) as [LOM Bracket],

age(rundate, date_of_birth) as MemberAge,
if(age(rundate, date_of_birth) <=25, '<25yrs',
if(age(rundate, date_of_birth) >25 and LOM <= 35, '25-35yrs',
if(age(rundate, date_of_birth) >35 and LOM <= 45, '35-45yrs',
if(age(rundate, date_of_birth) >45 and LOM <= 55, '45-55yrs',
if(age(rundate, date_of_birth) >55 and LOM <= 65, '55-65yrs',
if(age(rundate, date_of_birth) >65, '65yrs+')))))) as [Age Bracket]
Resident Characteristics;
Drop Table Characteristics;

LIB CONNECT TO 'rpsqlrp01 - paragonreporting';
LatestMembership:
LOAD membership_id,
	description as LatestReceiptType;
SQL SELECT 
    r.membership_id,
	sum(r.receipt_amount) as ReceiptAmount,
    rmt.description,
	r.create_datetime,
	count(r.receipt_id) as ReceiptCount,
	rm.receipt_method_type
FROM memship as m 
join receipt r on r.membership_id = m.membership_id

JOIN (
    SELECT 
        membership_id,
        MAX(r1.create_datetime) AS max_create_datetime
    FROM receipt r1 join receipt_method as rm2 on r1.receipt_link_id = rm2.receipt_link_id
    where rm2.receipt_method_type not in ('l','O','r','m','c','3','d','n','p','v','1','f','V','u','A','R','j')
    GROUP BY membership_id
) latest ON latest.membership_id = r.membership_id
        AND latest.max_create_datetime = r.create_datetime

JOIN receipt_method rm 
        ON r.receipt_link_id = rm.receipt_link_id
JOIN receipt_method_type rmt 
        ON rm.receipt_method_type = rmt.receipt_method_type
where  m.memship_status = 'A' 
group by  r.membership_id,
    rmt.description,
	r.create_datetime,
		rm.receipt_method_type
order by r.membership_id;

left join (LatestMembership)
load membership_id,
if(isnull(expiry_date),'Account',
if(expiry_date < today(),'Account','Card')) as DirectDebitBreakDown, 
account_number;
SQL SELECT m.membership_id, a.account_type, m.memship_status, a.expiry_date, a.account_number
FROM memship as m 
join account as a on m.membership_id = a.membership_id
where a.status_flag = 'A' and a.account_type = 'D';

left join (LatestMembership)
LOAD membership_id,
description as LatestPaymentFrequency;
SQL select *
from MemberPaymentFrequencyLatest;


WalletCard:
LOAD
    monthname("Payment Date") as MonthYear,
    "Merchant Reference",
    "Card Type",
    if(isnull("Wallet Type"),'Card',"Wallet Type") as WalletCard
FROM [lib://Manual Data (prdqs01_atobi)/Finance/Wallet v Card/WalletCard.xlsx]
(ooxml, embedded labels, table is Sheet1);



exit script;
