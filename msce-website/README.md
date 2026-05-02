# MSCE website (admin portals)

This folder holds the **web** projects for MSCE attendance (separate from the Flutter mobile app).

| Folder | Description |
|--------|-------------|
| `admin-portal-react` | React + Vite admin portal (`npm install`, `npm run dev` / `npm run build`). Configure `.env.local` with your Supabase URL and keys. |
| `admin-approval-portal` | Static HTML/JS approval UI — open `index.html` in a browser or serve with any static server. |

The Flutter app repo is a sibling: `../EDUSETU-ATTENDACE-APP-main/`.  
Flutter’s own **`web/`** bootstrap (icons, `index.html` for `flutter build web`) stays inside that project and is **not** moved here.
