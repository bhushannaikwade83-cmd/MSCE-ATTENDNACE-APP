-- Add face_embedding column to students table if it doesn't exist
-- This is needed for face recognition registration

BEGIN;

-- Add face_embedding column (JSONB to store embedding data)
ALTER TABLE students
ADD COLUMN IF NOT EXISTS face_embedding JSONB DEFAULT NULL;

-- Add face_photo_url column if missing
ALTER TABLE students
ADD COLUMN IF NOT EXISTS face_photo_url TEXT DEFAULT NULL;

-- Add updated_at column if missing (for tracking when face was registered)
ALTER TABLE students
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

COMMIT;

-- Verify columns were added
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'students'
AND column_name IN ('face_embedding', 'face_photo_url', 'updated_at')
ORDER BY column_name;
