-- ============================================================
-- Canadian ED Analytics — Stored Procedures
-- Database : hospital_DB
-- Total    : 7 Stored Procedures
-- Author   : Sabin Mainali
-- ============================================================

DELIMITER //

-- ============================================================
-- PROCEDURE 1: get_total_visits
-- Returns the total number of ED visits recorded in the
-- database across all hospitals and fiscal years.
-- Usage: CALL get_total_visits();
-- ============================================================

DROP PROCEDURE IF EXISTS get_total_visits //
CREATE PROCEDURE get_total_visits()
BEGIN
    SELECT COUNT(*) AS total_visits FROM ed_visits;
END //


-- ============================================================
-- PROCEDURE 2: get_visits_by_province
-- Returns total ED visits and average wait time for a given
-- province. Filters out LWBS patients (NULL seen_by_md).
-- Parameters: IN prov VARCHAR(20) — province code e.g. 'ON'
-- Usage: CALL get_visits_by_province('ON');
-- ============================================================

DROP PROCEDURE IF EXISTS get_visits_by_province //
CREATE PROCEDURE get_visits_by_province(IN prov VARCHAR(20))
BEGIN
    SELECT
        h.province,
        COUNT(e.patient_id)                                                        AS total_visits,
        ROUND(AVG(TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime)), 1) AS avg_wait_time
    FROM ed_visits e
    JOIN hospitals h ON e.hospital_id = h.hospital_id
    WHERE seen_by_md_datetime IS NOT NULL
      AND h.province = prov
    GROUP BY h.province;
END //


-- ============================================================
-- PROCEDURE 3: get_avg_wait_by_type
-- Returns average ED wait time for a given hospital type
-- using an OUT parameter. Filters out LWBS patients.
-- Parameters: IN  h_type VARCHAR(20) — 'teaching','community','rural'
--             OUT avg_wait DECIMAL(10,1) — average wait in minutes
-- Usage: CALL get_avg_wait_by_type('rural', @result);
--        SELECT @result;
-- ============================================================

DROP PROCEDURE IF EXISTS get_avg_wait_by_type //
CREATE PROCEDURE get_avg_wait_by_type(IN h_type VARCHAR(20), OUT avg_wait DECIMAL(10,1))
BEGIN
    SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime)), 1)
    INTO avg_wait
    FROM ed_visits e
    JOIN hospitals h ON e.hospital_id = h.hospital_id
    WHERE seen_by_md_datetime IS NOT NULL
      AND h.hospital_type = h_type;
END //


-- ============================================================
-- PROCEDURE 4: ed_summary
-- Calculates overall ED summary statistics across all hospitals:
-- total visits, total admissions, and admission rate percentage.
-- Uses local variables and SELECT INTO.
-- Usage: CALL ed_summary();
-- ============================================================

DROP PROCEDURE IF EXISTS ed_summary //
CREATE PROCEDURE ed_summary()
BEGIN
    DECLARE total_visits   INT           DEFAULT 0;
    DECLARE total_admitted INT           DEFAULT 0;
    DECLARE admission_rate DECIMAL(5,2)  DEFAULT 0.0;

    SELECT COUNT(*) INTO total_visits   FROM ed_visits;
    SELECT COUNT(*) INTO total_admitted FROM ed_visits WHERE disposition = 'admitted';

    SET admission_rate = (total_admitted / total_visits) * 100;

    SELECT total_visits, total_admitted, ROUND(admission_rate, 2) AS admission_rate_pct;
END //


-- ============================================================
-- PROCEDURE 5: rate_hospital
-- Classifies a hospital's ED performance based on average
-- wait time using IF/ELSE logic.
-- Ratings: Excellent (<50 min) | Acceptable (50-80) |
--          Needs Improvement (81-100) | Critical (>100)
-- Parameters: IN h_id VARCHAR(10) — hospital ID e.g. 'H001'
-- Usage: CALL rate_hospital('H001');
-- ============================================================

DROP PROCEDURE IF EXISTS rate_hospital //
CREATE PROCEDURE rate_hospital(IN h_id VARCHAR(10))
BEGIN
    DECLARE avg_wait DECIMAL(10,1) DEFAULT 0.0;

    SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime)), 1)
    INTO avg_wait
    FROM ed_visits
    WHERE hospital_id = h_id
      AND seen_by_md_datetime IS NOT NULL;

    IF avg_wait IS NULL THEN
        SELECT h_id AS hospital, 'No Data'  AS avg_wait_min, 'No Visits Recorded' AS performance;
    ELSEIF avg_wait <= 50 THEN
        SELECT h_id AS hospital, avg_wait   AS avg_wait_min, 'Excellent'           AS performance;
    ELSEIF avg_wait <= 80 THEN
        SELECT h_id AS hospital, avg_wait   AS avg_wait_min, 'Acceptable'          AS performance;
    ELSEIF avg_wait <= 100 THEN
        SELECT h_id AS hospital, avg_wait   AS avg_wait_min, 'Needs Improvement'   AS performance;
    ELSE
        SELECT h_id AS hospital, avg_wait   AS avg_wait_min, 'Critical'            AS performance;
    END IF;
END //


-- ============================================================
-- PROCEDURE 6: generate_shifts
-- Bulk inserts test physician shift records for a given
-- hospital using a WHILE loop. Includes input validation
-- and a 100-shift safety cap to prevent abuse.
-- Parameters: IN h_id       VARCHAR(10) — hospital ID
--             IN num_shifts INT         — number of shifts to insert (max 100)
-- Usage: CALL generate_shifts('H001', 5);
-- Cleanup: DELETE FROM physician_shifts WHERE shift_id LIKE 'TST%';
-- ============================================================

DROP PROCEDURE IF EXISTS generate_shifts //
CREATE PROCEDURE generate_shifts(IN h_id VARCHAR(10), IN num_shifts INT)
BEGIN
    DECLARE counter INT DEFAULT 1;

    IF h_id IS NULL OR num_shifts IS NULL OR num_shifts > 100 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid inputs. num_shifts must be between 1 and 100.';
    ELSE
        WHILE counter <= num_shifts DO
            INSERT INTO physician_shifts
                (shift_id, hospital_id, physician_id, shift_start, shift_end, physicians_on_duty, shift_type)
            VALUES (
                CONCAT('TST', counter),
                h_id,
                CONCAT('DR', counter + 5000),
                '2024-06-01 07:00:00',
                '2024-06-01 15:00:00',
                3,
                'day'
            );
            SET counter = counter + 1;
        END WHILE;

        SELECT CONCAT(num_shifts, ' shifts inserted for ', h_id) AS result;
    END IF;
END //


-- ============================================================
-- PROCEDURE 7: hospital_performance_report
-- Generates a complete ED performance report for any hospital
-- and fiscal year. Calculates 5 key metrics and automatically
-- assigns performance ratings using nested IF/ELSE logic.
-- Includes NULL checks, division-by-zero protection, and
-- input validation.
--
-- Metrics   : total visits, avg wait time, LWBS rate,
--             admission rate, avg boarding hours
-- Ratings   : wait_performance — Excellent/Acceptable/
--                                Needs Improvement/Critical
--             lwbs_performance — Good/Warning/Critical
--
-- Parameters: IN h_id VARCHAR(10) — hospital ID e.g. 'H001'
--             IN fy   VARCHAR(7)  — fiscal year e.g. '2023-24'
-- Usage: CALL hospital_performance_report('H001', '2023-24');
-- ============================================================

DROP PROCEDURE IF EXISTS hospital_performance_report //
CREATE PROCEDURE hospital_performance_report(IN h_id VARCHAR(10), IN fy VARCHAR(7))
BEGIN
    DECLARE total_visits     INT           DEFAULT 0;
    DECLARE lwbs_visits      INT           DEFAULT 0;
    DECLARE admission_visits INT           DEFAULT 0;
    DECLARE avg_wait         DECIMAL(10,1) DEFAULT 0.0;
    DECLARE lwbs_rate        DECIMAL(10,1) DEFAULT 0.0;
    DECLARE admission_rate   DECIMAL(10,1) DEFAULT 0.0;
    DECLARE avg_boarding_hrs DECIMAL(10,1) DEFAULT 0.0;
    DECLARE wait_performance VARCHAR(20)   DEFAULT 'NA';
    DECLARE lwbs_performance VARCHAR(20)   DEFAULT 'NA';

    IF h_id IS NULL OR fy IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'hospital_id and fiscal_year are required.';
    ELSE
        SELECT COUNT(*)
        INTO total_visits
        FROM ed_visits
        WHERE hospital_id = h_id AND fiscal_year = fy;

        SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, triage_datetime, seen_by_md_datetime)), 1)
        INTO avg_wait
        FROM ed_visits
        WHERE hospital_id = h_id AND fiscal_year = fy AND seen_by_md_datetime IS NOT NULL;

        SELECT ROUND(AVG(TIMESTAMPDIFF(HOUR, seen_by_md_datetime, departure_datetime)), 1)
        INTO avg_boarding_hrs
        FROM ed_visits
        WHERE hospital_id = h_id AND fiscal_year = fy AND disposition = 'admitted';

        SELECT COUNT(*) INTO lwbs_visits
        FROM ed_visits
        WHERE hospital_id = h_id AND fiscal_year = fy AND disposition = 'left_without_seen';

        SELECT COUNT(*) INTO admission_visits
        FROM ed_visits
        WHERE hospital_id = h_id AND fiscal_year = fy AND disposition = 'admitted';

        IF total_visits > 0 THEN
            SET lwbs_rate      = (lwbs_visits      / total_visits) * 100;
            SET admission_rate = (admission_visits / total_visits) * 100;

            -- Wait time rating
            IF avg_wait IS NULL THEN
                SET wait_performance = 'No Data';
            ELSEIF avg_wait <= 50 THEN
                SET wait_performance = 'Excellent';
            ELSEIF avg_wait <= 80 THEN
                SET wait_performance = 'Acceptable';
            ELSEIF avg_wait <= 100 THEN
                SET wait_performance = 'Needs Improvement';
            ELSE
                SET wait_performance = 'Critical';
            END IF;

            -- LWBS rating
            IF lwbs_rate < 5 THEN
                SET lwbs_performance = 'Good';
            ELSEIF lwbs_rate <= 10 THEN
                SET lwbs_performance = 'Warning';
            ELSE
                SET lwbs_performance = 'Critical';
            END IF;

        ELSE
            SET lwbs_rate        = 0.0;
            SET admission_rate   = 0.0;
            SET wait_performance = 'No Visits';
            SET lwbs_performance = 'No Visits';
        END IF;

        SELECT
            total_visits,
            avg_wait             AS avg_wait_min,
            ROUND(lwbs_rate, 2)  AS lwbs_rate_pct,
            ROUND(admission_rate, 2) AS admission_rate_pct,
            avg_boarding_hrs     AS avg_boarding_hrs,
            wait_performance,
            lwbs_performance;
    END IF;
END //

DELIMITER ;
