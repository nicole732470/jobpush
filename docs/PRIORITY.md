# JobPush priority rule

## Current rule: selected SOC roles v1

The source workbook is `outputs/job_roles_20260621/LCA_All_Job_Roles_Summary.xlsx`,
sheet `SOC标准岗位汇总`, column `是否目标`.

- The user selected 282 source rows.
- After normalizing and deduplicating SOC codes, 98 target codes remain.
- A company receives `priority_score = 1` when at least one of its LCA rows
  has an active code in `jobpush.target_soc_roles`.
- A company with no matching LCA rows receives `priority_score = 0`.
- Industry, recency, certification status, and LCA volume do not add points.

### Why raw job titles do not need a second matching rule

Every raw `job_title` belongs to an LCA row that already carries `soc_code`.
When that SOC code is selected, all corresponding raw job titles are included.
This is more reliable than fuzzy text matching and avoids duplicate or misspelled
raw titles changing a company's priority.

### SOC-code normalization

Codes are stored as eight digits: major group + detailed occupation + two-digit
extension. A code without an extension receives `00`; for example,
`15-1252`, `15-1252.00`, and `15-1252.00 - Software Developers` normalize to
`15125200`. Non-zero extensions remain distinct, such as `15-2051.01` becoming
`15205101`.

## Deduplicated target codes

| Normalized SOC code | Representative selected title | Selected title variants |
|---|---|---:|
| `11102100` | General and Operations Managers | 1 |
| `11202100` | Marketing Managers | 3 |
| `11302100` | Computer and Information Systems Managers | 7 |
| `11303100` | Financial Managers | 3 |
| `11303103` | Investment Fund Managers | 1 |
| `11904100` | Architectural and Engineering Managers | 1 |
| `11919900` | Managers, All Other | 1 |
| `12125200` | Software Developers | 1 |
| `12129909` | Information Technology Project Managers | 1 |
| `12205100` | Data Scientists | 1 |
| `13108200` | Project Management Specialists | 1 |
| `13111100` | MANAGEMENT ANALYSTS | 1 |
| `13116100` | Market Research Analysts and Marketing Specialists | 8 |
| `13119900` | Business Operations Specialists, All Other | 1 |
| `13205100` | Financial and Investment Analysts | 4 |
| `13205101` | Business Intelligence Analysts | 1 |
| `13205400` | Financial Risk Specialists | 2 |
| `13209900` | Financial Specialists, All Other | 2 |
| `13209901` | Financial Quantitative Analysts | 2 |
| `15102200` | Computer Programmers, Non R&D | 1 |
| `15103400` | Software Developers, Applications, Non R&D | 1 |
| `15103500` | Software Developers, Applications, R&D | 1 |
| `15103600` | Software Developers, Systems Software, Non R&D | 1 |
| `15105200` | Computer Systems Analysts, Non R&D | 1 |
| `15105300` | Computer Systems Analysts, R&D | 1 |
| `15105400` | Computer Network Architects, Non R&D | 1 |
| `15111100` | Computer and Information Research Scientists | 1 |
| `15112100` | Computer Systems Analysts | 3 |
| `15112200` | Information Security Analysts | 1 |
| `15113100` | Computer Programmers | 1 |
| `15113200` | Software Developers, Applications | 2 |
| `15113300` | Software Developers, Systems Software | 2 |
| `15113400` | Web Developers | 1 |
| `15114100` | Database Administrators | 2 |
| `15114200` | Network and Computer Systems Administrators | 1 |
| `15114300` | Computer Network Architects | 1 |
| `15115100` | Computer User Support Specialists | 1 |
| `15115200` | Computer Network Support Specialists | 1 |
| `15119900` | Computer Occupations, All Other | 1 |
| `15119901` | Software Quality Assurance Engineers and Testers | 1 |
| `15119902` | Computer Systems Engineers/Architects | 1 |
| `15119903` | Web Administrators | 1 |
| `15119906` | Database Architects | 1 |
| `15119907` | Data Warehousing Specialists | 1 |
| `15119908` | Business Intelligence Analysts | 2 |
| `15119909` | Information Technology Project Managers | 1 |
| `15119910` | Search Marketing Strategists | 1 |
| `15121100` | Computer Systems Analysts | 5 |
| `15121109` | Computer Systems Analysts | 1 |
| `15121200` | Information Security Analysts | 2 |
| `15121700` | Computer Systems Analysts, Non R&D | 2 |
| `15121800` | Computer Systems Analysts, R&D | 1 |
| `15122100` | Computer and Information Research Scientists | 2 |
| `15123100` | Computer Network Support Specialists | 2 |
| `15123200` | Computer User Support Specialists | 1 |
| `15124100` | Computer Network Architects | 1 |
| `15124101` | Telecommunications Engineering Specialists | 1 |
| `15124200` | Database Administrators | 4 |
| `15124300` | Database Architects | 4 |
| `15124301` | Data Warehousing Specialists | 2 |
| `15124400` | Network and Computer Systems Administrators | 6 |
| `15124700` | Computer Network Architects, Non R&D | 1 |
| `15124800` | Computer Network Architects, R&D | 1 |
| `15125100` | Computer Programmers | 4 |
| `15125200` | Software Developers | 23 |
| `15125300` | Software Quality Assurance Analysts and Testers | 12 |
| `15125400` | Web Developers | 1 |
| `15125500` | Web and Digital Interface Designers | 4 |
| `15129300` | Computer Programmers, Non R&D | 1 |
| `15129400` | Computer Programmers, R&D | 1 |
| `15129500` | Software Developers, Non R&D | 5 |
| `15129600` | Software Developers, R&D | 1 |
| `15129700` | Software Quality Assurance Analysts and Testers, Non R&D | 2 |
| `15129800` | Software Quality Assurance Analysts and Testers, R&D | 1 |
| `15129900` | Computer Occupations, All Other | 10 |
| `15129901` | Web Administrators | 1 |
| `15129902` | Geographic Information Systems Technologists and Technicians | 2 |
| `15129905` | Information Security Engineers | 2 |
| `15129906` | Information Technology Project Managers | 1 |
| `15129908` | Computer Systems Engineers/Architects | 9 |
| `15129909` | Information Technology Project Managers | 7 |
| `15129950` | Computer Occupations, ALL Other | 1 |
| `15203100` | Operations Research Analysts | 3 |
| `15204100` | Statisticians | 2 |
| `15205100` | Data Scientists | 5 |
| `15205101` | Business Intelligence Analysts | 7 |
| `15205102` | Business Intelligence Analyst | 1 |
| `17125200` | Software Developers | 1 |
| `17206300` | Computer Hardware Engineers, R&D | 1 |
| `19302200` | Survey Researchers | 1 |
| `25102100` | Computer Science Teachers, Postsecondary | 1 |
| `29102100` | Dentists, General | 1 |
| `33302106` | Intelligence Analysts | 1 |
| `40903100` | Sales Engineers | 2 |
| `41303100` | Securities, Commodities, and Financial Services Sales Agents | 1 |
| `41903100` | Sales Engineers | 2 |
| `41909900` | Sales and Related Workers, All Other | 1 |
| `43911100` | Statistical Assistants | 1 |
