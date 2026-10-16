-- Requirement 6: indexes of different types (B-tree, Hash, GIN, GiST, BRIN).

-- B-tree: partial unique indexes that respect soft delete (requirement 3)
CREATE UNIQUE INDEX uq_users_email_lower        ON users (lower(email));
CREATE UNIQUE INDEX uq_faculties_code_active    ON faculties (code)      WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_departments_code_active  ON departments (code)    WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_specialties_code_active  ON specialties (code, degree_level) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_groups_code_active       ON student_groups (code) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_courses_code_active      ON courses (code)        WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_buildings_code_active    ON buildings (code)      WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_classrooms_room_active   ON classrooms (building_id, room_number) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uq_students_email_active    ON students (lower(email)) WHERE deleted_at IS NULL AND email IS NOT NULL;
CREATE UNIQUE INDEX uq_teachers_email_active    ON teachers (lower(email)) WHERE deleted_at IS NULL AND email IS NOT NULL;

CREATE UNIQUE INDEX uq_semesters_single_current ON semesters (is_current) WHERE is_current;

-- B-tree
CREATE INDEX ix_departments_faculty        ON departments (faculty_id);
CREATE INDEX ix_specialties_department     ON specialties (department_id);
CREATE INDEX ix_teachers_department        ON teachers (department_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_groups_specialty           ON student_groups (specialty_id);
CREATE INDEX ix_students_group_active      ON students (group_id, last_name, first_name) WHERE deleted_at IS NULL;
CREATE INDEX ix_students_status            ON students (status) WHERE deleted_at IS NULL AND status <> 'active';
CREATE INDEX ix_students_deleted_at        ON students (deleted_at DESC) WHERE deleted_at IS NOT NULL;
CREATE INDEX ix_transfers_student          ON student_transfers (student_id, transfer_date DESC);
CREATE INDEX ix_courses_department         ON courses (department_id);
CREATE INDEX ix_curriculum_course          ON curriculum_items (course_id);
CREATE INDEX ix_assign_teacher_semester    ON teaching_assignments (teacher_id, semester_id);
CREATE INDEX ix_assign_group_semester      ON teaching_assignments (group_id, semester_id);
CREATE INDEX ix_schedule_assignment        ON schedule_entries (teaching_assignment_id);
CREATE INDEX ix_schedule_slot              ON schedule_entries (classroom_id, day_of_week, lesson_no);
CREATE INDEX ix_enrollments_course_sem     ON enrollments (course_id, semester_id);
CREATE INDEX ix_grades_enrollment_active   ON grades (enrollment_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_attendance_student         ON attendance (student_id, lesson_date);
CREATE INDEX ix_scholarships_student       ON scholarships (student_id, semester_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_payments_student_semester  ON tuition_payments (student_id, semester_id);
CREATE INDEX ix_audit_record               ON audit_log (table_name, record_id, changed_at DESC);

-- B-tree covering index (INCLUDE)
CREATE INDEX ix_enrollments_student_cover  ON enrollments (student_id, semester_id)
    INCLUDE (course_id, status, total_score, ects_grade);

-- B-tree partial index
CREATE INDEX ix_enrollments_failed         ON enrollments (semester_id, student_id) WHERE status = 'failed';

-- Hash
CREATE INDEX ix_audit_tx_hash              ON audit_log USING hash (tx_id);
CREATE INDEX ix_students_record_book_hash  ON students  USING hash (record_book_no);

-- GIN (pg_trgm)
CREATE INDEX ix_students_full_name_trgm    ON students USING gin (full_name gin_trgm_ops);
CREATE INDEX ix_teachers_full_name_trgm    ON teachers USING gin (full_name gin_trgm_ops);

-- GIN (full-text search)
CREATE INDEX ix_courses_search             ON courses USING gin (search_vector);

-- GIN (jsonb)
CREATE INDEX ix_audit_new_data             ON audit_log USING gin (new_data jsonb_path_ops);

-- BRIN
CREATE INDEX ix_attendance_date_brin       ON attendance       USING brin (lesson_date);
CREATE INDEX ix_audit_changed_at_brin      ON audit_log        USING brin (changed_at);
CREATE INDEX ix_payments_paid_at_brin      ON tuition_payments USING brin (paid_at);

-- GiST indexes are created by the EXCLUDE constraints excl_semesters_overlap and excl_scholarship_overlap (02_tables.sql)
