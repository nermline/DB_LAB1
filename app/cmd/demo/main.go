// Demo of working with the "University Management System" database through
// the Repository + Unit of Work patterns. All queries go through stored
// procedures (CALL sp_*), table functions (fn_*) and views (v_*).
//
//	go run ./cmd/demo -dsn "postgres://postgres:postgres@localhost:5432/university?sslmode=disable"
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"university/internal/domain"
	"university/internal/service"
	"university/internal/uow"
)

func main() {
	dsn := flag.String("dsn", envOr("DATABASE_URL",
		"postgres://postgres:postgres@localhost:5432/university?sslmode=disable"), "PostgreSQL connection string")
	actor := flag.Int64("actor", 2, "id of the user on whose behalf changes are made (2 = dean office employee)")
	flag.Parse()

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, *dsn)
	if err != nil {
		log.Fatalf("connect: %v", err)
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("database is not available: %v", err)
	}

	factory := uow.NewPostgresFactory(pool)
	svc := service.NewAcademicService(factory)
	suffix := time.Now().Unix() % 1_000_000

	// -----------------------------------------------------------------
	step(1, "Admit a student and enroll them in courses (one unit of work)")
	adm, err := svc.AdmitStudent(ctx, *actor, "SE-24", domain.NewStudent{
		RecordBookNo: fmt.Sprintf("DEMO-%06d", suffix),
		LastName:     "Ivanenko",
		FirstName:    "Mariia",
		MiddleName:   "Olehivna",
		BirthDate:    time.Date(2006, 5, 14, 0, 0, 0, 0, time.UTC),
		Email:        fmt.Sprintf("demo%06d@stud.univ.edu.ua", suffix),
		Phone:        "+380501234567",
		Funding:      domain.FundingBudget,
	})
	must(err)
	st := adm.Student
	fmt.Printf("Student #%d %s, record book %s\n", st.ID, st.FullName, st.RecordBookNo)
	fmt.Printf("Group %s (year %d), %s, %s\n", st.GroupCode, st.StudyYear, st.Specialty, st.Faculty)
	fmt.Printf("Created / changed by: %s at %s\n", deref(st.UpdatedByName), st.UpdatedAt.Format("15:04:05"))
	fmt.Printf("Course enrollments for semester %s (sp_enroll_student_by_curriculum):\n", adm.Semester.Name)
	printEnrollments(adm.Enrollments)
	if len(adm.Enrollments) < 2 {
		log.Fatal("the demo needs at least two courses in the curriculum")
	}
	first, second := adm.Enrollments[0], adm.Enrollments[1]

	// -----------------------------------------------------------------
	step(2, "Batch of grades for \""+first.CourseName+"\" (atomic)")
	updated, err := svc.RecordGrades(ctx, *actor, []domain.NewGrade{
		{EnrollmentID: first.ID, Type: domain.AssessmentLab, Title: "Lab 1", Score: 9, MaxScore: 10},
		{EnrollmentID: first.ID, Type: domain.AssessmentLab, Title: "Lab 2", Score: 10, MaxScore: 10},
		{EnrollmentID: first.ID, Type: domain.AssessmentLab, Title: "Lab 3", Score: 9, MaxScore: 10},
		{EnrollmentID: first.ID, Type: domain.AssessmentLab, Title: "Lab 4", Score: 10, MaxScore: 10},
		{EnrollmentID: first.ID, Type: domain.AssessmentModule, Title: "Module test", Score: 18, MaxScore: 20},
		{EnrollmentID: first.ID, Type: domain.AssessmentExam, Title: "Exam", Score: 35, MaxScore: 40},
	})
	must(err)
	fmt.Printf("Current total score (fn_enrollment_score): %.0f\n", updated[0].Score)

	// -----------------------------------------------------------------
	step(3, "Error inside the Unit of Work -> Rollback of the whole batch")
	_, err = svc.RecordGrades(ctx, *actor, []domain.NewGrade{
		{EnrollmentID: second.ID, Type: domain.AssessmentLab, Title: "Lab 1", Score: 8, MaxScore: 10},
		{EnrollmentID: second.ID, Type: domain.AssessmentModule, Title: "Module test", Score: 18, MaxScore: 20},
		{EnrollmentID: second.ID, Type: domain.AssessmentExam, Title: "Exam", Score: 40, MaxScore: 40},
		{EnrollmentID: second.ID, Type: domain.AssessmentBonus, Title: "Olympiad", Score: 35, MaxScore: 50},
	})
	fmt.Printf("Expected error (trigger trg_20_validate): %v\n", err)
	fmt.Printf("  errors.Is(err, domain.ErrBusinessRule) = %v\n", errors.Is(err, domain.ErrBusinessRule))
	card, err := svc.GetStudentCard(ctx, st.ID)
	must(err)
	fmt.Printf("Grades for \"%s\" in the database: %d, the first three grades of the batch were rolled back too\n",
		second.CourseName, len(card.Grades[second.ID]))

	// -----------------------------------------------------------------
	step(4, "Grade correction (sp_grade_update), updated_at / updated_by are recorded")
	firstGrades := card.Grades[first.ID]
	g, err := svc.CorrectGrade(ctx, *actor, firstGrades[0].ID, 10, "Lab resubmitted")
	must(err)
	fmt.Printf("%s: %.0f/%.0f (%s), changed by %s at %s\n", g.Title, g.Score, g.MaxScore, deref(g.Comment),
		deref(g.UpdatedByName), g.UpdatedAt.Format("15:04:05"))

	// -----------------------------------------------------------------
	step(5, "Final grade (sp_enrollment_finalize: fn_ects_grade + fn_national_grade)")
	fin, err := svc.FinalizeEnrollment(ctx, *actor, first.ID)
	must(err)
	fmt.Printf("%s: %.0f points -> ECTS %s, \"%s\", status %s\n",
		fin.CourseName, fin.Score, deref(fin.ECTSGrade), deref(fin.NationalGrade), fin.Status)
	_, err = svc.RecordGrades(ctx, *actor, []domain.NewGrade{
		{EnrollmentID: first.ID, Type: domain.AssessmentBonus, Title: "Bonus", Score: 1, MaxScore: 5},
	})
	fmt.Printf("Attempt to change grades of a finalized course: %v\n", err)

	// -----------------------------------------------------------------
	step(6, "Transfer to group CS-24 + enrollment in the courses of the new curriculum")
	tr, err := svc.TransferStudent(ctx, *actor, st.ID, "CS-24", "Transfer at own request")
	must(err)
	fmt.Printf("Transfer #%d: now in group %s (%s); new course enrollments: %d\n",
		tr.TransferID, tr.Student.GroupCode, tr.Student.Specialty, tr.NewEnrollments)

	// -----------------------------------------------------------------
	step(7, "Student card (read-only transaction, several views)")
	card, err = svc.GetStudentCard(ctx, st.ID)
	must(err)
	printEnrollments(card.Enrollments)
	for _, r := range card.Results {
		fmt.Printf("Semester %s: courses %d, passed %d, debts %d, credits %.0f/%.0f, rating %s\n",
			r.Semester, r.CoursesTotal, r.CoursesPassed, r.Debts, r.CreditsEarned, r.CreditsTotal, num(r.Rating))
	}

	// -----------------------------------------------------------------
	step(8, "Ranking of group SE-24 for the previous semester (fn_group_rating, RANK window function)")
	var lastClosed *domain.Semester
	must(factory.Read(ctx, func(u uow.UnitOfWork) error {
		semesters, err := u.Catalog().Semesters(ctx)
		for i := range semesters {
			if semesters[i].IsClosed {
				lastClosed = &semesters[i]
			}
		}
		return err
	}))
	if lastClosed != nil {
		rating, err := svc.GroupRating(ctx, "SE-24", lastClosed.ID)
		must(err)
		w := table("Place", "Student", "Funding", "Rating", "Credits", "Debts")
		for i, r := range rating {
			if i == 5 {
				break
			}
			fmt.Fprintf(w, "%d\t%s\t%s\t%s\t%.0f\t%d\n", r.Place, r.FullName, r.Funding, num(r.Rating), r.Credits, r.Debts)
		}
		w.Flush()
	}

	// -----------------------------------------------------------------
	step(9, "Fuzzy search by full name (fn_search_students, GIN pg_trgm index)")
	must(factory.Read(ctx, func(u uow.UnitOfWork) error {
		found, err := u.Students().Search(ctx, "Ivanenko Mariia", 3)
		for _, f := range found {
			fmt.Printf("  %-34s %-6s %s (similarity %.2f)\n", f.FullName, f.GroupCode, f.RecordBookNo, f.Similarity)
		}
		return err
	}))

	// -----------------------------------------------------------------
	step(10, "Soft delete and restore")
	must(svc.RemoveStudent(ctx, *actor, st.ID))
	err = factory.Read(ctx, func(u uow.UnitOfWork) error {
		_, err := u.Students().GetByID(ctx, st.ID)
		return err
	})
	fmt.Printf("After sp_student_soft_delete v_students does not return the student: %v (ErrNotFound = %v)\n",
		err, errors.Is(err, domain.ErrNotFound))
	must(factory.Read(ctx, func(u uow.UnitOfWork) error {
		deleted, err := u.Students().ListDeleted(ctx)
		for _, d := range deleted {
			if d.ID == st.ID {
				fmt.Printf("Soft-deleted (v_students_deleted): %s, deleted by %s at %s\n",
					d.FullName, deref(d.DeletedByName), d.DeletedAt.Format("15:04:05"))
			}
		}
		return err
	}))
	restored, err := svc.RestoreStudent(ctx, *actor, st.ID)
	must(err)
	fmt.Printf("Restored (sp_student_restore): %s, group %s\n", restored.FullName, restored.GroupCode)

	// -----------------------------------------------------------------
	step(11, "Student change log (v_change_history, written by the trg_90_audit_log trigger)")
	history, err := svc.StudentHistory(ctx, st.ID)
	must(err)
	w := table("Time", "Operation", "Changed fields", "By")
	for _, h := range history {
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", h.ChangedAt.Format("15:04:05.000"), h.Operation,
			strings.Join(h.ChangedFields, ", "), h.ChangedByName)
	}
	w.Flush()

	// -----------------------------------------------------------------
	step(12, "Cleanup: the demo student is soft-deleted so that repeated runs do not fill up the group")
	must(svc.RemoveStudent(ctx, *actor, st.ID))
	fmt.Println("Done.")
}

func printEnrollments(list []domain.Enrollment) {
	w := table("ID", "Course", "Credits", "Control", "Semester", "Status", "Score", "ECTS")
	for _, e := range list {
		fmt.Fprintf(w, "%d\t%s\t%.1f\t%s\t%s\t%s\t%.0f\t%s\n",
			e.ID, e.CourseName, e.Credits, e.Control, e.Semester, e.Status, e.Score, deref(e.ECTSGrade))
	}
	w.Flush()
}

func table(headers ...string) *tabwriter.Writer {
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, strings.Join(headers, "\t"))
	return w
}

func step(n int, title string) {
	fmt.Printf("\n=== %d. %s ===\n", n, title)
}

func must(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

func deref(s *string) string {
	if s == nil {
		return "-"
	}
	return *s
}

func num(f *float64) string {
	if f == nil {
		return "-"
	}
	return fmt.Sprintf("%.2f", *f)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
