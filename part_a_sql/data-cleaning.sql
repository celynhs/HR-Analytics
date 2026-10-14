/* =============================================================================
   PART A - A0: DATA CHECK AND CLEANING
   Table: hr-analysis-511005.hrdatasetv14.workforce  (HRDataset_v14 from Kaggle)
   311 employees, 36 columns. One row per employee.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   DATA DICTIONARY
   What each column means, and what the codes stand for.
   (Code meanings below are based on how they line up with the text columns in
   this file.)

   EMPLOYEE
   Employee_Name           Full name, written as "Last, First M"
   EmpID                   Unique employee ID
   Sex                     F = Female, M = Male
   GenderID                Code version of Sex: 0 = Female, 1 = Male
   DOB                     Date of birth (MM/DD/YY in the CSV; loaded into
                           BigQuery as a DATE, yyyy-mm-dd)
   MaritalDesc             Single, Married, Divorced, Separated, Widowed
   MaritalStatusID         Code version of MaritalDesc:
                             0 = Single, 1 = Married, 2 = Divorced,
                             3 = Separated, 4 = Widowed
   MarriedID               1 = Married, 0 = any other marital status
   CitizenDesc             US Citizen, Eligible NonCitizen, Non-Citizen
   HispanicLatino          Yes / No
   RaceDesc                Race/ethnicity (White, Black or African American,
                           Asian, Two or more races, American Indian or Alaska
                           Native, Hispanic)
   State, Zip              Home state and zip code

   JOB
   Department              Admin Offices, Executive Office, IT/IS, Production,
                           Sales, Software Engineering
   DeptID                  Code version of Department:
                             1 = Admin Offices, 2 = Executive Office,
                             3 = IT/IS, 4 = Software Engineering,
                             5 = Production, 6 = Sales
   Position                Job title (31 titles, e.g. Production Technician I)
   PositionID              Code version of Position (one number per title)
   ManagerName             Name of the employee's manager
   ManagerID               Code version of ManagerName
   Salary                  Annual salary (USD)

   HIRING
   DateofHire              Hire date, written M/D/YYYY
   RecruitmentSource       Where the employee was hired from (Indeed, LinkedIn,
                           Google Search, Employee Referral, Diversity Job Fair,
                           CareerBuilder, Website, Other, On-line Web application)
   FromDiversityJobFairID  1 = hired through the Diversity Job Fair, 0 = not

   EMPLOYMENT STATUS / LEAVING
   EmploymentStatus        Active, Voluntarily Terminated (resigned),
                           Terminated for Cause (dismissed)
   EmpStatusID             Code version of EmploymentStatus:
                             1 = Active, 4 = Terminated for Cause,
                             5 = Voluntarily Terminated
                             (2 and 3 also appear, but only on Active employees;
                              they don't match any label in this file)
   Termd                   1 = has left the company, 0 = still employed
   DateofTermination       Date the employee left, written M/D/YYYY
                           (blank if still employed)
   TermReason              Reason for leaving (free text);
                           'N/A-StillEmployed' for current employees

   PERFORMANCE AND ENGAGEMENT
   PerformanceScore        PIP (on a performance improvement plan),
                           Needs Improvement, Fully Meets, Exceeds
   PerfScoreID             Code version of PerformanceScore:
                             1 = PIP, 2 = Needs Improvement,
                             3 = Fully Meets, 4 = Exceeds
   EngagementSurvey        Engagement survey score, 1 to 5 (higher = more engaged)
   EmpSatisfaction         Satisfaction score, 1 to 5 (higher = more satisfied)
   SpecialProjectsCount    Number of special projects worked on
   LastPerformanceReview_Date  Date of last performance review, written M/D/YYYY
   DaysLateLast30          Days late to work in the last 30 days
   Absences                Number of absences
   ----------------------------------------------------------------------------- */


/* -----------------------------------------------------------------------------
   WHAT I NOTICED LOOKING THROUGH THE DATA
   1. Extra spaces: Department shows 'Production       ' and Sex shows 'M ' with
      trailing spaces. Some names also have double spaces
      (e.g. 'Adinolfi, Wilson  K').
   2. In the CSV the dates are written as M/D/YYYY. BigQuery recognised them and
      loaded hire, termination and review dates as real DATE columns, so I only
      need to check they make sense.
   3. DOB only has a two-digit year (e.g. 07/10/83). BigQuery may read years
      like '60' as 2060 instead of 1960.
   4. DateofTermination is blank for many rows, which should just mean the
      employee is still active.
   5. HispanicLatino is mostly 'Yes'/'No', but I spotted a lowercase 'no' and 'yes'.
      (BigQuery loaded it as TRUE/FALSE, which already merges these.)
   6. TermReason is inconsistent: some start with a capital ('Another position'),
      others don't ('unhappy'). A couple of entries don't look like real reasons
      ('Fatal attraction', 'Learned that he is a gangster').
   7. Lots of columns are just codes for another column (DeptID = Department,
      GenderID = Sex, etc.), so I need to check they actually match.
   8. A few salaries are much higher than the rest (e.g. the CEO at 250,000).
      Probably real, but worth checking.
   9. Zip codes start with 0 in the CSV (e.g. 01960), but BigQuery loaded Zip as a
      number, so the leading zero is gone (1960).
   ----------------------------------------------------------------------------- */


/* =============================================================================
   BASIC CHECKS
   ============================================================================= */

-- CHECK 1: Number of rows and whether each employee appears once
SELECT
  COUNT(*)              AS total_rows,
  COUNT(DISTINCT EmpID) AS unique_employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`;
-- Result: 311 rows and 311 unique EmpIDs, so there are no duplicate employees.


-- CHECK 2: Missing values in the columns that matter most
SELECT
  COUNTIF(EmpID IS NULL)             AS missing_emp_id,
  COUNTIF(DateofHire IS NULL)        AS missing_hire_date,
  COUNTIF(DateofTermination IS NULL) AS missing_termination_date,
  COUNTIF(Department IS NULL)        AS missing_department,
  COUNTIF(ManagerName IS NULL)       AS missing_manager_name,
  COUNTIF(ManagerID IS NULL)         AS missing_manager_id,
  COUNTIF(Salary IS NULL)            AS missing_salary
FROM `hr-analysis-511005.hrdatasetv14.workforce`;
-- Result: only DateofTermination (207) and ManagerID (8) have blanks.

-- Are the blank termination dates just the active employees?
SELECT
  EmploymentStatus,
  COUNT(*)                           AS employees,
  COUNTIF(DateofTermination IS NULL) AS blank_termination_date
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY EmploymentStatus;
-- Result: yes. All 207 Active employees have a blank termination date and
-- every leaver has one, so this is expected.

-- Whose ManagerID is blank?
SELECT ManagerName, COUNT(*) AS employees_with_blank_id
FROM `hr-analysis-511005.hrdatasetv14.workforce`
WHERE ManagerID IS NULL
GROUP BY ManagerName;
-- Result: all 8 blanks belong to one manager, Webster Butler.

-- Does that manager have an ID on his other rows?
SELECT ManagerName, ManagerID, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
WHERE ManagerName IN (
  SELECT DISTINCT ManagerName
  FROM `hr-analysis-511005.hrdatasetv14.workforce`
  WHERE ManagerID IS NULL)
GROUP BY ManagerName, ManagerID;
-- Result: his other 13 employees have ID 39, so the ID was just left out.
-- ManagerName is complete, so I'll use the name instead of the ID.


-- CHECK 3: Category values (the [ ] brackets make extra spaces visible)
SELECT CONCAT('[', Department, ']') AS department, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY Department ORDER BY employees DESC;
-- Result: 'Production' has trailing spaces (209 employees). The other 5
-- departments are fine. Executive Office only has 1 person (the CEO).

SELECT CONCAT('[', Sex, ']') AS sex, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY Sex;
-- Result: 'F' (176) and 'M ' with a trailing space (135).

SELECT HispanicLatino, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY HispanicLatino;
-- Result: BigQuery loaded this column as TRUE/FALSE (BOOL), so the mixed
-- 'yes'/'Yes' spellings from the CSV were already merged on upload. This just
-- confirms there are only two values and no blanks. I'll turn it back into
-- 'Yes'/'No' in the clean table so it reads better in Power BI.

SELECT CONCAT('[', Position, ']') AS position, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY Position ORDER BY position;
-- Result: 'Data Analyst' appears twice because one row is 'Data Analyst '
-- (trailing space). Everything else looks fine.

SELECT TermReason, EmploymentStatus, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
WHERE EmploymentStatus != 'Active'
GROUP BY TermReason, EmploymentStatus
ORDER BY employees DESC;
-- Result: 104 leavers across 17 reasons, with mixed capitalisation. Too many
-- small groups to compare, so I'll group them into a few broader categories.


-- CHECK 4: Do the dates make sense?
-- BigQuery already loaded DateofHire, DateofTermination and
-- LastPerformanceReview_Date as real DATE columns, so there's nothing to convert.
-- Instead I check the date ranges and that the dates are in a logical order.
SELECT
  MIN(DateofHire)                                AS first_hire,
  MAX(DateofHire)                                AS last_hire,
  MIN(DateofTermination)                         AS first_leaver,
  MAX(DateofTermination)                         AS last_leaver,
  COUNTIF(DateofTermination < DateofHire)        AS left_before_hired,   -- should be 0
  COUNTIF(DateofHire > CURRENT_DATE())           AS hired_in_future      -- should be 0
FROM `hr-analysis-511005.hrdatasetv14.workforce`;
-- Result: fill in from your output.

-- DOB was also loaded as a DATE (yyyy-mm-dd). Because the CSV only had a
-- two-digit year, check whether BigQuery guessed the century wrong.
SELECT
  COUNTIF(DOB > CURRENT_DATE()) AS dob_in_future,
  MIN(DOB)                      AS lowest_date,
  MAX(DOB)                      AS highest_date
FROM `hr-analysis-511005.hrdatasetv14.workforce`;
-- Result: fill in from your output. Any DOB in the future was given the wrong
-- century (e.g. 1960 read as 2060), so the cleaning step moves those back
-- 100 years.


-- CHECK 5: Do the code columns match their text columns?
SELECT Department, DeptID, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY Department, DeptID ORDER BY Department, DeptID;
-- Result: mostly consistent, but 1 Production employee has DeptID 6 (Sales'
-- code) and 1 Software Engineering employee has DeptID 1 (Admin Offices' code).

SELECT EmploymentStatus, EmpStatusID, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY EmploymentStatus, EmpStatusID ORDER BY EmploymentStatus, EmpStatusID;
-- Result: Active employees have codes 1, 2 and 3, and 2 'Terminated for Cause'
-- employees have code 1 (the Active code).

SELECT PerformanceScore, PerfScoreID, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY PerformanceScore, PerfScoreID ORDER BY PerfScoreID;
-- Result: 1 'Fully Meets' employee has code 1 (PIP's code) and 1 'PIP'
-- employee has code 3 (Fully Meets' code).

-- Overall: the text columns are consistent but the code columns aren't, so I'll
-- use the text columns and drop the codes. (Sex/GenderID and
-- MaritalDesc/MaritalStatusID do match, but they're still duplicates.)


-- CHECK 6: Do the leaving-related columns agree?
SELECT
  EmploymentStatus,
  Termd,
  DateofTermination IS NOT NULL      AS has_termination_date,
  TermReason = 'N/A-StillEmployed'   AS reason_says_still_employed,
  COUNT(*)                           AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce`
GROUP BY 1, 2, 3, 4;
-- Result: everything lines up. Active employees have Termd = 0, no termination
-- date and 'N/A-StillEmployed'; all leavers have Termd = 1, a date and a reason.


-- CHECK 7: Are the numbers within sensible ranges?
SELECT
  MIN(Salary) AS min_salary,                MAX(Salary) AS max_salary,
  MIN(EngagementSurvey) AS min_engagement,  MAX(EngagementSurvey) AS max_engagement,
  MIN(EmpSatisfaction) AS min_satisfaction, MAX(EmpSatisfaction) AS max_satisfaction,
  MIN(Absences) AS min_absences,            MAX(Absences) AS max_absences,
  MIN(DaysLateLast30) AS min_days_late,     MAX(DaysLateLast30) AS max_days_late
FROM `hr-analysis-511005.hrdatasetv14.workforce`;
-- Result: all scores are within their scales (engagement 1.12-5, satisfaction
-- 1-5, days late 0-6, absences 1-20). Salary goes from 45,046 to 250,000.

-- Who earns the most?
SELECT Position, Department, Salary
FROM `hr-analysis-511005.hrdatasetv14.workforce`
ORDER BY Salary DESC
LIMIT 10;
-- Result: the top salaries are senior roles (CEO, CIO, directors, IT managers),
-- so they're real, not errors. I'll keep them and use medians for pay
-- comparisons so they don't skew the averages.


/* =============================================================================
   CLEANING
   Creates workforce_clean, a cleaned copy of the data. The original table is
   left untouched.
   ============================================================================= */

CREATE OR REPLACE TABLE `hr-analysis-511005.hrdatasetv14.workforce_clean` AS

-- Step 1: fix the code columns first, so the mapping below starts from correct
-- codes. The text columns were consistent in Check 5, so I trust the text and
-- rebuild each code from it.
WITH manager_ids AS (
  -- One ID per manager, taken from the rows where the ID isn't blank
  SELECT ManagerName, MAX(ManagerID) AS known_manager_id
  FROM `hr-analysis-511005.hrdatasetv14.workforce`
  GROUP BY ManagerName
),

fixed AS (
  SELECT w.* REPLACE (

    -- Blank ManagerID -> use the ID the same manager has on his other rows
    -- (Webster Butler's 8 blanks become 39)
    COALESCE(w.ManagerID, m.known_manager_id)                 AS ManagerID,

    -- 'Accountant I' -> 'Accountant' (there is no Accountant II, so the
    -- 'I' doesn't add anything). Also removes the trailing space on 'Data Analyst '.
    CASE WHEN TRIM(Position) = 'Accountant I' THEN 'Accountant'
         ELSE TRIM(Position) END                              AS Position,

    -- DeptID rebuilt from Department (fixes the Production row coded 6 and the
    -- Software Engineering row coded 1)
    CASE TRIM(Department)
      WHEN 'Admin Offices'        THEN 1
      WHEN 'Executive Office'     THEN 2
      WHEN 'IT/IS'                THEN 3
      WHEN 'Software Engineering' THEN 4
      WHEN 'Production'           THEN 5
      WHEN 'Sales'                THEN 6
    END                                                       AS DeptID,

    -- EmpStatusID rebuilt from EmploymentStatus (Active coded 2 or 3 -> 1,
    -- Terminated for Cause coded 1 -> 4)
    CASE EmploymentStatus
      WHEN 'Active'                 THEN 1
      WHEN 'Terminated for Cause'   THEN 4
      WHEN 'Voluntarily Terminated' THEN 5
    END                                                       AS EmpStatusID,

    -- PerfScoreID rebuilt from PerformanceScore (fixes the Fully Meets row
    -- coded 1 and the PIP row coded 3)
    CASE PerformanceScore
      WHEN 'PIP'               THEN 1
      WHEN 'Needs Improvement' THEN 2
      WHEN 'Fully Meets'       THEN 3
      WHEN 'Exceeds'           THEN 4
    END                                                       AS PerfScoreID
  )
  FROM `hr-analysis-511005.hrdatasetv14.workforce` w
  LEFT JOIN manager_ids m
    ON w.ManagerName = m.ManagerName
)

-- Step 2: clean the rest and map the (now fixed) codes to labels
SELECT
  EmpID                                                    AS emp_id,
  REGEXP_REPLACE(TRIM(Employee_Name), r'\s+', ' ')         AS employee_name,  -- remove extra spaces

  -- Demographics
  TRIM(Sex)                                                AS sex,            -- 'M ' -> 'M'
  IF(DOB > CURRENT_DATE(),
     DATE_SUB(DOB, INTERVAL 100 YEAR), DOB)                AS date_of_birth,  -- 2060-07-10 -> 1960-07-10
  MaritalDesc                                              AS marital_status,
  CitizenDesc                                              AS citizenship,
  IF(HispanicLatino, 'Yes', 'No')                          AS hispanic_latino, -- TRUE -> 'Yes'
  RaceDesc                                                 AS race,
  State                                                    AS state,
  LPAD(CAST(Zip AS STRING), 5, '0')                        AS zip,            -- 1960 -> 01960

  -- Job
  TRIM(Department)                                         AS department,     -- remove trailing spaces
  Position                                                 AS position,       -- already fixed in step 1
  ManagerName                                              AS manager_name,
  ManagerID                                                AS manager_id,     -- blanks filled in step 1
  RecruitmentSource                                        AS recruitment_source,
  Salary                                                   AS salary,

  -- Employment and leaving
  DateofHire                                               AS hire_date,        -- already a DATE
  DateofTermination                                        AS termination_date, -- NULL = still employed
  EmploymentStatus                                         AS employment_status,
  EmploymentStatus != 'Active'                             AS has_left,
  CASE EmploymentStatus
    WHEN 'Voluntarily Terminated' THEN 'Voluntary'
    WHEN 'Terminated for Cause'   THEN 'Involuntary'
  END                                                      AS leaving_type,
  CASE WHEN EmploymentStatus = 'Active' THEN NULL
       ELSE LOWER(TermReason) END                          AS term_reason,
  CASE
    WHEN EmploymentStatus = 'Active' THEN NULL
    WHEN LOWER(TermReason) IN ('another position', 'career change', 'more money')
      THEN 'Career / better opportunity'
    WHEN LOWER(TermReason) IN ('unhappy', 'hours')
      THEN 'Work conditions'
    WHEN LOWER(TermReason) IN ('return to school', 'relocation out of area', 'retiring',
                               'military', 'maternity leave - did not return', 'medical issues')
      THEN 'Personal / life event'
    ELSE 'Conduct / performance'   -- attendance, performance, no-call no-show, misconduct
  END                                                      AS term_reason_group,

  -- Performance and engagement
  PerformanceScore                                         AS performance_score,
  EngagementSurvey                                         AS engagement_score,
  EmpSatisfaction                                          AS satisfaction_score,
  SpecialProjectsCount                                     AS special_projects,
  LastPerformanceReview_Date                               AS last_review_date,
  DaysLateLast30                                           AS days_late_last_30,
  Absences                                                 AS absences,

  -- Code columns mapped to their real category (using the data dictionary)
  -- DeptID, EmpStatusID and PerfScoreID were fixed in step 1, so these labels
  -- should now match the text columns exactly (confirmed in the check below).
  CASE GenderID
    WHEN 0 THEN 'Female'
    WHEN 1 THEN 'Male'
  END                                                      AS gender_from_code,

  CASE MaritalStatusID
    WHEN 0 THEN 'Single'
    WHEN 1 THEN 'Married'
    WHEN 2 THEN 'Divorced'
    WHEN 3 THEN 'Separated'
    WHEN 4 THEN 'Widowed'
  END                                                      AS marital_status_from_code,

  CASE MarriedID
    WHEN 1 THEN 'Married'
    WHEN 0 THEN 'Not married'
  END                                                      AS married,

  CASE
    WHEN EmpStatusID IN (1, 2, 3) THEN 'Active'      -- 2 and 3 only appear on Active rows
    WHEN EmpStatusID = 4          THEN 'Terminated for Cause'
    WHEN EmpStatusID = 5          THEN 'Voluntarily Terminated'
  END                                                      AS employment_status_from_code,

  CASE Termd
    WHEN 1 THEN 'Left'
    WHEN 0 THEN 'Still employed'
  END                                                      AS termination_status,

  CASE DeptID
    WHEN 1 THEN 'Admin Offices'
    WHEN 2 THEN 'Executive Office'
    WHEN 3 THEN 'IT/IS'
    WHEN 4 THEN 'Software Engineering'
    WHEN 5 THEN 'Production'
    WHEN 6 THEN 'Sales'
  END                                                      AS department_from_code,

  CASE PerfScoreID
    WHEN 1 THEN 'PIP'
    WHEN 2 THEN 'Needs Improvement'
    WHEN 3 THEN 'Fully Meets'
    WHEN 4 THEN 'Exceeds'
  END                                                      AS performance_from_code,

  CASE FromDiversityJobFairID
    WHEN 1 THEN 'Yes'
    WHEN 0 THEN 'No'
  END                                                      AS from_diversity_job_fair

  -- Not mapped: PositionID and ManagerID. They have 30+ values each and the
  -- Position and ManagerName text columns already give the same information.
FROM fixed;


-- QUICK CHECK OF THE CLEAN TABLE
SELECT
  COUNT(*)                         AS total_rows,         -- should be 311
  COUNTIF(has_left)                AS leavers,            -- should be 104
  COUNT(DISTINCT department)       AS departments,        -- should be 6
  COUNT(DISTINCT position)         AS positions,          -- should be 31 ('Data Analyst ' merged, 'Accountant I' renamed)
  COUNTIF(manager_id IS NULL)      AS blank_manager_id,   -- should be 0
  COUNT(DISTINCT sex)              AS sexes,              -- should be 2
  COUNT(DISTINCT hispanic_latino)  AS hispanic_values,    -- should be 2
  MIN(date_of_birth)               AS oldest_dob,         -- should be 1951-01-02
  MAX(date_of_birth)               AS youngest_dob        -- should be 1992-08-17
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`;

SELECT term_reason_group, leaving_type, COUNT(*) AS leavers
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
WHERE has_left
GROUP BY term_reason_group, leaving_type
ORDER BY leavers DESC;
-- Should show: Career / better opportunity 40, Personal / life event 24,
-- Work conditions 22, Conduct / performance 16 involuntary + 2 voluntary.

-- Do the mapped codes agree with the text columns?
SELECT
  COUNT(*)                                                           AS total_rows,
  COUNTIF(gender_from_code != IF(sex = 'F', 'Female', 'Male'))       AS gender_mismatch,
  COUNTIF(marital_status_from_code != marital_status)                AS marital_mismatch,
  COUNTIF(married = 'Married' AND marital_status != 'Married')       AS married_mismatch,
  COUNTIF(employment_status_from_code != employment_status)          AS status_mismatch,
  COUNTIF((termination_status = 'Left') != has_left)                 AS termd_mismatch,
  COUNTIF(department_from_code != department)                        AS department_mismatch,
  COUNTIF(performance_from_code != performance_score)                AS performance_mismatch,
  COUNTIF(from_diversity_job_fair = 'Yes'
          AND recruitment_source != 'Diversity Job Fair')            AS job_fair_mismatch
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`;
-- Result: every mismatch column should now be 0, because the wrong codes were
-- fixed in step 1. If any column isn't 0, a code still needs fixing.

-- Spot-check the fixes
SELECT position, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
WHERE position LIKE 'Accountant%' OR position LIKE 'Data Analyst%'
GROUP BY position;
-- Should show 'Accountant' and one 'Data Analyst' row only.

SELECT manager_name, manager_id, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
WHERE manager_name = 'Webster Butler'
GROUP BY manager_name, manager_id;
-- Should show one row: Webster Butler, 39, 21 employees.

SELECT department, department_from_code, COUNT(*) AS employees
FROM `hr-analysis-511005.hrdatasetv14.workforce_clean`
GROUP BY department, department_from_code ORDER BY department, department_from_code;