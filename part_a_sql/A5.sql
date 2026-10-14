/* =============================================================================
   PART A - A5: MANAGER EFFECT
   Tables: hr-analysis-511005.hrdatasetv14.workforce_clean
           hr-analysis-511005.hrdatasetv14.a3_exits   (from A3, for exit buckets)

   Questions:
   - Do some managers lose far more people than others with similar teams?
   Metrics: turnover, engagement and satisfaction by manager, only for managers
            with at least 10 reports (people who reported to them, current or past).

   Annual turnover here works the same way as in A4:
   leavers / total years worked by that manager's reports.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   A5.0a  Starting point: share of each manager's reports who have left
   ----------------------------------------------------------------------------- */

SELECT
  manager_name,
  COUNT(*)                                       AS reports,
  COUNTIF(has_left)                              AS leavers,
  ROUND(100 * COUNTIF(has_left) / COUNT(*), 1)   AS cumulative_left_pct
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY manager_name
HAVING COUNT(*) >= 10
ORDER BY cumulative_left_pct DESC;
-- Result:
--   - 14 managers have 10+ reports.
--   - Highest: Amy Dunn and Webster Butler, 61.9% each (13 of 21), then Kissy
--     Sullivan 54.5% (12 of 22) and Simon Roup 47.1% (8 of 17).
--   - Lowest: Peter Monroe 7.1% (1 of 14) and Lynn Daneault 7.7% (1 of 13).
--   - As in A2 and A4, this is cumulative, and managers run very different
--     teams. So before blaming anyone, check who they manage.


/* -----------------------------------------------------------------------------
   A5.0b  Who does each manager look after?
   ----------------------------------------------------------------------------- */

SELECT
  manager_name,
  STRING_AGG(DISTINCT department, ', ')                    AS departments,
  COUNT(*)                                                 AS reports,
  COUNTIF(position = 'Production Technician I')            AS tech_i,
  COUNTIF(position = 'Production Technician II')           AS tech_ii,
  ROUND(AVG(EXTRACT(YEAR FROM hire_date)), 1)              AS avg_hire_year
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY manager_name
HAVING COUNT(*) >= 10
ORDER BY departments, reports DESC;
-- Result:
--   - 9 managers run Production technician teams. The teams are almost
--     identical: 21-22 people each, 15-16 Technician I and 6-7 Technician II,
--     and an average hire year between 2011.9 and 2012.8.
--     That makes them a fair like-for-like comparison.
--   - Janet King manages across 5 departments (mostly the Production Managers),
--     so she isn't comparable to a team manager. I leave her out of the
--     within-department comparisons.
--   - IT/IS: Simon Roup and Peter Monroe (both avg hire year 2014.8).
--     Sales: John Smith and Lynn Daneault (both 2012.6).


/* -----------------------------------------------------------------------------
   A5.1  Manager scorecard (10+ reports)
   Saved as a table for Power BI.
   Engagement and satisfaction are the latest scores of everyone who reported to
   the manager (for leavers, the score before they left).
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE `hr-analysis-511005.hrdatasetv14.a5_manager_scorecard` AS
WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
)
SELECT
  c.manager_name,
  STRING_AGG(DISTINCT c.department, ', ')                                AS departments,
  COUNT(*)                                                               AS reports,
  COUNTIF(c.has_left)                                                    AS leavers,
  COUNTIF(c.leaving_type = 'Voluntary')                                  AS voluntary_leavers,
  ROUND(SUM(DATE_DIFF(COALESCE(c.termination_date, d.data_as_of),
                      c.hire_date, DAY)) / 365.25, 1)                    AS years_worked,
  ROUND(100 * COUNTIF(c.has_left)
        / (SUM(DATE_DIFF(COALESCE(c.termination_date, d.data_as_of),
                         c.hire_date, DAY)) / 365.25), 1)                AS annual_turnover_pct,
  ROUND(AVG(c.engagement_score), 2)                                      AS avg_engagement,
  ROUND(AVG(c.satisfaction_score), 2)                                    AS avg_satisfaction
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean` c
CROSS JOIN data_date d
GROUP BY c.manager_name
HAVING COUNT(*) >= 10;

SELECT *
FROM `hr-analysis-511005.hrdatasetv14.a5_manager_scorecard`
ORDER BY departments, annual_turnover_pct DESC;
-- Result (annual turnover):
--   - Production teams: Amy Dunn 14.3%, Webster Butler 14.3%, Kissy Sullivan
--     11.1%, Michael Albert 7.7%, Elijiah Gray 7.0%, David Stanley 5.8%,
--     Brannon Miller 5.4%, Kelley Spirea 5.4%, Ketsia Liebig 4.6%.
--   - IT/IS: Simon Roup 16.7% vs Peter Monroe 1.9%.
--   - Sales: John Smith 4.0% vs Lynn Daneault 1.3%.
--   - Janet King (cross-department): 6.0%.
-- Result (engagement and satisfaction):
--   - They don't line up with turnover. Among Production managers, Amy Dunn's
--     team has the lowest engagement (3.92), but Webster Butler's has the
--     highest (4.33), even though both lose people at the same rate.
--   - Brannon Miller's team has the lowest satisfaction (3.41) but one of the
--     lowest turnover rates (5.4%).
--   - So engagement and satisfaction scores alone wouldn't have flagged the
--     high-turnover teams.


/* -----------------------------------------------------------------------------
   A5.2  Production teams: actual vs expected leavers
   Expected = what each team would have lost at the average rate for all 9
   Production technician teams, given how many years its people worked.
   Excess = actual - expected. A positive number means more people left than
   you'd expect for that team.

   How peer_rate_pct is calculated:
   - Take every Production Technician I and II across the 9 teams (194 people).
   - years worked per person = hire date to leaving date, or to the end of the
     data (data_as_of) if still employed. Someone who worked 6 months counts
     as 0.5.
   - peer rate = all leavers / total years worked = 78 / 954.7 = 8.2% a year.
   - Total years worked is the same as average headcount x number of years,
     so this is still "leavers / average headcount", turned into a yearly
     rate. Example: 20 people for 5 years = 100 years worked; 10 leavers ->
     10 / 100 = 10% a year, the same as (10 / 5 years) / 20 people.
   - Expected leavers for a team = that team's years worked x peer rate.
     e.g. Amy Dunn: 91.0 years x 8.2% = 7.4 expected, vs 13 actual.
   ----------------------------------------------------------------------------- */

WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
),
techs AS (
  SELECT
    c.manager_name,
    c.has_left,
    DATE_DIFF(COALESCE(c.termination_date, d.data_as_of), c.hire_date, DAY) / 365.25 AS years_worked
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean` c
  CROSS JOIN data_date d
  WHERE c.position IN ('Production Technician I', 'Production Technician II')
),
peer_rate AS (
  SELECT COUNTIF(has_left) / SUM(years_worked) AS rate
  FROM techs
)
SELECT
  t.manager_name,
  COUNT(*)                                           AS reports,
  COUNTIF(t.has_left)                                AS actual_leavers,
  ROUND(SUM(t.years_worked) * ANY_VALUE(p.rate), 1)                        AS expected_leavers,
  ROUND(COUNTIF(t.has_left) - SUM(t.years_worked) * ANY_VALUE(p.rate), 1)   AS excess_leavers,
  ROUND(COUNTIF(t.has_left) / (SUM(t.years_worked) * ANY_VALUE(p.rate)), 2) AS actual_vs_expected,
  ROUND(100 * ANY_VALUE(p.rate), 1)                                         AS peer_rate_pct
FROM techs t
CROSS JOIN peer_rate p
GROUP BY t.manager_name
ORDER BY excess_leavers DESC;

-- The inputs behind peer_rate_pct (so 78 / 954.7 can be checked)
WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
)
SELECT
  COUNT(DISTINCT c.manager_name)                                            AS teams,
  COUNT(*)                                                                  AS technicians,
  COUNTIF(c.has_left)                                                       AS leavers,
  ROUND(SUM(DATE_DIFF(COALESCE(c.termination_date, d.data_as_of),
                      c.hire_date, DAY)) / 365.25, 1)                       AS total_years_worked,
  ROUND(100 * COUNTIF(c.has_left)
        / (SUM(DATE_DIFF(COALESCE(c.termination_date, d.data_as_of),
                         c.hire_date, DAY)) / 365.25), 1)                   AS peer_rate_pct
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean` c
CROSS JOIN data_date d
WHERE c.position IN ('Production Technician I', 'Production Technician II');
-- Result: 9 teams, 194 technicians, 78 leavers, 954.7 years worked -> 8.2% a year.

-- Result (main query):
--   - The peer rate across all 9 Production technician teams is 8.2% a year.
--   - Amy Dunn and Webster Butler: 13 leavers each vs 7.4 expected (+5.6 each),
--     1.75x what you'd expect.
--   - Kissy Sullivan: 12 vs 8.8 expected (+3.2).
--   - Everyone else is at or below expectation, from Michael Albert (-0.5) to
--     Ketsia Liebig (-3.9).
--   - So with near-identical teams, three managers account for most of the
--     extra turnover in Production.


/* -----------------------------------------------------------------------------
   A5.3  Why did people leave the high-turnover teams?
   Uses the controllable / uncontrollable / company decision buckets from A3.
   ----------------------------------------------------------------------------- */

SELECT
  c.manager_name,
  COUNT(*)                                          AS leavers,
  COUNTIF(e.exit_bucket = 'Controllable')           AS controllable,
  COUNTIF(e.exit_bucket = 'Uncontrollable')         AS uncontrollable,
  COUNTIF(e.exit_bucket = 'Company decision')       AS company_decision,
  STRING_AGG(e.term_reason, ', ' ORDER BY e.term_reason) AS reasons
FROM `hr-analysis-511005.hrdatasetv14.a3_exits` e
JOIN `hr-analysis-511005.hrdatasetv14.workforce_clean` c USING (emp_id)
WHERE c.manager_name IN ('Amy Dunn', 'Webster Butler', 'Kissy Sullivan',
                         'Simon Roup', 'Peter Monroe', 'John Smith', 'Lynn Daneault')
GROUP BY c.manager_name
ORDER BY leavers DESC;
-- Result:
--   - Amy Dunn: 9 of 13 controllable (unhappy 4, hours 2, more money 2,
--     another position 1). "Controllable" means controllable by the company,
--     though, not necessarily by the manager. Pay is usually set centrally.
--     A5.4 splits this further.
--   - Webster Butler: only 6 of 13 controllable. 7 were life events (military 3,
--     return to school 2, retiring 1, career change 1). His number looks just as
--     bad as Amy's, but much of it is outside his control.
--   - Kissy Sullivan: 7 of 12 controllable, 2 company decisions (performance).
--   - Simon Roup (IT/IS): 5 of 8 were company decisions (performance 2,
--     no-call no-show 2, and the 'gangster' entry). His high rate is mostly
--     dismissals, not people quitting. His team (data and database roles) also
--     differs from Peter Monroe's (network and IT support), so the two aren't a
--     clean comparison.
--   - Sales: John Smith 3 leavers and Lynn Daneault 1. Too few to call a pattern.


/* -----------------------------------------------------------------------------
   A5.4  Which controllable exits can the manager actually influence?
   Not all controllable reasons are in a line manager's hands:
   - Manager-level ('unhappy', 'hours'): day-to-day treatment, workload,
     rosters and shift patterns. These are things a team manager decides or
     strongly shapes.
   - Company-level ('more money', 'another position'): pay bands and
     promotion/career paths are usually set by HR and senior leadership. A
     manager can push for a raise or a promotion, but can't decide it alone.
   If a manager is the problem, manager-level exits should cluster in their
   team. If pay is the problem, company-level exits should be spread evenly.
   Compared across the 9 Production technician teams (near-identical teams).
   ----------------------------------------------------------------------------- */

SELECT
  c.manager_name,
  COUNT(*)                                                          AS leavers,
  COUNTIF(e.term_reason IN ('unhappy', 'hours'))                    AS manager_level_exits,
  COUNTIF(e.term_reason IN ('more money', 'another position'))      AS company_level_exits,
  ROUND(100 * COUNTIF(e.term_reason IN ('unhappy', 'hours'))
        / SUM(COUNTIF(e.term_reason IN ('unhappy', 'hours'))) OVER (), 1)  AS share_of_all_manager_level_pct
FROM `hr-analysis-511005.hrdatasetv14.a3_exits` e
JOIN `hr-analysis-511005.hrdatasetv14.workforce_clean` c USING (emp_id)
WHERE c.position IN ('Production Technician I', 'Production Technician II')
GROUP BY c.manager_name
ORDER BY manager_level_exits DESC;
-- Result:
--   - 19 manager-level exits across the 9 teams. Amy Dunn's team has 6 of them
--     (31.6%), double the next highest (Webster Butler and Kissy Sullivan, 3 each).
--     Ketsia Liebig's team has none.
--   - Company-level exits (pay / better offer) are spread fairly evenly: 2-4 per
--     team, 26 in total.
--   - So pay and better offers look like a company-wide Production issue (a
--     pay or career-path question for HR, see A3). Unhappiness and hours
--     cluster in Amy Dunn's team, and those are the parts a manager should be able to influence.


/* =============================================================================
   A5 SUMMARY
   - The early signal partly holds up. The 9 Production technician managers
     run almost identical teams, so their turnover can be compared fairly.
     Against a peer rate of 8.2% a year, Amy Dunn and Webster Butler each lost
     5.6 more people than expected (13 vs 7.4), and Kissy Sullivan 3.2 more.
     The other six were at or below expectation.
   - But the reasons differ:
       * Amy Dunn: 9 of 13 exits controllable. More importantly, 6 were for
         unhappiness or hours, the reasons a line manager actually shapes. That's
         31.6% of all such exits across the 9 teams. This is the clearest case to
         look at management practices.
       * Pay and better-offer exits are spread evenly across teams (2-4 each),
         so they point to company-level pay/career issues, not to any one manager.
       * Webster Butler: 7 of 13 exits were life events (military, school,
         retiring). His high number is less likely to be about how he manages.
       * Simon Roup (IT/IS, 16.7%): mostly dismissals (5 of 8), so this looks
         more like a hiring-quality issue than people leaving him.
   - Peter Monroe's 7% is real, but his network/support team isn't comparable
     to Simon Roup's data team, so it's not a direct benchmark.
   - Engagement and satisfaction scores don't track manager turnover (Webster
     Butler's team has the highest engagement), so they aren't a reliable early
     warning on their own.

   Next step for the business: exit interviews or stay interviews on Amy Dunn's
   team, and a look at Kissy Sullivan's team before its controllable exits grow.

   Limitations:
   - Each employee only has their latest manager. Anyone who changed manager is
     counted under their final one.
   - With about 21 people per team, a few leavers move the numbers a lot. A gap
     of 5-6 people is notable, but it could still partly be chance.
   ============================================================================= */