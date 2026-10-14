/* =============================================================================
   PART A - A6: PERFORMANCE, ENGAGEMENT AND EXITS
   Tables: hr-analysis-511005.hrdatasetv14.workforce_clean
           hr-analysis-511005.hrdatasetv14.a3_exits   (from A3, for exit buckets)

   Questions:
   - Are we losing strong performers (regretted attrition), or mostly weaker ones?
   Metrics: exit share by performance score; engagement and satisfaction of
            leavers vs stayers; regretted attrition.

   Definitions used in this file:
   - Strong performer = rated 'Fully Meets' or 'Exceeds'.
     Weaker performer = rated 'Needs Improvement' or 'PIP'.
   - Regretted attrition = a VOLUNTARY leaver who was a strong performer.
     These are people the company would have wanted to keep. Strong performers
     who were dismissed don't count, because that was the company's choice.
   - Annual turnover = leavers / total years worked, the same method as A4/A5
     (see A5.2 for a worked example).
   ============================================================================= */


/* -----------------------------------------------------------------------------
   A6.0a  Starting point: share of each performance group who have left
   ----------------------------------------------------------------------------- */

SELECT
  performance_score,
  COUNT(*)                                       AS employees,
  COUNTIF(has_left)                              AS leavers,
  ROUND(100 * COUNTIF(has_left) / COUNT(*), 1)   AS cumulative_left_pct
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY performance_score
ORDER BY cumulative_left_pct DESC;
-- Result:
--   - Needs Improvement group has leavers rate at 55.6% (10 of 18), PIP 38.5% (5 of 13),
--     Fully Meets 33.3% (81 of 243), and Exceeds 21.6% (8 of 37).
--   - So weaker performers leave more often, but more than 1 in 5 top
--     performers have gone too.


/* -----------------------------------------------------------------------------
   A6.0b  Check: was the performance score given before the person left?
   Each person only has one score, their latest review. For leavers that should
   be a review from before they left, otherwise we'd be comparing a rating
   given after the exit.
   ----------------------------------------------------------------------------- */

SELECT
  COUNTIF(last_review_date <= termination_date)                       AS reviewed_before_leaving,
  COUNTIF(last_review_date > termination_date)                        AS reviewed_after_leaving,
  ROUND(AVG(DATE_DIFF(termination_date, last_review_date, DAY)), 1)  AS avg_days_review_to_exit
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
WHERE has_left;
-- Result:
--   - 103 of 104 leavers were reviewed before they left, on average 187.3 days
--     (about 6 months) before their exit. So their score reflects how they were
--     performing while still employed.
--   - 1 leaver has a review date after their termination date. That's a data
--     entry error, but it's only one row, so it's kept in the dataset.
--   - Note: current staff were all reviewed in Jan-Feb 2019, so their scores are
--     more recent than the leavers'.


/* -----------------------------------------------------------------------------
   A6.1  Turnover by performance score: rate vs share of leavers
   Two different questions, and they give different answers:
   - annual_turnover_pct: how LIKELY is someone in this group to leave each year?
   - share_of_leavers_pct: of everyone who left, what % came from this group?
   A group can have a high leaving rate but still be a small slice of leavers
   if it's small. E.g. if 10 of 20 weak performers leave (50%) and 40 of 200
   strong performers leave (20%), strong performers are still 80% of leavers
   (40 of 50).
   ----------------------------------------------------------------------------- */

WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
)
SELECT
  c.performance_score,
  COUNT(*)                                                              AS employees,
  COUNTIF(c.has_left)                                                   AS leavers,
  COUNTIF(c.leaving_type = 'Voluntary')                                 AS voluntary,
  COUNTIF(c.leaving_type = 'Involuntary')                               AS involuntary,
  ROUND(100 * COUNTIF(c.has_left)
        / (SUM(DATE_DIFF(COALESCE(c.termination_date, d.data_as_of),
                         c.hire_date, DAY)) / 365.25), 1)               AS annual_turnover_pct,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                      AS share_of_workforce_pct,
  ROUND(100 * COUNTIF(c.has_left) / SUM(COUNTIF(c.has_left)) OVER (), 1) AS share_of_leavers_pct
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean` c
CROSS JOIN data_date d
GROUP BY c.performance_score
ORDER BY annual_turnover_pct DESC;
-- Result:
--   - Leaving rate per year: Needs Improvement 11.2%, PIP 8.4%,
--     Fully Meets 7.1%, Exceeds 3.9% (company average 6.9%, from A4).
--     So the better someone performs, the less likely they are to leave.
--   - But share of leavers: Fully Meets 77.9% and Exceeds 7.7%, so 85.6% of
--     everyone who left was a strong performer. Weaker performers are only
--     10.0% of the workforce (Needs Improvement 5.8% + PIP 4.2%), so even
--     though they leave faster, there aren't many of them to lose.
--   - Half of the Needs Improvement leavers were dismissed (5 of 10). 73 of the
--     81 Fully Meets leavers went voluntarily.


/* -----------------------------------------------------------------------------
   A6.2  Engagement and satisfaction: leavers vs stayers
   Scores are the latest survey result (for leavers, their last one before
   leaving).
   ----------------------------------------------------------------------------- */

-- a) Stayers vs voluntary vs involuntary leavers
SELECT
  COALESCE(leaving_type, 'Still employed')   AS employee_group,
  COUNT(*)                                   AS employees,
  ROUND(AVG(engagement_score), 2)            AS avg_engagement,
  ROUND(AVG(satisfaction_score), 2)          AS avg_satisfaction,
  COUNTIF(engagement_score < 3)              AS low_engagement_under_3
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY employee_group
ORDER BY employees DESC;
-- Result:
--   - Still employed: engagement 4.12, satisfaction 3.89.
--   - Voluntary leavers: engagement 4.18, satisfaction 3.90. That's basically
--     the same as stayers, or even slightly higher.
--   - Involuntary leavers: engagement 3.60, satisfaction 3.81. Lower, which
--     fits with them being let go.
--   - So people who resign don't look disengaged on the survey before they go.
--     The survey isn't flagging the people we lose voluntarily.

-- b) Strong performers only: regretted leavers vs strong performers who stayed
SELECT
  IF(has_left, 'Regretted leaver', 'Strong performer, still employed')  AS employee_group,
  COUNT(*)                                                              AS employees,
  ROUND(AVG(engagement_score), 2)                                       AS avg_engagement,
  ROUND(AVG(satisfaction_score), 2)                                     AS avg_satisfaction
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
WHERE performance_score IN ('Fully Meets', 'Exceeds')
  AND (NOT has_left OR leaving_type = 'Voluntary')
GROUP BY employee_group;
-- Result: regretted leavers 4.30 engagement / 3.96 satisfaction vs 4.26 / 3.97
-- for strong performers who stayed. No warning sign in the survey scores.


/* -----------------------------------------------------------------------------
   A6.3  Regretted attrition
   ----------------------------------------------------------------------------- */

-- a) How much of our turnover is regretted?
--    regretted_rate_pct = regretted leavers / total years worked by strong
--    performers. It's the yearly chance that a strong performer resigns, the
--    same method as annual turnover, but limited to strong performers.
WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
),
flags AS (
  SELECT
    c.*,
    c.performance_score IN ('Fully Meets', 'Exceeds')                    AS strong_performer,
    c.performance_score IN ('Fully Meets', 'Exceeds')
      AND c.leaving_type = 'Voluntary'                                   AS regretted,
    DATE_DIFF(COALESCE(c.termination_date, d.data_as_of), c.hire_date, DAY) / 365.25 AS years_worked
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean` c
  CROSS JOIN data_date d
)
SELECT
  COUNTIF(has_left)                                                         AS all_exits,
  COUNTIF(leaving_type = 'Voluntary')                                       AS voluntary_exits,
  COUNTIF(regretted)                                                        AS regretted_exits,
  ROUND(100 * COUNTIF(regretted) / COUNTIF(has_left), 1)                    AS regretted_pct_of_all_exits,
  ROUND(100 * COUNTIF(regretted) / COUNTIF(leaving_type = 'Voluntary'), 1)  AS regretted_pct_of_voluntary,
  ROUND(100 * COUNTIF(regretted)
        / SUM(IF(strong_performer, years_worked, 0)), 1)                    AS regretted_rate_pct
FROM flags;
-- Result:
--   - 80 of 104 exits were regretted (76.9%), and 90.9% of everyone who
--     resigned (80 of 88) was a strong performer.
--   - Each year about 5.9% of strong performers resign.

-- b) Why did regretted leavers go? (A3 buckets)
SELECT
  e.exit_bucket,
  COUNT(*)                                          AS regretted_exits,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct
FROM `hr-analysis-511005.hrdatasetv14.a3_exits` e
JOIN `hr-analysis-511005.hrdatasetv14.workforce_clean` c USING (emp_id)
WHERE c.performance_score IN ('Fully Meets', 'Exceeds')
  AND c.leaving_type = 'Voluntary'
GROUP BY e.exit_bucket
ORDER BY regretted_exits DESC;
-- Result: 49 of the 80 regretted exits (61.3%) were for controllable reasons
-- (pay, hours, unhappy, better offer), and 29 (36.3%) were life events.
-- 2 were labelled with a company-decision reason even though they resigned.

-- c) Where are regretted exits concentrated?
SELECT
  department,
  COUNTIF(has_left)                                                         AS all_exits,
  COUNTIF(performance_score IN ('Fully Meets', 'Exceeds')
          AND leaving_type = 'Voluntary')                                   AS regretted_exits,
  ROUND(100 * COUNTIF(performance_score IN ('Fully Meets', 'Exceeds')
                      AND leaving_type = 'Voluntary')
            / NULLIF(COUNTIF(has_left), 0), 1)                              AS regretted_pct_of_dept_exits
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY department
ORDER BY regretted_exits DESC;
-- Result: Production 67 of 83 exits regretted (80.7%), IT/IS 6 of 10,
-- Sales 3 of 5, Software Engineering 3 of 4, Admin Offices 1 of 2.
-- Production accounts for 67 of the 80 regretted exits.

-- d) Which managers lost the most strong performers?
SELECT
  manager_name,
  COUNTIF(performance_score IN ('Fully Meets', 'Exceeds')
          AND leaving_type = 'Voluntary')  AS regretted_exits
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY manager_name
ORDER BY regretted_exits DESC
LIMIT 5;
-- Result: Amy Dunn 12, Webster Butler 11, Kissy Sullivan 10, Michael Albert 8,
-- David Stanley 6. The same three managers flagged in A5 lost the most
-- strong performers.

-- e) Regretted exits per year (links to the 2015-16 spike in A2)
SELECT
  EXTRACT(YEAR FROM termination_date)  AS exit_year,
  COUNT(*)                             AS regretted_exits
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
WHERE performance_score IN ('Fully Meets', 'Exceeds')
  AND leaving_type = 'Voluntary'
GROUP BY exit_year
ORDER BY exit_year;
-- Result: 7 in 2012, 12 in 2013, 12 in 2014, 14 in 2015, 18 in 2016 (the
-- peak), then 5 in 2017 and 9 in 2018.


/* =============================================================================
   A6 SUMMARY
   - By rate, weaker performers leave faster (Needs Improvement 11.2% a year)
     and top performers slowest (Exceeds 3.9%). The early signal's direction
     holds.
   - By volume, though, we are mostly losing strong performers. 85.6% of
     leavers were rated Fully Meets or Exceeds, because that's 90% of the
     workforce.
   - Regretted attrition is high: 80 of 104 exits (76.9%) were strong
     performers who chose to leave, about 5.9% of strong performers a year.
     61.3% of them left for controllable reasons (pay, hours, unhappiness, a
     better offer).
   - It's concentrated where the rest of the analysis points: Production
     (67 of 80) and the teams of Amy Dunn, Webster Butler and Kissy Sullivan
     (33 between them).
   - Engagement and satisfaction scores don't separate voluntary leavers from
     stayers (4.18 vs 4.12 engagement). Only involuntary leavers score lower
     (3.60). So the survey isn't an early warning for regretted exits.

   Recommendations:
   1. Track regretted attrition as its own KPI, not just overall turnover.
      77% of exits are regretted, so overall turnover hides the real loss. Use
      5.9% a year of strong performers as the baseline to measure progress against.
   2. Run stay interviews with strong performers in Production, starting with
      Amy Dunn's, Webster Butler's and Kissy Sullivan's teams (33 of the 80
      regretted exits). The survey doesn't flag these people, so someone has to
      ask them directly.
   3. Go after the controllable reasons (61.3% of regretted exits):
      - pay: benchmark Production technician pay against the market
      - hours: review shift patterns and rosters
      - better offers: make the Technician I -> II -> Manager path clear,
        since 'another position' is the top regretted reason.
   4. Fix the early-warning gap. Add intent-to-stay, pay and workload questions
      to the engagement survey, or run short pulse surveys. The current scores
      look the same for people who resign and people who stay.
   5. Make performance ratings more differentiated. With 78% rated Fully
      Meets, it's hard to spot the top talent worth fighting hardest for.
   6. Weaker performers leave faster, but half of them were dismissed. That's
      performance management working, so no retention spend is needed there.

   Limitations:
   - One performance score per person (the latest), so we can't see whether
     someone's performance dropped before they left.
   - 78% of staff are rated 'Fully Meets', so the scale doesn't separate
     people much. "Strong performer" is a broad group.
   ============================================================================= */