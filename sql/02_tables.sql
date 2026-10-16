-- Requirement 2: 21 entities.
-- Requirement 3: soft delete (deleted_at, deleted_by) and last change date / user (updated_at, updated_by).

-- Requirement 3: audit
CREATE TABLE users (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email          varchar(255) NOT NULL,
    password_hash  text         NOT NULL,
    role           user_role    NOT NULL,
    display_name   varchar(200) NOT NULL,
    is_active      boolean      NOT NULL DEFAULT true,
    last_login_at  timestamptz,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    created_by     bigint REFERENCES users (id),
    updated_at     timestamptz  NOT NULL DEFAULT now(),
    updated_by     bigint REFERENCES users (id),
    CONSTRAINT chk_users_email CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);
COMMENT ON TABLE users IS 'System user accounts (administrators, dean office, teachers, students)';

-- Requirement 3: soft delete + audit
CREATE TABLE faculties (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code             varchar(10)  NOT NULL,
    name             varchar(200) NOT NULL,
    dean_teacher_id  bigint,
    phone            varchar(20),
    email            varchar(255),
    created_at       timestamptz NOT NULL DEFAULT now(),
    created_by       bigint REFERENCES users (id),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       bigint REFERENCES users (id),
    deleted_at       timestamptz,
    deleted_by       bigint REFERENCES users (id)
);
COMMENT ON TABLE faculties IS 'University faculties';

-- Requirement 3: soft delete + audit
CREATE TABLE departments (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    faculty_id       bigint       NOT NULL REFERENCES faculties (id),
    code             varchar(10)  NOT NULL,
    name             varchar(200) NOT NULL,
    head_teacher_id  bigint,
    room             varchar(20),
    created_at       timestamptz NOT NULL DEFAULT now(),
    created_by       bigint REFERENCES users (id),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       bigint REFERENCES users (id),
    deleted_at       timestamptz,
    deleted_by       bigint REFERENCES users (id)
);
COMMENT ON TABLE departments IS 'Departments (belong to faculties)';

-- Requirement 3: soft delete + audit
CREATE TABLE specialties (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id       bigint        NOT NULL REFERENCES departments (id),
    code                varchar(10)   NOT NULL,
    name                varchar(200)  NOT NULL,
    degree_level        degree_level  NOT NULL DEFAULT 'bachelor',
    duration_semesters  smallint      NOT NULL DEFAULT 8,
    tuition_fee         numeric(10,2) NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    created_by          bigint REFERENCES users (id),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    updated_by          bigint REFERENCES users (id),
    deleted_at          timestamptz,
    deleted_by          bigint REFERENCES users (id),
    CONSTRAINT chk_specialties_duration CHECK (duration_semesters BETWEEN 1 AND 12),
    CONSTRAINT chk_specialties_fee      CHECK (tuition_fee >= 0)
);
COMMENT ON TABLE specialties IS 'Specialties (study programs)';

-- Requirement 3: soft delete + audit
CREATE TABLE teachers (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          bigint UNIQUE REFERENCES users (id),
    department_id    bigint           NOT NULL REFERENCES departments (id),
    last_name        varchar(100)     NOT NULL,
    first_name       varchar(100)     NOT NULL,
    middle_name      varchar(100),
    full_name        text GENERATED ALWAYS AS
                     (last_name || ' ' || first_name || COALESCE(' ' || middle_name, '')) STORED,
    position         teacher_position NOT NULL DEFAULT 'assistant',
    academic_degree  varchar(50),
    email            varchar(255),
    phone            varchar(20),
    hire_date        date             NOT NULL DEFAULT CURRENT_DATE,
    created_at       timestamptz NOT NULL DEFAULT now(),
    created_by       bigint REFERENCES users (id),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       bigint REFERENCES users (id),
    deleted_at       timestamptz,
    deleted_by       bigint REFERENCES users (id)
);
COMMENT ON TABLE teachers IS 'Teaching staff';

ALTER TABLE faculties
    ADD CONSTRAINT fk_faculties_dean FOREIGN KEY (dean_teacher_id) REFERENCES teachers (id) ON DELETE SET NULL;
ALTER TABLE departments
    ADD CONSTRAINT fk_departments_head FOREIGN KEY (head_teacher_id) REFERENCES teachers (id) ON DELETE SET NULL;

-- Requirement 3: soft delete + audit
CREATE TABLE student_groups (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    specialty_id        bigint      NOT NULL REFERENCES specialties (id),
    code                varchar(20) NOT NULL,
    admission_year      smallint    NOT NULL,
    curator_teacher_id  bigint REFERENCES teachers (id) ON DELETE SET NULL,
    max_size            smallint    NOT NULL DEFAULT 30,
    created_at          timestamptz NOT NULL DEFAULT now(),
    created_by          bigint REFERENCES users (id),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    updated_by          bigint REFERENCES users (id),
    deleted_at          timestamptz,
    deleted_by          bigint REFERENCES users (id),
    CONSTRAINT chk_groups_year CHECK (admission_year BETWEEN 1990 AND 2100),
    CONSTRAINT chk_groups_size CHECK (max_size BETWEEN 1 AND 60)
);
COMMENT ON TABLE student_groups IS 'Student groups';

-- Requirement 3: soft delete + audit
CREATE TABLE students (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          bigint UNIQUE REFERENCES users (id),
    group_id         bigint         NOT NULL REFERENCES student_groups (id),
    record_book_no   varchar(20)    NOT NULL,
    last_name        varchar(100)   NOT NULL,
    first_name       varchar(100)   NOT NULL,
    middle_name      varchar(100),
    full_name        text GENERATED ALWAYS AS
                     (last_name || ' ' || first_name || COALESCE(' ' || middle_name, '')) STORED,
    birth_date       date           NOT NULL,
    email            varchar(255),
    phone            varchar(20),
    enrollment_date  date           NOT NULL DEFAULT CURRENT_DATE,
    status           student_status NOT NULL DEFAULT 'active',
    funding          funding_type   NOT NULL DEFAULT 'budget',
    created_at       timestamptz NOT NULL DEFAULT now(),
    created_by       bigint REFERENCES users (id),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       bigint REFERENCES users (id),
    deleted_at       timestamptz,
    deleted_by       bigint REFERENCES users (id),
    CONSTRAINT uq_students_record_book UNIQUE (record_book_no),
    CONSTRAINT chk_students_birth CHECK (birth_date BETWEEN DATE '1940-01-01' AND enrollment_date - INTERVAL '14 years'),
    CONSTRAINT chk_students_email CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);
COMMENT ON TABLE students IS 'University students';

CREATE TABLE student_transfers (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id     bigint NOT NULL REFERENCES students (id) ON DELETE CASCADE,
    from_group_id  bigint NOT NULL REFERENCES student_groups (id),
    to_group_id    bigint NOT NULL REFERENCES student_groups (id),
    transfer_date  date   NOT NULL DEFAULT CURRENT_DATE,
    reason         text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    created_by     bigint REFERENCES users (id),
    CONSTRAINT chk_transfers_groups CHECK (from_group_id <> to_group_id)
);
COMMENT ON TABLE student_transfers IS 'History of student transfers between groups';

-- Requirement 3: audit
CREATE TABLE semesters (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    academic_year  varchar(9) NOT NULL,
    term           smallint   NOT NULL,
    start_date     date       NOT NULL,
    end_date       date       NOT NULL,
    is_current     boolean    NOT NULL DEFAULT false,
    is_closed      boolean    NOT NULL DEFAULT false,
    created_at     timestamptz NOT NULL DEFAULT now(),
    created_by     bigint REFERENCES users (id),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    updated_by     bigint REFERENCES users (id),
    CONSTRAINT uq_semesters UNIQUE (academic_year, term),
    CONSTRAINT chk_semesters_term  CHECK (term IN (1, 2)),
    CONSTRAINT chk_semesters_year  CHECK (academic_year ~ '^\d{4}/\d{4}$'),
    CONSTRAINT chk_semesters_dates CHECK (start_date < end_date),
    CONSTRAINT excl_semesters_overlap EXCLUDE USING gist (daterange(start_date, end_date, '[]') WITH &&)
);
COMMENT ON TABLE semesters IS 'Academic semesters';

-- Requirement 3: soft delete + audit
CREATE TABLE courses (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id  bigint       NOT NULL REFERENCES departments (id),
    code           varchar(20)  NOT NULL,
    name           varchar(200) NOT NULL,
    credits        numeric(4,1) NOT NULL,
    lecture_hours  smallint     NOT NULL DEFAULT 0,
    practice_hours smallint     NOT NULL DEFAULT 0,
    lab_hours      smallint     NOT NULL DEFAULT 0,
    control        control_form NOT NULL DEFAULT 'exam',
    description    text,
    search_vector  tsvector GENERATED ALWAYS AS
                   (to_tsvector('simple', name || ' ' || COALESCE(description, ''))) STORED,
    created_at     timestamptz NOT NULL DEFAULT now(),
    created_by     bigint REFERENCES users (id),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    updated_by     bigint REFERENCES users (id),
    deleted_at     timestamptz,
    deleted_by     bigint REFERENCES users (id),
    CONSTRAINT chk_courses_credits CHECK (credits > 0 AND credits <= 30),
    CONSTRAINT chk_courses_hours   CHECK (lecture_hours >= 0 AND practice_hours >= 0 AND lab_hours >= 0)
);
COMMENT ON TABLE courses IS 'Courses (owned by departments)';

-- Requirement 3: audit
CREATE TABLE curriculum_items (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    specialty_id  bigint   NOT NULL REFERENCES specialties (id) ON DELETE CASCADE,
    course_id     bigint   NOT NULL REFERENCES courses (id),
    semester_no   smallint NOT NULL,
    is_mandatory  boolean  NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    created_by    bigint REFERENCES users (id),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    updated_by    bigint REFERENCES users (id),
    CONSTRAINT uq_curriculum UNIQUE (specialty_id, course_id),
    CONSTRAINT chk_curriculum_semester CHECK (semester_no BETWEEN 1 AND 12)
);
COMMENT ON TABLE curriculum_items IS 'Curriculum: which courses a specialty studies and in which semester';

-- Requirement 3: audit
CREATE TABLE teaching_assignments (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    semester_id    bigint      NOT NULL REFERENCES semesters (id),
    course_id      bigint      NOT NULL REFERENCES courses (id),
    group_id       bigint      NOT NULL REFERENCES student_groups (id),
    teacher_id     bigint      NOT NULL REFERENCES teachers (id),
    lesson_type    lesson_type NOT NULL,
    planned_hours  smallint    NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    created_by     bigint REFERENCES users (id),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    updated_by     bigint REFERENCES users (id),
    CONSTRAINT uq_teaching_assignment UNIQUE (semester_id, course_id, group_id, lesson_type),
    CONSTRAINT chk_assignment_hours CHECK (planned_hours > 0)
);
COMMENT ON TABLE teaching_assignments IS 'Teaching load: which teacher teaches which lesson type of a course to a group in a semester';

-- Requirement 3: soft delete + audit
CREATE TABLE buildings (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        varchar(10)  NOT NULL,
    name        varchar(200) NOT NULL,
    address     varchar(300) NOT NULL,
    floors      smallint     NOT NULL DEFAULT 1,
    created_at  timestamptz NOT NULL DEFAULT now(),
    created_by  bigint REFERENCES users (id),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    updated_by  bigint REFERENCES users (id),
    deleted_at  timestamptz,
    deleted_by  bigint REFERENCES users (id),
    CONSTRAINT chk_buildings_floors CHECK (floors BETWEEN 1 AND 50)
);
COMMENT ON TABLE buildings IS 'University buildings';

-- Requirement 3: soft delete + audit
CREATE TABLE classrooms (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    building_id    bigint      NOT NULL REFERENCES buildings (id),
    room_number    varchar(10) NOT NULL,
    capacity       smallint    NOT NULL,
    room_type      room_type   NOT NULL DEFAULT 'classroom',
    has_projector  boolean     NOT NULL DEFAULT false,
    created_at     timestamptz NOT NULL DEFAULT now(),
    created_by     bigint REFERENCES users (id),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    updated_by     bigint REFERENCES users (id),
    deleted_at     timestamptz,
    deleted_by     bigint REFERENCES users (id),
    CONSTRAINT chk_classrooms_capacity CHECK (capacity BETWEEN 1 AND 500)
);
COMMENT ON TABLE classrooms IS 'Classrooms in university buildings';

-- Requirement 3: audit
CREATE TABLE schedule_entries (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    teaching_assignment_id  bigint      NOT NULL REFERENCES teaching_assignments (id) ON DELETE CASCADE,
    classroom_id            bigint      NOT NULL REFERENCES classrooms (id),
    day_of_week             smallint    NOT NULL,
    lesson_no               smallint    NOT NULL,
    week                    week_parity NOT NULL DEFAULT 'every',
    created_at              timestamptz NOT NULL DEFAULT now(),
    created_by              bigint REFERENCES users (id),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    updated_by              bigint REFERENCES users (id),
    CONSTRAINT chk_schedule_day    CHECK (day_of_week BETWEEN 1 AND 6),
    CONSTRAINT chk_schedule_lesson CHECK (lesson_no BETWEEN 1 AND 8)
);
COMMENT ON TABLE schedule_entries IS 'Timetable: lesson slot (day, number, week) of a teaching assignment in a classroom';

-- Requirement 3: audit
CREATE TABLE enrollments (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id      bigint            NOT NULL REFERENCES students (id),
    course_id       bigint            NOT NULL REFERENCES courses (id),
    semester_id     bigint            NOT NULL REFERENCES semesters (id),
    status          enrollment_status NOT NULL DEFAULT 'enrolled',
    enrolled_at     timestamptz       NOT NULL DEFAULT now(),
    total_score     numeric(5,2),
    ects_grade      varchar(2),
    national_grade  varchar(20),
    finalized_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      bigint REFERENCES users (id),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    updated_by      bigint REFERENCES users (id),
    CONSTRAINT uq_enrollment UNIQUE (student_id, course_id, semester_id),
    CONSTRAINT chk_enrollment_score CHECK (total_score IS NULL OR total_score BETWEEN 0 AND 100),
    CONSTRAINT chk_enrollment_ects  CHECK (ects_grade IS NULL OR ects_grade IN ('A','B','C','D','E','FX','F')),
    CONSTRAINT chk_enrollment_final CHECK ((status IN ('completed','failed')) = (finalized_at IS NOT NULL))
);
COMMENT ON TABLE enrollments IS 'Student enrollment in a course for a semester and the final grade';

-- Requirement 3: soft delete + audit
CREATE TABLE grades (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    enrollment_id    bigint          NOT NULL REFERENCES enrollments (id) ON DELETE CASCADE,
    assessment_type  assessment_type NOT NULL,
    title            varchar(100)    NOT NULL,
    score            numeric(5,2)    NOT NULL,
    max_score        numeric(5,2)    NOT NULL,
    graded_on        date            NOT NULL DEFAULT CURRENT_DATE,
    teacher_id       bigint REFERENCES teachers (id),
    comment          text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    created_by       bigint REFERENCES users (id),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       bigint REFERENCES users (id),
    deleted_at       timestamptz,
    deleted_by       bigint REFERENCES users (id),
    CONSTRAINT chk_grades_max   CHECK (max_score > 0 AND max_score <= 100),
    CONSTRAINT chk_grades_score CHECK (score >= 0 AND score <= max_score)
);
COMMENT ON TABLE grades IS 'Assessment grades within a course enrollment';

-- Requirement 3: audit
CREATE TABLE attendance (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schedule_entry_id  bigint            NOT NULL REFERENCES schedule_entries (id) ON DELETE CASCADE,
    student_id         bigint            NOT NULL REFERENCES students (id),
    lesson_date        date              NOT NULL,
    status             attendance_status NOT NULL DEFAULT 'present',
    created_at         timestamptz NOT NULL DEFAULT now(),
    created_by         bigint REFERENCES users (id),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    updated_by         bigint REFERENCES users (id),
    CONSTRAINT uq_attendance UNIQUE (schedule_entry_id, student_id, lesson_date)
);
COMMENT ON TABLE attendance IS 'Lesson attendance log';

-- Requirement 3: soft delete + audit
CREATE TABLE scholarships (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id        bigint           NOT NULL REFERENCES students (id),
    semester_id       bigint           NOT NULL REFERENCES semesters (id),
    scholarship_type  scholarship_type NOT NULL,
    amount            numeric(10,2)    NOT NULL,
    start_date        date             NOT NULL,
    end_date          date             NOT NULL,
    order_no          varchar(30),
    created_at        timestamptz NOT NULL DEFAULT now(),
    created_by        bigint REFERENCES users (id),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    updated_by        bigint REFERENCES users (id),
    deleted_at        timestamptz,
    deleted_by        bigint REFERENCES users (id),
    CONSTRAINT chk_scholarship_amount CHECK (amount > 0),
    CONSTRAINT chk_scholarship_dates  CHECK (start_date <= end_date),
    CONSTRAINT excl_scholarship_overlap EXCLUDE USING gist (
        student_id WITH =,
        scholarship_type WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    ) WHERE (deleted_at IS NULL)
);
COMMENT ON TABLE scholarships IS 'Scholarships granted to students';

-- Requirement 3: audit
CREATE TABLE tuition_payments (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id   bigint         NOT NULL REFERENCES students (id),
    semester_id  bigint         NOT NULL REFERENCES semesters (id),
    amount       numeric(10,2)  NOT NULL,
    paid_at      timestamptz    NOT NULL DEFAULT now(),
    method       payment_method NOT NULL,
    receipt_no   varchar(40)    NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    created_by   bigint REFERENCES users (id),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    updated_by   bigint REFERENCES users (id),
    CONSTRAINT uq_payment_receipt UNIQUE (receipt_no),
    CONSTRAINT chk_payment_amount CHECK (amount > 0)
);
COMMENT ON TABLE tuition_payments IS 'Tuition payments of contract students';

-- Requirement 3: change history (who, when, what) written by triggers
CREATE TABLE audit_log (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name      text        NOT NULL,
    record_id       bigint      NOT NULL,
    operation       varchar(12) NOT NULL,
    old_data        jsonb,
    new_data        jsonb,
    changed_fields  text[],
    changed_by      bigint,
    changed_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
    tx_id           bigint      NOT NULL DEFAULT txid_current(),
    CONSTRAINT chk_audit_operation CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'SOFT_DELETE', 'RESTORE'))
);
COMMENT ON TABLE audit_log IS 'Full change log (who, when, what) for audited tables';
