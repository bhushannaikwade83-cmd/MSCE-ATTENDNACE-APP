# Supabase CSV import — institutes, batches, students

## Backend database (this app only)

The mobile app uses **Supabase** as its backend. All relational data (institutes, batches, students, attendance rows, profiles, etc.) lives in a **PostgreSQL** database hosted on your Supabase project. The Flutter app talks to it through the **Supabase API** (`supabase_flutter`). Table definitions and changes for this app are in the repo folder `supabase/migrations/`.

*(This section describes only what this codebase uses as its primary database — not other optional services.)*

---

Use this when preparing **CSV files** to load data into Supabase so it shows correctly in the MSCE / EduSetu attendance app.

**Excel (.xlsx) templates** in `excel_templates/`: each Sheet1 header row lists **every column** on that table as defined in `supabase/migrations` (not a short list). Files: `institutes_import_template.xlsx`, `batches_import_template.xlsx`, `students_import_template.xlsx` (each has a README sheet). Regenerate: `python tools/generate_excel_import_templates.py` (requires `openpyxl`).

**Import order:** `institutes` → `batches` → `students` (students need a real `batch_id` from `batches`).

---

## 1. `institutes` (one row per institute)

| Column | Required? | Notes |
|--------|-----------|--------|
| `id` | **Yes** | Stable institute key; the app uses this everywhere. Can match `institute_code`. |
| `institute_code` | **Yes** (or keep in sync with `id`) | DB trigger syncs `id` and `institute_code`; both must be non-empty. |
| `name` | **Yes** | Display name. |
| `location`, `address`, `city`, `district`, `taluka`, `state` | No | Address / location. |
| `country` | No | DB default is `India`. |
| `pincode` | No | India PIN (6 digits) if used. |
| `mobile_no` | No | Contact. |
| `is_active` | No | Default `true`. |
| `user_count`, `student_count` | No | Can start at `0` and reconcile after imports. |

**Optional (JSONB — awkward in CSV):** `batch_open_time`, `batch_close_time`, `batch_duration_minutes` — often set later in the app or via SQL.

---

## 2. `batches` (per institute)

| Column | Required? | Notes |
|--------|-----------|--------|
| `institute_id` | **Yes** | Must equal `institutes.id`. |
| `name` | **Yes** | Batch name (app avoids duplicate name + year). |
| `year` | **Yes** | e.g. `2025` or `First Year` — same convention you use in the app. |
| `timing` | **Yes** | Human-readable slot, e.g. `08:00 - 09:00`. |
| `subjects` | **Yes for normal app flow** | Postgres `text[]`. In CSV: `{Subject A,Subject B}` or `{}` if you add subjects later. |
| `id` | No | Omit → Supabase generates a **UUID**. **Copy this** into `students.batch_id`. |
| `semester` | No | e.g. `1` / `2` if used. |
| `start_time`, `end_time` | No | JSONB like `{"hour":8,"minute":0}` — optional; set in app/SQL if needed. |
| `batch_duration_minutes` | No | Default `60`. |
| `created_by` | No | e.g. `csv_import`. |
| `student_count` | No | Start at `0`; update after students are linked. |
| `is_auto_generated` | No | Default `false`. |

---

## 3. `students` (per institute)

| Column | Required? | Notes |
|--------|-----------|--------|
| `institute_id` | **Yes** | Same as the institute row. |
| `user_id` | **Strongly yes** | Roll / PRN — used in the app and for duplicate checks. |
| `name` | **Yes** | Full name (or use `first_name`, `middle_name`, `last_name`). |
| `phone_number` | Recommended | Contact. |
| `year` | Recommended | Academic year string. |
| `batch_id` | **Yes** (primary batch) | **UUID** from `batches.id` for that institute. |
| `id` | No | Omit → DB default; or set a stable text id. |
| `sr_no` | No | Serial number if used in reports. |
| `batch_ids` | No | Multiple batches: `text[]`, e.g. `{uuid1,uuid2}`. |
| `batch_name`, `batch_timing` | No | Helpful for display in lists. |
| `subjects` | No | **Use this** for subject list: Postgres `text[]`, e.g. `{Subj1,Subj2}`. |
| `subject` | No | **Legacy** single text field (older app data). Prefer `subjects` only; both exist in the DB for backward compatibility. |
| `semester`, `semester_name` | No | If used in your workflow. |
| `email` | No | Default empty. |
| `role` | No | Use `student`. |
| `status` | No | Use `approved` so students appear like app-created rows. |
| `has_device` | No | Default `false`. |
| `uid` | No | App may mirror `id`; optional on import. |
| `photo_url`, `face_photo_url`, `face_embedding` | No | Usually **empty** on CSV; add via app when face is registered. |

---

## Workflow checklist

1. Import **institutes** — note each `id`.
2. Import **batches** with that `institute_id` — copy each new **`batches.id` (UUID)**.
3. Import **students** with `institute_id` + `batch_id` (UUID).
4. Recompute **`batches.student_count`** and **`institutes.student_count`** if the app shows wrong totals (SQL `COUNT` updates).

## CSV tips (PostgreSQL)

- **Arrays:** `subjects`, `batch_ids` — use `{item1,item2}`; quote the whole field if values contain commas.
- **JSONB columns:** Prefer setting `start_time` / `end_time` / institute timing in SQL or the app after CSV import.
- **RLS:** Bulk insert may need **SQL Editor (service role)** or policies that allow your role; otherwise inserts can fail silently or with permission errors.

---

*Document version: aligns with `supabase/migrations` schema for `institutes`, `batches`, `students`.*
