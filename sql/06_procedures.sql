-- Requirement 5: stored procedures.

CREATE OR REPLACE PROCEDURE sp_student_create(
    p_group_id        bigint,
    p_record_book_no  varchar,
    p_last_name       varchar,
    p_first_name      varchar,
    p_middle_name     varchar,
    p_birth_date      date,
    p_email           varchar,
    p_phone           varchar,
    p_funding         funding_type,
    INOUT p_student_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO students (group_id, record_book_no, last_name, first_name, middle_name,
                          birth_date, email, phone, funding)
    VALUES (p_group_id, trim(p_record_book_no), trim(p_last_name), trim(p_first_name),
            NULLIF(trim(p_middle_name), ''), p_birth_date,
            NULLIF(lower(trim(p_email)), ''), NULLIF(trim(p_phone), ''), p_funding)
    RETURNING id INTO p_student_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_student_update(
    p_student_id   bigint,
    p_last_name    varchar,
    p_first_name   varchar,
    p_middle_name  varchar,
    p_birth_date   date,
    p_email        varchar,
    p_phone        varchar,
    p_funding      funding_type
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE students
    SET last_name   = trim(p_last_name),
        first_name  = trim(p_first_name),
        middle_name = NULLIF(trim(p_middle_name), ''),
        birth_date  = p_birth_date,
        email       = NULLIF(lower(trim(p_email)), ''),
        phone       = NULLIF(trim(p_phone), ''),
        funding     = p_funding
    WHERE id = p_student_id
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student #% not found', p_student_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_student_set_status(p_student_id bigint, p_status student_status)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE students
    SET status = p_status
    WHERE id = p_student_id
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student #% not found', p_student_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_student_transfer(
    p_student_id   bigint,
    p_to_group_id  bigint,
    p_reason       text,
    INOUT p_transfer_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_from_group bigint;
BEGIN
    SELECT group_id INTO v_from_group
    FROM students
    WHERE id = p_student_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student #% not found', p_student_id USING ERRCODE = 'no_data_found';
    END IF;
    IF v_from_group = p_to_group_id THEN
        RAISE EXCEPTION 'Student is already in group #%', p_to_group_id USING ERRCODE = 'UA001';
    END IF;

    UPDATE students SET group_id = p_to_group_id WHERE id = p_student_id;

    INSERT INTO student_transfers (student_id, from_group_id, to_group_id, reason, created_by)
    VALUES (p_student_id, v_from_group, p_to_group_id, p_reason, fn_current_user_id())
    RETURNING id INTO p_transfer_id;
END;
$$;

-- Requirement 3: soft delete
CREATE OR REPLACE PROCEDURE sp_student_soft_delete(p_student_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE students
    SET deleted_at = now(),
        deleted_by = fn_current_user_id()
    WHERE id = p_student_id
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student #% not found or already deleted', p_student_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

-- Requirement 3: restore after soft delete
CREATE OR REPLACE PROCEDURE sp_student_restore(p_student_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE students
    SET deleted_at = NULL,
        deleted_by = NULL
    WHERE id = p_student_id
      AND deleted_at IS NOT NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deleted student #% not found', p_student_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_enrollment_create(
    p_student_id   bigint,
    p_course_id    bigint,
    p_semester_id  bigint,
    INOUT p_enrollment_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO enrollments (student_id, course_id, semester_id)
    VALUES (p_student_id, p_course_id, p_semester_id)
    ON CONFLICT (student_id, course_id, semester_id) DO UPDATE
        SET status = 'enrolled'
        WHERE enrollments.status = 'dropped'
    RETURNING id INTO p_enrollment_id;

    IF p_enrollment_id IS NULL THEN
        RAISE EXCEPTION 'Student #% is already enrolled in course #% in semester #%',
            p_student_id, p_course_id, p_semester_id USING ERRCODE = 'unique_violation';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_enroll_group_by_curriculum(
    p_group_id     bigint,
    p_semester_id  bigint,
    INOUT p_enrolled integer DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_specialty  bigint;
    v_year       integer;
    v_sem_no     integer;
BEGIN
    SELECT specialty_id, admission_year INTO v_specialty, v_year
    FROM student_groups
    WHERE id = p_group_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Group #% not found', p_group_id USING ERRCODE = 'no_data_found';
    END IF;

    v_sem_no := fn_semester_number(v_year, p_semester_id);

    INSERT INTO enrollments (student_id, course_id, semester_id)
    SELECT s.id, ci.course_id, p_semester_id
    FROM students s
    JOIN curriculum_items ci ON ci.specialty_id = v_specialty AND ci.semester_no = v_sem_no
    JOIN courses c           ON c.id = ci.course_id AND c.deleted_at IS NULL
    WHERE s.group_id = p_group_id
      AND s.deleted_at IS NULL
      AND s.status = 'active'
    ON CONFLICT (student_id, course_id, semester_id) DO NOTHING;

    GET DIAGNOSTICS p_enrolled = ROW_COUNT;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_enroll_student_by_curriculum(
    p_student_id   bigint,
    p_semester_id  bigint,
    INOUT p_enrolled integer DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Student #% not found', p_student_id USING ERRCODE = 'no_data_found';
    END IF;

    INSERT INTO enrollments (student_id, course_id, semester_id)
    SELECT s.id, ci.course_id, p_semester_id
    FROM students s
    JOIN student_groups g    ON g.id = s.group_id
    JOIN curriculum_items ci ON ci.specialty_id = g.specialty_id
                            AND ci.semester_no = fn_semester_number(g.admission_year, p_semester_id)
    JOIN courses c           ON c.id = ci.course_id AND c.deleted_at IS NULL
    WHERE s.id = p_student_id
    ON CONFLICT (student_id, course_id, semester_id) DO NOTHING;

    GET DIAGNOSTICS p_enrolled = ROW_COUNT;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_enrollment_drop(p_enrollment_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE enrollments SET status = 'dropped'
    WHERE id = p_enrollment_id AND status = 'enrolled';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active enrollment #% not found', p_enrollment_id
            USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_enrollment_finalize(p_enrollment_id bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_score    numeric(5,2);
    v_control  control_form;
BEGIN
    SELECT c.control INTO v_control
    FROM enrollments e
    JOIN courses c ON c.id = e.course_id
    WHERE e.id = p_enrollment_id AND e.status = 'enrolled'
    FOR UPDATE OF e;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active enrollment #% not found', p_enrollment_id
            USING ERRCODE = 'no_data_found';
    END IF;

    v_score := fn_enrollment_score(p_enrollment_id);

    UPDATE enrollments
    SET total_score    = v_score,
        ects_grade     = fn_ects_grade(v_score),
        national_grade = fn_national_grade(v_score, v_control),
        status         = CASE WHEN v_score >= 60 THEN 'completed' ELSE 'failed' END::enrollment_status,
        finalized_at   = now()
    WHERE id = p_enrollment_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_grade_add(
    p_enrollment_id  bigint,
    p_type           assessment_type,
    p_title          varchar,
    p_score          numeric,
    p_max_score      numeric,
    p_teacher_id     bigint,
    p_comment        text,
    INOUT p_grade_id bigint DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO grades (enrollment_id, assessment_type, title, score, max_score, teacher_id, comment)
    VALUES (p_enrollment_id, p_type, p_title, p_score, p_max_score, p_teacher_id, NULLIF(p_comment, ''))
    RETURNING id INTO p_grade_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_grade_update(p_grade_id bigint, p_score numeric, p_comment text)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE grades
    SET score   = p_score,
        comment = NULLIF(p_comment, '')
    WHERE id = p_grade_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Grade #% not found', p_grade_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

-- Requirement 3: soft delete
CREATE OR REPLACE PROCEDURE sp_grade_soft_delete(p_grade_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE grades
    SET deleted_at = now(),
        deleted_by = fn_current_user_id()
    WHERE id = p_grade_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Grade #% not found or already deleted', p_grade_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

-- Requirement 3: restore after soft delete
CREATE OR REPLACE PROCEDURE sp_grade_restore(p_grade_id bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE grades
    SET deleted_at = NULL,
        deleted_by = NULL
    WHERE id = p_grade_id AND deleted_at IS NOT NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deleted grade #% not found', p_grade_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_semester_close(p_semester_id bigint, INOUT p_finalized integer DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM semesters WHERE id = p_semester_id AND NOT is_closed) THEN
        RAISE EXCEPTION 'Open semester #% not found', p_semester_id USING ERRCODE = 'no_data_found';
    END IF;

    p_finalized := 0;
    FOR v_id IN
        SELECT id FROM enrollments WHERE semester_id = p_semester_id AND status = 'enrolled' ORDER BY id
    LOOP
        CALL sp_enrollment_finalize(v_id);
        p_finalized := p_finalized + 1;
    END LOOP;

    UPDATE semesters SET is_closed = true WHERE id = p_semester_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_scholarships_assign(
    p_semester_id    bigint,
    p_min_score      numeric,
    p_amount         numeric,
    p_quota_percent  numeric DEFAULT 40,
    p_order_no       varchar DEFAULT NULL,
    INOUT p_assigned integer DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_next_semester  semesters%ROWTYPE;
BEGIN
    SELECT n.* INTO v_next_semester
    FROM semesters s
    JOIN semesters n ON n.start_date > s.end_date
    WHERE s.id = p_semester_id
    ORDER BY n.start_date
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No semester after #%', p_semester_id USING ERRCODE = 'no_data_found';
    END IF;

    WITH candidates AS (
        SELECT s.id AS student_id,
               s.group_id,
               fn_student_rating(s.id, p_semester_id) AS rating
        FROM students s
        WHERE s.deleted_at IS NULL
          AND s.status = 'active'
          AND s.funding = 'budget'
          AND EXISTS (SELECT 1 FROM enrollments e
                      WHERE e.student_id = s.id AND e.semester_id = p_semester_id AND e.status = 'completed')
          AND NOT EXISTS (SELECT 1 FROM enrollments e
                          WHERE e.student_id = s.id AND e.semester_id = p_semester_id
                            AND e.status IN ('failed', 'enrolled'))
    ),
    ranked AS (
        SELECT c.*,
               PERCENT_RANK() OVER (PARTITION BY c.group_id ORDER BY c.rating DESC) AS pr
        FROM candidates c
        WHERE c.rating >= p_min_score
    )
    INSERT INTO scholarships (student_id, semester_id, scholarship_type, amount, start_date, end_date, order_no)
    SELECT r.student_id,
           v_next_semester.id,
           CASE WHEN r.rating >= 95 THEN 'increased_academic' ELSE 'academic' END::scholarship_type,
           CASE WHEN r.rating >= 95 THEN round(p_amount * 1.45, 2) ELSE p_amount END,
           v_next_semester.start_date,
           v_next_semester.end_date,
           p_order_no
    FROM ranked r
    WHERE r.pr * 100 < p_quota_percent
      AND NOT EXISTS (SELECT 1 FROM scholarships x
                      WHERE x.student_id = r.student_id
                        AND x.semester_id = v_next_semester.id
                        AND x.scholarship_type IN ('academic', 'increased_academic')
                        AND x.deleted_at IS NULL);

    GET DIAGNOSTICS p_assigned = ROW_COUNT;
END;
$$;

-- Requirement 3: permanent removal of rows soft-deleted earlier than p_older_than
CREATE OR REPLACE PROCEDURE sp_purge_soft_deleted(
    p_table       text,
    p_older_than  interval,
    INOUT p_purged integer DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_table NOT IN ('faculties', 'departments', 'specialties', 'teachers', 'student_groups', 'students',
                       'courses', 'buildings', 'classrooms', 'grades', 'scholarships') THEN
        RAISE EXCEPTION 'Table "%" does not support soft delete', p_table USING ERRCODE = 'UA001';
    END IF;

    PERFORM set_config('app.allow_hard_delete', 'on', true);
    EXECUTE format('DELETE FROM %I WHERE deleted_at < now() - $1', p_table) USING p_older_than;
    GET DIAGNOSTICS p_purged = ROW_COUNT;
    PERFORM set_config('app.allow_hard_delete', 'off', true);
END;
$$;

CREATE OR REPLACE PROCEDURE sp_refresh_statistics()
LANGUAGE plpgsql
AS $$
BEGIN
    IF (SELECT ispopulated FROM pg_matviews WHERE matviewname = 'mv_faculty_statistics') THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_faculty_statistics;
    ELSE
        REFRESH MATERIALIZED VIEW mv_faculty_statistics;
    END IF;
END;
$$;
