# Scalable Email System (Supabase Edge Functions + Resend)

This setup sends emails with Resend (not Supabase Auth email), supports queue-based processing, and logs every attempt.

## 1) Deploy SQL (queue + logs)

Run:

- `supabase/migrations/008_email_queue_resend.sql`

This creates:

- `email_jobs` queue table
- `email_logs` delivery/audit table
- RPC helpers:
  - `enqueue_email_job`
  - `claim_email_jobs`
  - `mark_email_job_sent`
  - `mark_email_job_failed`

## 2) Deploy Edge Function

Function file:

- `supabase/functions/email-dispatch/index.ts`

Deploy:

```bash
supabase functions deploy email-dispatch
```

## 3) Set secrets (server-side only)

```bash
supabase secrets set RESEND_API_KEY=your_resend_key
supabase secrets set EMAIL_FROM="Attendance App <no-reply@yourdomain.com>"
supabase secrets set EMAIL_QUEUE_CRON_SECRET=your_strong_random_secret
```

> Do not expose `RESEND_API_KEY` in Flutter/frontend.

## 4) API structure

### Queue email (recommended)

`POST /functions/v1/email-dispatch`

Body:

```json
{
  "to": "user@example.com",
  "subject": "Test Email",
  "html": "<h1>Hello</h1>"
}
```

Example success response:

```json
{
  "success": true,
  "mode": "queued",
  "jobId": 123,
  "message": "Email queued successfully"
}
```

### Optional immediate send

```json
{
  "to": "user@example.com",
  "subject": "Urgent",
  "html": "<p>Sent now</p>",
  "sendNow": true
}
```

## 5) Queue processing endpoint (internal/cron)

Call same function with:

```json
{
  "mode": "process",
  "limit": 50,
  "delayMs": 120
}
```

Required header:

- `x-queue-secret: <EMAIL_QUEUE_CRON_SECRET>`

Example response:

```json
{
  "success": true,
  "mode": "process",
  "claimed": 50,
  "sent": 48,
  "failed": 2
}
```

## 6) Flutter / Dart example

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> queueEmail() async {
  final client = Supabase.instance.client;

  final response = await client.functions.invoke(
    'email-dispatch',
    body: {
      'to': 'user@example.com',
      'subject': 'Test Email',
      'html': '<h1>Hello</h1>',
    },
  );

  if (response.status != 202 && response.status != 200) {
    throw Exception('Email queue failed: ${response.data}');
  }
}
```

## 7) Basic burst protection + retries

Implemented in this system:

- Queue-first flow (non-blocking for app)
- Processor delay between sends (`delayMs`)
- Retry with exponential backoff via `mark_email_job_failed`
- Dead-letter style state (`dead`) after max retries

## 8) Suggested production scaling

- Run queue processor frequently (every 10-30s) from secure cron.
- Increase parallelism by running multiple processors with safe `claim_email_jobs` + `FOR UPDATE SKIP LOCKED`.
- Track dashboard metrics from `email_logs`.

