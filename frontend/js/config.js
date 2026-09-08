// =========================================================================
// SUPABASE CLIENT CONFIG
// The publishable/anon key is designed to be public — it's safe to ship in
// frontend code because every table it can touch is protected by Row Level
// Security. Never put the service_role key here or anywhere else in this
// folder.
// =========================================================================
const SUPABASE_URL = "https://xrjctoisrgycfesstgbg.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_KNEHRVU2nK2OUb8DB_CMww_g5OZ7teo";

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
