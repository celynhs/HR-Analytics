/* =============================================================================
   PART A - A7: PAY EQUITY (OPTIONAL)
   Table: hr-analysis-511005.hrdatasetv14.workforce_clean

   Questions:
   - Is pay fair by sex, overall and within the same position?
   Metrics: average (mean) and median pay gap overall, plus the gap within each
            position.

   How the gap is calculated:
   pay gap % = (men's pay - women's pay) / men's pay x 100
   - Positive = men are paid more. Negative = women are paid more.
   - Example: men average 60,000 and women 57,000 -> (60,000 - 57,000) /
     60,000 = 5.0%, i.e. women earn 5% less.
   - The median is the middle salary when everyone is lined up from lowest to
     highest. Unlike the mean, it isn't pulled up by a few very high salaries
     (e.g. the CEO), so it's shown alongside.

   Who's included: the main analysis uses current employees only (207).
   Leavers' salaries are their final pay from whenever they left (some as far
   back as 2010), so mixing them with today's salaries compares pay from
   different years. A7.0a shows the all-employee figure only because that's
   where the early signal comes from.

   Small numbers: most positions have only a handful of people, so
   position-level gaps are indicative, not conclusive.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   A7.0a  Starting point: gap across everyone in the file (incl. leavers)
   ----------------------------------------------------------------------------- */

WITH medians AS (
  SELECT DISTINCT
    sex,
    PERCENTILE_CONT(salary, 0.5) OVER (PARTITION BY sex) AS median_salary
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
),
means AS (
  SELECT sex, COUNT(*) AS employees, AVG(salary) AS mean_salary
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
  GROUP BY sex
)
SELECT
  MAX(IF(sex = 'M', employees, NULL))                    AS men,
  MAX(IF(sex = 'F', employees, NULL))                    AS women,
  ROUND(MAX(IF(sex = 'M', mean_salary, NULL)), 1)        AS mean_men,
  ROUND(MAX(IF(sex = 'F', mean_salary, NULL)), 1)        AS mean_women,
  ROUND(100 * (MAX(IF(sex = 'M', mean_salary, NULL)) - MAX(IF(sex = 'F', mean_salary, NULL)))
            / MAX(IF(sex = 'M', mean_salary, NULL)), 1)  AS mean_gap_pct,
  MAX(IF(sex = 'M', median_salary, NULL))                AS median_men,
  MAX(IF(sex = 'F', median_salary, NULL))                AS median_women,
  ROUND(100 * (MAX(IF(sex = 'M', median_salary, NULL)) - MAX(IF(sex = 'F', median_salary, NULL)))
            / MAX(IF(sex = 'M', median_salary, NULL)), 1) AS median_gap_pct
FROM means
JOIN medians USING (sex);
-- Result: 135 men, 176 women. Mean 70,629.4 vs 67,786.7 -> 4.0% gap.
-- Median 63,353 vs 62,066.5 -> 2.0% gap.


/* -----------------------------------------------------------------------------
   A7.1  Overall gap, current employees
   Same query as above, filtered to people still employed.
   ----------------------------------------------------------------------------- */

WITH current_staff AS (
  SELECT * FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
  WHERE NOT has_left
),
medians AS (
  SELECT DISTINCT
    sex,
    PERCENTILE_CONT(salary, 0.5) OVER (PARTITION BY sex) AS median_salary
  FROM current_staff
),
means AS (
  SELECT sex, COUNT(*) AS employees, AVG(salary) AS mean_salary
  FROM current_staff
  GROUP BY sex
)
SELECT
  MAX(IF(sex = 'M', employees, NULL))                    AS men,
  MAX(IF(sex = 'F', employees, NULL))                    AS women,
  ROUND(MAX(IF(sex = 'M', mean_salary, NULL)), 1)        AS mean_men,
  ROUND(MAX(IF(sex = 'F', mean_salary, NULL)), 1)        AS mean_women,
  ROUND(100 * (MAX(IF(sex = 'M', mean_salary, NULL)) - MAX(IF(sex = 'F', mean_salary, NULL)))
            / MAX(IF(sex = 'M', mean_salary, NULL)), 1)  AS mean_gap_pct,
  MAX(IF(sex = 'M', median_salary, NULL))                AS median_men,
  MAX(IF(sex = 'F', median_salary, NULL))                AS median_women,
  ROUND(100 * (MAX(IF(sex = 'M', median_salary, NULL)) - MAX(IF(sex = 'F', median_salary, NULL)))
            / MAX(IF(sex = 'M', median_salary, NULL)), 1) AS median_gap_pct
FROM means
JOIN medians USING (sex);
-- Result: 91 men, 116 women. Mean 71,303.9 vs 70,215.6 -> 1.5% gap.
-- Median 63,973 vs 62,662 -> 2.0% gap.
-- Among current staff the mean gap shrinks from 4.0% to 1.5%. The median gap
-- stays at 2.0%.


/* -----------------------------------------------------------------------------
   A7.2  Gap within each position (current employees)
   Only positions that have both men and women can be compared. Positions
   where either group has fewer than 5 people are flagged as 'small'.
   ----------------------------------------------------------------------------- */

WITH current_staff AS (
  SELECT * FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
  WHERE NOT has_left
),
with_median AS (
  SELECT
    position,
    sex,
    salary,
    PERCENTILE_CONT(salary, 0.5) OVER (PARTITION BY position, sex) AS median_salary
  FROM current_staff
),
by_sex AS (
  SELECT
    position,
    COUNTIF(sex = 'M')                                AS men,
    COUNTIF(sex = 'F')                                AS women,
    AVG(IF(sex = 'M', salary, NULL))                  AS mean_men,
    AVG(IF(sex = 'F', salary, NULL))                  AS mean_women,
    MAX(IF(sex = 'M', median_salary, NULL))           AS median_men,
    MAX(IF(sex = 'F', median_salary, NULL))           AS median_women
  FROM with_median
  GROUP BY position
)
SELECT
  position,
  men,
  women,
  ROUND(mean_men, 0)                                          AS mean_men,
  ROUND(mean_women, 0)                                        AS mean_women,
  ROUND(100 * (mean_men - mean_women) / mean_men, 1)          AS mean_gap_pct,
  ROUND(100 * (median_men - median_women) / median_men, 1)    AS median_gap_pct,
  IF(men < 5 OR women < 5, 'small', 'ok')                     AS sample_size
FROM by_sex
WHERE men > 0 AND women > 0
ORDER BY men + women DESC;
-- Result (13 positions have both men and women):
--   - The 3 biggest roles all favour women or are close to even:
--       Production Technician I (33 men, 52 women): mean gap -2.7%, median -8.1%
--       Production Technician II (12 men, 19 women): mean -3.0%, median -3.6%
--   - Roles where men are paid more:
--       Area Sales Manager (13 men, 10 women): mean 2.9%, median 5.5%
--       Production Manager (5 men, 4 women, small): mean 6.2%, median 3.0%
--   - Network Engineer shows a 20.1% gap, but that's 2 men vs 2 women. Sales
--     Manager (10.0%) is 1 vs 1. Too small to read anything into.
--   - The other small roles range from -5.6% (Sr. Network Engineer) to 5.6%
--     (Senior BI Developer), with no consistent direction.


/* -----------------------------------------------------------------------------
   A7.3  Like-for-like gap (adjusting for position)
   One number that answers: "for the same job, are women paid less?"
   How it works:
   1. For each person, divide their salary by the average salary for their
      position. 1.00 = paid exactly the position average, 1.05 = 5% above it.
      e.g. if Technician I averages 56,000 and someone earns 58,800, their
      index is 1.05.
   2. Average that index for men and for women separately.
   3. Gap % = (men's index - women's index) / men's index x 100.
   Because everyone is compared with their own position's average, differences
   in who holds which job are removed. Only positions with both men and women
   are included.
   ----------------------------------------------------------------------------- */

WITH current_staff AS (
  SELECT * FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
  WHERE NOT has_left
),
mixed_positions AS (
  SELECT position
  FROM current_staff
  GROUP BY position
  HAVING COUNT(DISTINCT sex) = 2
),
indexed AS (
  SELECT
    c.sex,
    c.salary / AVG(c.salary) OVER (PARTITION BY c.position) AS pay_index
  FROM current_staff c
  JOIN mixed_positions USING (position)
)
SELECT
  COUNT(*)                                                       AS employees_compared,
  ROUND(AVG(IF(sex = 'M', pay_index, NULL)), 4)                  AS men_index,
  ROUND(AVG(IF(sex = 'F', pay_index, NULL)), 4)                  AS women_index,
  ROUND(100 * (AVG(IF(sex = 'M', pay_index, NULL)) - AVG(IF(sex = 'F', pay_index, NULL)))
            / AVG(IF(sex = 'M', pay_index, NULL)), 1)            AS like_for_like_gap_pct
FROM indexed;
-- Result: 189 employees in 13 positions. Men's index 0.9972, women's 1.0022,
-- so the like-for-like gap is -0.5%. In the same job, women are paid about
-- the same as men (marginally more).


/* -----------------------------------------------------------------------------
   A7.4  So where does the overall 1.5-2.0% gap come from?
   If pay is equal within jobs, the overall gap must come from which jobs men
   and women hold. Production pays less than other departments, so this checks
   who works there.
   ----------------------------------------------------------------------------- */

SELECT
  sex,
  COUNT(*)                                                         AS employees,
  ROUND(100 * COUNTIF(department = 'Production') / COUNT(*), 1)    AS pct_in_production,
  ROUND(AVG(IF(department = 'Production', salary, NULL)), 0)       AS avg_salary_production,
  ROUND(AVG(IF(department != 'Production', salary, NULL)), 0)      AS avg_salary_other_depts
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
WHERE NOT has_left
GROUP BY sex;
-- Result:
--   - 64.7% of women work in Production vs 56.0% of men.
--   - Production pays far less than other departments (around 60,000 vs over
--     80,000 for both sexes).
--   - Outside Production, women actually earn more on average (89,429 vs
--     83,856).
--   - So the overall gap comes from more women being in the lower-paid
--     Production department, not from women being paid less for the same work.


/* =============================================================================
   A7 SUMMARY
   - Overall gap (current staff): 1.5% on the mean and 2.0% on the median, in
     men's favour. It's smaller than the 4.0% in the early signal, which mixed
     in leavers' old salaries.
   - Like for like (same position): -0.5%. Women are paid about the same as
     men for the same job.
   - The overall gap is a mix effect: a higher share of women work in
     Production (64.7% vs 56.0%), which pays less.
   - Worth a closer look: Area Sales Manager (men paid 2.9% more on average,
     5.5% on the median, 23 people) and Production Manager (6.2% / 3.0%, only
     9 people). Neither is conclusive, but they're the only sizeable roles
     where men are paid more.

   Recommendations:
   - No sign of systematic unequal pay for the same job. Keep checking it
     every year as part of the pay review.
   - Review pay for Area Sales Managers and Production Managers individually,
     taking experience and tenure into account, which this analysis doesn't.
   - The bigger fairness question is representation: why more women sit in
     lower-paid Production roles, and what the path is from Technician to
     Production Manager. This links to the career-path point in A6.

   Limitations:
   - Salary only. No bonus, overtime or hours data.
   - Doesn't adjust for tenure, experience or performance, which can
     legitimately affect pay within a role.
   - Most positions have fewer than 5 people of one sex, so position-level
     gaps are indicative only.
   ============================================================================= */