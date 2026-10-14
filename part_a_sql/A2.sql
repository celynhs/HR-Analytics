/* =============================================================================
   PART A - A2: TURNOVER TREND
   Tables: hr-analysis-511005.hrdatasetv14.workforce_clean
           hr-analysis-511005.hrdatasetv14.a1_year_end_headcount  (from A1)

   Questions:
   - Is turnover rising or falling, and where is it concentrated?
   Metrics: annual turnover rate = exits in the year / average headcount,
            split voluntary vs involuntary, by department.

   How the rate is worked out:
   average headcount = (headcount at start of year + headcount at end of year) / 2
   start of year     = the previous year's year-end headcount
   ============================================================================= */


/* -----------------------------------------------------------------------------
   A2.0a  Starting point: what share of each department has ever left?
   The simplest view: of everyone who ever worked in a department, how many
   have left. It's a quick first signal, but it's cumulative, not a rate.
   ----------------------------------------------------------------------------- */

SELECT
  department,
  COUNT(*)                                       AS ever_employed,
  COUNTIF(has_left)                              AS ever_left,
  ROUND(100 * COUNTIF(has_left) / COUNT(*), 1)   AS cumulative_left_pct
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY department
ORDER BY cumulative_left_pct DESC;
-- Result:
--   - Production: 83 of 209 have left (39.7%).
--   - Software Engineering 36.4% (4 of 11), Admin Offices 22.2% (2 of 9),
--     IT/IS 20.0% (10 of 50), Sales 16.1% (5 of 31), Executive Office 0% (0 of 1).
--   - So Production looks far worse than Sales (40% vs 16%). But a cumulative
--     share depends on how long people have been around and when the
--     department did its hiring. It doesn't say how fast people leave each
--     year. The annual rates below fix that.


/* -----------------------------------------------------------------------------
   A2.0b  Turnover table: one row per department per year
   Start/end headcount, exits and exit type. A2.1 to A2.3 all read from this,
   and it can go straight into Power BI.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE `hr-analysis-511005.hrdatasetv14.a2_turnover_by_dept_year` AS
WITH grid AS (
  -- every year x every department, so years with 0 exits still show up
  SELECT y.year, d.department
  FROM (SELECT DISTINCT year FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`) y
  CROSS JOIN (SELECT DISTINCT department FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`) d
),
year_end AS (
  SELECT year, department, COUNT(*) AS end_headcount
  FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
  GROUP BY year, department
),
exits AS (
  SELECT
    EXTRACT(YEAR FROM termination_date)    AS year,
    department,
    COUNT(*)                               AS exits,
    COUNTIF(leaving_type = 'Voluntary')    AS voluntary_exits,
    COUNTIF(leaving_type = 'Involuntary')  AS involuntary_exits
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
  WHERE has_left
  GROUP BY year, department
)
SELECT
  g.year,
  g.department,
  COALESCE(LAG(ye.end_headcount) OVER (PARTITION BY g.department ORDER BY g.year), 0) AS start_headcount,
  COALESCE(ye.end_headcount, 0)                                                         AS end_headcount,
  (COALESCE(LAG(ye.end_headcount) OVER (PARTITION BY g.department ORDER BY g.year), 0)
   + COALESCE(ye.end_headcount, 0)) / 2                                                 AS avg_headcount,
  COALESCE(e.exits, 0)             AS exits,
  COALESCE(e.voluntary_exits, 0)   AS voluntary_exits,
  COALESCE(e.involuntary_exits, 0) AS involuntary_exits
FROM grid g
LEFT JOIN year_end ye USING (year, department)
LEFT JOIN exits    e  USING (year, department);

-- Check: total exits should be 104 (every leaver lands in a year in the table).
SELECT SUM(exits) AS total_exits
FROM `hr-analysis-511005.hrdatasetv14.a2_turnover_by_dept_year`;
-- Result: 104. All exits happened between 2010 and 2018, so none are lost.


/* -----------------------------------------------------------------------------
   A2.1  Company turnover rate per year (voluntary vs involuntary)
   ----------------------------------------------------------------------------- */

SELECT
  year,
  SUM(avg_headcount)                                                AS avg_headcount,
  SUM(exits)                                                        AS exits,
  ROUND(100 * SAFE_DIVIDE(SUM(exits),             SUM(avg_headcount)), 1) AS turnover_rate_pct,
  ROUND(100 * SAFE_DIVIDE(SUM(voluntary_exits),   SUM(avg_headcount)), 1) AS voluntary_rate_pct,
  ROUND(100 * SAFE_DIVIDE(SUM(involuntary_exits), SUM(avg_headcount)), 1) AS involuntary_rate_pct
FROM `hr-analysis-511005.hrdatasetv14.a2_turnover_by_dept_year`
GROUP BY year
ORDER BY year;
-- Result:
--   - 2006-2010 can be ignored: average headcount was under 20 and there was
--     only 1 exit in total, so the rates don't mean much.
--   - Turnover sat around 5-8% from 2011 to 2014 (4.9%, 6.7%, 8.5%, 6.8%),
--     peaked in 2015 (10.3%) and 2016 (9.8%), then dropped to 3.6% in 2017
--     and 6.1% in 2018.
--   - So it isn't steadily rising. It's a 2015-16 spike that has since eased.
--   - Most exits are voluntary. Involuntary exits were 0 until 2013, but have
--     been 0.9-2.2% a year since 2015 (1.9% in 2018).

-- Whole-period rate (all years together)
SELECT
  ROUND(100 * SUM(exits)             / SUM(avg_headcount), 1) AS turnover_rate_pct,
  ROUND(100 * SUM(voluntary_exits)   / SUM(avg_headcount), 1) AS voluntary_rate_pct,
  ROUND(100 * SUM(involuntary_exits) / SUM(avg_headcount), 1) AS involuntary_rate_pct
FROM `hr-analysis-511005.hrdatasetv14.a2_turnover_by_dept_year`;
-- Result: 7.2% a year on average (6.1% voluntary, 1.1% involuntary).


/* -----------------------------------------------------------------------------
   A2.2  Turnover by department: cumulative share vs annual rate
   ----------------------------------------------------------------------------- */

WITH dept_totals AS (
  SELECT
    department,
    COUNT(*)          AS ever_employed,
    COUNTIF(has_left) AS ever_left
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
  GROUP BY department
),
rates AS (
  SELECT
    department,
    SUM(avg_headcount)     AS employee_years,
    SUM(exits)             AS exits,
    SUM(voluntary_exits)   AS voluntary_exits,
    SUM(involuntary_exits) AS involuntary_exits
  FROM `hr-analysis-511005.hrdatasetv14.a2_turnover_by_dept_year`
  GROUP BY department
)
SELECT
  department,
  ever_employed,
  ever_left,
  ROUND(100 * ever_left / ever_employed, 1)                               AS cumulative_left_pct,
  employee_years,
  ROUND(100 * SAFE_DIVIDE(exits,             employee_years), 1)          AS annual_turnover_pct,
  ROUND(100 * SAFE_DIVIDE(voluntary_exits,   employee_years), 1)          AS voluntary_pct,
  ROUND(100 * SAFE_DIVIDE(involuntary_exits, employee_years), 1)          AS involuntary_pct,
  ROUND(100 * exits / SUM(exits) OVER (), 1)                              AS share_of_all_exits_pct,
  ROUND(100 * employee_years / SUM(employee_years) OVER (), 1)            AS share_of_workforce_pct
FROM dept_totals
JOIN rates USING (department)
ORDER BY annual_turnover_pct DESC;
-- Result:
--   - Production: 39.7% cumulative -> 8.3% a year (7.5% voluntary, 0.8% involuntary).
--   - Sales: 16.1% cumulative -> 3.1% a year.
--   - So the gap holds up as a proper rate: Production loses people at about
--     2.7x the rate of Sales.
--   - Production makes up 69.4% of the workforce but 79.8% of all exits
--     (83 of 104).
--   - Software Engineering (7.2%), IT/IS (5.7%) and Admin Offices (4.9%) sit in
--     between, but they're small (4, 10 and 2 exits), so one or two leavers
--     move their rate a lot.
--   - Production's turnover is almost all voluntary (75 of 83 exits). People
--     are choosing to leave, rather than being let go.


/* -----------------------------------------------------------------------------
   A2.3  Production vs the rest of the company, per year
   The other departments are combined because on their own they're too small
   for yearly rates to be reliable.
   ----------------------------------------------------------------------------- */

SELECT
  year,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(department = 'Production', exits, 0)),
                          SUM(IF(department = 'Production', avg_headcount, 0))), 1)   AS production_rate_pct,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(department != 'Production', exits, 0)),
                          SUM(IF(department != 'Production', avg_headcount, 0))), 1)  AS other_depts_rate_pct,
  SUM(IF(department = 'Production', exits, 0))    AS production_exits,
  SUM(IF(department != 'Production', exits, 0))   AS other_exits
FROM `hr-analysis-511005.hrdatasetv14.a2_turnover_by_dept_year`
WHERE year >= 2011
GROUP BY year
ORDER BY year;
-- Result:
--   - Production's rate is higher than the rest of the company in every year
--     except 2015 (9.7% vs 11.9%).
--   - Production peaked at 12.2% in 2016 (18 exits). In 2018 it was 7.7% vs
--     3.6% for everyone else.
--   - The other departments jumped to 11.9% in 2015. The query below shows
--     where that came from.

-- What drove the 2015 jump outside Production?
SELECT
  department,
  avg_headcount,
  exits,
  ROUND(100 * SAFE_DIVIDE(exits, avg_headcount), 1) AS turnover_rate_pct
FROM `hr-analysis-511005.hrdatasetv14.a2_turnover_by_dept_year`
WHERE year = 2015
  AND department != 'Production'
ORDER BY exits DESC;
-- Result:
--   - 8 exits outside Production in 2015: IT/IS 4 (14.8%), Software
--     Engineering 2 (22.2%), Admin Offices 1 (20.0%), Sales 1 (3.9%).
--   - Half of them came from IT/IS. Software Engineering and Admin Offices have
--     higher rates, but that's only 2 and 1 people out of average headcounts of
--     9 and 5.


/* -----------------------------------------------------------------------------
   A2.4  Inside Production: which roles turn over most?
   ----------------------------------------------------------------------------- */

WITH years AS (
  SELECT DISTINCT year FROM `hr-analysis-511005.hrdatasetv14.a1_year_end_headcount`
),
by_position_year AS (
  SELECT
    y.year,
    c.position,
    -- headcount at the start and end of the year
    COUNTIF(c.hire_date <= DATE(y.year - 1, 12, 31)
            AND (c.termination_date IS NULL OR c.termination_date > DATE(y.year - 1, 12, 31))) AS start_hc,
    COUNTIF(c.hire_date <= DATE(y.year, 12, 31)
            AND (c.termination_date IS NULL OR c.termination_date > DATE(y.year, 12, 31)))     AS end_hc,
    COUNTIF(EXTRACT(YEAR FROM c.termination_date) = y.year)                                   AS exits
  FROM years y
  CROSS JOIN `hr-analysis-511005.hrdatasetv14.workforce_clean` c
  WHERE c.department = 'Production'
  GROUP BY y.year, c.position
)
SELECT
  position,
  SUM(exits)                                                              AS exits,
  SUM((start_hc + end_hc) / 2)                                            AS employee_years,
  ROUND(100 * SAFE_DIVIDE(SUM(exits), SUM((start_hc + end_hc) / 2)), 1)   AS annual_turnover_pct
FROM by_position_year
GROUP BY position
ORDER BY exits DESC;
-- Result:
--   - Production Technician I: 52 exits, 7.4% a year.
--   - Production Technician II: 26 exits, 11.7% a year, the highest of any
--     sizeable group.
--   - Production Manager: 5 exits, 7.4% a year.
--   - So the more experienced technicians (Tech II) leave at a higher rate than
--     entry-level ones. That's worth following up in A3 (exit reasons) and
--     A6 (performance/engagement).


/* =============================================================================
   A2 SUMMARY
   - Trend: turnover isn't steadily rising. It sat around 5-8% a year in
     2011-2014, spiked to 10.3% in 2015 and 9.8% in 2016, then eased to 3.6%
     in 2017 and 6.1% in 2018. The average across all years is 7.2%.
   - Type: it's mostly voluntary (6.1% vs 1.1% involuntary a year). Involuntary
     exits only started in 2013, but have been a steady 1-2% a year since 2015.
   - Where: Production. Its 40% vs 16% cumulative gap with Sales holds up as
     annual rates (8.3% vs 3.1%). It accounts for 80% of exits from 69% of the
     workforce, and it's higher than the rest of the company in almost every
     year.
   - Within Production, Technician II roles have the highest rate (11.7%).

   Limitations:
   - Small departments have only 0-10 exits in total, so their rates are
     unstable and shouldn't be compared year by year.
   - Each employee only has their latest department and position, so anyone
     who moved roles is counted in their final one for every year.
   ============================================================================= */