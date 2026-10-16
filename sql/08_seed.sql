BEGIN;

SELECT setseed(0.42);

INSERT INTO users (email, password_hash, role, display_name)
VALUES ('admin@univ.edu.ua', '$2b$12$' || encode(sha256('admin'::bytea), 'hex'), 'admin', 'System Administrator');

DO $$ BEGIN PERFORM fn_set_current_user((SELECT id FROM users WHERE email = 'admin@univ.edu.ua')); END $$;

INSERT INTO users (email, password_hash, role, display_name) VALUES
    ('dean.office@univ.edu.ua', '$2b$12$' || encode(sha256('dean.office'::bytea), 'hex'), 'dean_office', 'Olena Koval (Dean Office)'),
    ('registrar@univ.edu.ua',   '$2b$12$' || encode(sha256('registrar'::bytea), 'hex'),   'dean_office', 'Ihor Danyliuk (Registrar)');

INSERT INTO faculties (code, name, phone, email) VALUES
    ('FIT', 'Faculty of Information Technology',   '+380442000101', 'fit@univ.edu.ua'),
    ('FEM', 'Faculty of Economics and Management', '+380442000202', 'fem@univ.edu.ua'),
    ('FAM', 'Faculty of Applied Mathematics',      '+380442000303', 'fam@univ.edu.ua');

INSERT INTO departments (faculty_id, code, name, room)
SELECT f.id, d.code, d.name, d.room
FROM (SELECT v.*, row_number() OVER () AS ord FROM (VALUES
    ('FIT', 'SE',  'Department of Software Engineering', 'B-301'),
    ('FIT', 'CS',  'Department of Computer Science',     'B-310'),
    ('FEM', 'ECO', 'Department of Economics',            'C-201'),
    ('FEM', 'MGT', 'Department of Management',           'C-210'),
    ('FAM', 'HM',  'Department of Higher Mathematics',   'A-401'),
    ('FAM', 'AM',  'Department of Applied Mathematics',  'A-410')
) AS v(faculty, code, name, room)) AS d
JOIN faculties f ON f.code = d.faculty
ORDER BY d.ord;

INSERT INTO specialties (department_id, code, name, degree_level, duration_semesters, tuition_fee)
SELECT d.id, s.code, s.name, 'bachelor', 8, s.fee
FROM (SELECT v.*, row_number() OVER () AS ord FROM (VALUES
    ('SE',  '121', 'Software Engineering', 42000),
    ('CS',  '122', 'Computer Science',     45000),
    ('ECO', '051', 'Economics',            30000),
    ('MGT', '073', 'Management',           28000),
    ('AM',  '113', 'Applied Mathematics',  32000)
) AS v(dept, code, name, fee)) AS s
JOIN departments d ON d.code = s.dept
ORDER BY s.ord;

WITH t (last_name, first_name, middle_name, dept, pos, degree, email, hired) AS (VALUES
    ('Petrenko',    'Oleksandr', 'Ivanovych',      'SE',  'professor',           'DSc', 'o.petrenko@univ.edu.ua',    DATE '2005-09-01'),
    ('Kovalenko',   'Iryna',     'Vasylivna',      'SE',  'associate_professor', 'PhD', 'i.kovalenko@univ.edu.ua',   DATE '2011-09-01'),
    ('Tkachenko',   'Dmytro',    'Olehovych',      'SE',  'senior_lecturer',     'PhD', 'd.tkachenko@univ.edu.ua',   DATE '2018-09-01'),
    ('Shevchuk',    'Andrii',    'Mykolaiovych',   'CS',  'professor',           'DSc', 'a.shevchuk@univ.edu.ua',    DATE '2003-09-01'),
    ('Bondarenko',  'Nataliia',  'Petrivna',       'CS',  'associate_professor', 'PhD', 'n.bondarenko@univ.edu.ua',  DATE '2012-09-01'),
    ('Kravchenko',  'Olena',     'Serhiivna',      'CS',  'assistant',           NULL,  'o.kravchenko@univ.edu.ua',  DATE '2022-09-01'),
    ('Melnyk',      'Viktor',    'Stepanovych',    'ECO', 'professor',           'DSc', 'v.melnyk@univ.edu.ua',      DATE '2001-09-01'),
    ('Savchenko',   'Yurii',     'Petrovych',      'ECO', 'senior_lecturer',     'PhD', 'y.savchenko@univ.edu.ua',   DATE '2015-09-01'),
    ('Oliinyk',     'Tetiana',   'Andriivna',      'MGT', 'associate_professor', 'PhD', 't.oliinyk@univ.edu.ua',     DATE '2010-09-01'),
    ('Kuzmenko',    'Oksana',    'Valeriivna',     'MGT', 'senior_lecturer',     NULL,  'o.kuzmenko@univ.edu.ua',    DATE '2019-09-01'),
    ('Rudenko',     'Maryna',    'Oleksandrivna',  'HM',  'professor',           'DSc', 'm.rudenko@univ.edu.ua',     DATE '2000-09-01'),
    ('Lysenko',     'Bohdan',    'Ihorovych',      'HM',  'associate_professor', 'PhD', 'b.lysenko@univ.edu.ua',     DATE '2014-09-01'),
    ('Moroz',       'Svitlana',  'Viktorivna',     'AM',  'associate_professor', 'PhD', 's.moroz@univ.edu.ua',       DATE '2009-09-01'),
    ('Honcharenko', 'Pavlo',     'Romanovych',     'AM',  'assistant',           NULL,  'p.honcharenko@univ.edu.ua', DATE '2023-09-01')
),
u AS (
    INSERT INTO users (email, password_hash, role, display_name)
    SELECT email, '$2b$12$' || encode(sha256(convert_to(email, 'UTF8')), 'hex'), 'teacher',
           last_name || ' ' || first_name
    FROM t
    RETURNING id, email
)
INSERT INTO teachers (user_id, department_id, last_name, first_name, middle_name, position,
                      academic_degree, email, phone, hire_date)
SELECT u.id, d.id, t.last_name, t.first_name, t.middle_name, t.pos::teacher_position,
       t.degree, t.email, '+38050' || lpad((1234567 + u.id * 104729 % 8000000)::text, 7, '0'), t.hired
FROM t
JOIN u           ON u.email = t.email
JOIN departments d ON d.code = t.dept
ORDER BY u.id;

UPDATE faculties f SET dean_teacher_id = t.id
FROM (VALUES ('FIT', 'Shevchuk'), ('FEM', 'Melnyk'), ('FAM', 'Rudenko')) AS x(faculty, teacher)
JOIN teachers t ON t.last_name = x.teacher
WHERE f.code = x.faculty;

UPDATE departments d SET head_teacher_id = t.id
FROM (VALUES ('SE', 'Petrenko'), ('CS', 'Shevchuk'), ('ECO', 'Melnyk'),
             ('MGT', 'Oliinyk'), ('HM', 'Rudenko'),  ('AM', 'Moroz')) AS x(dept, teacher)
JOIN teachers t ON t.last_name = x.teacher
WHERE d.code = x.dept;

INSERT INTO buildings (code, name, address, floors) VALUES
    ('A', 'Main Building',      'Kyiv, 1 Nauky Ave',       5),
    ('B', 'IT Building',        'Kyiv, 7 Akademichna St',  4),
    ('C', 'Economics Building', 'Kyiv, 9 Akademichna St',  3);

INSERT INTO classrooms (building_id, room_number, capacity, room_type, has_projector)
SELECT b.id, r.room, r.cap, r.rtype::room_type, r.proj
FROM (SELECT v.*, row_number() OVER () AS ord FROM (VALUES
    ('A', '101', 120, 'lecture_hall', true),  ('A', '102',  90, 'lecture_hall', true),
    ('A', '201',  30, 'classroom',    false), ('A', '202',  30, 'classroom',    true),
    ('A', '203',  35, 'classroom',    false),
    ('B', '105',  30, 'computer_lab', true),  ('B', '106',  30, 'computer_lab', false),
    ('B', '107',  28, 'computer_lab', true),  ('B', '210',  60, 'lecture_hall', true),
    ('B', '211',  30, 'classroom',    true),  ('B', '305',  24, 'laboratory',   false),
    ('C', '110',  80, 'lecture_hall', true),  ('C', '120',  32, 'classroom',    true),
    ('C', '121',  30, 'classroom',    false)
) AS v(building, room, cap, rtype, proj)) AS r
JOIN buildings b ON b.code = r.building
ORDER BY r.ord;

INSERT INTO semesters (academic_year, term, start_date, end_date, is_current) VALUES
    ('2025/2026', 1, '2025-09-01', '2025-12-28', false),
    ('2025/2026', 2, '2026-01-26', '2026-06-28', false),
    ('2026/2027', 1, '2026-09-01', '2026-12-27', true);

INSERT INTO courses (department_id, code, name, credits, lecture_hours, practice_hours, lab_hours, control, description)
SELECT d.id, c.code, c.name, c.credits, c.lec, c.prac, c.lab, c.ctrl::control_form, c.descr
FROM (SELECT v.*, row_number() OVER () AS ord FROM (VALUES
    ('HM',  'MATH-101', 'Higher Mathematics',                               6, 48, 32,  0, 'exam',        'Linear algebra, analytic geometry, calculus'),
    ('HM',  'MATH-102', 'Discrete Mathematics',                             5, 32, 32,  0, 'exam',        'Sets, relations, combinatorics, graph theory, Boolean functions'),
    ('HM',  'MATH-201', 'Probability Theory and Mathematical Statistics',   4, 32, 16,  0, 'exam',        'Random variables, distributions, statistical estimation, hypothesis testing'),
    ('SE',  'SE-101',   'Programming Fundamentals',                         6, 32,  0, 48, 'exam',        'Algorithms, the C language, data structures, debugging'),
    ('SE',  'SE-102',   'Web Technologies',                                 4, 16,  0, 32, 'diff_credit', 'HTML, CSS, JavaScript, HTTP, REST API'),
    ('SE',  'SE-201',   'Object-Oriented Programming',                      5, 32,  0, 32, 'exam',        'Classes, encapsulation, inheritance, polymorphism, design patterns'),
    ('SE',  'SE-301',   'Databases',                                        5, 32,  0, 32, 'exam',        'Relational model, SQL, normalization, transactions, indexes, PostgreSQL'),
    ('SE',  'SE-302',   'Software Architecture',                            4, 32,  0, 16, 'diff_credit', 'Architectural styles, microservices, DDD, Repository and Unit of Work patterns'),
    ('SE',  'SE-303',   'Software Testing',                                 4, 16,  0, 32, 'credit',      'Unit, integration and load testing, TDD'),
    ('SE',  'SE-304',   'Cloud Technologies',                               4, 16,  0, 32, 'credit',      'Docker, Kubernetes, CI/CD, cloud services'),
    ('SE',  'SE-305',   'IT Project Management',                            3, 16, 16,  0, 'credit',      'Scrum, Kanban, effort estimation, risk management'),
    ('CS',  'CS-201',   'Algorithms and Data Structures',                   5, 32,  0, 32, 'exam',        'Algorithm complexity, sorting, trees, graphs, dynamic programming'),
    ('CS',  'CS-301',   'Computer Networks',                                4, 32,  0, 16, 'exam',        'OSI model, TCP/IP, routing, network security'),
    ('CS',  'CS-302',   'Machine Learning',                                 5, 32,  0, 32, 'exam',        'Regression, classification, neural networks, model evaluation'),
    ('CS',  'CS-303',   'Operating Systems',                                4, 32,  0, 16, 'credit',      'Processes, threads, scheduling, memory, file systems'),
    ('CS',  'CS-304',   'Computer Graphics',                                4, 16,  0, 32, 'exam',        'Raster and vector graphics, OpenGL, shaders'),
    ('ECO', 'ECO-101',  'Microeconomics',                                   5, 32, 32,  0, 'exam',        'Supply and demand, consumer behavior, theory of the firm'),
    ('ECO', 'ECO-201',  'Macroeconomics',                                   5, 32, 32,  0, 'exam',        'GDP, inflation, unemployment, monetary and fiscal policy'),
    ('ECO', 'ECO-301',  'Econometrics',                                     4, 16,  0, 32, 'diff_credit', 'Regression models, time series, forecasting'),
    ('ECO', 'ECO-302',  'Finance, Money and Credit',                        5, 32, 32,  0, 'exam',        'Financial system, money circulation, banking'),
    ('ECO', 'ECO-303',  'International Economics',                          4, 32, 16,  0, 'credit',      'International trade, exchange rates, globalization'),
    ('MGT', 'MGT-101',  'Fundamentals of Management',                       4, 32, 16,  0, 'exam',        'Management functions: planning, organizing, motivation, control'),
    ('MGT', 'MGT-201',  'Marketing',                                        4, 16, 32,  0, 'credit',      'Market research, market segmentation, marketing mix'),
    ('MGT', 'MGT-202',  'Strategic Management',                             5, 32, 32,  0, 'exam',        'Strategic analysis, SWOT, competitive strategies'),
    ('AM',  'AM-201',   'Numerical Methods',                                5, 32,  0, 32, 'exam',        'Solving equations, interpolation, numerical integration'),
    ('AM',  'AM-301',   'Optimization Methods',                             5, 32, 16,  0, 'exam',        'Linear programming, the simplex method, nonlinear optimization'),
    ('AM',  'AM-302',   'Mathematical Modeling',                            5, 32,  0, 32, 'exam',        'Building and analyzing mathematical models of systems')
) AS v(dept, code, name, credits, lec, prac, lab, ctrl, descr)) AS c
JOIN departments d ON d.code = c.dept
ORDER BY c.ord;

INSERT INTO curriculum_items (specialty_id, course_id, semester_no)
SELECT sp.id, c.id, x.sem
FROM (SELECT v.*, row_number() OVER () AS ord FROM (VALUES
    ('121', 'MATH-101', 1), ('121', 'SE-101', 1),
    ('121', 'MATH-102', 2), ('121', 'SE-102', 2),
    ('121', 'SE-201',   3), ('121', 'CS-201', 3), ('121', 'MATH-201', 3),
    ('121', 'SE-301',   4), ('121', 'CS-303', 4),
    ('121', 'SE-302',   5), ('121', 'CS-301', 5), ('121', 'SE-303', 5),
    ('121', 'CS-302',   6), ('121', 'SE-305', 6),
    ('121', 'SE-304',   7), ('121', 'CS-304', 7),
    ('122', 'MATH-101', 1), ('122', 'SE-101', 1),
    ('122', 'MATH-102', 2), ('122', 'SE-102', 2),
    ('122', 'CS-201',   3), ('122', 'MATH-201', 3), ('122', 'SE-201', 3),
    ('122', 'CS-303',   4), ('122', 'SE-301', 4),
    ('122', 'CS-301',   5), ('122', 'CS-302', 5), ('122', 'CS-304', 5),
    ('051', 'ECO-101',  1), ('051', 'MATH-101', 1),
    ('051', 'MGT-101',  2), ('051', 'MATH-201', 2),
    ('051', 'ECO-201',  3), ('051', 'MGT-201', 3),
    ('051', 'ECO-301',  4), ('051', 'ECO-303', 4),
    ('051', 'ECO-302',  5), ('051', 'MGT-202', 5),
    ('073', 'MGT-101',  1), ('073', 'ECO-101', 1),
    ('073', 'MGT-201',  2), ('073', 'MATH-101', 2),
    ('073', 'MGT-202',  3), ('073', 'ECO-201', 3),
    ('113', 'MATH-101', 1), ('113', 'SE-101', 1),
    ('113', 'MATH-102', 2), ('113', 'MATH-201', 2),
    ('113', 'AM-201',   3), ('113', 'CS-201', 3),
    ('113', 'AM-301',   4), ('113', 'SE-301', 4),
    ('113', 'AM-302',   5), ('113', 'CS-302', 5)
) AS v(spec, course, sem)) AS x
JOIN specialties sp ON sp.code = x.spec
JOIN courses c      ON c.code  = x.course
ORDER BY x.ord;

INSERT INTO student_groups (specialty_id, code, admission_year, curator_teacher_id, max_size)
SELECT sp.id, g.code, g.yr, t.id, 25
FROM (SELECT v.*, row_number() OVER () AS ord FROM (VALUES
    ('SE-23', '121', 2023, 'Tkachenko'),
    ('SE-24', '121', 2024, 'Kovalenko'),
    ('CS-24', '122', 2024, 'Bondarenko'),
    ('CS-25', '122', 2025, 'Kravchenko'),
    ('EC-24', '051', 2024, 'Savchenko'),
    ('MG-25', '073', 2025, 'Kuzmenko'),
    ('AM-24', '113', 2024, 'Honcharenko')
) AS v(code, spec, yr, curator)) AS g
JOIN specialties sp ON sp.code = g.spec
JOIN teachers t     ON t.last_name = g.curator
ORDER BY g.ord;

WITH grp (ord, code, cnt) AS (VALUES
    (1, 'SE-23', 10), (2, 'SE-24', 12), (3, 'CS-24', 12), (4, 'CS-25', 12),
    (5, 'EC-24', 10), (6, 'MG-25', 9),  (7, 'AM-24', 9)
),
seq AS (
    SELECT grp.code, row_number() OVER (ORDER BY grp.ord, n) AS rn
    FROM grp, generate_series(1, grp.cnt) AS n
),
names AS (
    SELECT ARRAY['Shevchenko','Kovalenko','Bondarenko','Tkachenko','Kravchuk','Melnychuk','Polishchuk','Savchuk',
                 'Marchenko','Lytvynenko','Hrytsenko','Pavlenko','Kyrylenko','Holovko','Diachuk','Ostapchuk',
                 'Romanenko','Yaroshenko','Yakovenko','Nesterenko','Tymoshenko','Levchenko','Zakharchenko',
                 'Onyshchenko','Demchenko','Zinchenko','Ponomarenko','Humeniuk','Petruk','Karpenko'] AS last_names,
           ARRAY['Oleksandr','Andrii','Dmytro','Maksym','Vladyslav','Bohdan','Artem','Nazar','Taras','Yevhen'] AS male,
           ARRAY['Anna','Mariia','Sofiia','Viktoriia','Daryna','Yuliia','Kateryna','Olena','Iryna','Khrystyna'] AS female,
           ARRAY['Oleksandrovych','Ivanovych','Petrovych','Serhiiovych','Mykhailovych',
                 'Vasylovych','Andriiovych','Volodymyrovych','Mykolaiovych','Yuriiovych'] AS male_pat,
           ARRAY['Oleksandrivna','Ivanivna','Petrivna','Serhiivna','Mykhailivna',
                 'Vasylivna','Andriivna','Volodymyrivna','Mykolaivna','Yuriivna'] AS female_pat
)
INSERT INTO students (group_id, record_book_no, last_name, first_name, middle_name, birth_date,
                      email, phone, enrollment_date, funding)
SELECT g.id,
       'RB' || g.admission_year || '-' || lpad(seq.rn::text, 4, '0'),
       n.last_names[(seq.rn * 7) % 30 + 1],
       CASE WHEN seq.rn % 2 = 0 THEN n.male[(seq.rn * 3) % 10 + 1]       ELSE n.female[(seq.rn * 3) % 10 + 1] END,
       CASE WHEN seq.rn % 2 = 0 THEN n.male_pat[(seq.rn * 7 + 3) % 10 + 1] ELSE n.female_pat[(seq.rn * 7 + 3) % 10 + 1] END,
       make_date(g.admission_year - 17, 1 + seq.rn::int % 12, 1 + (seq.rn::int * 13) % 28),
       's' || g.admission_year || lpad(seq.rn::text, 4, '0') || '@stud.univ.edu.ua',
       '+38067' || lpad((1000000 + seq.rn * 7919 % 9000000)::text, 7, '0'),
       make_date(g.admission_year, 9, 1),
       CASE WHEN seq.rn % 3 = 0 THEN 'contract' ELSE 'budget' END::funding_type
FROM seq
JOIN student_groups g ON g.code = seq.code
CROSS JOIN names n
ORDER BY seq.rn;

INSERT INTO teaching_assignments (semester_id, course_id, group_id, teacher_id, lesson_type, planned_hours)
SELECT sm.id, c.id, g.id,
       (SELECT t.id FROM teachers t
        WHERE t.department_id = c.department_id
        ORDER BY t.position DESC, t.id
        LIMIT 1 OFFSET CASE WHEN lt.kind = 'lecture' THEN 0 ELSE 1 END),
       lt.kind, lt.hours
FROM student_groups g
JOIN curriculum_items ci ON ci.specialty_id = g.specialty_id
JOIN courses c           ON c.id = ci.course_id
JOIN semesters sm        ON fn_semester_number(g.admission_year, sm.id) = ci.semester_no
CROSS JOIN LATERAL (VALUES ('lecture'::lesson_type, c.lecture_hours),
                           ('practice'::lesson_type, c.practice_hours),
                           ('lab'::lesson_type, c.lab_hours)) AS lt(kind, hours)
WHERE lt.hours > 0
ORDER BY sm.id, g.id, c.id, lt.kind;

DO $$
DECLARE
    a       record;
    r       record;
    v_day   integer;
    v_les   integer;
    placed  boolean;
BEGIN
    FOR a IN
        SELECT ta.id, ta.lesson_type
        FROM teaching_assignments ta
        WHERE ta.semester_id = fn_current_semester_id()
        ORDER BY ta.group_id, ta.course_id, ta.lesson_type
    LOOP
        placed := false;
        <<slots>>
        FOR v_les IN 1..5 LOOP
            FOR v_day IN 1..5 LOOP
                FOR r IN
                    SELECT c.id
                    FROM classrooms c
                    WHERE c.deleted_at IS NULL
                      AND c.room_type = CASE a.lesson_type
                                            WHEN 'lecture' THEN 'lecture_hall'
                                            WHEN 'lab'     THEN 'computer_lab'
                                            ELSE 'classroom'
                                        END::room_type
                    ORDER BY c.capacity, c.id
                LOOP
                    BEGIN
                        INSERT INTO schedule_entries (teaching_assignment_id, classroom_id, day_of_week, lesson_no)
                        VALUES (a.id, r.id, v_day, v_les);
                        placed := true;
                        EXIT slots;
                    EXCEPTION WHEN SQLSTATE 'UA001' THEN
                        NULL;
                    END;
                END LOOP;
            END LOOP;
        END LOOP;
        IF NOT placed THEN
            RAISE WARNING 'Could not place teaching assignment #% in the schedule', a.id;
        END IF;
    END LOOP;
END;
$$;

DO $$ BEGIN PERFORM fn_set_current_user((SELECT id FROM users WHERE email = 'dean.office@univ.edu.ua')); END $$;

CREATE FUNCTION pg_temp.seed_grades(p_semester_id bigint, p_works integer, p_with_final boolean)
RETURNS void
LANGUAGE sql
AS $$
    WITH e AS (
        SELECT e.id, s.group_id, e.course_id, c.control, sm.start_date,
               c.lab_hours > 0                          AS has_lab,
               0.50 + ((s.id * 7919) % 49) / 100.0      AS ability
        FROM enrollments e
        JOIN students s   ON s.id  = e.student_id
        JOIN courses c    ON c.id  = e.course_id
        JOIN semesters sm ON sm.id = e.semester_id
        WHERE e.semester_id = p_semester_id AND e.status = 'enrolled'
    ),
    items AS (
        SELECT e.*, k AS no,
               (CASE WHEN e.has_lab THEN 'lab' ELSE 'practice' END)::assessment_type AS kind,
               CASE WHEN e.has_lab THEN 'Lab ' ELSE 'Practice ' END || k             AS title,
               10::numeric AS max_score,
               e.start_date + k * 14                                                AS graded_on
        FROM e CROSS JOIN generate_series(1, p_works) AS k
        UNION ALL
        SELECT e.*, 5, 'module', 'Module test', 20, e.start_date + 60
        FROM e WHERE p_with_final
        UNION ALL
        SELECT e.*, 6,
               (CASE WHEN e.control = 'exam' THEN 'exam' ELSE 'test' END)::assessment_type,
               CASE WHEN e.control = 'exam' THEN 'Exam' ELSE 'Final test' END,
               40, e.start_date + 110
        FROM e WHERE p_with_final
    )
    INSERT INTO grades (enrollment_id, assessment_type, title, score, max_score, graded_on, teacher_id)
    SELECT i.id, i.kind, i.title,
           LEAST(i.max_score, round(i.max_score * LEAST(1.0, i.ability * (0.85 + random() * 0.30)))),
           i.max_score, i.graded_on,
           (SELECT ta.teacher_id
            FROM teaching_assignments ta
            WHERE ta.semester_id = p_semester_id AND ta.course_id = i.course_id AND ta.group_id = i.group_id
            ORDER BY (ta.lesson_type = 'lecture') = (i.kind IN ('module', 'exam', 'test')) DESC
            LIMIT 1)
    FROM items i
    ORDER BY i.id, i.no
$$;

DO $$
DECLARE
    v_sem    record;
    v_group  record;
    v_cnt    integer;
BEGIN
    FOR v_sem IN SELECT id FROM semesters WHERE NOT is_current ORDER BY start_date LOOP
        FOR v_group IN SELECT id FROM student_groups ORDER BY id LOOP
            CALL sp_enroll_group_by_curriculum(v_group.id, v_sem.id, v_cnt);
        END LOOP;
        PERFORM pg_temp.seed_grades(v_sem.id, 4, true);
        CALL sp_semester_close(v_sem.id, v_cnt);
    END LOOP;

    FOR v_group IN SELECT id FROM student_groups ORDER BY id LOOP
        CALL sp_enroll_group_by_curriculum(v_group.id, fn_current_semester_id(), v_cnt);
    END LOOP;
    PERFORM pg_temp.seed_grades(fn_current_semester_id(), 2, false);
END;
$$;

DO $$
DECLARE
    v_cnt  integer;
    v_sem  bigint;
BEGIN
    FOR v_sem IN SELECT id FROM semesters WHERE is_closed ORDER BY start_date LOOP
        CALL sp_scholarships_assign(v_sem, 75, 2000, 40, 'Order No. ' || (200 + v_sem) || '-S', v_cnt);
    END LOOP;
END;
$$;

INSERT INTO scholarships (student_id, semester_id, scholarship_type, amount, start_date, end_date, order_no)
SELECT s.id, sm.id, 'social', 1500, sm.start_date, sm.end_date, 'Order No. 120-S'
FROM students s, semesters sm
WHERE s.record_book_no = 'RB2024-0020' AND sm.is_current;

INSERT INTO tuition_payments (student_id, semester_id, amount, paid_at, method, receipt_no)
SELECT q.student_id, q.semester_id, q.amount, q.paid_at, q.method, q.receipt
FROM (
    SELECT s.id AS student_id, sm.id AS semester_id,
           CASE
               WHEN NOT sm.is_current OR (s.id / 3) % 3 = 0 THEN sp.tuition_fee / 2
               ELSE sp.tuition_fee / 4
           END AS amount,
           (sm.start_date - 14 + (s.id % 10)::int)::timestamptz + interval '10 hours' AS paid_at,
           (ARRAY['card', 'bank_transfer', 'cash'])[s.id % 3 + 1]::payment_method AS method,
           'RC-' || sm.id || '-' || lpad(s.id::text, 5, '0') AS receipt
    FROM students s
    JOIN student_groups g ON g.id  = s.group_id
    JOIN specialties sp   ON sp.id = g.specialty_id
    JOIN semesters sm     ON sm.start_date >= s.enrollment_date
    WHERE s.funding = 'contract'
      AND (NOT sm.is_current OR (s.id / 3) % 3 <> 2)
) q
ORDER BY q.paid_at;

INSERT INTO attendance (schedule_entry_id, student_id, lesson_date, status)
SELECT q.entry_id, q.student_id, q.lesson_date,
       CASE
           WHEN q.r < 0.80 THEN 'present'
           WHEN q.r < 0.87 THEN 'late'
           WHEN q.r < 0.93 THEN 'excused'
           ELSE 'absent'
       END::attendance_status
FROM (
    SELECT se.id AS entry_id, s.id AS student_id, d::date AS lesson_date,
           random() * (0.75 + ((s.id * 7919) % 49) / 100.0 * 0.5) AS r
    FROM schedule_entries se
    JOIN teaching_assignments ta ON ta.id = se.teaching_assignment_id
    JOIN semesters sm            ON sm.id = ta.semester_id AND sm.is_current
    JOIN students s              ON s.group_id = ta.group_id AND s.deleted_at IS NULL AND s.status = 'active'
    CROSS JOIN LATERAL generate_series(sm.start_date, DATE '2026-10-05', interval '1 day') AS d
    WHERE EXTRACT(ISODOW FROM d) = se.day_of_week
) q
ORDER BY q.lesson_date, q.entry_id, q.student_id;

DO $$
DECLARE
    v_student  bigint;
    v_group    bigint;
    v_grade    bigint;
    v_id       bigint;
BEGIN
    SELECT id INTO v_student FROM students WHERE record_book_no = 'RB2024-0025';
    SELECT id INTO v_group   FROM student_groups WHERE code = 'SE-24';
    CALL sp_student_transfer(v_student, v_group, 'Transfer at own request (order No. 77-K)', v_id);

    SELECT id INTO v_student FROM students WHERE record_book_no = 'RB2024-0050';
    CALL sp_student_set_status(v_student, 'academic_leave');

    UPDATE students SET phone = '+380671112233', email = 'viktoriia.new@stud.univ.edu.ua'
    WHERE record_book_no = 'RB2024-0011';

    SELECT min(g.id) INTO v_grade
    FROM grades g JOIN enrollments e ON e.id = g.enrollment_id
    WHERE e.semester_id = fn_current_semester_id();
    CALL sp_grade_soft_delete(v_grade);

    PERFORM fn_set_current_user((SELECT id FROM users WHERE email = 'registrar@univ.edu.ua'));
    SELECT id INTO v_student FROM students WHERE record_book_no = 'RB2025-0036';
    CALL sp_student_set_status(v_student, 'expelled');
END;
$$;

-- Requirement 3: a regular DELETE becomes a soft delete
DELETE FROM students WHERE record_book_no = 'RB2025-0060';

DELETE FROM classrooms WHERE room_number = '121'
  AND building_id = (SELECT id FROM buildings WHERE code = 'C');

CALL sp_refresh_statistics();

COMMIT;

VACUUM ANALYZE;
