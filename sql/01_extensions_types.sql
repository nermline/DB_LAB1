CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE user_role AS ENUM ('admin', 'dean_office', 'teacher', 'student');
COMMENT ON TYPE user_role IS 'Account role: administrator, dean office employee, teacher, student';

CREATE TYPE degree_level AS ENUM ('bachelor', 'master', 'phd');
COMMENT ON TYPE degree_level IS 'Degree level: bachelor, master, doctor of philosophy';

CREATE TYPE teacher_position AS ENUM ('assistant', 'senior_lecturer', 'associate_professor', 'professor');
COMMENT ON TYPE teacher_position IS 'Teacher position: assistant, senior lecturer, associate professor, professor';

CREATE TYPE student_status AS ENUM ('active', 'academic_leave', 'expelled', 'graduated');
COMMENT ON TYPE student_status IS 'Student status: studying, academic leave, expelled, graduated';

CREATE TYPE funding_type AS ENUM ('budget', 'contract');
COMMENT ON TYPE funding_type IS 'Tuition funding: state budget / contract';

CREATE TYPE control_form AS ENUM ('exam', 'credit', 'diff_credit');
COMMENT ON TYPE control_form IS 'Final assessment form: exam, pass/fail credit, graded credit';

CREATE TYPE lesson_type AS ENUM ('lecture', 'practice', 'lab', 'seminar');
COMMENT ON TYPE lesson_type IS 'Lesson type: lecture, practice, lab, seminar';

CREATE TYPE week_parity AS ENUM ('every', 'odd', 'even');
COMMENT ON TYPE week_parity IS 'Week in which the lesson takes place: every week, odd weeks, even weeks';

CREATE TYPE room_type AS ENUM ('lecture_hall', 'classroom', 'computer_lab', 'laboratory');
COMMENT ON TYPE room_type IS 'Classroom type';

CREATE TYPE enrollment_status AS ENUM ('enrolled', 'completed', 'failed', 'dropped');
COMMENT ON TYPE enrollment_status IS 'Course enrollment state: studying, passed, failed (academic debt), dropped';

CREATE TYPE assessment_type AS ENUM ('lab', 'practice', 'test', 'module', 'coursework', 'exam', 'bonus');
COMMENT ON TYPE assessment_type IS 'Assessment type';

CREATE TYPE attendance_status AS ENUM ('present', 'absent', 'excused', 'late');
COMMENT ON TYPE attendance_status IS 'Attendance mark';

CREATE TYPE scholarship_type AS ENUM ('academic', 'increased_academic', 'social', 'presidential');
COMMENT ON TYPE scholarship_type IS 'Scholarship type';

CREATE TYPE payment_method AS ENUM ('card', 'bank_transfer', 'cash');
COMMENT ON TYPE payment_method IS 'Tuition payment method';
