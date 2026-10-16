\pset pager off
\set ON_ERROR_STOP on

BEGIN;
SELECT fn_set_current_user(2);

\echo '\n=== 1. Grading scale functions (requirement 5) ==='
SELECT s AS score, fn_ects_grade(s) AS ects,
       fn_national_grade(s, 'exam') AS exam, fn_national_grade(s, 'credit') AS credit
FROM unnest(ARRAY[95, 85, 76, 65, 61, 40, 20]) AS s;

\echo '\n=== 2. Table functions: group ranking and fuzzy search (requirement 5) ==='
SELECT * FROM fn_group_rating(2, 2) LIMIT 5;
SELECT * FROM fn_search_students('Shevchenko Oleks', 5);

\echo '\n=== 3. Scalar functions (requirement 5) ==='
SELECT fn_student_rating(13, 2)       AS rating,
       fn_teacher_workload(1, 3)      AS petrenko_hours,
       fn_tuition_debt(24, 3)         AS debt,
       fn_attendance_rate(13, 8, 3)   AS attendance_pct,
       fn_study_year(2024)            AS year_of_study,
       fn_current_semester_id()       AS current_semester;

\echo '\n=== 4. Views (requirement 5) ==='
SELECT * FROM v_groups ORDER BY code;
SELECT * FROM v_academic_debtors ORDER BY group_code, full_name LIMIT 5;
SELECT group_code, day_name, lesson_no, lesson_time, course_name, lesson_type, teacher_name, room
FROM v_schedule WHERE group_code = 'CS-24' ORDER BY day_of_week, lesson_no;
SELECT code, name, semester, students, avg_score, pass_rate, a, b, c, d, e, fx_f
FROM v_course_statistics ORDER BY semester, code LIMIT 6;
SELECT full_name, semester, lecture_hours, practice_hours, lab_hours, total_hours
FROM v_teacher_workload WHERE semester_id = 3 ORDER BY total_hours DESC;
SELECT * FROM v_tuition_debts WHERE debt > 0 ORDER BY debt DESC;
SELECT full_name, course_name, lessons, present, late, absent, attendance_pct
FROM v_attendance_summary ORDER BY attendance_pct LIMIT 5;
SELECT * FROM mv_faculty_statistics;

\echo '\n=== 5. Procedure + audit trigger: last change date and user (requirement 3) ==='
CALL sp_student_update(13, 'Kovalenko', 'Khrystyna', 'Mykhailivna', '2007-02-14',
                       'kh.kovalenko@stud.univ.edu.ua', '+380509998877', 'budget');
SELECT full_name, email, phone, updated_at, updated_by_name FROM v_students WHERE id = 13;
SELECT operation, changed_fields, changed_by_name,
       old_data ->> 'phone' AS old_phone, new_data ->> 'phone' AS new_phone
FROM v_change_history WHERE table_name = 'students' AND record_id = 13 ORDER BY id DESC LIMIT 1;

\echo '\n=== 6. Soft delete: DELETE is intercepted by a trigger (requirement 3) ==='
DELETE FROM students WHERE id = 14;
SELECT id, deleted_at IS NOT NULL AS soft_deleted, deleted_by FROM students WHERE id = 14;
SELECT count(*) AS visible_in_v_students FROM v_students WHERE id = 14;
SELECT id, status FROM enrollments WHERE student_id = 14 AND semester_id = 3;
CALL sp_student_restore(14);
SELECT full_name, group_code FROM v_students WHERE id = 14;

\echo '\n=== 7. Business rule triggers, expected errors are caught (requirement 5) ==='
DO $$
DECLARE
    v_entry  schedule_entries%ROWTYPE;
    v_other  bigint;
BEGIN
    BEGIN
        INSERT INTO grades (enrollment_id, assessment_type, title, score, max_score)
        SELECT id, 'bonus', 'Bonus', 100, 100 FROM enrollments WHERE semester_id = 3 AND status = 'enrolled' LIMIT 1;
    EXCEPTION WHEN SQLSTATE 'UA001' THEN RAISE NOTICE '7.1 grade: %', SQLERRM;
    END;

    SELECT * INTO v_entry FROM schedule_entries ORDER BY id LIMIT 1;
    SELECT ta.id INTO v_other
    FROM teaching_assignments ta
    WHERE ta.semester_id = 3 AND ta.id <> v_entry.teaching_assignment_id AND ta.lesson_type <> 'lecture'
    LIMIT 1;
    BEGIN
        INSERT INTO schedule_entries (teaching_assignment_id, classroom_id, day_of_week, lesson_no)
        VALUES (v_other, v_entry.classroom_id, v_entry.day_of_week, v_entry.lesson_no);
    EXCEPTION WHEN SQLSTATE 'UA001' THEN RAISE NOTICE '7.2 schedule: %', SQLERRM;
    END;

    BEGIN
        INSERT INTO enrollments (student_id, course_id, semester_id) VALUES (13, 1, 1);
    EXCEPTION WHEN SQLSTATE 'UA001' THEN RAISE NOTICE '7.3 enrollment: %', SQLERRM;
    END;

    BEGIN
        UPDATE student_groups SET max_size = 13 WHERE code = 'SE-24';
        UPDATE students SET group_id = (SELECT id FROM student_groups WHERE code = 'SE-24') WHERE id = 30;
    EXCEPTION WHEN SQLSTATE 'UA001' THEN RAISE NOTICE '7.4 group: %', SQLERRM;
    END;

    BEGIN
        DELETE FROM audit_log WHERE id = 1;
    EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE '7.5 audit log: %', SQLERRM;
    END;

    BEGIN
        INSERT INTO scholarships (student_id, semester_id, scholarship_type, amount, start_date, end_date)
        SELECT student_id, semester_id, scholarship_type, amount, start_date + 10, end_date
        FROM scholarships WHERE deleted_at IS NULL LIMIT 1;
    EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE '7.6 scholarship: %', SQLERRM;
    END;
END;
$$;

\echo '\n=== 8. Switching the current semester (trigger) and closing a semester (procedure) (requirement 5) ==='
INSERT INTO semesters (academic_year, term, start_date, end_date, is_current)
VALUES ('2026/2027', 2, '2027-01-25', '2027-06-27', true);
SELECT id, academic_year, term, is_current FROM v_semesters ORDER BY start_date;
INSERT INTO grades (enrollment_id, assessment_type, title, score, max_score)
SELECT e.id, k.kind::assessment_type, k.title,
       round(k.max_score * (0.50 + ((e.student_id * 7919) % 49) / 100.0)), k.max_score
FROM enrollments e
CROSS JOIN (VALUES ('lab', 'Labs 3-4', 20), ('module', 'Module test', 20), ('exam', 'Exam', 40)) AS k(kind, title, max_score)
WHERE e.semester_id = 3 AND e.status = 'enrolled';
CALL sp_semester_close(3, NULL);
SELECT status, count(*) FROM enrollments WHERE semester_id = 3 GROUP BY status;
CALL sp_scholarships_assign(3, 75, 2000, 40, 'Order No. 999-S', NULL);
SELECT scholarship_type, count(*), sum(amount) FROM scholarships
WHERE semester_id = (SELECT id FROM semesters WHERE is_current) GROUP BY scholarship_type;

\echo '\n=== 9. Permanent removal of soft-deleted rows (requirement 3) ==='
CALL sp_purge_soft_deleted('grades', interval '0 seconds', NULL);
CALL sp_refresh_statistics();

ROLLBACK;

\echo '\n=== 10. Query plans that use the indexes (requirement 6) ==='
VACUUM (ANALYZE) enrollments;
SET enable_seqscan = off;

\echo '--- B-tree partial unique (uq_groups_code_active)'
EXPLAIN (COSTS OFF) SELECT * FROM student_groups WHERE code = 'CS-24' AND deleted_at IS NULL;

\echo '--- B-tree covering INCLUDE (ix_enrollments_student_cover) -> Index Only Scan'
EXPLAIN (COSTS OFF) SELECT course_id, status, total_score FROM enrollments WHERE student_id = 13 AND semester_id = 2;

\echo '--- Hash (ix_students_record_book_hash)'
EXPLAIN (COSTS OFF) SELECT * FROM students WHERE record_book_no = 'RB2024-0013';

\echo '--- GIN pg_trgm (ix_students_full_name_trgm)'
EXPLAIN (COSTS OFF) SELECT id, full_name FROM students WHERE full_name ILIKE '%valenk%';

\echo '--- GIN tsvector (ix_courses_search)'
EXPLAIN (COSTS OFF) SELECT code, name FROM courses WHERE search_vector @@ to_tsquery('simple', 'postgresql');

\echo '--- GIN jsonb_path_ops (ix_audit_new_data)'
EXPLAIN (COSTS OFF) SELECT id, table_name FROM audit_log WHERE new_data @> '{"status": "expelled"}';

\echo '--- BRIN (ix_attendance_date_brin)'
EXPLAIN (COSTS OFF) SELECT count(*) FROM attendance WHERE lesson_date BETWEEN '2026-09-14' AND '2026-09-18';

\echo '--- GiST (EXCLUDE excl_semesters_overlap)'
EXPLAIN (COSTS OFF) SELECT * FROM semesters WHERE daterange(start_date, end_date, '[]') && daterange('2026-03-01', '2026-03-31');

RESET enable_seqscan;
