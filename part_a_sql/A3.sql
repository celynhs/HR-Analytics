/* =============================================================================
   PART A - A3: WHY PEOPLE LEAVE
   Table: hr-analysis-511005.hrdatasetv14.workforce_clean

   Questions:
   - What are the main exit reasons?
   - How many of them could the company have done something about?
   Metrics: share of exits by reason category, by department, and the
            controllable vs uncontrollable split.

   How I split the reasons:
   - Controllable: things the company can influence. Pay ('more money'),
     hours ('hours'), unhappiness ('unhappy') and leaving for a better offer
     ('another position').
   - Uncontrollable: life events the company can't really change. Return to
     school, relocation, retiring, military, maternity leave, medical issues,
     and career change (leaving the field altogether).
   - Company decision: the company ended the employment. Attendance,
     performance, no-call no-show, misconduct and the two odd entries noted in
     A0. These aren't "losses" in the same sense, so I keep them separate.

   'Career change' is a judgement call. It could be read as a development
   issue the company could address, so A3.3 also shows the split with it
   counted as controllable.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   A3.0  Exits table
   One row per leaver with the reason, reason group and controllable bucket.
   Everything below reads from it, and it can go straight into Power BI.
   ----------------------------------------------------------------------------- */

CREATE OR REPLACE TABLE `hr-analysis-511005.hrdatasetv14.a3_exits` AS
SELECT
  emp_id,
  department,
  position,
  EXTRACT(YEAR FROM termination_date)  AS exit_year,
  leaving_type,
  term_reason,
  term_reason_group,
  CASE
    WHEN term_reason IN ('more money', 'hours', 'unhappy', 'another position')
      THEN 'Controllable'
    WHEN term_reason IN ('return to school', 'relocation out of area', 'retiring', 'military',
                         'maternity leave - did not return', 'medical issues', 'career change')
      THEN 'Uncontrollable'
    ELSE 'Company decision'
  END                                  AS exit_bucket
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
WHERE has_left;

-- Check: should be 104 leavers
SELECT COUNT(*) AS leavers FROM `hr-analysis-511005.hrdatasetv14.a3_exits`;
-- Result: 104.


/* -----------------------------------------------------------------------------
   A3.1  Every exit reason
   ----------------------------------------------------------------------------- */

SELECT
  term_reason,
  COUNT(*)                                            AS exits,
  COUNTIF(leaving_type = 'Voluntary')                 AS voluntary,
  COUNTIF(leaving_type = 'Involuntary')               AS involuntary,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_exits
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
GROUP BY term_reason
ORDER BY exits DESC;
-- Result:
--   - Top 5 reasons: another position 20 (19.2%), unhappy 14 (13.5%),
--     more money 11 (10.6%), career change 9 (8.7%), hours 8 (7.7%).
--   - The top 3 alone (a better job, being unhappy, pay) are 45 of 104 exits.
--   - Attendance (7) is the biggest company-decision reason. 6 of those were
--     terminated for cause, 1 was voluntary.


/* -----------------------------------------------------------------------------
   A3.2  Exits by reason group
   ----------------------------------------------------------------------------- */

SELECT
  term_reason_group,
  COUNT(*)                                          AS exits,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_exits
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
GROUP BY term_reason_group
ORDER BY exits DESC;
-- Result:
--   - Career / better opportunity 40 (38.5%), Personal / life event 24 (23.1%),
--     Work conditions 22 (21.2%), Conduct / performance 18 (17.3%).
--   - So more than a third of people left for something better elsewhere.


/* -----------------------------------------------------------------------------
   A3.3  Controllable vs uncontrollable
   ----------------------------------------------------------------------------- */

SELECT
  exit_bucket,
  COUNT(*)                                                       AS exits,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_of_all_exits,
  COUNTIF(leaving_type = 'Voluntary')                            AS voluntary_exits,
  ROUND(100 * COUNTIF(leaving_type = 'Voluntary')
            / SUM(COUNTIF(leaving_type = 'Voluntary')) OVER (), 1) AS pct_of_voluntary_exits
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
GROUP BY exit_bucket
ORDER BY exits DESC;
-- Result:
--   - Controllable 53 (51.0%), Uncontrollable 33 (31.7%), Company decision 18 (17.3%).
--   - Looking only at people who chose to leave (88 voluntary exits), 60.2%
--     left for a controllable reason.
--   - (2 voluntary exits are in Company decision because their reason was
--     attendance or performance.)

-- Sensitivity: what if 'career change' counts as controllable too?
SELECT
  COUNTIF(exit_bucket = 'Controllable' OR term_reason = 'career change')            AS controllable_exits,
  ROUND(100 * COUNTIF(exit_bucket = 'Controllable' OR term_reason = 'career change')
            / COUNT(*), 1)                                                            AS pct_of_all_exits
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`;
-- Result: 62 exits (59.6%). Either way, roughly half to 60% of all exits are
-- things the company could influence.


/* -----------------------------------------------------------------------------
   A3.4  By department
   ----------------------------------------------------------------------------- */

-- a) Controllable share by department
SELECT
  department,
  COUNT(*)                                                   AS exits,
  COUNTIF(exit_bucket = 'Controllable')                      AS controllable,
  COUNTIF(exit_bucket = 'Uncontrollable')                    AS uncontrollable,
  COUNTIF(exit_bucket = 'Company decision')                  AS company_decision,
  COUNTIF(leaving_type = 'Voluntary')                        AS voluntary,
  COUNTIF(leaving_type = 'Involuntary')                      AS involuntary,
  ROUND(100 * COUNTIF(exit_bucket = 'Controllable') / COUNT(*), 1) AS controllable_pct
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
GROUP BY department
ORDER BY exits DESC;
-- Result:
--   - Production: 48 of 83 exits controllable (57.8%).
--   - IT/IS: 3 of 10 (30.0%) controllable. Half of its exits (5) were company decisions.
--   - Sales 1 of 5, Software Engineering 1 of 4, Admin Offices 0 of 2. Too few
--     exits to read much into.

-- b) Production vs the rest of the company
SELECT
  IF(department = 'Production', 'Production', 'All other departments')  AS dept_group,
  COUNT(*)                                                               AS exits,
  COUNTIF(exit_bucket = 'Controllable')                                  AS controllable,
  ROUND(100 * COUNTIF(exit_bucket = 'Controllable') / COUNT(*), 1)       AS controllable_pct
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
GROUP BY dept_group;
-- Result: Production 57.8% controllable vs 23.8% (5 of 21) everywhere else.

-- c) Where do the controllable reasons happen?
SELECT
  term_reason,
  COUNT(*)                               AS exits,
  COUNTIF(department = 'Production')     AS production,
  COUNTIF(department != 'Production')    AS other_depts
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
WHERE exit_bucket = 'Controllable'
GROUP BY term_reason
ORDER BY exits DESC;
-- Result:
--   - another position: 17 of 20 in Production
--   - unhappy:          14 of 14 in Production
--   - more money:       11 of 11 in Production
--   - hours:             6 of 8 in Production
--   - Every exit for unhappiness or pay came from Production.


/* -----------------------------------------------------------------------------
   A3.5  Has the mix changed over time?
   Links back to the 2015-16 turnover spike found in A2.
   ----------------------------------------------------------------------------- */

SELECT
  exit_year,
  COUNT(*)                                                         AS exits,
  COUNTIF(exit_bucket = 'Controllable')                            AS controllable,
  COUNTIF(exit_bucket = 'Uncontrollable')                          AS uncontrollable,
  COUNTIF(exit_bucket = 'Company decision')                        AS company_decision,
  ROUND(100 * COUNTIF(exit_bucket = 'Controllable') / COUNT(*), 1) AS controllable_pct
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
GROUP BY exit_year
ORDER BY exit_year;
-- Result:
--   - Controllable exits were fairly steady at 7-10 a year from 2012 to 2016
--     (7, 10, 8, 10, 8), then 4 in 2017 and 6 in 2018.
--   - What grew in 2015-16 was the other two buckets. Company decisions went
--     from 0-1 a year to 5 and 6, and uncontrollable exits were 8 in each year.
--   - So the 2015-16 spike wasn't mainly people leaving for pay or a better
--     job. More dismissals and more life-event exits pushed it up.


/* -----------------------------------------------------------------------------
   A3.6  Inside Production: by position
   Follows up on A2, where Technician II had the highest turnover rate.
   ----------------------------------------------------------------------------- */

-- a) Controllable share by position
SELECT
  position,
  COUNT(*)                                                         AS exits,
  COUNTIF(exit_bucket = 'Controllable')                            AS controllable,
  COUNTIF(exit_bucket = 'Uncontrollable')                          AS uncontrollable,
  COUNTIF(exit_bucket = 'Company decision')                        AS company_decision,
  ROUND(100 * COUNTIF(exit_bucket = 'Controllable') / COUNT(*), 1) AS controllable_pct
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
WHERE department = 'Production'
GROUP BY position
ORDER BY exits DESC;
-- Result:
--   - Technician I: 28 of 52 controllable (53.8%), 8 company decisions.
--   - Technician II: 17 of 26 controllable (65.4%), 0 company decisions.
--   - Production Manager: 3 of 5 controllable.
--   - Technician II leavers are all people who chose to go, and two thirds of
--     them for reasons the company could influence.

-- b) Reasons for Technician II exits
SELECT term_reason, exit_bucket, COUNT(*) AS exits
FROM `hr-analysis-511005.hrdatasetv14.a3_exits`
WHERE position = 'Production Technician II'
GROUP BY term_reason, exit_bucket
ORDER BY exits DESC;
-- Result: unhappy 6, another position 4, more money 4, career change 4,
-- hours 3, then 1 each for return to school, relocation, retiring, military
-- and maternity leave.


/* =============================================================================
   A3 SUMMARY
   - Main reasons: another position (19.2%), unhappy (13.5%) and more money
     (10.6%) are the top three, together 45 of 104 exits.
   - Controllable: 51.0% of all exits (53) and 60.2% of voluntary exits were for
     reasons the company could influence. If career change counts too, it's 59.6% (% of all exits).
   - Where: almost entirely Production. 57.8% of its exits are controllable vs
     23.8% elsewhere, and every 'unhappy' and 'more money' exit was in Production.
   - Technician II: 65.4% controllable and no dismissals (company decision). These are experienced
     people choosing to leave, mostly over unhappiness, pay, hours or a better job.
   - The 2015-16 spike: controllable exits stayed steady. The jump came from
     more dismissals (5 and 6 a year vs 0-1 before) and life-event exits.

   Limitations:
   - Each leaver has a single exit reason, entered as free text. People often
     leave for more than one reason, so the split is approximate.
   - Classifying a reason as controllable is a judgement call (see the
     sensitivity check in A3.3).
   ============================================================================= */