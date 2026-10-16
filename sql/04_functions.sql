-- Requirement 5: user-defined functions.

-- Requirement 3: the user who makes changes in the current transaction (used by the audit triggers)
CREATE OR REPLACE FUNCTION fn_set_current_user(p_user_id bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_user_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND is_active) THEN
        RAISE EXCEPTION 'User with id=% does not exist or is blocked', p_user_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    PERFORM set_config('app.current_user_id', COALESCE(p_user_id::text, ''), true);
END;
$$;
COMMENT ON FUNCTION fn_set_current_user(bigint) IS 'Sets the user on whose behalf changes are made in the current transaction';

CREATE OR REPLACE FUNCTION fn_current_user_id()
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::bigint
$$;
COMMENT ON FUNCTION fn_current_user_id() IS 'Returns the application user id set by fn_set_current_user()';

CREATE OR REPLACE FUNCTION fn_ects_grade(p_score numeric)
RETURNS varchar(2)
LANGUAGE sql
IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN p_score >= 90 THEN 'A'
        WHEN p_score >= 82 THEN 'B'
        WHEN p_score >= 74 THEN 'C'
        WHEN p_score >= 64 THEN 'D'
        WHEN p_score >= 60 THEN 'E'
        WHEN p_score >= 35 THEN 'FX'
        ELSE 'F'
    END
$$;
COMMENT ON FUNCTION fn_ects_grade(numeric) IS 'ECTS grade (A..F) for a 100-point score';

CREATE OR REPLACE FUNCTION fn_national_grade(p_score numeric, p_control control_form)
RETURNS varchar(20)
LANGUAGE sql
IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN p_control = 'credit' THEN
            CASE WHEN p_score >= 60 THEN 'passed' ELSE 'not passed' END
        WHEN p_score >= 90 THEN 'excellent'
        WHEN p_score >= 74 THEN 'good'
        WHEN p_score >= 60 THEN 'satisfactory'
        ELSE 'unsatisfactory'
    END
$$;
COMMENT ON FUNCTION fn_national_grade(numeric, control_form) IS 'National scale grade (excellent / good / ... / passed)';

CREATE OR REPLACE FUNCTION fn_enrollment_score(p_enrollment_id bigint)
RETURNS numeric(5,2)
LANGUAGE sql
STABLE
AS $$
    SELECT LEAST(100, COALESCE(SUM(g.score), 0))::numeric(5,2)
    FROM grades g
    WHERE g.enrollment_id = p_enrollment_id
      AND g.deleted_at IS NULL
$$;
COMMENT ON FUNCTION fn_enrollment_score(bigint) IS 'Total course score of a student (active grades only)';

CREATE OR REPLACE FUNCTION fn_student_rating(p_student_id bigint, p_semester_id bigint)
RETURNS numeric(5,2)
LANGUAGE sql
STABLE
AS $$
    SELECT ROUND(SUM(COALESCE(e.total_score, fn_enrollment_score(e.id)) * c.credits)
                 / NULLIF(SUM(c.credits), 0), 2)
    FROM enrollments e
    JOIN courses c ON c.id = e.course_id
    WHERE e.student_id  = p_student_id
      AND e.semester_id = p_semester_id
      AND e.status <> 'dropped'
$$;
COMMENT ON FUNCTION fn_student_rating(bigint, bigint) IS 'Credit-weighted average score of a student in a semester';

CREATE OR REPLACE FUNCTION fn_group_rating(p_group_id bigint, p_semester_id bigint)
RETURNS TABLE (
    place        bigint,
    student_id   bigint,
    full_name    text,
    funding      funding_type,
    rating       numeric,
    credits      numeric,
    debts        bigint
)
LANGUAGE sql
STABLE
AS $$
    WITH r AS (
        SELECT s.id,
               s.full_name,
               s.funding,
               ROUND(SUM(COALESCE(e.total_score, fn_enrollment_score(e.id)) * c.credits)
                     / NULLIF(SUM(c.credits), 0), 2)            AS rating,
               SUM(c.credits)                                    AS credits,
               COUNT(*) FILTER (WHERE e.status = 'failed')       AS debts
        FROM students s
        JOIN enrollments e ON e.student_id = s.id
                          AND e.semester_id = p_semester_id
                          AND e.status <> 'dropped'
        JOIN courses c     ON c.id = e.course_id
        WHERE s.group_id = p_group_id
          AND s.deleted_at IS NULL
          AND s.status = 'active'
        GROUP BY s.id, s.full_name, s.funding
    )
    SELECT RANK() OVER (ORDER BY (r.debts = 0) DESC, r.rating DESC NULLS LAST) AS place,
           r.id, r.full_name, r.funding, r.rating, r.credits, r.debts
    FROM r
    ORDER BY place, r.full_name
$$;
COMMENT ON FUNCTION fn_group_rating(bigint, bigint) IS 'Student ranking of a group for a semester';

CREATE OR REPLACE FUNCTION fn_search_students(p_query text, p_limit integer DEFAULT 20)
RETURNS TABLE (
    student_id      bigint,
    full_name       text,
    group_code      varchar,
    record_book_no  varchar,
    similarity      real
)
LANGUAGE sql
STABLE
AS $$
    SELECT s.id, s.full_name, g.code, s.record_book_no,
           word_similarity(p_query, s.full_name) AS similarity
    FROM students s
    JOIN student_groups g ON g.id = s.group_id
    WHERE s.deleted_at IS NULL
      AND (p_query <% s.full_name OR s.full_name ILIKE '%' || p_query || '%')
    ORDER BY similarity DESC, s.full_name
    LIMIT p_limit
$$;
COMMENT ON FUNCTION fn_search_students(text, integer) IS 'Fuzzy search of active students by full name (pg_trgm)';

CREATE OR REPLACE FUNCTION fn_teacher_workload(p_teacher_id bigint, p_semester_id bigint)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(planned_hours), 0)::integer
    FROM teaching_assignments
    WHERE teacher_id = p_teacher_id
      AND semester_id = p_semester_id
$$;
COMMENT ON FUNCTION fn_teacher_workload(bigint, bigint) IS 'Total teaching hours of a teacher in a semester';

CREATE OR REPLACE FUNCTION fn_tuition_debt(p_student_id bigint, p_semester_id bigint)
RETURNS numeric(10,2)
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
             WHEN s.funding = 'contract' THEN
                 GREATEST(0, sp.tuition_fee / 2 - COALESCE((
                     SELECT SUM(p.amount)
                     FROM tuition_payments p
                     WHERE p.student_id = s.id AND p.semester_id = p_semester_id), 0))
             ELSE 0
           END::numeric(10,2)
    FROM students s
    JOIN student_groups g ON g.id = s.group_id
    JOIN specialties sp   ON sp.id = g.specialty_id
    WHERE s.id = p_student_id
$$;
COMMENT ON FUNCTION fn_tuition_debt(bigint, bigint) IS 'Amount left to pay for a semester (half of the yearly fee minus payments)';

CREATE OR REPLACE FUNCTION fn_attendance_rate(p_student_id bigint, p_course_id bigint, p_semester_id bigint)
RETURNS numeric(5,2)
LANGUAGE sql
STABLE
AS $$
    SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE a.status IN ('present', 'late'))
                 / NULLIF(COUNT(*), 0), 2)
    FROM attendance a
    JOIN schedule_entries se     ON se.id = a.schedule_entry_id
    JOIN teaching_assignments ta ON ta.id = se.teaching_assignment_id
    WHERE a.student_id    = p_student_id
      AND ta.course_id    = p_course_id
      AND ta.semester_id  = p_semester_id
$$;
COMMENT ON FUNCTION fn_attendance_rate(bigint, bigint, bigint) IS 'Percentage of attended lessons (present + late)';

CREATE OR REPLACE FUNCTION fn_current_semester_id()
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT id FROM semesters WHERE is_current
$$;
COMMENT ON FUNCTION fn_current_semester_id() IS 'Id of the current semester';

CREATE OR REPLACE FUNCTION fn_study_year(p_admission_year integer, p_on date DEFAULT CURRENT_DATE)
RETURNS integer
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT (EXTRACT(YEAR FROM p_on)::integer - p_admission_year)
         + CASE WHEN EXTRACT(MONTH FROM p_on) >= 9 THEN 1 ELSE 0 END
$$;
COMMENT ON FUNCTION fn_study_year(integer, date) IS 'Year of study of a group by admission year on the given date';

CREATE OR REPLACE FUNCTION fn_semester_number(p_admission_year integer, p_semester_id bigint)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT (left(academic_year, 4)::integer - p_admission_year) * 2 + term
    FROM semesters
    WHERE id = p_semester_id
$$;
COMMENT ON FUNCTION fn_semester_number(integer, bigint) IS 'Semester number of study (1..12) for a group with the given admission year';

CREATE OR REPLACE FUNCTION fn_lesson_time(p_lesson_no integer)
RETURNS text
LANGUAGE sql
IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT (ARRAY['08:30-09:50', '10:05-11:25', '11:40-13:00', '13:15-14:35',
                  '14:50-16:10', '16:25-17:45', '18:00-19:20', '19:30-20:50'])[p_lesson_no]
$$;

CREATE OR REPLACE FUNCTION fn_day_name(p_day integer)
RETURNS text
LANGUAGE sql
IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT (ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'])[p_day]
$$;
