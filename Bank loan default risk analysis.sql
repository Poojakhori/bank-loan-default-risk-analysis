-- Create database
Create database bank_loan;
use bank_loan;
-- 1. Display the tables
select * from loans;
select * from borrowers;
select * from delinquency;
select * from credit_grade;

-- 1. How many loans are in the portfolio?
Select count(loan_id) as total_loans from loans;

-- 2. How many loans are in the portfolio?
Select count(*) as total_loans from loans;

-- 	3. How many loans have defaulted?
Select count(*) as total_defaulted from loans
where default_flag=1;

-- 4. List the distinct credit grades in use
Select distinct(credit_grade) AS credit_grades_used from borrowers
order by credit_grade;

-- 5. Average loan amount across the whole portfolio
select (round(avg(loan_amount),2) )as average_loan_amount from loans;

-- 6. Loans priced above 20% interest, most expensive first
select loan_id, loan_amount, interest_rate, status from loans
where interest_rate> '20%' 
order by interest_rate desc;

-- 7. Count of loans by status
Select status, count(*) as loan_counts from loans
group by status;

-- 8. Default rate by credit grade
Select b.credit_grade, 
	count(*) as total_loans,
	sum(l.default_flag) as defaults,
    round(100.0*sum(l.default_flag)/count(*),2) as default_rate
    from loans l
    join borrowers b on 
    b. borrower_id= l.borrower_id
    group by b.credit_grade
    order by b.credit_grade;
    
    -- 9. Default rate by income band
    Select b.income_band, 
	count(*) as total_loans,
	sum(l.default_flag) as defaults,
    round(100.0*sum(l.default_flag)/count(*),2) as default_rate
    from loans l
    join borrowers b on 
    b. borrower_id= l.borrower_id
    group by b.income_band
    order by income_band;
    
-- 10. Default rate by employment type, only segments with 500+ loans
Select b.employment_type, 
count(*) as total_loans,
sum(l.default_flag) as defaults,
round(100.0*sum(l.default_flag)/count(*),2) as default_rate
from loans l
join borrowers b on 
b.borrower_id=l. borrower_id
group by b.employment_type
having count(*)>=500
order by default_rate;

-- 11. Average interest spread by credit grade, using the reference table
Select c. credit_grade, c. grade_description, 
count(*) as total_loans,
round(Avg(l. interest_rate),2) as avg_interest_rate,
round(Avg(l. interest_spread),2) as avg_interest_spread
 from credit_grade c
 join borrowers b on b. credit_grade= c. credit_grade
 join loans l on b. borrower_id= l. borrower_id
 group by  c. credit_grade, c. grade_description
 order by  c. credit_grade;
 
 -- 12 Region-level portfolio size vs. default rate
 Select b. region,
 count(*) as total_loans, 
 sum(l.loan_amount) as total_amount,
 round(sum(l.default_flag)*100.0/count(*),2) as default_rate
 from loans l
 join borrowers b on 
 b. borrower_id= l. borrower_id
 group by b. region
 order by default_Rate desc;
 
 -- 13 Three-table join: delinquency history by credit grade
SELECT
    b.credit_grade,
    COUNT(DISTINCT l.loan_id)                          AS total_loans,
    ROUND(AVG(d.days_past_due), 1)                     AS avg_days_past_due,
    ROUND(100.0 * SUM(d.delinquent_flag) / COUNT(d.payment_record_id), 2)
                                                        AS pct_snapshots_seriously_delinquent
FROM loans l
JOIN borrowers b   ON b.borrower_id = l.borrower_id
JOIN delinquency d ON d.loan_id = l.loan_id
GROUP BY b.credit_grade
ORDER BY b.credit_grade; 

-- 14. default rate by credit_grade (rows) x income_band (columns)
SELECT
    b.credit_grade,
    ROUND(100.0 * SUM(CASE WHEN b.income_band = 'Low'          THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.income_band = 'Low'          THEN 1 END), 0), 2) AS low_income_default_pct,
    ROUND(100.0 * SUM(CASE WHEN b.income_band = 'Lower-Middle'  THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.income_band = 'Lower-Middle' THEN 1 END), 0), 2) AS lower_mid_default_pct,
    ROUND(100.0 * SUM(CASE WHEN b.income_band = 'Middle'        THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.income_band = 'Middle'       THEN 1 END), 0), 2) AS middle_default_pct,
    ROUND(100.0 * SUM(CASE WHEN b.income_band = 'Upper-Middle'  THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.income_band = 'Upper-Middle' THEN 1 END), 0), 2) AS upper_mid_default_pct,
    ROUND(100.0 * SUM(CASE WHEN b.income_band = 'High'          THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.income_band = 'High'         THEN 1 END), 0), 2) AS high_income_default_pct
FROM loans l
JOIN borrowers b ON b.borrower_id = l.borrower_id
GROUP BY b.credit_grade
ORDER BY b.credit_grade;
 
 -- 15. Window function: rank employment types by default rate
 WITH by_employment AS (
    SELECT
        b.employment_type,
        COUNT(*)                                          AS total_loans,
        100.0 * SUM(l.default_flag) / COUNT(*)             AS default_rate_pct
    FROM loans l
    JOIN borrowers b ON b.borrower_id = l.borrower_id
    GROUP BY b.employment_type
)
SELECT
    employment_type,
    total_loans,
    ROUND(default_rate_pct, 2)                                AS default_rate_pct,
    RANK() OVER (ORDER BY default_rate_pct DESC)               AS risk_rank,
    ROUND(default_rate_pct - AVG(default_rate_pct) OVER (), 2) AS gap_vs_portfolio_avg
FROM by_employment
ORDER BY risk_rank;

--  16. Cohort analysis: default rate by origination year-month cohort, plus a running (cumulative) default rate over time
WITH cohort AS (
    SELECT
        DATE_FORMAT(origination_date, '%Y-%m')  AS cohort_month,
        COUNT(*)                                AS total_loans,
        SUM(default_flag)                       AS defaults
    FROM loans
    GROUP BY DATE_FORMAT(origination_date, '%Y-%m')
)
SELECT
    cohort_month,
    total_loans,
    defaults,
    ROUND(100.0 * defaults / total_loans, 2)                              AS cohort_default_rate_pct,
    SUM(total_loans) OVER (ORDER BY cohort_month)                         AS cumulative_loans,
    SUM(defaults)    OVER (ORDER BY cohort_month)                         AS cumulative_defaults,
    ROUND(100.0 * SUM(defaults) OVER (ORDER BY cohort_month)
          / SUM(total_loans) OVER (ORDER BY cohort_month), 2)             AS running_default_rate_pct
FROM cohort
ORDER BY cohort_month;

-- -- 17. High-risk segment: grade D-G borrowers in the two lowest income bands
WITH segment AS (
    SELECT
        l.loan_id,
        l.loan_amount,
        l.interest_spread,
        l.default_flag,
        b.credit_grade,
        b.income_band
    FROM loans l
    JOIN borrowers b ON b.borrower_id = l.borrower_id
    WHERE b.credit_grade IN ('D','E','F','G')
      AND b.income_band IN ('Low','Lower-Middle')
)
SELECT
    credit_grade,
    income_band,
    COUNT(*)                                          AS total_loans,
    SUM(loan_amount)                                   AS total_exposure,
    ROUND(100.0 * SUM(default_flag) / COUNT(*), 2)     AS default_rate_pct,
    ROUND(AVG(interest_spread), 2)                     AS avg_interest_spread
FROM segment
GROUP BY credit_grade, income_band
HAVING COUNT(*) >= 30
ORDER BY default_rate_pct DESC;

-- 18. Full pivot: credit_grade (rows) x employment_type (columns)
SELECT
    b.credit_grade,
    ROUND(100.0 * SUM(CASE WHEN b.employment_type='Salaried'       THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.employment_type='Salaried'       THEN 1 END),0), 2) AS salaried_default_pct,
    ROUND(100.0 * SUM(CASE WHEN b.employment_type='Self-Employed'   THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.employment_type='Self-Employed'  THEN 1 END),0), 2) AS self_employed_default_pct,
    ROUND(100.0 * SUM(CASE WHEN b.employment_type='Business Owner'  THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.employment_type='Business Owner' THEN 1 END),0), 2) AS business_owner_default_pct,
    ROUND(100.0 * SUM(CASE WHEN b.employment_type='Freelancer'      THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.employment_type='Freelancer'     THEN 1 END),0), 2) AS freelancer_default_pct,
    ROUND(100.0 * SUM(CASE WHEN b.employment_type='Unemployed'      THEN l.default_flag END)
          / NULLIF(SUM(CASE WHEN b.employment_type='Unemployed'     THEN 1 END),0), 2) AS unemployed_default_pct
FROM loans l
JOIN borrowers b ON b.borrower_id = l.borrower_id
GROUP BY b.credit_grade
ORDER BY b.credit_grade;

-- 19. Loans that ever hit serious delinquency (DPD >= 90), using EXISTS
SELECT
    l.loan_id,
    b.credit_grade,
    b.income_band,
    b.employment_type,
    l.loan_amount,
    l.interest_spread,
    l.status
FROM loans l
JOIN borrowers b ON b.borrower_id = l.borrower_id
WHERE EXISTS (
    SELECT 1 FROM delinquency d
    WHERE d.loan_id = l.loan_id AND d.delinquent_flag = 1
)
ORDER BY l.interest_spread DESC
LIMIT 50;

-- 20. Portfolio risk scorecard: one summary row per grade
WITH loan_grade AS (
    SELECT l.*, b.credit_grade, b.income_band, b.employment_type
    FROM loans l
    JOIN borrowers b ON b.borrower_id = l.borrower_id
),
delinq_agg AS (
    SELECT loan_id, MAX(days_past_due) AS max_dpd, MAX(delinquent_flag) AS ever_serious_delinquent
    FROM delinquency
    GROUP BY loan_id
)
SELECT
    lg.credit_grade,
    COUNT(*)                                                     AS total_loans,
    ROUND(100.0 * SUM(lg.default_flag) / COUNT(*), 2)            AS default_rate_pct,
    ROUND(100.0 * SUM(COALESCE(da.ever_serious_delinquent,0)) / COUNT(*), 2)
                                                                  AS serious_delinquency_rate_pct,
    ROUND(AVG(da.max_dpd), 1)                                    AS avg_max_days_past_due,
    ROUND(AVG(lg.interest_spread), 2)                            AS avg_interest_spread,
    SUM(lg.loan_amount)                                          AS total_exposure
FROM loan_grade lg
LEFT JOIN delinq_agg da ON da.loan_id = lg.loan_id
GROUP BY lg.credit_grade
ORDER BY lg.credit_grade;