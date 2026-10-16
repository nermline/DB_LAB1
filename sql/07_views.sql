-- Requirement 5: views.

-- Requirement 3: soft-deleted students are hidden
CREATE OR REPLACE VIEW v_students AS
SELECT s.id,
       s.record_book_no,
       s.last_name,
       s.first_name,
       s.middle_name,
       s.full_name,
       s.birth_date,
       s.email,
       s.phone,
       s.enrollment_date,
       s.status,
       s.funding,
       g.id                                  AS group_id,
       g.code                                AS group_code,
       fn_study_year(g.admission_year)       AS study_year,
       sp.id                                 AS specialty_id,
       sp.code || ' ' || sp.name             AS specialty,
       f.id                                  AS faculty_id,
       f.name                                AS faculty,
       ct.full_name                          AS curator,
       s.created_at,
       s.updated_at,
       uu.display_name                       AS updated_by_name
FROM students s
JOIN student_groups g   ON g.id  = s.group_id
JOIN specialties sp     ON sp.id = g.specialty_id
JOIN departments d      ON d.id  = sp.department_id
JOIN faculties f        ON f.id  = d.faculty_id
LEFT JOIN teachers ct   ON ct.id = g.curator_teacher_id
LEFT JOIN users uu      ON uu.id = s.updated_by
WHERE s.deleted_at IS NULL;
COMMENT ON VIEW v_students IS 'Active (not deleted) students with group, specialty and faculty';

-- Requirement 3: soft-deleted students (who and when deleted them)
CREATE OR REPLACE VIEW v_students_deleted AS
SELECT s.id,
       s.record_book_no,
       s.full_name,
       g.code                 AS group_code,
       s.status,
       s.deleted_at,
       s.deleted_by,
       u.display_name         AS deleted_by_name
FROM students s
JOIN student_groups g ON g.id = s.group_id
LEFT JOIN users u     ON u.id = s.deleted_by
WHERE s.deleted_at IS NOT NULL;
COMMENT ON VIEW v_students_deleted IS 'Students removed with soft delete (can be restored)';

CREATE OR REPLACE VIEW v_groups AS
SELECT g.id,
       g.code,
       g.admission_year,
       fn_study_year(g.admission_year)  AS study_year,
       g.max_size,
       sp.id                            AS specialty_id,
       sp.code || ' ' || sp.name        AS specialty,
       sp.degree_level,
       f.name                           AS faculty,
       t.full_name                      AS curator,
       COUNT(s.id) FILTER (WHERE s.status = 'active')                         AS active_students,
       COUNT(s.id) FILTER (WHERE s.status = 'active' AND s.funding = 'budget') AS budget_students,
       COUNT(s.id) FILTER (WHERE s.status = 'academic_leave')                 AS on_leave
FROM student_groups g
JOIN specialties sp   ON sp.id = g.specialty_id
JOIN departments d    ON d.id  = sp.department_id
JOIN faculties f      ON f.id  = d.faculty_id
LEFT JOIN teachers t  ON t.id  = g.curator_teacher_id
LEFT JOIN students s  ON s.group_id = g.id AND s.deleted_at IS NULL
WHERE g.deleted_at IS NULL
GROUP BY g.id, sp.id, f.name, t.full_name;
COMMENT ON VIEW v_groups IS 'Groups: specialty, curator, number of students';

CREATE OR REPLACE VIEW v_enrollments AS
SELECT e.id,
       e.student_id,
       s.full_name                                   AS student_name,
       g.code                                        AS group_code,
       e.course_id,
       c.code                                        AS course_code,
       c.name                                        AS course_name,
       c.credits,
       c.control,
       e.semester_id,
       sm.academic_year || ' / ' || sm.term          AS semester,
       e.status,
       COALESCE(e.total_score, fn_enrollment_score(e.id)) AS score,
       e.ects_grade,
       e.national_grade,
       e.enrolled_at,
       e.finalized_at,
       e.updated_at,
       e.updated_by
FROM enrollments e
JOIN students s        ON s.id  = e.student_id
JOIN student_groups g  ON g.id  = s.group_id
JOIN courses c         ON c.id  = e.course_id
JOIN semesters sm      ON sm.id = e.semester_id
WHERE s.deleted_at IS NULL;
COMMENT ON VIEW v_enrollments IS 'Course enrollments: current total score or final grade';

CREATE OR REPLACE VIEW v_grades AS
SELECT gr.id,
       gr.enrollment_id,
       e.student_id,
       s.full_name           AS student_name,
       c.name                AS course_name,
       e.semester_id,
       gr.assessment_type,
       gr.title,
       gr.score,
       gr.max_score,
       gr.graded_on,
       gr.teacher_id,
       t.full_name           AS teacher_name,
       gr.comment,
       gr.updated_at,
       u.display_name        AS updated_by_name
FROM grades gr
JOIN enrollments e    ON e.id = gr.enrollment_id
JOIN students s       ON s.id = e.student_id
JOIN courses c        ON c.id = e.course_id
LEFT JOIN teachers t  ON t.id = gr.teacher_id
LEFT JOIN users u     ON u.id = gr.updated_by
WHERE gr.deleted_at IS NULL;
COMMENT ON VIEW v_grades IS 'Active grades with student, course and teacher';

CREATE OR REPLACE VIEW v_student_semester_results AS
SELECT s.id                                          AS student_id,
       s.full_name,
       g.code                                        AS group_code,
       sm.id                                         AS semester_id,
       sm.academic_year || ' / ' || sm.term          AS semester,
       COUNT(*)                                      AS courses_total,
       COUNT(*) FILTER (WHERE e.status = 'completed') AS courses_passed,
       COUNT(*) FILTER (WHERE e.status = 'failed')    AS debts,
       SUM(c.credits)                                AS credits_total,
       COALESCE(SUM(c.credits) FILTER (WHERE e.status = 'completed'), 0) AS credits_earned,
       fn_student_rating(s.id, sm.id)                AS rating
FROM students s
JOIN student_groups g ON g.id  = s.group_id
JOIN enrollments e    ON e.student_id = s.id AND e.status <> 'dropped'
JOIN courses c        ON c.id  = e.course_id
JOIN semesters sm     ON sm.id = e.semester_id
WHERE s.deleted_at IS NULL
GROUP BY s.id, s.full_name, g.code, sm.id;
COMMENT ON VIEW v_student_semester_results IS 'Semester results of a student: credits, debts, rating';

CREATE OR REPLACE VIEW v_academic_debtors AS
SELECT s.id              AS student_id,
       s.full_name,
       g.code            AS group_code,
       c.name            AS course_name,
       sm.academic_year || ' / ' || sm.term AS semester,
       e.total_score,
       e.ects_grade
FROM enrollments e
JOIN students s       ON s.id  = e.student_id
JOIN student_groups g ON g.id  = s.group_id
JOIN courses c        ON c.id  = e.course_id
JOIN semesters sm     ON sm.id = e.semester_id
WHERE e.status = 'failed'
  AND s.deleted_at IS NULL
  AND s.status = 'active';
COMMENT ON VIEW v_academic_debtors IS 'Students with academic debts (FX/F)';

CREATE OR REPLACE VIEW v_teacher_workload AS
SELECT t.id                         AS teacher_id,
       t.full_name,
       t.position,
       d.name                       AS department,
       sm.id                        AS semester_id,
       sm.academic_year || ' / ' || sm.term AS semester,
       COALESCE(SUM(ta.planned_hours) FILTER (WHERE ta.lesson_type = 'lecture'), 0)  AS lecture_hours,
       COALESCE(SUM(ta.planned_hours) FILTER (WHERE ta.lesson_type = 'practice'), 0) AS practice_hours,
       COALESCE(SUM(ta.planned_hours) FILTER (WHERE ta.lesson_type = 'lab'), 0)      AS lab_hours,
       COALESCE(SUM(ta.planned_hours) FILTER (WHERE ta.lesson_type = 'seminar'), 0)  AS seminar_hours,
       SUM(ta.planned_hours)        AS total_hours,
       COUNT(DISTINCT ta.course_id) AS courses,
       COUNT(DISTINCT ta.group_id)  AS groups
FROM teachers t
JOIN departments d           ON d.id = t.department_id
JOIN teaching_assignments ta ON ta.teacher_id = t.id
JOIN semesters sm            ON sm.id = ta.semester_id
WHERE t.deleted_at IS NULL
GROUP BY t.id, t.full_name, t.position, d.name, sm.id;
COMMENT ON VIEW v_teacher_workload IS 'Teaching load of teachers (hours by lesson type)';

CREATE OR REPLACE VIEW v_schedule AS
SELECT se.id,
       ta.semester_id,
       g.id                            AS group_id,
       g.code                          AS group_code,
       se.day_of_week,
       fn_day_name(se.day_of_week)     AS day_name,
       se.lesson_no,
       fn_lesson_time(se.lesson_no)    AS lesson_time,
       se.week,
       c.name                          AS course_name,
       ta.lesson_type,
       t.id                            AS teacher_id,
       t.full_name                     AS teacher_name,
       b.code || '-' || cr.room_number AS room
FROM schedule_entries se
JOIN teaching_assignments ta ON ta.id = se.teaching_assignment_id
JOIN student_groups g        ON g.id  = ta.group_id
JOIN courses c               ON c.id  = ta.course_id
JOIN teachers t              ON t.id  = ta.teacher_id
JOIN classrooms cr           ON cr.id = se.classroom_id
JOIN buildings b             ON b.id  = cr.building_id;
COMMENT ON VIEW v_schedule IS 'Timetable: group, day, lesson, course, teacher, classroom';

CREATE OR REPLACE VIEW v_course_statistics AS
SELECT c.id                                         AS course_id,
       c.code,
       c.name,
       sm.id                                        AS semester_id,
       sm.academic_year || ' / ' || sm.term         AS semester,
       COUNT(*)                                     AS students,
       ROUND(AVG(e.total_score), 2)                 AS avg_score,
       ROUND(100.0 * COUNT(*) FILTER (WHERE e.status = 'completed') / NULLIF(COUNT(*), 0), 1) AS pass_rate,
       COUNT(*) FILTER (WHERE e.ects_grade = 'A')  AS a,
       COUNT(*) FILTER (WHERE e.ects_grade = 'B')  AS b,
       COUNT(*) FILTER (WHERE e.ects_grade = 'C')  AS c,
       COUNT(*) FILTER (WHERE e.ects_grade = 'D')  AS d,
       COUNT(*) FILTER (WHERE e.ects_grade = 'E')  AS e,
       COUNT(*) FILTER (WHERE e.ects_grade IN ('FX', 'F')) AS fx_f
FROM enrollments e
JOIN courses c    ON c.id  = e.course_id
JOIN semesters sm ON sm.id = e.semester_id
WHERE e.status IN ('completed', 'failed')
GROUP BY c.id, sm.id;
COMMENT ON VIEW v_course_statistics IS 'Average score, pass rate and ECTS grade distribution per course';

CREATE OR REPLACE VIEW v_attendance_summary AS
SELECT a.student_id,
       s.full_name,
       g.code                                         AS group_code,
       ta.course_id,
       c.name                                         AS course_name,
       ta.semester_id,
       COUNT(*)                                       AS lessons,
       COUNT(*) FILTER (WHERE a.status = 'present')   AS present,
       COUNT(*) FILTER (WHERE a.status = 'late')      AS late,
       COUNT(*) FILTER (WHERE a.status = 'excused')   AS excused,
       COUNT(*) FILTER (WHERE a.status = 'absent')    AS absent,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.status IN ('present', 'late')) / COUNT(*), 1) AS attendance_pct
FROM attendance a
JOIN schedule_entries se     ON se.id = a.schedule_entry_id
JOIN teaching_assignments ta ON ta.id = se.teaching_assignment_id
JOIN courses c               ON c.id  = ta.course_id
JOIN students s              ON s.id  = a.student_id
JOIN student_groups g        ON g.id  = s.group_id
WHERE s.deleted_at IS NULL
GROUP BY a.student_id, s.full_name, g.code, ta.course_id, c.name, ta.semester_id;
COMMENT ON VIEW v_attendance_summary IS 'Lesson attendance of students per course';

CREATE OR REPLACE VIEW v_tuition_debts AS
SELECT s.id                           AS student_id,
       s.full_name,
       g.code                         AS group_code,
       (sp.tuition_fee / 2)::numeric(10,2) AS semester_fee,
       COALESCE(p.paid, 0)            AS paid,
       fn_tuition_debt(s.id, sm.id)   AS debt,
       p.last_payment_at
FROM students s
JOIN student_groups g ON g.id  = s.group_id
JOIN specialties sp   ON sp.id = g.specialty_id
CROSS JOIN semesters sm
LEFT JOIN LATERAL (
    SELECT SUM(tp.amount) AS paid, MAX(tp.paid_at) AS last_payment_at
    FROM tuition_payments tp
    WHERE tp.student_id = s.id AND tp.semester_id = sm.id
) p ON true
WHERE sm.is_current
  AND s.funding = 'contract'
  AND s.status = 'active'
  AND s.deleted_at IS NULL;
COMMENT ON VIEW v_tuition_debts IS 'Contract students of the current semester: fee, paid, debt';

-- Requirement 3: change history with the user name
CREATE OR REPLACE VIEW v_change_history AS
SELECT a.id,
       a.changed_at,
       a.table_name,
       a.record_id,
       a.operation,
       a.changed_fields,
       a.changed_by,
       COALESCE(u.display_name, 'system') AS changed_by_name,
       a.old_data,
       a.new_data,
       a.tx_id
FROM audit_log a
LEFT JOIN users u ON u.id = a.changed_by;
COMMENT ON VIEW v_change_history IS 'Change log: what was changed, when and by whom';

CREATE OR REPLACE VIEW v_semesters AS
SELECT sm.id,
       sm.academic_year,
       sm.term,
       sm.academic_year || ' / ' || sm.term AS name,
       sm.start_date,
       sm.end_date,
       sm.is_current,
       sm.is_closed
FROM semesters sm;
COMMENT ON VIEW v_semesters IS 'Academic semesters';

CREATE OR REPLACE VIEW v_courses AS
SELECT c.id,
       c.code,
       c.name,
       c.credits,
       c.lecture_hours,
       c.practice_hours,
       c.lab_hours,
       c.control,
       d.id     AS department_id,
       d.name   AS department
FROM courses c
JOIN departments d ON d.id = c.department_id
WHERE c.deleted_at IS NULL;
COMMENT ON VIEW v_courses IS 'Active (not deleted) courses';

CREATE MATERIALIZED VIEW mv_faculty_statistics AS
SELECT f.id                                                       AS faculty_id,
       f.code,
       f.name,
       (SELECT COUNT(*) FROM departments d
         WHERE d.faculty_id = f.id AND d.deleted_at IS NULL)      AS departments,
       (SELECT COUNT(*) FROM teachers t JOIN departments d ON d.id = t.department_id
         WHERE d.faculty_id = f.id AND t.deleted_at IS NULL)      AS teachers,
       COUNT(DISTINCT g.id)                                       AS groups,
       COUNT(s.id) FILTER (WHERE s.status = 'active')             AS active_students,
       COUNT(s.id) FILTER (WHERE s.status = 'active' AND s.funding = 'budget')   AS budget_students,
       COUNT(s.id) FILTER (WHERE s.status = 'active' AND s.funding = 'contract') AS contract_students,
       now()                                                      AS refreshed_at
FROM faculties f
LEFT JOIN departments d     ON d.faculty_id = f.id AND d.deleted_at IS NULL
LEFT JOIN specialties sp    ON sp.department_id = d.id AND sp.deleted_at IS NULL
LEFT JOIN student_groups g  ON g.specialty_id = sp.id AND g.deleted_at IS NULL
LEFT JOIN students s        ON s.group_id = g.id AND s.deleted_at IS NULL
WHERE f.deleted_at IS NULL
GROUP BY f.id, f.code, f.name
WITH NO DATA;

CREATE UNIQUE INDEX uq_mv_faculty_statistics ON mv_faculty_statistics (faculty_id);
COMMENT ON MATERIALIZED VIEW mv_faculty_statistics IS 'Faculty statistics (refreshed by sp_refresh_statistics)';
