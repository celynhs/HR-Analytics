# HR Analytics: Workforce, Turnover and Attrition Risk

An end-to-end HR analytics project covering descriptive workforce reporting in **SQL (BigQuery)** and predictive attrition modelling in **Python**. The goal is to answer questions HR leaders actually ask: who is leaving, why, what it costs, and what to do about it.

> **A note on the data**
> This project uses **two separate datasets from different sources**. They describe different (fictional) organisations and are **not linked** in any way. I've combined them into one project only to show how I would approach HR analysis end to end, from workforce reporting to predictive modelling. Each part should be read on its own.

| | Part A: Workforce and turnover analysis | Part B: Attrition drivers and risk model |
|---|---|---|
| **Dataset** | [HRDataset_v14](https://www.kaggle.com/datasets/rhuebner/human-resources-data-set) (Kaggle, Huebner & Patalano) | [employee_attrition_hr_2026]([https://www.kaggle.com/datasets/rhuebner/human-resources-data-set](https://www.kaggle.com/datasets/uditjain13/employee-attrition-and-hr-analytics-2026)) |
| **Size** | 311 employees, 36 columns | 5,000 employees, 895 leavers |
| **What it has** | Hire and exit dates, exit reasons, managers, recruitment source, performance | Wellbeing scores, pay and promotion history, work mode, AI exposure (no dates) |
| **Tools** | BigQuery SQL | Python (pandas, scipy, statsmodels, scikit-learn) |
| **Focus** | Trends, exit reasons, managers, hiring channels, pay equity | Statistical drivers, risk model, cost of attrition, fairness |

---

## Repository structure

```
HR-Analytics/
├── README.md
├── part_a_sql/
│   ├── A0_data_check_and_cleaning.sql
│   ├── A1_workforce_profile.sql
│   ├── A2_turnover_trend.sql
│   ├── A3_exit_reasons.sql
│   ├── A4_recruitment_source.sql
│   ├── A5_manager_effect.sql
│   ├── A6_performance_engagement_exits.sql
│   └── A7_pay_equity.sql
├── part_b_python/
│   └── HR_Analysis.ipynb
└── data/
    ├── HRDataset_v14.csv
    └── employee_attrition_hr_2026.csv
```

Every SQL file follows the same pattern. A starting-point query shows the simple "early signal", a check tests whether that signal is misleading, and the analysis follows. Each query has a short comment with its result, and every number in this README comes from a query or notebook output.

---

## Part A: Workforce and turnover analysis (SQL)

### A0. Data check and cleaning
- Wrote a data dictionary for all 36 columns, including what every code means (e.g. `EmpStatusID` 1 = Active, 5 = Voluntarily Terminated).
- **Issues found and fixed:**
  - trailing spaces (`'Production       '`, `'M '`)
  - two-digit birth years read as 2060s instead of 1960s
  - blank manager IDs
  - code columns that didn't match their text columns (e.g. a Production employee coded as Sales)
  - zip codes that lost their leading zero
- Built a clean table, `workforce_clean`, that rebuilds the codes from the text, maps codes to labels, and groups 17 free-text exit reasons into 4 categories.

### A1. Workforce profile
- **Headcount:** grew from 21 at the end of 2010 to a peak of **229 in 2015**, then fell to **207 by the end of 2018**.
- **Hiring vs exits:** hiring peaked in 2011 (83 hires) and then fell sharply: 14 in 2016, 6 in 2017, 1 in 2018. Exits kept going (13 in 2018), so headcount shrank.
- **Departments and roles:** Production is 60.9% of staff. Production Technician I is the biggest role (85 people).
- **Demographics:** 56% female, 52.7% aged 30–39, 59.9% White and 24.6% Black or African American.
- **Tenure:** current staff have been with the company 5.5 years on average. Leavers stayed 3.5 years.

### A2. Turnover trend
- **Trend:** annual turnover (exits ÷ average headcount) was 5–8% from 2011 to 2014, **peaked at 10.3% in 2015 and 9.8% in 2016**, then eased to 3.6% (2017) and 6.1% (2018). The average across all years is 7.2% (6.1% voluntary, 1.1% involuntary).
- **Production:** the raw numbers say 40% of Production staff have ever left vs 16% in Sales. As a proper annual rate that's **8.3% vs 3.1%**. Production is 69% of the workforce but **80% of exits**.
- **Within Production:** Technician II has the highest turnover (11.7% a year).

### A3. Why people leave
- **Top reasons:** another position (19.2%), unhappy (13.5%), more money (10.6%).
- **51.0% of exits were controllable** (pay, hours, unhappiness, a better offer), and 60.2% of voluntary exits.
- **Every** "unhappy" and "more money" exit came from Production.
- The 2015–16 spike wasn't driven by controllable exits, which stayed at 7–10 a year. It came from more dismissals and life-event exits.

### A4. Recruitment source quality
- **The early signal:** 61% of Google Search hires have left vs 16% of referrals. But Google Search mostly hired into Production (89.8%) and in earlier years, and both make a channel look worse.
- **After correcting for both** (fixed 1/2/3-year retention windows, and comparing within Production only), **Google Search is still the weakest channel**. 71.4% are still employed after 3 years vs 85.3% overall, and it has the fewest top performers.
- **Referrals and LinkedIn are the strongest** (93.1% and 90.1% after 3 years). Referrals also have the best performance mix.
- Indeed loses people earliest (93.0% retained at 1 year vs 97.1% overall).

### A5. Manager effect
- **A fair comparison:** the 9 Production technician managers run near-identical teams (21–22 people, same role mix, same hiring years).
- **Turnover vs expected:** against a peer rate of 8.2% a year, **Amy Dunn and Webster Butler each lost 13 people vs 7.4 expected** (1.75× expected rate), and Kissy Sullivan 12 vs 8.8.
- **The reasons differ:**
  - Amy Dunn's team accounts for **6 of the 19 exits for unhappiness or hours**, the reasons a line manager shapes.
  - Webster Butler's exits were mostly life events.
  - Pay and better-offer exits are spread evenly across all teams, which points to a company-level issue.
- **Engagement scores don't track manager turnover.** Webster Butler's team has the highest engagement.

### A6. Performance, engagement and exits
- **By rate:** weaker performers leave faster (Needs Improvement 11.2% a year vs Exceeds 3.9%).
- **By volume:** **85.6% of leavers were strong performers** (Fully Meets or Exceeds), because that's 90% of the workforce.
- **Regretted attrition** (strong performers who resigned) is **80 of 104 exits (76.9%)**. 61.3% of them left for controllable reasons.
- **Voluntary leavers score the same on engagement as stayers** (4.18 vs 4.12), so the survey isn't an early warning.

### A7. Pay equity
- **Overall gap (current staff):** 1.5% on the mean and 2.0% on the median, in men's favour.
- **Like for like (same position):** −0.5%. Women are paid about the same as men for the same job.
- **Where the gap comes from:** a mix effect. 64.7% of women work in Production vs 56.0% of men, and Production pays less.
- **Roles worth a closer look:** Area Sales Manager and Production Manager (small samples).

### Part A recommendations
1. **Focus retention on Production**, especially experienced Technician II staff. Benchmark pay, review rosters and hours, and make the Technician → Manager career path clear.
2. **Track regretted attrition as its own KPI** (baseline: 5.9% of strong performers a year).
3. **Shift recruitment budget** towards referrals and LinkedIn, review spend on Google Search, and look at first-year onboarding for Indeed hires.
4. **Run stay interviews on high-turnover teams**, starting with Amy Dunn's, where unhappiness and hours drive exits.
5. **Improve the early-warning signal.** Add intent-to-stay, pay and workload questions to the engagement survey.
6. **Keep checking pay equity every year.** Look at why more women sit in lower-paid Production roles.
7. **Restart and plan hiring.** Hiring nearly stopped after 2016 while exits continued.

---

## Part B: Attrition drivers and risk model (Python)

**Business question:** what drives employees to leave, which groups are most at risk, and what would reducing attrition be worth?

**Methods:** data validation (15 sanity checks with flag columns), non-parametric tests (Mann-Whitney U, chi-square, Spearman), effect sizes (Cramér's V, odds ratios), logistic regression, mediation analysis, permutation importance, model evaluation (AUC, PR-AUC, calibration, lift), cost simulation and fairness checks.

### Key findings
1. **Group membership alone explains little.** Attrition is 17.9% overall. It's highest in Customer Support (24.1%) and among onsite staff (21.2%), but these effects are weak on their own (Cramér's V < 0.15).
2. **Wellbeing is the strongest driver.** Low-burnout employees leave at 4.6%, against 51.5% for the most burnt-out. Wellbeing alone nearly matches the full model (CV AUC 0.762 vs 0.777). About 91% of overtime's effect runs through burnout.
3. **Stalled careers matter more than pay level.** Attrition rises from 14.2% (promoted within the last year) to 35.5% (no promotion for 6+ years). Pay relative to peers has no independent effect.
4. **AI job anxiety is a distinct driver** (about +11% odds per point), and using AI tools doesn't reduce it. Work mode, commute and travel have no independent effect once burnout is accounted for.
5. **A simple model finds most at-risk employees.** Test AUC is 0.769, and the riskiest 20% of employees contain 45.5% of leavers. Attrition ranges from 4.9% (Low risk tier) to 51.2% (Very high).
6. **Most drivers are within the company's control.** 7 of the 8 key drivers are things the company can change or influence, accounting for 87.9% of the model's predictive power.
7. **Attrition is costly.** It costs about $35.5M a year (8.54% of payroll; range $21.3M–$70.9M). A targeted package for the 23.7% of staff in the High and Very high risk tiers could save about **$6.54M a year**.
8. **The model is fair across gender** (AUC 0.779 women vs 0.772 men) but **weaker for employees aged 50+** (AUC 0.724).

### Part B recommendations
1. **Launch a targeted retention programme** for High and Very high risk employees, starting with Customer Support and onsite teams.
2. **Make burnout reduction the first priority.** A 1-point reduction among high-risk staff could save about $2.75M a year.
3. **Invest in managers.** Manager support is the strongest protective factor (−19.2% odds per point).
4. **Fix career progression before pay levels.** Review anyone approaching 3 years without a promotion.
5. **Address AI-related job anxiety** with clear communication and reskilling paths.
6. **Use the risk model responsibly.** Risk scores should only start supportive conversations. For staff aged 50+, add regular career conversations.

---

## What the two parts show together

The datasets are unrelated, but some themes came up in both:
- **Most attrition is controllable.** 51% of exits in Part A were for controllable reasons. In Part B, 7 of the 8 key drivers are changeable.
- **Managers and career progression matter more than pay level.** Part A's manager comparison and Part B's promotion-timing effect point the same way.
- **Engagement surveys alone are a weak early warning.** In Part A, leavers scored the same as stayers. In Part B, burnout and manager support carried more signal.

---

## Limitations
- **Part A:** a small company (311 people), one row per person (latest department, manager and score only), and a single free-text exit reason. Small groups are flagged throughout.
- **Part B:** no dates (a single snapshot), self-reported wellbeing measures, and likely synthetic data. All findings are associations, not proven causes.
- **Cost estimates** in Part B rely on assumed replacement costs (30–100% of salary).

---

*Author: Jocelin · [LinkedIn](https://www.linkedin.com/in/jocelin-helsa-418092264/) · [Email](celinhelsa28@gmail.com)*
