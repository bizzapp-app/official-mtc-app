# MercyLife ERP - Production Setup

## 1. Supabase database
Run these scripts in order in the Supabase SQL Editor:
1. `schema.sql`
2. `schema_secure_rls.sql`

The schema now includes the complete lifecycle tables:
- admissions
- students
- student_enrollments
- courses / units / academic years / intakes
- attendance
- examinations / results
- finance / invoices / payments
- clinical attachments
- assignments / submissions
- library
- messaging / announcements
- certificates / documents
- graduation_records / alumni
- audit_logs

## 2. Authentication model
- Create the initial administrator directly in Supabase Auth.
- Create the matching `profiles` row with `role='administrator'`, `username`, `status='active'`.
- After that, administrators create all other accounts from System Settings.
- Staff and students log in using their assigned username and password.
- Do not expose or store the Supabase service-role key in the browser.

## 3. Edge Functions
Deploy:
- `admin-create-user`
- `admin-update-user`

The browser must never receive the service-role key.

## 4. Environment variables
Set these in the deployment platform:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_ALLOW_MOCK_READ=false`

## 5. Storage
Create the required private Storage buckets and Storage RLS policies before enabling document uploads. Do not use public buckets for student records unless the college explicitly accepts that exposure.

## 6. School workflow
The intended production lifecycle is:

**Application → Admissions Review → Acceptance → Student Admission Number → Enrollment → Fees → Attendance → Assignments → Clinical → Exams → Results → Clearance → Certificate → Graduation → Alumni**

Admissions conversion and graduation finalization use database transactions so the system does not create half-completed lifecycle records.

## 7. Deployment verification
Run locally before deployment:

```bash
npm install
npm run lint
npm run build
```

Then smoke-test with a real Supabase project:

1. Administrator login
2. Administrator creates a registrar account
3. Fresh browser logs in as registrar
4. Registrar creates an applicant
5. Applicant is accepted and converted to a student
6. Student appears in Student Records
7. Enrollment is created
8. Invoice is created
9. Payment is recorded and receipt generated
10. Attendance is saved
11. Exam and result are recorded/published
12. Clinical attachment is completed/evaluated
13. Graduation page shows clearance state
14. Eligible student is graduated
15. Certificate/alumni record exists
16. Student account only sees permitted modules
17. Non-admin cannot create administrator accounts
18. Suspended user cannot sign in
19. Light/dark theme persists
20. College Website button opens the public college site

## 8. Important honesty check
This repository can be statically audited here, but a real production PASS requires the final `npm run build` and a live Supabase smoke test against the school's project. Do not treat a source-code audit as proof that a live deployment is healthy.
