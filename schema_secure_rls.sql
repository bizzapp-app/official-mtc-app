-- =========================================================
-- MERCYLIFE — SECURE RLS (run AFTER schema.sql on a fresh project)
-- Replaces open USING (true) policies and tightens grants.
-- =========================================================

-- Profile columns used by the ERP UI
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS title TEXT,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_unique ON public.profiles (lower(username)) WHERE username IS NOT NULL;

ALTER TABLE public.audit_logs
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Drop dangerous open policies
DROP POLICY IF EXISTS "Allow public read and write on profiles" ON public.profiles;
DROP POLICY IF EXISTS "Allow public read and write on students" ON public.students;
DROP POLICY IF EXISTS "Allow public read and write on fee_invoices" ON public.fee_invoices;
DROP POLICY IF EXISTS "Allow public read and write on fee_payments" ON public.fee_payments;
DROP POLICY IF EXISTS "Allow public read and write on exam_results" ON public.exam_results;
DROP POLICY IF EXISTS "Allow public read and write on courses" ON public.courses;
DROP POLICY IF EXISTS "Allow public read and write on announcements" ON public.announcements;

-- Enable RLS on remaining tables
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.academic_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intakes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinical_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.library_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.library_borrows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assignment_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.downloads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alumni ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Role helpers
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role::text FROM public.profiles WHERE id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION public.is_admin_or_principal()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role::text IN ('administrator', 'principal')
      AND COALESCE(status, 'active') = 'active'
  )
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role::text IN (
        'administrator', 'principal', 'registrar', 'finance_officer',
        'lecturer', 'librarian', 'reception'
      )
      AND COALESCE(status, 'active') = 'active'
  )
$$;

-- Revoke broad anon rights; authenticated gets limited table rights under RLS
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- profiles
DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select ON public.profiles FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_admin_or_principal());

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid() OR public.is_admin_or_principal())
  WITH CHECK (
    public.is_admin_or_principal()
    OR (id = auth.uid() AND role = (SELECT role FROM public.profiles WHERE id = auth.uid()))
  );

-- students
DROP POLICY IF EXISTS students_select ON public.students;
CREATE POLICY students_select ON public.students FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR user_id = auth.uid()
  );

DROP POLICY IF EXISTS students_write ON public.students;
CREATE POLICY students_write ON public.students FOR ALL TO authenticated
  USING (
    public.is_admin_or_principal()
    OR public.current_user_role() IN ('registrar', 'reception')
  )
  WITH CHECK (
    public.is_admin_or_principal()
    OR public.current_user_role() IN ('registrar', 'reception')
  );

-- courses (staff read; admin/registrar write)
DROP POLICY IF EXISTS courses_select ON public.courses;
CREATE POLICY courses_select ON public.courses FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS courses_write ON public.courses;
CREATE POLICY courses_write ON public.courses FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() = 'registrar')
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'registrar');

-- finance
DROP POLICY IF EXISTS fee_invoices_select ON public.fee_invoices;
CREATE POLICY fee_invoices_select ON public.fee_invoices FOR SELECT TO authenticated
  USING (
    public.is_admin_or_principal()
    OR public.current_user_role() = 'finance_officer'
    OR public.current_user_role() = 'registrar'
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS fee_invoices_write ON public.fee_invoices;
CREATE POLICY fee_invoices_write ON public.fee_invoices FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() = 'finance_officer')
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'finance_officer');

DROP POLICY IF EXISTS fee_payments_select ON public.fee_payments;
CREATE POLICY fee_payments_select ON public.fee_payments FOR SELECT TO authenticated
  USING (
    public.is_admin_or_principal()
    OR public.current_user_role() = 'finance_officer'
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS fee_payments_write ON public.fee_payments;
CREATE POLICY fee_payments_write ON public.fee_payments FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() = 'finance_officer')
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'finance_officer');

-- exam results
DROP POLICY IF EXISTS exam_results_select ON public.exam_results;
CREATE POLICY exam_results_select ON public.exam_results FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS exam_results_write ON public.exam_results;
CREATE POLICY exam_results_write ON public.exam_results FOR ALL TO authenticated
  USING (
    public.is_admin_or_principal()
    OR public.current_user_role() IN ('lecturer', 'registrar')
  )
  WITH CHECK (
    public.is_admin_or_principal()
    OR public.current_user_role() IN ('lecturer', 'registrar')
  );

-- announcements
DROP POLICY IF EXISTS announcements_select ON public.announcements;
CREATE POLICY announcements_select ON public.announcements FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS announcements_write ON public.announcements;
CREATE POLICY announcements_write ON public.announcements FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'reception'))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'reception'));

-- audit: insert for authenticated; select admin only; no client updates
DROP POLICY IF EXISTS audit_insert ON public.audit_logs;
CREATE POLICY audit_insert ON public.audit_logs FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS audit_select ON public.audit_logs;
CREATE POLICY audit_select ON public.audit_logs FOR SELECT TO authenticated
  USING (public.is_admin_or_principal());

-- Generic staff read for remaining academic tables
DROP POLICY IF EXISTS attendance_staff ON public.attendance;
CREATE POLICY attendance_staff ON public.attendance FOR ALL TO authenticated
  USING (public.is_staff())
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('lecturer', 'registrar'));

DROP POLICY IF EXISTS clinical_staff ON public.clinical_attachments;
CREATE POLICY clinical_staff ON public.clinical_attachments FOR ALL TO authenticated
  USING (public.is_staff() OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid()))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('lecturer', 'registrar'));

DROP POLICY IF EXISTS library_staff ON public.library_books;
CREATE POLICY library_staff ON public.library_books FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'librarian');

DROP POLICY IF EXISTS library_borrows_pol ON public.library_borrows;
CREATE POLICY library_borrows_pol ON public.library_borrows FOR ALL TO authenticated
  USING (public.is_staff() OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid()))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'librarian');

COMMENT ON FUNCTION public.is_admin_or_principal IS 'ERP helper: active administrator or principal';

-- =========================================================
-- COMPLETE policies for tables that had RLS enabled with none
-- =========================================================

-- staff
DROP POLICY IF EXISTS staff_select ON public.staff;
CREATE POLICY staff_select ON public.staff FOR SELECT TO authenticated
  USING (public.is_staff() OR user_id = auth.uid());
DROP POLICY IF EXISTS staff_write ON public.staff;
CREATE POLICY staff_write ON public.staff FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() = 'registrar')
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'registrar');

-- academic_years / intakes / units
DROP POLICY IF EXISTS academic_years_all ON public.academic_years;
CREATE POLICY academic_years_all ON public.academic_years FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'registrar');

DROP POLICY IF EXISTS intakes_all ON public.intakes;
CREATE POLICY intakes_all ON public.intakes FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'registrar');

DROP POLICY IF EXISTS units_select ON public.units;
CREATE POLICY units_select ON public.units FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS units_write ON public.units;
CREATE POLICY units_write ON public.units FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'lecturer'))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'lecturer'));

-- student_documents
DROP POLICY IF EXISTS student_documents_select ON public.student_documents;
CREATE POLICY student_documents_select ON public.student_documents FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  );
DROP POLICY IF EXISTS student_documents_write ON public.student_documents;
CREATE POLICY student_documents_write ON public.student_documents FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'reception'))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'reception'));

-- classes
DROP POLICY IF EXISTS classes_select ON public.classes;
CREATE POLICY classes_select ON public.classes FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS classes_write ON public.classes;
CREATE POLICY classes_write ON public.classes FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'lecturer'))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'lecturer'));

-- exams
DROP POLICY IF EXISTS exams_select ON public.exams;
CREATE POLICY exams_select ON public.exams FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS exams_write ON public.exams;
CREATE POLICY exams_write ON public.exams FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'lecturer'))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar', 'lecturer'));

-- messages
DROP POLICY IF EXISTS messages_select ON public.messages;
CREATE POLICY messages_select ON public.messages FOR SELECT TO authenticated
  USING (sender_id = auth.uid() OR receiver_id = auth.uid() OR public.is_admin_or_principal());
DROP POLICY IF EXISTS messages_insert ON public.messages;
CREATE POLICY messages_insert ON public.messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());
DROP POLICY IF EXISTS messages_update ON public.messages;
CREATE POLICY messages_update ON public.messages FOR UPDATE TO authenticated
  USING (receiver_id = auth.uid() OR sender_id = auth.uid() OR public.is_admin_or_principal());

-- assignments
DROP POLICY IF EXISTS assignments_select ON public.assignments;
CREATE POLICY assignments_select ON public.assignments FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS assignments_write ON public.assignments;
CREATE POLICY assignments_write ON public.assignments FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() IN ('lecturer', 'registrar'))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('lecturer', 'registrar'));

DROP POLICY IF EXISTS assignment_submissions_select ON public.assignment_submissions;
CREATE POLICY assignment_submissions_select ON public.assignment_submissions FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  );
DROP POLICY IF EXISTS assignment_submissions_write ON public.assignment_submissions;
CREATE POLICY assignment_submissions_write ON public.assignment_submissions FOR ALL TO authenticated
  USING (
    public.is_admin_or_principal()
    OR public.current_user_role() IN ('lecturer', 'registrar')
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  )
  WITH CHECK (
    public.is_admin_or_principal()
    OR public.current_user_role() IN ('lecturer', 'registrar')
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  );

-- downloads (read all authenticated; write admin/registrar)
DROP POLICY IF EXISTS downloads_select ON public.downloads;
CREATE POLICY downloads_select ON public.downloads FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS downloads_write ON public.downloads;
CREATE POLICY downloads_write ON public.downloads FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() = 'registrar')
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'registrar');

-- alumni
DROP POLICY IF EXISTS alumni_select ON public.alumni;
CREATE POLICY alumni_select ON public.alumni FOR SELECT TO authenticated
  USING (public.is_staff() OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS alumni_write ON public.alumni;
CREATE POLICY alumni_write ON public.alumni FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() = 'registrar')
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'registrar');

-- =========================================================
-- ATOMIC fee payment + invoice balance update
-- =========================================================
CREATE OR REPLACE FUNCTION public.record_fee_payment(
  p_student_id UUID,
  p_amount_paid NUMERIC,
  p_payment_method TEXT,
  p_reference_code TEXT,
  p_invoice_id UUID DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_received_by TEXT DEFAULT 'Finance Office',
  p_payment_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_receipt TEXT;
  v_payment_id UUID;
  v_inv public.fee_invoices%ROWTYPE;
  v_paid NUMERIC;
  v_balance NUMERIC;
  v_status TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT role::text INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('administrator', 'principal', 'finance_officer') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF p_amount_paid IS NULL OR p_amount_paid <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT';
  END IF;

  IF p_reference_code IS NULL OR length(trim(p_reference_code)) = 0 THEN
    RAISE EXCEPTION 'REFERENCE_REQUIRED';
  END IF;

  IF EXISTS (SELECT 1 FROM public.fee_payments WHERE reference_code = trim(p_reference_code)) THEN
    RAISE EXCEPTION 'DUPLICATE_REFERENCE';
  END IF;

  v_receipt := 'RCP-' || to_char(now(), 'YYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  INSERT INTO public.fee_payments (
    receipt_no, invoice_id, student_id, amount_paid, payment_method,
    reference_code, payment_date, received_by, notes
  ) VALUES (
    v_receipt, p_invoice_id, p_student_id, p_amount_paid,
    COALESCE(p_payment_method, 'mpesa')::payment_method,
    trim(p_reference_code), COALESCE(p_payment_date, CURRENT_DATE),
    COALESCE(p_received_by, 'Finance Office'), p_notes
  )
  RETURNING id INTO v_payment_id;

  IF p_invoice_id IS NOT NULL THEN
    SELECT * INTO v_inv FROM public.fee_invoices WHERE id = p_invoice_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'INVOICE_NOT_FOUND';
    END IF;
    IF v_inv.student_id IS DISTINCT FROM p_student_id THEN
      RAISE EXCEPTION 'INVOICE_STUDENT_MISMATCH';
    END IF;

    v_paid := COALESCE(v_inv.paid_amount, 0) + p_amount_paid;
    v_balance := GREATEST(0, COALESCE(v_inv.amount, 0) - v_paid);
    IF v_balance <= 0 THEN
      v_status := 'paid';
    ELSIF v_paid > 0 THEN
      v_status := 'partially_paid';
    ELSE
      v_status := 'unpaid';
    END IF;

    UPDATE public.fee_invoices
    SET paid_amount = v_paid,
        balance = v_balance,
        status = v_status::invoice_status
    WHERE id = p_invoice_id;
  END IF;

  INSERT INTO public.audit_logs (user_email, action, details)
  VALUES (
    COALESCE((SELECT email FROM auth.users WHERE id = auth.uid()), 'finance'),
    'RECORD_PAYMENT',
    format('Receipt %s ref %s amount %s', v_receipt, trim(p_reference_code), p_amount_paid)
  );

  RETURN jsonb_build_object(
    'id', v_payment_id,
    'receipt_no', v_receipt,
    'amount_paid', p_amount_paid,
    'reference_code', trim(p_reference_code),
    'invoice_id', p_invoice_id,
    'student_id', p_student_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_fee_payment FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_fee_payment TO authenticated;

COMMENT ON FUNCTION public.record_fee_payment IS 'Atomic payment insert + invoice balance update; finance/admin only';

-- =========================================================
-- ADMISSIONS / ENROLLMENT / GRADUATION SECURITY
-- =========================================================
ALTER TABLE public.admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.graduation_records ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.admissions, public.student_enrollments, public.graduation_records TO authenticated;

DROP POLICY IF EXISTS admissions_select ON public.admissions;
CREATE POLICY admissions_select ON public.admissions FOR SELECT TO authenticated
  USING (public.is_staff());
DROP POLICY IF EXISTS admissions_write ON public.admissions;
CREATE POLICY admissions_write ON public.admissions FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar','reception'))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar','reception'));

DROP POLICY IF EXISTS enrollments_select ON public.student_enrollments;
CREATE POLICY enrollments_select ON public.student_enrollments FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  );
DROP POLICY IF EXISTS enrollments_write ON public.student_enrollments;
CREATE POLICY enrollments_write ON public.student_enrollments FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar','lecturer'))
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() IN ('registrar','lecturer'));

DROP POLICY IF EXISTS graduation_select ON public.graduation_records;
CREATE POLICY graduation_select ON public.graduation_records FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid())
  );
DROP POLICY IF EXISTS graduation_write ON public.graduation_records;
CREATE POLICY graduation_write ON public.graduation_records FOR ALL TO authenticated
  USING (public.is_admin_or_principal() OR public.current_user_role() = 'registrar')
  WITH CHECK (public.is_admin_or_principal() OR public.current_user_role() = 'registrar');

-- Atomic conversion of an approved applicant into a student + first enrollment.
CREATE OR REPLACE FUNCTION public.convert_admission_to_student(p_admission_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  a public.admissions%ROWTYPE;
  v_student_id UUID;
  v_admission_no TEXT;
  v_course_fee NUMERIC;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  SELECT role::text INTO v_role FROM public.profiles WHERE id = auth.uid() AND COALESCE(status,'active')='active';
  IF v_role IS NULL OR v_role NOT IN ('administrator','principal','registrar','reception') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;

  SELECT * INTO a FROM public.admissions WHERE id = p_admission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'APPLICATION_NOT_FOUND'; END IF;
  IF a.status NOT IN ('submitted','under_review','accepted') THEN RAISE EXCEPTION 'APPLICATION_NOT_ELIGIBLE'; END IF;
  IF a.converted_student_id IS NOT NULL THEN RAISE EXCEPTION 'ALREADY_CONVERTED'; END IF;
  IF a.course_id IS NULL THEN RAISE EXCEPTION 'COURSE_REQUIRED'; END IF;

  v_admission_no := 'MTC/' || to_char(CURRENT_DATE,'YYYY') || '/' || lpad((SELECT COALESCE(count(*),0)+1 FROM public.students WHERE EXTRACT(YEAR FROM created_at)=EXTRACT(YEAR FROM CURRENT_DATE))::text,4,'0');
  WHILE EXISTS (SELECT 1 FROM public.students WHERE admission_no=v_admission_no) LOOP
    v_admission_no := 'MTC/' || to_char(CURRENT_DATE,'YYYY') || '/' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  END LOOP;

  INSERT INTO public.students (
    admission_no, full_name, gender, dob, national_id, phone, email,
    guardian_name, guardian_phone, address, county, kcse_grade, course_id,
    intake_id, status, current_semester
  ) VALUES (
    v_admission_no, a.full_name, a.gender, a.dob, NULLIF(a.national_id,''), a.phone, a.email,
    a.guardian_name, a.guardian_phone, a.address, a.county, a.kcse_grade, a.course_id,
    a.intake_id, 'active', 'Semester 1'
  ) RETURNING id INTO v_student_id;

  INSERT INTO public.student_enrollments (student_id, course_id, intake_id, semester, status, start_date)
  VALUES (v_student_id, a.course_id, a.intake_id, 'Semester 1', 'active', CURRENT_DATE);

  UPDATE public.admissions
  SET status='converted', converted_student_id=v_student_id, reviewed_by=auth.uid(), reviewed_at=NOW(), updated_at=NOW()
  WHERE id=p_admission_id;

  INSERT INTO public.audit_logs(user_email, action, details)
  VALUES (COALESCE((SELECT email FROM auth.users WHERE id=auth.uid()),'registrar'), 'CONVERT_ADMISSION', format('Application %s converted to %s', a.application_no, v_admission_no));

  RETURN jsonb_build_object('student_id',v_student_id,'admission_no',v_admission_no,'application_no',a.application_no);
END;
$$;
REVOKE ALL ON FUNCTION public.convert_admission_to_student(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.convert_admission_to_student(UUID) TO authenticated;

-- Finalize graduation only after all three institutional clearances are true.
CREATE OR REPLACE FUNCTION public.finalize_graduation(
  p_student_id UUID,
  p_graduation_date DATE,
  p_certificate_no TEXT,
  p_academic_clearance BOOLEAN,
  p_finance_clearance BOOLEAN,
  p_clinical_clearance BOOLEAN,
  p_final_average NUMERIC DEFAULT NULL,
  p_classification TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_role TEXT; v_course TEXT; v_name TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  SELECT role::text INTO v_role FROM public.profiles WHERE id=auth.uid() AND COALESCE(status,'active')='active';
  IF v_role IS NULL OR v_role NOT IN ('administrator','principal','registrar') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF NOT (p_academic_clearance AND p_finance_clearance AND p_clinical_clearance) THEN RAISE EXCEPTION 'ALL_CLEARANCES_REQUIRED'; END IF;
  IF p_certificate_no IS NULL OR length(trim(p_certificate_no)) < 4 THEN RAISE EXCEPTION 'CERTIFICATE_REQUIRED'; END IF;

  SELECT s.full_name INTO v_name FROM public.students s WHERE s.id=p_student_id FOR UPDATE;
  SELECT c.name INTO v_course FROM public.courses c WHERE c.id=(SELECT course_id FROM public.students WHERE id=p_student_id);
  IF v_name IS NULL THEN RAISE EXCEPTION 'STUDENT_NOT_FOUND'; END IF;

  INSERT INTO public.graduation_records (
    student_id, graduation_date, certificate_no, academic_clearance, finance_clearance,
    clinical_clearance, status, final_average, classification, notes, created_by, updated_at
  ) VALUES (
    p_student_id, p_graduation_date, trim(p_certificate_no), p_academic_clearance, p_finance_clearance,
    p_clinical_clearance, 'graduated', p_final_average, p_classification, p_notes, auth.uid(), NOW()
  )
  ON CONFLICT (student_id) DO UPDATE SET
    graduation_date=EXCLUDED.graduation_date, certificate_no=EXCLUDED.certificate_no,
    academic_clearance=EXCLUDED.academic_clearance, finance_clearance=EXCLUDED.finance_clearance,
    clinical_clearance=EXCLUDED.clinical_clearance, status='graduated', final_average=EXCLUDED.final_average,
    classification=EXCLUDED.classification, notes=EXCLUDED.notes, updated_at=NOW();

  INSERT INTO public.alumni (student_id, graduation_date, certificate_no, email, phone)
  SELECT p_student_id, p_graduation_date, trim(p_certificate_no), s.email, s.phone
  FROM public.students s WHERE s.id=p_student_id
  ON CONFLICT (student_id) DO UPDATE SET graduation_date=EXCLUDED.graduation_date, certificate_no=EXCLUDED.certificate_no, email=EXCLUDED.email, phone=EXCLUDED.phone;

  UPDATE public.students SET status='graduated', updated_at=NOW() WHERE id=p_student_id;

  INSERT INTO public.audit_logs(user_email, action, details)
  VALUES (COALESCE((SELECT email FROM auth.users WHERE id=auth.uid()),'registrar'), 'FINALIZE_GRADUATION', format('%s graduated from %s; certificate %s',v_name,COALESCE(v_course,'course'),trim(p_certificate_no)));

  RETURN jsonb_build_object('student_id',p_student_id,'certificate_no',trim(p_certificate_no),'status','graduated');
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_graduation(UUID,DATE,TEXT,BOOLEAN,BOOLEAN,BOOLEAN,NUMERIC,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finalize_graduation(UUID,DATE,TEXT,BOOLEAN,BOOLEAN,BOOLEAN,NUMERIC,TEXT,TEXT) TO authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS assignment_submission_unique ON public.assignment_submissions(assignment_id, student_id);
