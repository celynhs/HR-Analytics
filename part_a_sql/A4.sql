/* =============================================================================
   PART A - A4: RECRUITMENT SOURCE QUALITY
   Table: hr-analysis-511005.hrdatasetv14.workforce_clean

   Questions:
   - Which hiring channels bring in people who stay and perform well?
     (This tells us where the recruitment budget should go.)
   - Is it really the channel, or just the roles and years it hired for?
   Metrics: hires, share still employed after 1 and 2 years (plus 3 years),
            performance and engagement by source.

   Small channels: 'Other' (2 hires) and 'On-line Web application' (1 hire) are
   too small to judge. Website (13) is borderline, so read it with care.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   A4.0a  Starting point: share of each channel's hires who have left
   ----------------------------------------------------------------------------- */

SELECT
  recruitment_source,
  COUNT(*)                                       AS hires,
  COUNTIF(has_left)                              AS left_company,
  ROUND(100 * COUNTIF(has_left) / COUNT(*), 1)   AS cumulative_left_pct
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY recruitment_source
ORDER BY cumulative_left_pct DESC;
-- Result:
--   - Google Search 61.2% (30 of 49), Diversity Job Fair 55.2% (16 of 29),
--     CareerBuilder 47.8% (11 of 23), Indeed 24.1% (21 of 87),
--     LinkedIn 23.7% (18 of 76), Employee Referral 16.1% (5 of 31),
--     Website 7.7% (1 of 13).
--   - On the face of it, Google Search looks like a bad channel and referrals a
--     great one. But like the department numbers in A2, this is cumulative.
--     Two things could be distorting it, checked next.


/* -----------------------------------------------------------------------------
   A4.0b  Could the roles or the hiring years explain it?
   - Role: Production has the highest turnover (A2). A channel that mostly
     fills Production roles will look worse even if the channel itself is fine.
   - Timing: someone hired in 2011 has had 8 years to leave, someone hired in
     2016 only 3. Channels used more in earlier years will look worse.
   ----------------------------------------------------------------------------- */

-- annual_turnover_pct = leavers / total years worked by that channel's hires.
-- It's the same idea as A2 (exits / average headcount): a per-year rate, so
-- a channel isn't penalised just because its hires have been around longer.
WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
)
SELECT
  recruitment_source,
  COUNT(*)                                                           AS hires,
  COUNTIF(has_left)                                                  AS leavers,
  ROUND(100 * COUNTIF(has_left) / COUNT(*), 1)                       AS cumulative_left_pct,
  ROUND(SUM(DATE_DIFF(COALESCE(termination_date, d.data_as_of),
                      hire_date, DAY)) / 365.25, 1)                  AS years_worked,
  ROUND(100 * COUNTIF(has_left)
        / (SUM(DATE_DIFF(COALESCE(termination_date, d.data_as_of),
                         hire_date, DAY)) / 365.25), 1)              AS annual_turnover_pct,
  COUNTIF(department = 'Production')                                 AS production_hires,
  COUNTIF(department = 'Production' AND has_left)                    AS production_leavers,
  ROUND(100 * COUNTIF(department = 'Production') / COUNT(*), 1)      AS pct_hired_into_production,
  ROUND(AVG(EXTRACT(YEAR FROM hire_date)), 1)                        AS avg_hire_year
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
CROSS JOIN data_date d
GROUP BY recruitment_source
ORDER BY pct_hired_into_production DESC;

-- Company benchmark for annual_turnover_pct
WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
)
SELECT
  COUNTIF(has_left) AS leavers,
  ROUND(100 * COUNTIF(has_left)
        / (SUM(DATE_DIFF(COALESCE(termination_date, d.data_as_of),
                         hire_date, DAY)) / 365.25), 1) AS annual_turnover_pct
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
CROSS JOIN data_date d;
-- Result: 104 leavers, 6.9% a year across the company.
-- (Slightly different from A2's 7.2% because this counts exact days worked,
--  including Jan-Feb 2019. A2 averaged year-end headcounts up to 2018.)

-- Result (main query):
--   - Role: 89.8% of Google Search hires went into Production (44 of 49, 27 of
--     whom left), and 69.6% of CareerBuilder's (16 of 23, 9 left). That compares
--     with 51.6% of referrals (16 of 31, 2 left) and 30.8% of Website hires.
--   - LinkedIn is also heavily Production (80.3%, 61 of 76), but only 14 of
--     those 61 left. Its annual turnover is 5.0%, below the 6.9% company rate.
--     Google Search is at 12.3%. So role can't be the whole story.
--   - Annual turnover by channel: Website 1.5%, Referral 3.5%, LinkedIn 5.0%,
--     Indeed 5.1%, CareerBuilder 9.5%, Diversity Job Fair 11.2%,
--     Google Search 12.3%.
--   - Timing: Google Search (avg hire year 2011.5), Diversity Job Fair (2011.7)
--     and CareerBuilder (2012.2) hires are older than referrals (2013.8) and
--     Website (2013.5). So these channels have had more time to lose people.
--   - Both effects push the same way, so A4.1 uses fixed time windows and A4.2
--     compares channels inside Production only.


/* -----------------------------------------------------------------------------
   A4.1  Retention after 1, 2 and 3 years
   "Still employed after 1 year" only counts people hired at least a year
   before the data ends, otherwise recent hires would look perfect just because
   they haven't had time to leave. Same for 2 and 3 years.
   This fixed window also removes the timing problem from A4.0b.
   I added 3 years as well, because the share of leavers keeps building after
   year 2 (see the overall row in the results).
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE `hr-analysis-511005.hrdatasetv14.a4_hires` AS
WITH data_date AS (
  SELECT GREATEST(MAX(termination_date), MAX(last_review_date)) AS data_as_of
  FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
)
SELECT
  c.emp_id,
  c.recruitment_source,
  c.department,
  c.position,
  c.hire_date,
  c.has_left,
  c.performance_score,
  c.engagement_score,
  c.satisfaction_score,
  -- hired long enough ago to be measured?
  DATE_ADD(c.hire_date, INTERVAL 1 YEAR) <= d.data_as_of  AS eligible_1y,
  DATE_ADD(c.hire_date, INTERVAL 2 YEAR) <= d.data_as_of  AS eligible_2y,
  DATE_ADD(c.hire_date, INTERVAL 3 YEAR) <= d.data_as_of  AS eligible_3y,
  -- still employed at that point?
  c.termination_date IS NULL OR c.termination_date > DATE_ADD(c.hire_date, INTERVAL 1 YEAR) AS stayed_1y,
  c.termination_date IS NULL OR c.termination_date > DATE_ADD(c.hire_date, INTERVAL 2 YEAR) AS stayed_2y,
  c.termination_date IS NULL OR c.termination_date > DATE_ADD(c.hire_date, INTERVAL 3 YEAR) AS stayed_3y
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean` c
CROSS JOIN data_date d;

SELECT
  IF(GROUPING(recruitment_source) = 1, 'All sources', recruitment_source)  AS source_name,
  COUNT(*)                                                                  AS hires,
  ROUND(100 * COUNTIF(eligible_1y AND stayed_1y) / COUNTIF(eligible_1y), 1) AS retained_1y_pct,
  ROUND(100 * COUNTIF(eligible_2y AND stayed_2y) / COUNTIF(eligible_2y), 1) AS retained_2y_pct,
  COUNTIF(eligible_3y)                                                      AS measurable_3y,
  ROUND(100 * COUNTIF(eligible_3y AND stayed_3y) / COUNTIF(eligible_3y), 1) AS retained_3y_pct
FROM `hr-analysis-511005.hrdatasetv14.a4_hires`
GROUP BY ROLLUP (recruitment_source)
ORDER BY source_name = 'All sources', hires DESC;
-- Result:
--   - Overall: 97.1% still employed after 1 year, 90.6% after 2, 85.3% after 3.
--   - After 1 year almost every channel is at 97-100%. The exception is Indeed
--     at 93.0%, so Indeed hires who leave tend to leave early.
--   - After 2 years: Google Search is lowest (83.7%), then Indeed (86.9%).
--     Referrals 96.8%, LinkedIn 94.7%.
--   - After 3 years the gap is clearest: Google Search 71.4%, CareerBuilder
--     82.6%, Indeed 84.4%, Diversity Job Fair 85.7%, LinkedIn 90.1%,
--     Referral 93.1%, Website 100% (12 people).
--   - So once timing is removed, Google Search is still clearly the weakest.
--   - CareerBuilder (47.8% left in A4.0a) and Diversity Job Fair (55.2% left)
--     are close to the 85.3% average at 3 years (82.6% and 85.7%). Their annual
--     turnover is still high, though (9.5% and 11.2% in A4.0b). So their hires
--     do fine early on, but more of them leave after year 3.


/* -----------------------------------------------------------------------------
   A4.2  Is it the channel or the role? Compare channels within Production
   ----------------------------------------------------------------------------- */

SELECT
  IF(department = 'Production', 'Production', 'Other departments')            AS dept_group,
  recruitment_source,
  COUNTIF(eligible_3y)                                                         AS measurable_3y,
  ROUND(100 * COUNTIF(eligible_3y AND stayed_3y) / COUNTIF(eligible_3y), 1)    AS retained_3y_pct
FROM `hr-analysis-511005.hrdatasetv14.a4_hires`
WHERE recruitment_source NOT IN ('Other', 'On-line Web application')
GROUP BY dept_group, recruitment_source
ORDER BY dept_group DESC, measurable_3y DESC;
-- Result (Production only, 3-year retention):
--   - LinkedIn 93.1% (58 people), Indeed 83.3% (48), Google Search 75.0% (44),
--     CareerBuilder 87.5% (16), Diversity Job Fair 81.2% (16),
--     Referral 100% (14), Website 100% (4).
--   - Even comparing like for like inside Production, Google Search hires are
--     the least likely to still be there after 3 years, and referrals and
--     LinkedIn the most. So it's the channel, not just the roles it fills.
--   - Outside Production the groups are small (5-29 per channel), so I
--     wouldn't draw conclusions from that half.

-- Production benchmark for the comparison above
SELECT
  COUNTIF(eligible_3y)                                                       AS measurable_3y,
  ROUND(100 * COUNTIF(eligible_3y AND stayed_3y) / COUNTIF(eligible_3y), 1)  AS retained_3y_pct
FROM `hr-analysis-511005.hrdatasetv14.a4_hires`
WHERE department = 'Production';
-- Result: of the 202 Production hires who joined at least 3 years before the
-- data ends (out of 209 Production hires in total), 86.1% were still employed
-- 3 years after their hire date.


/* -----------------------------------------------------------------------------
   A4.3  Performance and engagement by source
   Uses each person's latest performance score (for leavers, their score before
   they left).
   ----------------------------------------------------------------------------- */

SELECT
  IF(GROUPING(recruitment_source) = 1, 'All sources', recruitment_source)   AS source_name,
  COUNT(*)                                                                    AS hires,
  ROUND(100 * COUNTIF(performance_score = 'Exceeds') / COUNT(*), 1)           AS exceeds_pct,
  ROUND(100 * COUNTIF(performance_score IN ('Needs Improvement', 'PIP'))
            / COUNT(*), 1)                                                    AS below_expectations_pct,
  ROUND(AVG(engagement_score), 2)                                             AS avg_engagement,
  ROUND(AVG(satisfaction_score), 2)                                           AS avg_satisfaction
FROM `hr-analysis-511005.hrdatasetv14.a4_hires`
GROUP BY ROLLUP (recruitment_source)
ORDER BY source_name = 'All sources', hires DESC;
-- Result:
--   - Overall: 11.9% Exceeds, 10.0% below expectations, engagement 4.11,
--     satisfaction 3.89.
--   - Employee Referral has the best mix: 16.1% Exceeds and only 3.2% below
--     expectations.
--   - Diversity Job Fair is split: the most Exceeds (20.7%) but also 17.2%
--     below expectations.
--   - CareerBuilder: 17.4% below expectations and the lowest satisfaction of the
--     bigger channels (3.65).
--   - Google Search: only 4.1% Exceeds (2 of 49), the lowest of the main
--     channels, though its below-expectations rate (8.2%) is about average.
--   - Engagement is similar across the main channels (3.99 to 4.22), so it
--     doesn't separate them much.


/* =============================================================================
   A4 SUMMARY
   - The early signal (61% of Google Search hires left vs 16% of referrals) is
     partly inflated. Google Search mostly hired into Production (89.8%) and in
     earlier years (avg 2011.5), and both make a channel look worse.
   - After correcting for both, Google Search is still the weakest channel:
     71.4% still employed after 3 years vs 85.3% overall, and 75.0% vs 86.1%
     when compared only within Production. It also has the fewest top
     performers (4.1% Exceeds).
   - Referrals are the strongest: 93.1% retained after 3 years (100% within
     Production), and the best performance mix (16.1% Exceeds, 3.2% below).
     LinkedIn is the best of the large-volume channels (90.1% at 3 years, 93.1%
     within Production).
   - CareerBuilder and Diversity Job Fair keep people about as well as average
     for the first 3 years (82.6% and 85.7%), but their annual turnover is
     still high (9.5% and 11.2% vs 6.9%), so they lose people later on. Both
     also have a high share of below-expectation performers (17.4% and 17.2%).
   - Indeed loses people earliest (93.0% retention rate at 1 year vs 97.1% overall).

   What this means for budget: lean on referrals and LinkedIn. Review the spend
   on Google Search. For Indeed, look at why people leave in the first year
   (onboarding, role expectations).

   Limitations:
   - Several channels have fewer than 30 hires, so a few people can shift the
     percentages a lot.
   - Performance is a single latest score, not performance over time.
   - Only the channel is recorded, not cost per hire, so this shows quality
     but not value for money.
   ============================================================================= */