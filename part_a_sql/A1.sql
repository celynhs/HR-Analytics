/* =============================================================================
   PART A - A1: WORKFORCE PROFILE
   Table: hr-analysis-511005.hrdatasetv14.workforce_clean

   Questions:
   - What does headcount look like at each year-end, by department, position
     and demographics?
   - How many people were hired vs left each year?
   Metrics: year-end headcount, hires, exits, average tenure.

   Two things to keep in mind before reading the results:
   1. The data is a snapshot from around 2019, so "today" for this dataset is
      not CURRENT_DATE(). I use the latest date found in the data instead
      (data_as_of), otherwise tenure for current staff would be inflated by 7+
      years.
   2. The file only holds one row per person, with their latest department and
      position. If someone moved department, it can't be detected, so historical
      headcount by department assumes people stayed in the same department.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   A1.0  Year-end snapshot table
   One row per employee per year-end they were employed. Everything else in A1
   is built on this, and it's also the table I'll load into Power BI so the
   dashboard can slice headcount by any department or demographic.

   Someone counts at a year-end if they were hired on or before 31 Dec and
   hadn't left by then.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount` AS
WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
),

years AS (
  -- Every year from the first hire up to the last complete year in the data
  SELECT year, DATE(year, 12, 31) AS year_end
  FROM UNNEST(GENERATE_ARRAY(
         (SELECT EXTRACT(YEAR FROM MIN(hire_date))
          FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`),
         (SELECT EXTRACT(YEAR FROM data_as_of) FROM data_date))) AS year
  WHERE DATE(year, 12, 31) <= (SELECT data_as_of FROM data_date)
)

SELECT
  y.year,
  y.year_end,
  d.data_as_of,
  c.emp_id,
  c.department,
  c.position,
  c.manager_name,
  c.sex,
  c.race,
  c.marital_status,
  c.citizenship,
  DATE_DIFF(y.year_end, c.date_of_birth, YEAR)                AS age,
  CASE
    WHEN DATE_DIFF(y.year_end, c.date_of_birth, YEAR) < 30 THEN 'Under 30'
    WHEN DATE_DIFF(y.year_end, c.date_of_birth, YEAR) < 40 THEN '30-39'
    WHEN DATE_DIFF(y.year_end, c.date_of_birth, YEAR) < 50 THEN '40-49'
    ELSE '50+'
  END                                                         AS age_band,
  ROUND(DATE_DIFF(y.year_end, c.hire_date, DAY) / 365.25, 1)  AS tenure_years
FROM years y
JOIN `hr-analysis-511005.hrdatasetv14.workforce_clean` c
  ON c.hire_date <= y.year_end
 AND (c.termination_date IS NULL OR c.termination_date > y.year_end)
CROSS JOIN data_date d;

-- Quick look: which years are covered and what date is the data "as of"?
SELECT MIN(year) AS first_year, MAX(year) AS last_year, MAX(data_as_of) AS data_as_of
FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`;
-- Result: [first year] to [last year], data as of [date].


/* -----------------------------------------------------------------------------
   A1.1  Hires, exits and year-end headcount per year
   ----------------------------------------------------------------------------- */

WITH hires AS (
  SELECT EXTRACT(YEAR FROM hire_date) AS year, COUNT(*) AS hires
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
  GROUP BY year
),
exits AS (
  SELECT EXTRACT(YEAR FROM termination_date) AS year, COUNT(*) AS exits
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
  WHERE has_left
  GROUP BY year
),
headcount AS (
  SELECT year, COUNT(*) AS year_end_headcount, ROUND(AVG(tenure_years), 1) AS avg_tenure_years
  FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
  GROUP BY year
)
SELECT
  hc.year,
  COALESCE(h.hires, 0)                          AS hires,
  COALESCE(e.exits, 0)                          AS exits,
  COALESCE(h.hires, 0) - COALESCE(e.exits, 0)   AS net_change,
  hc.year_end_headcount,
  hc.avg_tenure_years
FROM headcount hc
LEFT JOIN hires h USING (year)
LEFT JOIN exits e USING (year)
ORDER BY hc.year;
-- Sanity check: each year's headcount minus the previous year's should equal
-- that year's net_change.
-- Result:
--   - Headcount went from 1 at the end of 2006 to 207 at the end of
--     2018.
--   - Hiring peaked in 2011 (83 hires). Exits peaked in 2015 (23 exits).
--   - Exits overtook hires from 2016, so headcount shrank.
--   - Average tenure of staff at year-end rose from 1 to 5 years.


/* -----------------------------------------------------------------------------
   A1.2  Year-end headcount by department
   ----------------------------------------------------------------------------- */

SELECT
  year,
  COUNTIF(department = 'Production')           AS production,
  ROUND(COUNTIF(department = 'Production') / COUNT(*) *100,2)  AS production_percent, 
  COUNTIF(department = 'IT/IS')                AS it_is,
  ROUND(COUNTIF(department = 'IT/IS') / COUNT(*) *100,2)  AS it_is_percent, 
  COUNTIF(department = 'Sales')                AS sales,
  ROUND(COUNTIF(department = 'Sales') / COUNT(*) *100,2)  AS sales_percent,   
  COUNTIF(department = 'Software Engineering') AS software_engineering,
  ROUND(COUNTIF(department = 'Software Engineering') / COUNT(*) *100,2)  AS software_engineering_percent,   
  COUNTIF(department = 'Admin Offices')        AS admin_offices,
  ROUND(COUNTIF(department = 'Admin Offices') / COUNT(*) *100,2)  AS admin_percent,   
  COUNTIF(department = 'Executive Office')     AS executive_office,
  ROUND(COUNTIF(department = 'Executive Office') / COUNT(*) *100,2)  AS executive_office_percent,   
  COUNT(*)                                     AS total
FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
GROUP BY year
ORDER BY year;
-- Result:
--   - Production is by far the biggest department, at 126 of 207 people
--     (60.9%) in 2018, while admin and software engineering is the smallest department (7 / 207 employee)
--      excluding executive office department (1 employee).
--   - Production grew the most between 2012 and 2013.


/* -----------------------------------------------------------------------------
   A1.3  Headcount by position (latest year-end)
   ----------------------------------------------------------------------------- */

SELECT
  department,
  position,
  COUNT(*)                     AS headcount,
  ROUND(AVG(tenure_years), 1)  AS avg_tenure_years
FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
WHERE year = (SELECT MAX(year) FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`)
GROUP BY department, position
ORDER BY headcount DESC;
-- Result:
--   - Production Technicians is the biggest role with 116 people (85 for tech I and 31 for tech II),      
--     followed by Area sales manager (n = 23).
--   - 14 positions have only 1 person, mostly senior/management roles.


/* -----------------------------------------------------------------------------
   A1.4  Demographics
   ----------------------------------------------------------------------------- */

-- a) Workforce mix at the latest year-end
WITH latest AS (
  SELECT *
  FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
  WHERE year = (SELECT MAX(year) FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`)
),
stacked AS (
  SELECT 'Sex' AS category, sex AS value FROM latest
  UNION ALL SELECT 'Age band',       age_band       FROM latest
  UNION ALL SELECT 'Race',           race           FROM latest
  UNION ALL SELECT 'Marital status', marital_status FROM latest
  UNION ALL SELECT 'Citizenship',    citizenship    FROM latest
)
SELECT
  category,
  value,
  COUNT(*) AS headcount,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY category), 1) AS pct
FROM stacked
GROUP BY category, value
ORDER BY category, headcount DESC;
-- Result:
--   - Sex: 56% female, 44% male.
--   - Age: the largest group is 30-39 age group (~53%).
--   - Race: ~60% White, ~25% Black or African American, with hispanic as the smallest group (1 employee)
--   - Citizenship: 96% US citizens.

-- b) Sex mix by department (latest year-end)
SELECT
  department,
  COUNT(*)                                       AS headcount,
  ROUND(100 * COUNTIF(sex = 'F') / COUNT(*), 1)  AS pct_female
FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
WHERE year = (SELECT MAX(year) FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`)
GROUP BY department
ORDER BY headcount DESC;
-- Result: Software engineering department is the most female-heavy (70%+), and Sales the least (46%).
--         The CEO (Executive office) is also female.

-- c) How the mix changed over time
SELECT
  year,
  COUNT(*)                                       AS headcount,
  ROUND(100 * COUNTIF(sex = 'F') / COUNT(*), 1)  AS pct_female,
  ROUND(AVG(age), 1)                             AS avg_age
FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
GROUP BY year
ORDER BY year;
-- Result: share of women moved from 0% to 50% starting from 2008 
--         and increased since then, ranging between 55-63%. 
--         Average age among the female employee is fluctuating within the late 20 to 30s range.


/* -----------------------------------------------------------------------------
   A1.5  Average tenure: current staff vs leavers
   Current staff: hire date to data_as_of. Leavers: hire date to leaving date.
   ----------------------------------------------------------------------------- */

WITH data_date AS (
  SELECT MAX(data_as_of) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
)
SELECT
  -- ROLLUP adds a total row where department is NULL; label it.
  -- (Alias is dept_name, not department, otherwise BigQuery groups by the
  -- alias and the label never shows.)
  IF(GROUPING(department) = 1, 'All departments', department)  AS dept_name,
  COUNTIF(NOT has_left)                    AS current_staff,
  ROUND(AVG(IF(NOT has_left,
               DATE_DIFF(d.data_as_of, hire_date, DAY) / 365.25, NULL)), 1)        AS avg_tenure_current,
  COUNTIF(has_left)                        AS leavers,
  ROUND(AVG(IF(has_left,
               DATE_DIFF(termination_date, hire_date, DAY) / 365.25, NULL)), 1)    AS avg_tenure_at_exit
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
CROSS JOIN data_date d
GROUP BY ROLLUP (department)
ORDER BY dept_name = 'All departments', current_staff DESC;   -- departments first, total last
-- Result:
--   - Current staff have been in the company for 5.5 years on average. Leavers 
--     stayed 3.5 years before leaving.
--   - Admin offices department has the shortest tenure at exit (~1 years), so 
--     people there tend to leave sooner.


/* =============================================================================
   A1 SUMMARY  (fill in from the results above)
   - Headcount: 1 at the end of 2006 -> 207 at the end of 2018.
   - Hiring vs leaving: Hires outpaced exits until 2016, after that hiring seems  
     to decrease while exits increase.
   - Department: Production holds 60.87% of staff (as of 2018); Admin & Software 
     Engineering department is the smallest (excluding Executive office which is 
     only 1 employee, the CEO).
   - Demographics: 56% female, mostly 30-39 years old, 60% White (not much 
     diversity in terms of race).
   - Tenure: current staff worked with the company for 5.5 years on average vs 3.5 
     years for leavers (although the tenure at exit varies by department).

   Limitation: this file only holds people who were still on record when the
   data was pulled. Staff who left in the early years may be missing, so the
   early headcounts are probably lower than they really were.
   ============================================================================= */