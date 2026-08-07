/**
 * Shared Supabase client for all pages.
 * Credentials are configured once via setting.html (stored in localStorage)
 * under the same keys setting.html already writes to: SUPABASE_URL / SUPABASE_KEY.
 *
 * Include order on every page:
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
 *   <script src="assets/supabase-client.js"></script>
 */
(function () {
  const SUPABASE_URL = localStorage.getItem("SUPABASE_URL");
  const SUPABASE_KEY = localStorage.getItem("SUPABASE_KEY");

  const onSettingPage = /setting\.html$/.test(location.pathname);

  if (!SUPABASE_URL || !SUPABASE_KEY) {
    if (!onSettingPage) {
      alert("Konfigurasi Supabase belum diisi. Silakan isi Project URL & Anon Key di halaman Pengaturan terlebih dahulu.");
      location.href = "setting.html";
    }
    return;
  }

  window.db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
})();

/** Ambil query string, mis. qs('id') dari form-wawancara.html?id=12 */
function qs(name) {
  return new URLSearchParams(location.search).get(name);
}

/** Escape teks sebelum disisipkan ke innerHTML agar aman dari HTML injection */
function escapeHtml(str) {
  if (str === null || str === undefined) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** Tampilkan pesan error Supabase secara konsisten */
function showDbError(context, error) {
  console.error(context, error);
  alert(`Gagal ${context}: ${error.message || error}`);
}

/** Ambil id periode_seleksi yang sedang aktif (dipakai saat menambah peserta baru) */
async function getPeriodeAktifId() {
  const { data, error } = await db
    .from("periode_seleksi")
    .select("id")
    .eq("status_aktif", true)
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  if (!data) throw new Error("Belum ada periode seleksi aktif. Atur di halaman Pengaturan > Parameter Seleksi.");
  return data.id;
}
