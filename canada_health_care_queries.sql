-- Q.1 Which hospitals are failing CTAS benchmarks, broken down by triage level? Calculate the benchmark breach
-- 		percentage for each hospital and CTAS level.

with cte as (select 
	h.hospital_name,
    e.ctas_level,
    e.patient_id,
	TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime) as wait_time,
    case 
		when e.ctas_level = 1 and TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime) <= 1 THEN 'not breached'
        when e.ctas_level = 2 and TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime) <= 15 THEN 'not breached'
        when e.ctas_level = 3 and TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime) <= 30 THEN 'not breached'
        when e.ctas_level = 4 and TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime) <= 60 THEN 'not breached'
        when e.ctas_level = 5 and TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime) <= 120 THEN 'not breached' else 'breached'
	end as breach_info
 from 
	ed_visits e join hospitals h 
    on e.hospital_id = h.hospital_id
    where seen_by_md_datetime IS NOT NULL)
    
    select 
		hospital_name, 
        ctas_level, 
        count(patient_id) as total_visit, 
        round(avg(wait_time),2) as avg_wait_time,
        round(sum(case when breach_info = 'breached' then 1 else 0 end)/count(breach_info) * 100,2) as percent_breach
	from cte
    group by ctas_level,hospital_name
    order by percent_breach desc;
    
    
-- Q.2 What is the LWBS rate per hospital and fiscal year? Compare community vs. teaching vs. rural hospitals. Which
-- 		hospital type has the worst LWBS trend?
select 
	h.hospital_name,
    h.hospital_type, 
    e.fiscal_year,
    count(patient_id) as total_visit,
    sum(case when e.disposition = 'left_without_seen' then 1 else 0 end) as LWBS,
    round(sum(case when e.disposition = 'left_without_seen' then 1 else 0 end)/count(patient_id) * 100,1) as lwbs_rate
from 
	hospitals h join ed_visits e on h.hospital_id = e.hospital_id
group by e.fiscal_year,h.hospital_type,h.hospital_name
order by lwbs_rate desc;

-- Q.3 For admitted patients, how many exceeded the 8-hour boarding threshold? Calculate average boarding hours per
-- hospital and identify the worst-performing sites.
select 
	h.hospital_name,
    h.province,
    count(patient_id) as admitted_patients,
    sum(case when TIMESTAMPDIFF(HOUR, seen_by_md_datetime, departure_datetime) > 8 then 1 else 0 end) as boarded_over_8H,
	round(avg(TIMESTAMPDIFF(HOUR, seen_by_md_datetime, departure_datetime)),1) as average_boarding_hours
 from ed_visits e join hospitals h on e.hospital_id = h.hospital_id
 where 
	e.disposition = 'admitted' and 
    e.seen_by_md_datetime is not null
 group by 
	h.hospital_name,
	h.province
order by boarded_over_8H desc;
    

-- Q.4 At what hours and days of the week does ED volume peak for teaching vs. community vs. rural hospitals? What is the
-- average wait time during peak vs. off-peak hours?
select 
    h.hospital_type,
    DAYNAME(arrival_datetime) as day_name,
    HOUR(arrival_datetime) as hour,
    count(visit_id) as visit_count,
    round(avg(TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime)),2) as avg_wait_time
from hospitals h join ed_visits e on h.hospital_id = e.hospital_id
where e.seen_by_md_datetime is not null
group by 
	h.hospital_type,
    day_name,
    hour
order by visit_count desc;


-- Q.5 How many patients visited the ED 4 or more times in a fiscal year? What are the most common chief complaints for
-- these patients, and which provinces have the highest high-utilizer rates?
with complaint_count as (SELECT 
        p.province,
        p.patient_id,
        e.fiscal_year,
        e.chief_complaint,
        COUNT(*) AS complaint_rep_count,
        COUNT(*) OVER(PARTITION BY p.patient_id, e.fiscal_year) as total_patient_visits
    FROM patients p 
    JOIN ed_visits e ON p.patient_id = e.patient_id
    GROUP BY 
          e.fiscal_year,p.patient_id,p.province, e.chief_complaint
), ranked_complaint as ( 
	select 
		*, 
        row_number() over(partition by fiscal_year ,patient_id order by complaint_rep_count desc) as rnk
	from complaint_count
)
    
select 
	province,
    fiscal_year,
    count(patient_id) as total_patient,
    GROUP_CONCAT(
        CONCAT(chief_complaint, ' (', complaint_rep_count, ')') 
        ORDER BY complaint_rep_count DESC SEPARATOR ', '
    ) AS common_complaints
from ranked_complaint 
where 
	total_patient_visits >=4 and
    rnk <= 2
group by 
	fiscal_year, province
order by 
	total_patient desc;



-- Q.6 Does increasing physicians on duty during a shift reduce average wait times? Is the relationship different for 
-- day vs. evening vs. night shifts?
select 
	p.shift_type,
    p.physicians_on_duty,
    round(avg(TIMESTAMPDIFF(MINUTE, e.triage_datetime, e.seen_by_md_datetime)),2) as wait_time,
    count(e.patient_id) as total_visit
 from 
	hospitals h join ed_visits e on e.hospital_id = h.hospital_id
	join physician_shifts p on p.hospital_id = h.hospital_id and 
	e.arrival_datetime BETWEEN p.shift_start AND p.shift_end
where e.seen_by_md_datetime is not null
group by 
	p.shift_type,
    p.physicians_on_duty
order by wait_time desc, physicians_on_duty desc;

-- Q.7 Do rural hospitals serve patients with higher average acuity (lower CTAS scores) and older age, yet deliver 
-- worse wait times compared to urban teaching hospitals?
select 
	h.hospital_type,
    h.province,
    round(avg(p.age),2) as avg_age,
    round(avg(e.ctas_level),2) as avg_ctas_level,
    round(avg(TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime)),2) as avg_wait_time,
    COUNT(DISTINCT e.patient_id) as unique_patient
from 
	hospitals h join ed_visits e on h.hospital_id = e.hospital_id
    join patients p on p.patient_id = e.patient_id
where
	e.seen_by_md_datetime is not null
group by 
	h.hospital_type,
    h.province
order by 
	h.province, avg_wait_time desc;
    
-- Q.8 Rank each hospital within its province by average ED wait time. How far is each hospital 
-- above or below the provincial average?

with wait_time as (select 
	h.hospital_name,
    h.province,
    round(avg(TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime)),2) as avg_wait_time
from ed_visits e join hospitals h on e.hospital_id = h.hospital_id
where
	e.seen_by_md_datetime is not null
group by h.province, h.hospital_name),

p_avg as (
	select 
		*,
        ROUND(AVG(avg_wait_time) OVER(PARTITION BY province), 2) AS provincial_avg
	from wait_time
)
select 
	hospital_name,
	province,
    avg_wait_time,
    rank() over (partition by province order by avg_wait_time desc) as hospital_rank,
    case 
		when avg_wait_time > provincial_avg then "Worse than Provincial Average"
        when avg_wait_time < provincial_avg then "Better than Provincial Average"
        Else "Exactly Average"
	End as performance_status,
    ROUND(avg_wait_time - provincial_avg, 2) AS deviation_from_avg
from p_avg
order by 
	province;


