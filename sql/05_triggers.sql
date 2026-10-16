-- Requirement 5: triggers.

-- Requirement 3: last change date and user (created_at/by, updated_at/by)
CREATE OR REPLACE FUNCTION fn_trg_set_audit_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := now();
        NEW.created_by := COALESCE(fn_current_user_id(), NEW.created_by);
        NEW.updated_by := NEW.created_by;
    ELSE
        NEW.created_at := OLD.created_at;
        NEW.created_by := OLD.created_by;
        NEW.updated_by := fn_current_user_id();
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION fn_trg_set_audit_fields() IS 'Fills created_at/by and updated_at/by from the session context (app.current_user_id)';

-- Requirement 3: soft delete (DELETE is turned into setting deleted_at / deleted_by)
CREATE OR REPLACE FUNCTION fn_trg_soft_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('app.allow_hard_delete', true) = 'on' THEN
        RETURN OLD;
    END IF;

    EXECUTE format(
        'UPDATE %I.%I SET deleted_at = now(), deleted_by = $1 WHERE id = $2 AND deleted_at IS NULL',
        TG_TABLE_SCHEMA, TG_TABLE_NAME)
    USING fn_current_user_id(), OLD.id;

    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION fn_trg_soft_delete() IS 'Replaces DELETE with setting deleted_at / deleted_by';

-- Requirement 3: change history (who, when, what)
CREATE OR REPLACE FUNCTION fn_trg_audit_log()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    c_hidden  CONSTANT text[] := ARRAY['password_hash', 'search_vector', 'full_name'];
    v_old     jsonb;
    v_new     jsonb;
    v_op      text := TG_OP;
    v_changed text[];
BEGIN
    IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD) - c_hidden; END IF;
    IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW) - c_hidden; END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(n.key ORDER BY n.key)
        INTO v_changed
        FROM jsonb_each(v_new) AS n
        WHERE n.key NOT IN ('updated_at', 'updated_by')
          AND n.value IS DISTINCT FROM v_old -> n.key;

        IF v_changed IS NULL THEN
            RETURN NULL;
        END IF;

        IF v_old ->> 'deleted_at' IS NULL AND v_new ->> 'deleted_at' IS NOT NULL THEN
            v_op := 'SOFT_DELETE';
        ELSIF v_old ->> 'deleted_at' IS NOT NULL AND v_new ->> 'deleted_at' IS NULL THEN
            v_op := 'RESTORE';
        END IF;
    END IF;

    INSERT INTO audit_log (table_name, record_id, operation, old_data, new_data, changed_fields, changed_by)
    VALUES (TG_TABLE_NAME,
            COALESCE(v_new ->> 'id', v_old ->> 'id')::bigint,
            v_op, v_old, v_new, v_changed,
            fn_current_user_id());

    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION fn_trg_audit_log() IS 'Writes INSERT / UPDATE / DELETE / SOFT_DELETE / RESTORE to audit_log';

CREATE OR REPLACE FUNCTION fn_trg_audit_log_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'The audit log cannot be modified or deleted (operation %)', TG_OP
        USING ERRCODE = 'insufficient_privilege';
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_student_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_group  student_groups%ROWTYPE;
    v_count  integer;
BEGIN
    IF NEW.deleted_at IS NOT NULL OR NEW.status NOT IN ('active', 'academic_leave') THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE'
       AND NEW.group_id = OLD.group_id
       AND OLD.deleted_at IS NULL
       AND OLD.status IN ('active', 'academic_leave') THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_group FROM student_groups WHERE id = NEW.group_id FOR UPDATE;

    IF v_group.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Group "%" is deleted, students cannot be added to it', v_group.code
            USING ERRCODE = 'UA001';
    END IF;

    SELECT count(*) INTO v_count
    FROM students
    WHERE group_id = NEW.group_id
      AND id <> NEW.id
      AND deleted_at IS NULL
      AND status IN ('active', 'academic_leave');

    IF v_count >= v_group.max_size THEN
        RAISE EXCEPTION 'Group "%" is full (% of % places)', v_group.code, v_count, v_group.max_size
            USING ERRCODE = 'UA001';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_student_after_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
       OR (NEW.status IN ('expelled', 'graduated') AND OLD.status IS DISTINCT FROM NEW.status) THEN

        UPDATE enrollments
        SET status = 'dropped'
        WHERE student_id = NEW.id
          AND status = 'enrolled';

        UPDATE scholarships
        SET end_date = GREATEST(start_date, CURRENT_DATE)
        WHERE student_id = NEW.id
          AND deleted_at IS NULL
          AND end_date > CURRENT_DATE;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_enrollment_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM students
                   WHERE id = NEW.student_id AND deleted_at IS NULL AND status = 'active') THEN
        RAISE EXCEPTION 'Student #% is not studying (deleted, expelled or on academic leave)', NEW.student_id
            USING ERRCODE = 'UA001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM courses WHERE id = NEW.course_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Course #% does not exist or is deleted', NEW.course_id
            USING ERRCODE = 'UA001';
    END IF;
    IF EXISTS (SELECT 1 FROM semesters WHERE id = NEW.semester_id AND is_closed) THEN
        RAISE EXCEPTION 'Semester #% is closed, enrollment is not possible', NEW.semester_id
            USING ERRCODE = 'UA001';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_grade_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status  enrollment_status;
    v_total   numeric;
BEGIN
    SELECT status INTO v_status FROM enrollments WHERE id = NEW.enrollment_id FOR UPDATE;

    IF v_status <> 'enrolled' THEN
        RAISE EXCEPTION 'Enrollment #% has status "%", grades cannot be changed', NEW.enrollment_id, v_status
            USING ERRCODE = 'UA001';
    END IF;

    IF NEW.deleted_at IS NULL THEN
        SELECT COALESCE(SUM(score), 0) INTO v_total
        FROM grades
        WHERE enrollment_id = NEW.enrollment_id
          AND deleted_at IS NULL
          AND id <> NEW.id;

        IF v_total + NEW.score > 100 THEN
            RAISE EXCEPTION 'Total score exceeds 100 (already %, adding %)', v_total, NEW.score
                USING ERRCODE = 'UA001';
        END IF;
    END IF;

    IF NEW.teacher_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM teachers WHERE id = NEW.teacher_id AND deleted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Teacher #% is deleted', NEW.teacher_id USING ERRCODE = 'UA001';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_schedule_validate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_ta        teaching_assignments%ROWTYPE;
    v_room      classrooms%ROWTYPE;
    v_size      integer;
    v_conflict  record;
BEGIN
    SELECT * INTO v_ta   FROM teaching_assignments WHERE id = NEW.teaching_assignment_id;
    SELECT * INTO v_room FROM classrooms           WHERE id = NEW.classroom_id;

    IF v_room.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Classroom % is deleted', v_room.room_number USING ERRCODE = 'UA001';
    END IF;

    SELECT count(*) INTO v_size
    FROM students
    WHERE group_id = v_ta.group_id AND deleted_at IS NULL AND status = 'active';

    IF v_size > v_room.capacity THEN
        RAISE EXCEPTION 'Classroom % is too small: % seats for % students', v_room.room_number, v_room.capacity, v_size
            USING ERRCODE = 'UA001';
    END IF;

    SELECT se.id,
           CASE
               WHEN se.classroom_id = NEW.classroom_id THEN 'classroom'
               WHEN ta.teacher_id   = v_ta.teacher_id  THEN 'teacher'
               ELSE 'group'
           END AS resource
    INTO v_conflict
    FROM schedule_entries se
    JOIN teaching_assignments ta ON ta.id = se.teaching_assignment_id
    WHERE se.id <> NEW.id
      AND ta.semester_id = v_ta.semester_id
      AND se.day_of_week = NEW.day_of_week
      AND se.lesson_no   = NEW.lesson_no
      AND (se.week = 'every' OR NEW.week = 'every' OR se.week = NEW.week)
      AND (se.classroom_id = NEW.classroom_id
           OR ta.teacher_id = v_ta.teacher_id
           OR ta.group_id   = v_ta.group_id)
      AND NOT (ta.lesson_type = 'lecture' AND v_ta.lesson_type = 'lecture'
               AND ta.course_id = v_ta.course_id
               AND ta.teacher_id = v_ta.teacher_id
               AND se.classroom_id = NEW.classroom_id
               AND ta.group_id <> v_ta.group_id)
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Schedule conflict: the % is already busy on %, lesson % (schedule entry #%)',
            v_conflict.resource, fn_day_name(NEW.day_of_week), NEW.lesson_no, v_conflict.id
            USING ERRCODE = 'UA001';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_semester_current()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.is_current THEN
        UPDATE semesters SET is_current = false WHERE is_current AND id <> NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

-- Requirement 3: audit triggers
DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'users', 'faculties', 'departments', 'specialties', 'teachers', 'student_groups',
        'students', 'semesters', 'courses', 'curriculum_items', 'teaching_assignments',
        'buildings', 'classrooms', 'schedule_entries', 'enrollments', 'grades',
        'attendance', 'scholarships', 'tuition_payments']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_30_audit_fields BEFORE INSERT OR UPDATE ON %I
                        FOR EACH ROW EXECUTE FUNCTION fn_trg_set_audit_fields()', t);
        EXECUTE format('CREATE TRIGGER trg_90_audit_log AFTER INSERT OR UPDATE OR DELETE ON %I
                        FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log()', t);
    END LOOP;
END;
$$;

CREATE TRIGGER trg_90_audit_log AFTER INSERT OR UPDATE OR DELETE ON student_transfers
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log();

-- Requirement 3: soft delete triggers
DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'faculties', 'departments', 'specialties', 'teachers', 'student_groups', 'students',
        'courses', 'buildings', 'classrooms', 'grades', 'scholarships']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_10_soft_delete BEFORE DELETE ON %I
                        FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete()', t);
    END LOOP;
END;
$$;

CREATE TRIGGER trg_20_validate
    BEFORE INSERT OR UPDATE OF group_id, status, deleted_at ON students
    FOR EACH ROW EXECUTE FUNCTION fn_trg_student_validate();

CREATE TRIGGER trg_80_after_change
    AFTER UPDATE OF status, deleted_at ON students
    FOR EACH ROW EXECUTE FUNCTION fn_trg_student_after_change();

CREATE TRIGGER trg_20_validate
    BEFORE INSERT ON enrollments
    FOR EACH ROW EXECUTE FUNCTION fn_trg_enrollment_validate();

CREATE TRIGGER trg_20_validate
    BEFORE INSERT OR UPDATE ON grades
    FOR EACH ROW EXECUTE FUNCTION fn_trg_grade_validate();

CREATE TRIGGER trg_20_validate
    BEFORE INSERT OR UPDATE OF teaching_assignment_id, classroom_id, day_of_week, lesson_no, week
    ON schedule_entries
    FOR EACH ROW EXECUTE FUNCTION fn_trg_schedule_validate();

CREATE TRIGGER trg_20_single_current
    BEFORE INSERT OR UPDATE OF is_current ON semesters
    FOR EACH ROW WHEN (NEW.is_current)
    EXECUTE FUNCTION fn_trg_semester_current();

CREATE TRIGGER trg_immutable
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log_immutable();

CREATE TRIGGER trg_immutable_truncate
    BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION fn_trg_audit_log_immutable();
