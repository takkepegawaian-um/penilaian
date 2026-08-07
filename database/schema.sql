-- =====================================================================
-- SISTEM PENILAIAN SELEKSI DOSEN / TENAGA KEPENDIDIKAN UM
-- Desain Database (PostgreSQL / Supabase)
-- =====================================================================
-- Urutan eksekusi: ENUM -> Tabel Master -> Tabel Transaksi -> Trigger -> View
-- =====================================================================


-- =====================================================================
-- 1. ENUM TYPES
-- =====================================================================

create type jenis_kelamin_enum as enum ('Laki-Laki', 'Perempuan');

create type agama_enum as enum ('Islam', 'Kristen', 'Katolik', 'Hindu', 'Buddha', 'Khonghucu');

create type jabatan_fungsional_enum as enum (
  'Guru Besar / Profesor', 'Lektor Kepala', 'Lektor', 'Asisten Ahli'
);

create type peran_penguji_enum as enum ('Pewawancara', 'Penilai Praktik Mengajar');

create type jenis_sesi_enum as enum ('Wawancara', 'Praktik Mengajar');

create type status_kehadiran_enum as enum ('Offline', 'Online', 'Tidak Hadir');


-- =====================================================================
-- 2. TABEL MASTER
-- =====================================================================

-- Master Fakultas (dropdown Fakultas di daftar-peserta.html, badge di tabel-*.html)
create table fakultas (
  id           smallserial primary key,
  kode         varchar(10) not null unique,   -- FT, FMIPA, FIP, FEB, FS, FIK, FIS, FPSI, FV, FK, SPS
  nama         varchar(100) not null,
  created_at   timestamptz not null default now()
);

-- Master Ruangan (menu "Data Master Ruangan" di index.html)
create table ruangan (
  id           serial primary key,
  kode         varchar(20) not null unique,   -- mis. R-A9-01
  nama_ruangan varchar(100) not null,
  gedung       varchar(100),
  lokasi       varchar(150),
  kapasitas    smallint,
  keterangan   text,
  created_at   timestamptz not null default now()
);

-- Master Periode Seleksi (tahun berjalan + parameter ambang batas dari setting.html)
create table periode_seleksi (
  id                      serial primary key,
  tahun                   varchar(9) not null unique,   -- "2026"
  nama                    varchar(150),
  ambang_batas_wawancara  numeric(5,2) not null default 10.0,   -- skala mentah, maks 20
  ambang_batas_praktik    numeric(5,2) not null default 12.5,   -- skala mentah, maks 25
  status_aktif            boolean not null default true,
  created_at              timestamptz not null default now()
);

-- Master Dosen Penguji (penguji.html)
create table penguji (
  id                  serial primary key,
  nip                 varchar(20) not null unique,
  nama                varchar(150) not null,
  jabatan_fungsional  jabatan_fungsional_enum not null,
  email               varchar(150),
  no_hp               varchar(20),
  aktif               boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Peran penguji: satu dosen bisa merangkap Pewawancara & Penilai Praktik Mengajar
-- (checkbox ganda pada modal Tambah/Edit Dosen Penguji)
create table penguji_peran (
  id           serial primary key,
  penguji_id   int not null references penguji(id) on delete cascade,
  peran        peran_penguji_enum not null,
  kuota        smallint,   -- "Kuota Peserta Diwawancara" (setting.html)
  unique (penguji_id, peran)
);

-- Master unsur/kriteria penilaian (butir soal form-wawancara.html & form-praktik-mengajar.html)
-- Disimpan sebagai data, bukan hardcode, supaya kriteria bisa diubah dari Pengaturan.
create table unsur_penilaian (
  id          serial primary key,
  jenis_sesi  jenis_sesi_enum not null,
  urutan      smallint not null,
  nama_unsur  text not null,
  skor_maks   smallint not null default 5,
  aktif       boolean not null default true,
  unique (jenis_sesi, urutan)
);


-- =====================================================================
-- 3. TABEL DATA PESERTA
-- =====================================================================

create table peserta (
  id                   serial primary key,
  periode_id           int not null references periode_seleksi(id),
  kode_peserta         varchar(30) not null unique,   -- 2026-FT-001
  nama                 varchar(150) not null,
  email                varchar(150) not null,
  usia                 smallint check (usia between 17 and 80),
  jenis_kelamin        jenis_kelamin_enum not null,
  agama                agama_enum not null,
  formasi_jabatan      varchar(150) not null,          -- "Dosen Teknik Informatika"
  fakultas_id          smallint not null references fakultas(id),
  penempatan           varchar(150),                   -- kota/lokasi tugas, mis. "Malang"
  pendidikan_terakhir  varchar(150),                   -- "S2 Pendidikan Matematika"
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index idx_peserta_periode on peserta(periode_id);
create index idx_peserta_fakultas on peserta(fakultas_id);


-- =====================================================================
-- 4. PLOTTING / PENUGASAN PENGUJI (plotting.html)
-- =====================================================================
-- Satu baris = satu penugasan penguji ke peserta, untuk satu sesi (Wawancara/
-- Praktik Mengajar) & urutan (1 atau 2). Ini juga menjadi "slot" yang nanti
-- diisi oleh tabel penilaian saat penguji mengisi form penilaian.

create table penugasan (
  id           serial primary key,
  peserta_id   int not null references peserta(id) on delete cascade,
  penguji_id   int not null references penguji(id),
  jenis_sesi   jenis_sesi_enum not null,
  urutan       smallint not null check (urutan in (1, 2)),   -- I atau II
  ruangan_id   int references ruangan(id),
  created_at   timestamptz not null default now(),
  unique (peserta_id, jenis_sesi, urutan)
);

create index idx_penugasan_penguji on penugasan(penguji_id);


-- =====================================================================
-- 5. PENILAIAN (form-wawancara.html / form-praktik-mengajar.html)
-- =====================================================================

-- Header hasil penilaian per penugasan (1:1 dengan penugasan)
create table penilaian (
  id                 serial primary key,
  penugasan_id       int not null unique references penugasan(id) on delete cascade,
  status_kehadiran   status_kehadiran_enum not null default 'Offline',
  catatan            text,
  file_berkas_url    text,          -- upload bukti fisik, khusus form wawancara
  total_skor         numeric(5,2) not null default 0,   -- dihitung via trigger dari penilaian_detail
  submitted_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- Detail skor per butir/unsur (radio 1-5 di form)
create table penilaian_detail (
  id            serial primary key,
  penilaian_id  int not null references penilaian(id) on delete cascade,
  unsur_id      int not null references unsur_penilaian(id),
  skor          smallint not null check (skor between 1 and 5),
  unique (penilaian_id, unsur_id)
);

create index idx_penilaian_detail_penilaian on penilaian_detail(penilaian_id);


-- =====================================================================
-- 6. TRIGGER: auto-hitung total_skor & status "Tidak Hadir" mengosongkan skor
-- =====================================================================

create or replace function fn_recalc_total_skor() returns trigger as $$
begin
  update penilaian
     set total_skor = coalesce((
           select sum(skor) from penilaian_detail where penilaian_id = coalesce(new.penilaian_id, old.penilaian_id)
         ), 0),
         updated_at = now()
   where id = coalesce(new.penilaian_id, old.penilaian_id);
  return null;
end;
$$ language plpgsql;

create trigger trg_recalc_total_skor
after insert or update or delete on penilaian_detail
for each row execute function fn_recalc_total_skor();

-- Saat status_kehadiran diubah menjadi "Tidak Hadir", hapus detail skor (selaras dengan
-- perilaku cekKehadiran() di form-wawancara.html / form-praktik-mengajar.html)
create or replace function fn_clear_skor_if_absent() returns trigger as $$
begin
  if new.status_kehadiran = 'Tidak Hadir' and old.status_kehadiran is distinct from new.status_kehadiran then
    delete from penilaian_detail where penilaian_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger trg_clear_skor_if_absent
before update on penilaian
for each row execute function fn_clear_skor_if_absent();


-- =====================================================================
-- 7. VIEW: REKAPITULASI NILAI AKHIR (rekapitulasi.html)
-- =====================================================================
-- Mengonversi total_skor mentah (maks 20 utk wawancara, 25 utk praktik)
-- menjadi skala 0-100, lalu dipivot per peserta menjadi kolom P1/P2/PM1/PM2.

create view v_nilai_sesi as
select
  pu.peserta_id,
  pu.jenis_sesi,
  pu.urutan,
  pn.status_kehadiran,
  pn.total_skor,
  round(pn.total_skor / nullif(sm.skor_maks_sesi, 0) * 100, 2) as nilai_100,
  (pn.submitted_at is not null) as sudah_dinilai
from penugasan pu
join penilaian pn on pn.penugasan_id = pu.id
cross join lateral (
  select sum(skor_maks) as skor_maks_sesi
  from unsur_penilaian
  where jenis_sesi = pu.jenis_sesi and aktif = true
) sm;

create view v_rekapitulasi as
select
  p.id as peserta_id,
  p.kode_peserta,
  p.nama,
  p.formasi_jabatan,
  f.nama as fakultas,
  max(v.nilai_100) filter (where v.jenis_sesi = 'Wawancara' and v.urutan = 1) as nilai_wawancara_p1,
  max(v.nilai_100) filter (where v.jenis_sesi = 'Wawancara' and v.urutan = 2) as nilai_wawancara_p2,
  max(v.nilai_100) filter (where v.jenis_sesi = 'Praktik Mengajar' and v.urutan = 1) as nilai_praktik_pm1,
  max(v.nilai_100) filter (where v.jenis_sesi = 'Praktik Mengajar' and v.urutan = 2) as nilai_praktik_pm2,
  round(avg(v.nilai_100) filter (where v.jenis_sesi = 'Wawancara'), 2) as rerata_wawancara,
  round(avg(v.nilai_100) filter (where v.jenis_sesi = 'Praktik Mengajar'), 2) as rerata_praktik,
  bool_or(v.sudah_dinilai) filter (where v.jenis_sesi = 'Wawancara' and v.urutan = 1) as status_p1,
  bool_or(v.sudah_dinilai) filter (where v.jenis_sesi = 'Wawancara' and v.urutan = 2) as status_p2,
  bool_or(v.sudah_dinilai) filter (where v.jenis_sesi = 'Praktik Mengajar' and v.urutan = 1) as status_pm1,
  bool_or(v.sudah_dinilai) filter (where v.jenis_sesi = 'Praktik Mengajar' and v.urutan = 2) as status_pm2
from peserta p
join fakultas f on f.id = p.fakultas_id
left join v_nilai_sesi v on v.peserta_id = p.id
group by p.id, p.kode_peserta, p.nama, p.formasi_jabatan, f.nama;


-- =====================================================================
-- 8. SEED DATA
-- =====================================================================
-- Data acuan yang saat ini hardcode di HTML/JS (dropdown fakultas, butir
-- kriteria form penilaian) dipindahkan ke sini supaya aplikasi punya isi
-- begitu schema selesai dijalankan.

insert into fakultas (kode, nama) values
  ('FIP',  'Fakultas Ilmu Pendidikan'),
  ('FS',   'Fakultas Sastra'),
  ('FMIPA','Fakultas Matematika dan Ilmu Pengetahuan Alam'),
  ('FEB',  'Fakultas Ekonomi dan Bisnis'),
  ('FT',   'Fakultas Teknik'),
  ('FIK',  'Fakultas Ilmu Keolahragaan'),
  ('FIS',  'Fakultas Ilmu Sosial'),
  ('FPSI', 'Fakultas Psikologi'),
  ('FV',   'Fakultas Vokasi'),
  ('FK',   'Fakultas Kedokteran'),
  ('SPS',  'Sekolah Pascasarjana')
on conflict (kode) do nothing;

insert into periode_seleksi (tahun, nama, ambang_batas_wawancara, ambang_batas_praktik, status_aktif) values
  ('2026', 'Seleksi Dosen/Tenaga Kependidikan UM 2026', 10.0, 12.5, true)
on conflict (tahun) do nothing;

insert into unsur_penilaian (jenis_sesi, urutan, nama_unsur, skor_maks) values
  ('Wawancara', 1, 'Motivasi Kerja', 5),
  ('Wawancara', 2, 'Kemampuan Komunikasi dan Berpikir Analitis (Pengetahuan Dasar tentang Keilmuan)', 5),
  ('Wawancara', 3, 'Pengenalan Lingkungan Kampus', 5),
  ('Wawancara', 4, 'Pembentukan karakter yang berlandaskan Pancasila, Undang-Undang 1945, dan Bhinneka Tunggal Ika', 5),
  ('Praktik Mengajar', 1, 'Kemampuan verbal (intonasi, pemilihan kata/diksi, kualitas suara)', 5),
  ('Praktik Mengajar', 2, 'Kemampuan menggunakan alat bantu mengajar termasuk RPS dan media pembelajaran', 5),
  ('Praktik Mengajar', 3, 'Kemampuan akademik (penguasaan materi)', 5),
  ('Praktik Mengajar', 4, 'Kemampuan Bahasa Asing/Inggris', 5),
  ('Praktik Mengajar', 5, 'Sikap dan penampilan di kelas', 5)
on conflict (jenis_sesi, urutan) do nothing;


-- =====================================================================
-- 9. STORAGE BUCKET UNTUK BERKAS PENDUKUNG (form-wawancara.html)
-- =====================================================================

insert into storage.buckets (id, name, public)
values ('berkas', 'berkas', true)
on conflict (id) do nothing;

create policy "publik dapat melihat berkas"
  on storage.objects for select
  using (bucket_id = 'berkas');

create policy "anon dapat mengunggah berkas"
  on storage.objects for insert
  with check (bucket_id = 'berkas');


-- =====================================================================
-- 10. (OPSIONAL) AKSES PENGGUNA VIA SUPABASE AUTH
-- =====================================================================
-- Jika penguji nantinya login sendiri untuk mengisi form (bukan dioperasikan
-- admin), hubungkan ke auth.users bawaan Supabase dan aktifkan RLS per baris.

-- alter table penguji add column auth_user_id uuid references auth.users(id);
--
-- alter table penilaian enable row level security;
-- create policy "penguji hanya bisa ubah penilaian miliknya"
--   on penilaian for update
--   using (
--     exists (
--       select 1 from penugasan pu
--       join penguji pg on pg.id = pu.penguji_id
--       where pu.id = penilaian.penugasan_id and pg.auth_user_id = auth.uid()
--     )
--   );
